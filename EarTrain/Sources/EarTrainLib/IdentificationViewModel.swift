import SwiftUI

/// Drives Identification Mode — "Is this a m3?"
///
/// Exercise loop:
///   1. App plays focus interval + shows its name ("This is a Minor 3rd") — teaching
///   2. App plays a new pair (target or foil) without revealing the name — quiz
///   3. User taps Yes / No
///   4. Immediate result; back to step 1
///
/// After `streakToAdvance` consecutive correct answers, the focus interval
/// rotates so the user progressively covers the full set.
@MainActor
public final class IdentificationViewModel: ObservableObject, DifficultyAdjustable {

    // MARK: - Phase

    public enum Phase: Equatable {
        case idle
        case teaching
        case playingQuiz
        case awaitingAnswer
        case result(correct: Bool, wasTarget: Bool, actual: Interval)
    }

    // MARK: - Published

    @Published public var phase: Phase = .idle
    @Published public var focusInterval: Interval = .m3
    @Published public var totalTrials: Int = 0
    @Published public var correctTrials: Int = 0

    /// 1 = easiest (2-interval pool, maximally different), 5 = hardest (6-interval pool).
    @Published public var difficultyLevel: Int = 3 {
        didSet {
            UserDefaults.standard.set(difficultyLevel, forKey: "difficultyLevel_identification")
            // If the current focus interval fell out of the new pool, pick a new one.
            if !activeIntervals.contains(focusInterval) {
                focusInterval = activeIntervals.randomElement() ?? .P5
            }
        }
    }

    @Published public var timeRemainingSeconds: Int? = nil
    @Published public var sessionExpired: Bool = false

    // MARK: - Audio

    private let audio: any AudioPlaying

    // MARK: - Difficulty

    /// Active interval pool — smaller at easy levels, grows as difficulty rises.
    private var activeIntervals: [Interval] {
        switch difficultyLevel {
        case 1:  return [.P5, .P8]                          // 2 intervals, max gap (5 st)
        case 2:  return [.M3, .P5, .P8]                     // 3 intervals
        case 3:  return [.m3, .M3, .P5, .P8]               // 4 (default — priority drill set)
        case 4:  return [.m3, .M3, .P4, .P5, .P8]          // 5 intervals
        default: return [.m3, .M3, .P4, .P5, .M6, .P8]    // 6 intervals
        }
    }

    /// Human-readable description for each difficulty level (1–5).
    public var difficultyDescriptions: [String] {
        [
            "P5 and octave only",
            "Add major third (M3)",
            "Add minor third (m3) — default",
            "Add perfect fourth (P4)",
            "All six intervals",
        ]
    }

    public func lowerDifficulty() { difficultyLevel = max(1, difficultyLevel - 1) }
    public func raiseDifficulty() { difficultyLevel = min(5, difficultyLevel + 1) }

    /// Correct answers in a row before rotating to the next focus interval.
    public let streakToAdvance = 3

    // MARK: - Private

    private var quizIsTarget  = true
    private var quizInterval: Interval = .m3
    private var teachRootHz: Float = 440
    private var quizRootHz:  Float = 440
    private var correctStreak = 0
    private var currentTask: Task<Void, Never>?
    private var timerTask:   Task<Void, Never>?
    private var timerExpired = false
    private var logger: SessionLogger?
    private var sessionStartDate: Date? = nil

    public var sessionDuration: TimeInterval {
        sessionStartDate.map { Date().timeIntervalSince($0) } ?? 0
    }

    public init(audio: any AudioPlaying) {
        self.audio = audio
        let saved = UserDefaults.standard.integer(forKey: "difficultyLevel_identification")
        if saved > 0 { difficultyLevel = saved }
    }

    // MARK: - Session lifecycle

