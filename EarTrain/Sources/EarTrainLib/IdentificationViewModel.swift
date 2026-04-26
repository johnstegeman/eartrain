import SwiftUI

/// Drives Identification Mode — "Is this a m3?"
///
/// Exercise loop (from DESIGN.md):
///   1. App plays focus interval + shows its name ("This is a Minor 3rd") — teaching
///   2. App plays a new pair (target or foil) without revealing the name — quiz
///   3. User taps Yes / No
///   4. Immediate result; back to step 1
///
/// After `streakToAdvance` consecutive correct answers, the focus interval
/// rotates so the user progressively covers the full set.
///
/// Listening-only — no guitar required.
@MainActor
public final class IdentificationViewModel: ObservableObject {

    // MARK: - Phase

    public enum Phase: Equatable {
        case idle
        case teaching           // playing focus interval; label visible
        case playingQuiz        // playing quiz interval; name hidden
        case awaitingAnswer     // waiting for Yes / No
        case result(correct: Bool, wasTarget: Bool, actual: Interval)
    }

    // MARK: - Published

    @Published public var phase: Phase = .idle
    @Published public var focusInterval: Interval = .m3
    @Published public var totalTrials: Int = 0
    @Published public var correctTrials: Int = 0

    // MARK: - Audio (injected — owned by AppSession)

    private let audio: any AudioPlaying

    // MARK: - Configuration

    /// Pool of intervals rotated through as focus changes.
    public var activeIntervals: [Interval] = [.m3, .M3, .P5, .P8]

    /// Correct answers in a row before moving to the next focus interval.
    public let streakToAdvance = 3

    // MARK: - Private

    private var quizIsTarget = true
    private var quizInterval: Interval = .m3
    private var teachRootHz: Float = 440
    private var quizRootHz:  Float = 440
    private var correctStreak = 0
    private var currentTask: Task<Void, Never>?
    private var logger: SessionLogger?

    public init(audio: any AudioPlaying) {
        self.audio = audio
    }

    /// Begin a new logging session. Call before `startSession()`.
    public func beginSession() {
        logger?.endSession()
        logger = SessionLogger(mode: "identification")
    }

    /// Cancel any in-flight task. Ends the current logging session.
    /// Engine lifecycle is AppSession's responsibility.
    public func cancel() {
        currentTask?.cancel()
        currentTask = nil
        logger?.endSession()
        logger = nil
    }

    // MARK: - Control

    public func startSession() {
        focusInterval = activeIntervals.randomElement() ?? .m3
        correctStreak = 0
        playTeaching()
    }

    public func answer(_ yes: Bool) {
        guard case .awaitingAnswer = phase else { return }

        let correct = yes == quizIsTarget
        totalTrials  += 1
        if correct { correctTrials += 1; correctStreak += 1 }
        else        { correctStreak = 0 }

        phase = .result(correct: correct, wasTarget: quizIsTarget, actual: quizInterval)
        logger?.logIdentificationTrial(interval: quizInterval, rootHz: quizRootHz,
                                       correct: correct)

        // Rotate focus interval after a streak of correct answers.
        if correctStreak >= streakToAdvance {
            correctStreak = 0
            let others = activeIntervals.filter { $0 != focusInterval }
            focusInterval = others.randomElement() ?? focusInterval
        }

        currentTask?.cancel()
        currentTask = Task {
            try? await Task.sleep(for: .seconds(correct ? 1.5 : 3.0))
            guard !Task.isCancelled else { return }
            startNextRound()
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

    /// Teaching only when starting fresh: new focus interval, or just got one wrong.
    /// Once the user is on a streak, skip straight to the quiz.
    private func startNextRound() {
        if correctStreak == 0 {
            playTeaching()
        } else {
            playQuiz()
        }
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
        // 50 / 50 target vs. foil
        quizIsTarget  = Bool.random()
        quizInterval  = quizIsTarget
            ? focusInterval
            : (activeIntervals.filter { $0 != focusInterval }.randomElement() ?? focusInterval)
        quizRootHz    = randomRootHz()
        phase         = .playingQuiz

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

    /// Random root in a comfortable vocal/guitar range (C3–G4).
    private func randomRootHz() -> Float {
        let midi = Int.random(in: 48...67)
        return Float(440.0 * pow(2.0, Double(midi - 69) / 12.0))
    }
}
