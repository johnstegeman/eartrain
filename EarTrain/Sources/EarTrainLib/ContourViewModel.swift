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
    private var currentTask: Task<Void, Never>?

    public init(audio: any AudioPlaying) {
        self.audio = audio
    }

    /// Cancel any in-flight exercise task. Does not touch the audio engine
    /// (lifecycle is AppSession's responsibility).
    public func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }

    // MARK: - Control

    public func startExercise() {
        currentTask?.cancel()
        phase = .playing
        let (root, second, contour) = generatePair()
        rootHz = root
        secondHz = second
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

        currentTask = Task {
            let delay: TimeInterval = correct ? 1.5 : 3.0
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            startExercise()
        }
    }

    // MARK: - Generation

    /// Returns (rootHz, secondHz, contour).
    /// Root is randomly chosen from the guitar range (E2–C5, MIDI 40–72).
    private func generatePair() -> (Float, Float, Contour) {
        let rootMidi = Int.random(in: 40...72)
        let rootHz = midiToHz(rootMidi)

        // Weights: same is less common (20%) to keep the exercise challenging.
        let roll = Int.random(in: 0..<10)
        let contour: Contour
        switch roll {
        case 0..<4: contour = .higher   // 40%
        case 4..<8: contour = .lower    // 40%
        default:    contour = .same     // 20%
        }

        let semitones = Int.random(in: semitoneRange)
        let secondHz: Float
        switch contour {
        case .higher: secondHz = midiToHz(rootMidi + semitones)
        case .lower:  secondHz = midiToHz(rootMidi - semitones)
        case .same:   secondHz = rootHz
        }

        return (rootHz, secondHz, contour)
    }

    private func midiToHz(_ midi: Int) -> Float {
        Float(440.0 * pow(2.0, Double(midi - 69) / 12.0))
    }
}
