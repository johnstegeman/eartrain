import AVFoundation
import SwiftUI

/// Drives a single interval-training session.
///
/// State machine:
///   idle → playing → listening → result → (next) playing …
///   Any state → noRead (8 s timeout) → listening (user can replay)
@MainActor
public final class ExerciseViewModel: ObservableObject {

    // MARK: - Phase

    public enum Phase: Equatable {
        case idle
        case playing
        case listening
        case result(ExerciseResult)
        case noRead          // pitch couldn't be detected — prompt user to replay
    }

    // MARK: - Published

    @Published public var phase: Phase = .idle
    @Published public var currentInterval: Interval = .m3
    @Published public var rootHz: Float = 440.0   // A4 default; user-settable per session

    // MARK: - Settings

    /// Active interval set — defaults to priority drill set from DESIGN.md.
    public var activeIntervals: [Interval] = [.m3, .M3, .P5, .P8]

    // MARK: - Audio (owned here so ExerciseView can use @StateObject cleanly)

    public let audio = AudioEngineManager()

    // MARK: - Private

    private var listenTask: Task<Void, Never>?

    // Stability tracking: collect consecutive pitch readings and check spread
    private let stabilityCount  = 3
    private let stabilityCents: Float = 25

    // Noise floor and timeout
    private let amplitudeThreshold: Float = 0.02
    private let listenTimeoutSeconds: TimeInterval = 8

    public init() {}

    public func startEngine() { audio.start() }
    public func stopEngine()  { audio.stop() }

    // MARK: - Control

    /// Start (or restart) an exercise with a random interval from `activeIntervals`.
    public func startExercise() {
        listenTask?.cancel()
        let interval = activeIntervals.randomElement() ?? .m3
        currentInterval = interval
        phase = .playing

        Task {
            let targetHz = interval.targetHz(rootHz: rootHz)
            await audio.intervalPlayer.playInterval(rootHz: rootHz, intervalHz: targetHz)
            // 500 ms gate: prevent the sine tone from self-triggering the detector.
            try? await Task.sleep(for: .milliseconds(500))
            beginListening(for: interval)
        }
    }

    /// Replay the current interval without picking a new one.
    public func replayInterval() {
        listenTask?.cancel()
        phase = .playing
        Task {
            let targetHz = currentInterval.targetHz(rootHz: rootHz)
            await audio.intervalPlayer.playInterval(rootHz: rootHz, intervalHz: targetHz)
            try? await Task.sleep(for: .milliseconds(500))
            beginListening(for: currentInterval)
        }
    }

    // MARK: - Private

    private func beginListening(for interval: Interval) {
        phase = .listening
        listenTask = Task { [weak self] in
            guard let self else { return }
            let result = await self.waitForStablePitch(interval: interval)
            guard !Task.isCancelled else { return }
            if let result {
                self.phase = .result(result)
                // Auto-advance after feedback delay: 2s correct/close, 4s wrong/displaced
                let delay: TimeInterval
                switch result {
                case .correct, .close:    delay = 2.0
                case .wrong, .octaveDisplaced: delay = 4.0
                }
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                self.startExercise()
            } else {
                self.phase = .noRead
            }
        }
    }

    /// Poll for a stable pitch reading. Returns nil on timeout or cancellation.
    private func waitForStablePitch(interval: Interval) async -> ExerciseResult? {
        let deadline = Date().addingTimeInterval(listenTimeoutSeconds)
        var readings: [Float] = []
        var wasQuiet = true

        while Date() < deadline {
            guard !Task.isCancelled else { return nil }
            try? await Task.sleep(for: .milliseconds(50))

            let amp = audio.amplitude
            let hz  = audio.detectedHz

            // Reset accumulator on silence
            if amp < amplitudeThreshold {
                wasQuiet = true
                readings = []
                continue
            }

            // Onset
            if wasQuiet { wasQuiet = false; readings = [] }

            // Accumulate readings while signal is present
            if hz > 20 { readings.append(hz) }

            // Need at least stabilityCount readings
            guard readings.count >= stabilityCount else { continue }

            // Check that the last N readings are within stabilityCents of each other
            let window = readings.suffix(stabilityCount).map { Double($0) }
            let minHz = window.min()!
            let maxHz = window.max()!
            let spread = Float(abs(1200 * log2(maxHz / minHz)))
            guard spread < stabilityCents else { continue }

            // Stable — grade the average
            let avgHz = Float(window.reduce(0, +) / Double(window.count))
            return ExerciseResult.grade(rootHz: rootHz, interval: interval, detectedHz: avgHz)
        }

        return nil   // timeout
    }
}
