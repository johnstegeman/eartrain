import AVFoundation
import SwiftUI

/// Drives a single interval-training session (guitar playback mode).
///
/// State machine:
///   idle → playing → awaitingRoot → awaitingInterval → result → (next) playing …
///   Any state → noRead (timeout) → user can replay
///
/// Two-note detection: the app listens for the root first, then the interval.
/// The interval is graded from the two detected pitches — not the Settings root —
/// so the exercise works from any starting note the user chooses.
@MainActor
public final class ExerciseViewModel: ObservableObject, DifficultyAdjustable {

    // MARK: - Phase

    public enum Phase: Equatable {
        case idle
        case playing
        case awaitingRoot
        case awaitingInterval
        case result(ExerciseResult)
        case noRead
    }

    // MARK: - Published

    @Published public var phase: Phase = .idle
    @Published public var currentInterval: Interval = .m3
    @Published public var rootHz: Float = 440.0
    @Published public var totalTrials: Int = 0
    @Published public var correctTrials: Int = 0

    /// 1 = easiest (.close counts as .correct, loose detection), 5 = hardest (tight).
    @Published public var difficultyLevel: Int = 3 {
        didSet { UserDefaults.standard.set(difficultyLevel, forKey: "difficultyLevel_intervals") }
    }

    @Published public var timeRemainingSeconds: Int? = nil
    @Published public var sessionExpired: Bool = false

    // MARK: - Settings

    public var activeIntervals: [Interval] = [.m3, .M3, .P5, .P8]

    // MARK: - Audio

    private let audio: any AudioPlaying & MicListening

    // MARK: - Difficulty

    /// At levels 1-2, widen the "correct" band by treating close as correct.
    private var promoteCloseToCorrect: Bool { difficultyLevel <= 2 }

    /// Pitch stability window in cents; looser at easy levels.
    private var stabilityCents: Float {
        difficultyLevel == 1 ? 40 : 25
    }

    /// Human-readable description for each difficulty level (1–5).
    public var difficultyDescriptions: [String] {
        [
            "Wide tolerance — close counts as correct",
            "Easy — some tolerance for pitch",
            "Standard grading",
            "Precise — must be close",
            "Exact pitch required",
        ]
    }

    public func lowerDifficulty() { difficultyLevel = max(1, difficultyLevel - 1) }
    public func raiseDifficulty() { difficultyLevel = min(5, difficultyLevel + 1) }

    /// Set by ExerciseView in onAppear. Called after every graded trial so the view
    /// can feed CompanionEngine and ProgressStore without coupling the VM to them.
    public var onTrialResult: ((Bool) -> Void)?

    // MARK: - Private

    private var listenTask: Task<Void, Never>?
    private var playTask:   Task<Void, Never>?
    private var timerTask:  Task<Void, Never>?
    private var timerExpired = false
    private var logger: SessionLogger?
    private var sessionStartDate: Date? = nil

    public var sessionDuration: TimeInterval {
        sessionStartDate.map { Date().timeIntervalSince($0) } ?? 0
    }

    private let stabilityCount = 3
    private let amplitudeThreshold: Float = 0.02
    private let listenTimeoutSeconds: TimeInterval = 10

    public init(audio: any AudioPlaying & MicListening) {
        self.audio = audio
        let saved = UserDefaults.standard.integer(forKey: "difficultyLevel_intervals")
        if saved > 0 { difficultyLevel = saved }
    }

    // MARK: - Session lifecycle

    public func beginSession(duration: SessionDuration = .open) {
        logger = SessionLogger(primitive: "interval-playback")
        audio.enableMicTap()
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
        listenTask?.cancel()
        listenTask = nil
        playTask?.cancel()
        playTask = nil
        logger?.endSession()
        logger = nil
        audio.disableMicTap()
        phase = .idle
        timeRemainingSeconds = nil
        timerExpired  = false
        sessionExpired = false
    }

    // MARK: - Control

