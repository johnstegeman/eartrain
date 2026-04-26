import AVFoundation
import SwiftUI

/// Drives the Contour Mode exercise ("Higher, Lower, or Same?").
///
/// Exercise loop:
///   1. App plays two notes sequentially.
///   2. User taps Higher / Lower / Same.
///   3. Immediate feedback → next pair.
///
/// Designed for CI users who are not yet ready for interval identification.
/// Research baseline: melodic contour discrimination is the easiest pitch
/// task for CI users and is used as the entry-level measure in published
/// CI music training studies.
@MainActor
public final class ContourViewModel: ObservableObject {

    // MARK: - Contour

    public enum Contour: Equatable, CaseIterable {
        case higher, lower, same

        public var label: String {
            switch self {
            case .higher: return "Higher"
            case .lower:  return "Lower"
            case .same:   return "Same"
            }
        }

        public var icon: String {
            switch self {
            case .higher: return "arrow.up"
            case .lower:  return "arrow.down"
            case .same:   return "equal"
            }
        }

        public var directionKey: String {
            switch self {
            case .higher: return "higher"
            case .lower:  return "lower"
            case .same:   return "same"
            }
        }
    }

    // MARK: - Phase

    public enum Phase: Equatable {
        case idle
        case playing
        case awaitingAnswer
        case result(correct: Bool, correctAnswer: Contour)
    }

    // MARK: - Published

    @Published public var phase: Phase = .idle
    @Published public var totalTrials: Int = 0
    @Published public var correctTrials: Int = 0

    // MARK: - Audio (injected — owned by AppSession)

    private let audio: any AudioPlaying

    // MARK: - Configuration

    /// Semitone range for higher/lower pairs. Wider = easier for CI users.
    public var semitoneRange: ClosedRange<Int> = 3...12

    // MARK: - Private

    private var correctContour: Contour = .higher
    private var rootHz: Float = 440
    private var secondHz: Float = 660
    private var semitones: Int = 7
    private var currentTask: Task<Void, Never>?
    private var logger: SessionLogger?

    public init(audio: any AudioPlaying) {
        self.audio = audio
    }

    /// Begin a new logging session. Call before `startExercise()`.
    public func beginSession() {
        logger?.endSession()
        logger = SessionLogger(mode: "contour")
    }

    /// Cancel any in-flight exercise task. Ends the current logging session.
    /// Engine lifecycle is AppSession's responsibility.
    public func cancel() {
        currentTask?.cancel()
        currentTask = nil
        logger?.endSession()
        logger = nil
        phase = .idle
    }

    // MARK: - Control

    public func startExercise() {
        currentTask?.cancel()
        phase = .playing
        let (root, second, st, contour) = generatePair()
        rootHz = root
        secondHz = second
        semitones = st
        correctContour = contour

        currentTask = Task {
            await audio.playInterval(
                rootHz: rootHz, intervalHz: secondHz,
                noteDuration: 1.2, gap: 0.35
            )
            guard !Task.isCancelled else { return }
            phase = .awaitingAnswer
        }
    }

    public func replayPair() {
        guard case .awaitingAnswer = phase else { return }
        currentTask?.cancel()
        phase = .playing
        currentTask = Task {
            await audio.playInterval(
                rootHz: rootHz, intervalHz: secondHz,
                noteDuration: 1.2, gap: 0.35
            )
            guard !Task.isCancelled else { return }
            phase = .awaitingAnswer
        }
    }

    public func answer(_ contour: Contour) {
        guard case .awaitingAnswer = phase else { return }
        let correct = contour == correctContour
        totalTrials += 1
        if correct { correctTrials += 1 }
        phase = .result(correct: correct, correctAnswer: correctContour)
        logger?.logContourTrial(rootHz: rootHz, semitones: semitones,
                                direction: correctContour.directionKey, correct: correct)

        currentTask = Task {
            let delay: TimeInterval = correct ? 1.5 : 3.0
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            startExercise()
        }
    }

    // MARK: - Generation

    /// Returns (rootHz, secondHz, semitones, contour).
    ///
    /// Contour and semitone count are chosen first so the root MIDI range can be
    /// constrained to keep BOTH notes within the guitar sample set (MIDI 40–81).
    /// Without this, a `.lower` pair from a low root would request a buffer index
    /// below 40, which SamplePlayer doesn't have — producing silence for note 2.
    private func generatePair() -> (Float, Float, Int, Contour) {
        // Weights: same is less common (20%) to keep the exercise challenging.
        let roll = Int.random(in: 0..<10)
        let contour: Contour
        switch roll {
        case 0..<4: contour = .higher   // 40%
        case 4..<8: contour = .lower    // 40%
        default:    contour = .same     // 20%
        }

        let semitones = Int.random(in: semitoneRange)

        // Constrain root so the second note stays within MIDI 40–81.
        let rootMidi: Int
        switch contour {
        case .higher: rootMidi = Int.random(in: 40...max(40, 81 - semitones))
        case .lower:  rootMidi = Int.random(in: min(72, 40 + semitones)...72)
        case .same:   rootMidi = Int.random(in: 40...72)
        }

        let rootHz = midiToHz(rootMidi)
        let secondHz: Float
        switch contour {
        case .higher: secondHz = midiToHz(rootMidi + semitones)
        case .lower:  secondHz = midiToHz(rootMidi - semitones)
        case .same:   secondHz = rootHz
        }

        return (rootHz, secondHz, semitones, contour)
    }

    private func midiToHz(_ midi: Int) -> Float {
        Float(440.0 * pow(2.0, Double(midi - 69) / 12.0))
    }
}
