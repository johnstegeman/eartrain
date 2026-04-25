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

    // MARK: - Audio

    public let audio = AudioEngineManager()

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

    public init() {}

    public func startEngine() { audio.start() }
    public func stopEngine()  { audio.stop() }

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

        // Rotate focus interval after a streak of correct answers.
        if correctStreak >= streakToAdvance {
            correctStreak = 0
            let others = activeIntervals.filter { $0 != focusInterval }
            focusInterval = others.randomElement() ?? focusInterval
        }

        Task {
            try? await Task.sleep(for: .seconds(correct ? 1.5 : 3.0))
            playTeaching()
        }
    }

    public func replayQuiz() {
        guard case .awaitingAnswer = phase else { return }
        phase = .playingQuiz
        Task {
            await audio.intervalPlayer.playInterval(
                rootHz: quizRootHz,
                intervalHz: quizInterval.targetHz(rootHz: quizRootHz)
            )
            phase = .awaitingAnswer
        }
    }

    // MARK: - Private

    private func playTeaching() {
        teachRootHz = randomRootHz()
        phase = .teaching
        let root = teachRootHz
        let interval = focusInterval
        Task {
            await audio.intervalPlayer.playInterval(
                rootHz: root,
                intervalHz: interval.targetHz(rootHz: root)
            )
            try? await Task.sleep(for: .milliseconds(400))
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
        Task {
            await audio.intervalPlayer.playInterval(
                rootHz: root,
                intervalHz: quiz.targetHz(rootHz: root)
            )
            phase = .awaitingAnswer
        }
    }

    /// Random root in a comfortable vocal/guitar range (C3–G4).
    private func randomRootHz() -> Float {
        let midi = Int.random(in: 48...67)
        return Float(440.0 * pow(2.0, Double(midi - 69) / 12.0))
    }
}