    public func startExercise() {
        listenTask?.cancel()
        playTask?.cancel()
        let interval = activeIntervals.randomElement() ?? .m3
        currentInterval = interval
        phase = .playing

        playTask = Task {
            let targetHz = interval.targetHz(rootHz: rootHz)
            await audio.playInterval(rootHz: rootHz, intervalHz: targetHz)
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            beginListening(for: interval)
        }
    }

    public func replayInterval() {
        listenTask?.cancel()
        playTask?.cancel()
        phase = .playing
        playTask = Task {
            let targetHz = currentInterval.targetHz(rootHz: rootHz)
            await audio.playInterval(rootHz: rootHz, intervalHz: targetHz)
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            beginListening(for: currentInterval)
        }
    }

    // MARK: - Private

    private func beginListening(for interval: Interval,
                                onResult: ((Bool) -> Void)? = nil) {
        phase = .awaitingRoot
        listenTask = Task { [weak self] in
            guard let self else { return }

            guard let detectedRoot = await self.waitForStableNote() else {
                guard !Task.isCancelled else { return }
                self.logger?.logNoRead(interval: interval, rootHz: self.rootHz,
                                       difficulty: self.difficultyLevel)
                self.phase = .noRead
                self.totalTrials += 1
                return
            }
            guard !Task.isCancelled else { return }

            self.phase = .awaitingInterval
            await self.waitForSilence()
            guard !Task.isCancelled else { return }

            guard let detectedInterval = await self.waitForStableNote() else {
                guard !Task.isCancelled else { return }
                self.logger?.logNoRead(interval: interval, rootHz: detectedRoot,
                                       difficulty: self.difficultyLevel)
                self.phase = .noRead
                self.totalTrials += 1
                return
            }
            guard !Task.isCancelled else { return }

            var result = ExerciseResult.grade(
                rootHz: detectedRoot,
                interval: interval,
                detectedHz: detectedInterval
            )
            // At easy difficulty levels, treat "close" as correct to widen the success zone.
            if self.promoteCloseToCorrect, case .close = result {
                result = .correct
            }

            self.logger?.logTrial(interval: interval,
                                   rootHz: detectedRoot,
                                   detectedHz: detectedInterval,
                                   result: result,
                                   difficulty: self.difficultyLevel)
            self.phase = .result(result)
            self.totalTrials += 1
            let correct: Bool
            if case .correct = result { self.correctTrials += 1; correct = true }
            else { correct = false }
            onResult?(correct)
            self.onTrialResult?(correct)

            let delay: TimeInterval
            switch result {
            case .correct, .close:         delay = 2.0
            case .wrong, .octaveDisplaced: delay = 4.0
            }
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            if self.timerExpired {
                self.sessionExpired = true
            } else {
                self.startExercise()
            }
        }
    }

    // MARK: - Note detection helpers

    private func waitForStableNote() async -> Float? {
        let deadline = Date().addingTimeInterval(listenTimeoutSeconds)
        var readings: [Float] = []

        while Date() < deadline {
            guard !Task.isCancelled else { return nil }
            try? await Task.sleep(for: .milliseconds(50))

            let amp = audio.amplitude
            let hz  = audio.detectedHz

            if amp < amplitudeThreshold { readings = []; continue }
            if hz > 20 { readings.append(hz) }
            guard readings.count >= stabilityCount else { continue }

            let window = readings.suffix(stabilityCount).map { Double($0) }
            let spread = Float(abs(1200 * log2(window.max()! / window.min()!)))
            guard spread < stabilityCents else { continue }

            return Float(window.reduce(0, +) / Double(window.count))
        }
        return nil
    }

    private func waitForSilence() async {
        let deadline = Date().addingTimeInterval(listenTimeoutSeconds)
        var quietFrames = 0
        let requiredFrames = 3

        while Date() < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(50))
            if audio.amplitude < amplitudeThreshold {
                quietFrames += 1
                if quietFrames >= requiredFrames { return }
            } else {
                quietFrames = 0
            }
        }
    }
}