    public func beginSession(duration: SessionDuration = .open) {
        logger?.endSession()
        logger = SessionLogger(primitive: "interval-id")
        sessionStartDate = Date()
        totalTrials   = 0
        correctTrials = 0
        timerExpired  = false
        sessionExpired = false

        timerTask?.cancel()
        if let minutes = duration.minutes {
            let endDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
            timerTask = Task { [weak self] in
                guard let self else { return }
                while Date() < endDate, !Task.isCancelled {
                    self.timeRemainingSeconds = max(0, Int(endDate.timeIntervalSince(Date())))
                    try? await Task.sleep(for: .seconds(1))
                }
                guard !Task.isCancelled else { return }
                self.timerExpired = true
                self.timeRemainingSeconds = 0
            }
        } else {
            timeRemainingSeconds = nil
        }
    }

    public func cancel() {
        timerTask?.cancel()
        timerTask = nil
        currentTask?.cancel()
        currentTask = nil
        logger?.endSession()
        logger = nil
        phase = .idle
        timeRemainingSeconds = nil
        timerExpired  = false
        sessionExpired = false
    }

    // MARK: - Control

    public func startSession() {
        focusInterval = activeIntervals.randomElement() ?? .m3
        correctStreak = 0
        playTeaching()
    }

    public func answer(_ yes: Bool, onResult: ((Bool) -> Void)? = nil) {
        guard case .awaitingAnswer = phase else { return }

        let correct = yes == quizIsTarget
        totalTrials  += 1
        if correct { correctTrials += 1; correctStreak += 1 }
        else        { correctStreak = 0 }

        phase = .result(correct: correct, wasTarget: quizIsTarget, actual: quizInterval)
        logger?.logIdentificationTrial(interval: quizInterval, rootHz: quizRootHz,
                                       correct: correct, difficulty: difficultyLevel)
        onResult?(correct)

        if correctStreak >= streakToAdvance {
            correctStreak = 0
            let others = activeIntervals.filter { $0 != focusInterval }
            focusInterval = others.randomElement() ?? focusInterval
        }

        currentTask?.cancel()
        currentTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(correct ? 1.5 : 3.0))
            guard !Task.isCancelled else { return }
            if self.timerExpired {
                self.sessionExpired = true
            } else {
                self.startNextRound()
            }
        }
    }

    public func replayQuiz() {
        guard case .awaitingAnswer = phase else { return }
        currentTask?.cancel()
        phase = .playingQuiz
        currentTask = Task {
            await audio.playInterval(
                rootHz: quizRootHz,
                intervalHz: quizInterval.targetHz(rootHz: quizRootHz)
            )
            guard !Task.isCancelled else { return }
            phase = .awaitingAnswer
        }
    }

    // MARK: - Private

    private func startNextRound() {
        if correctStreak == 0 { playTeaching() } else { playQuiz() }
    }

    private func playTeaching() {
        teachRootHz = randomRootHz()
        phase = .teaching
        let root = teachRootHz
        let interval = focusInterval
        currentTask?.cancel()
        currentTask = Task {
            await audio.playInterval(
                rootHz: root,
                intervalHz: interval.targetHz(rootHz: root)
            )
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            playQuiz()
        }
    }

    private func playQuiz() {
        quizIsTarget = Bool.random()
        quizInterval = quizIsTarget
            ? focusInterval
            : (activeIntervals.filter { $0 != focusInterval }.randomElement() ?? focusInterval)
        quizRootHz = randomRootHz()
        phase = .playingQuiz

        let root = quizRootHz
        let quiz = quizInterval
        currentTask?.cancel()
        currentTask = Task {
            await audio.playInterval(
                rootHz: root,
                intervalHz: quiz.targetHz(rootHz: root)
            )
            guard !Task.isCancelled else { return }
            phase = .awaitingAnswer
        }
    }

    private func randomRootHz() -> Float {
        let midi = Int.random(in: 48...67)
        return Float(440.0 * pow(2.0, Double(midi - 69) / 12.0))
    }
}
