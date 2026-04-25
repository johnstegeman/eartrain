import AVFoundation
import SwiftUI

/// Drives a single interval-training session.
///
/// State machine:
///   idle → playing → awaitingRoot → awaitingInterval → result → (next) playing …
///   Any state → noRead (8 s timeout) → user can replay
///
/// Two-note detection: the app listens for the root note first, then the
/// interval note. The interval is graded from the relationship between the
/// two detected pitches — not from the Settings root — so the exercise works
/// from any starting note the user chooses.
@MainActor
public final class ExerciseViewModel: ObservableObject {

    // MARK: - Phase

    public enum Phase: Equatable {
        case idle
        case playing
        case awaitingRoot       // waiting for user to play first note
        case awaitingInterval   // root detected, waiting for interval note
        case result(ExerciseResult)
        case noRead             // couldn't detect pitch — prompt to replay
    }

    // MARK: - Published

    @Published public var phase: Phase = .idle
    @Published public var currentInterval: Interval = .m3
    @Published public var rootHz: Float = 440.0   // A4 default; used for playback only

    // MARK: - Settings

    /// Active interval set — defaults to priority drill set from DESIGN.md.
    public var activeIntervals: [Interval] = [.m3, .M3, .P5, .P8]

    // MARK: - Audio (owned here so ExerciseView can use @StateObject cleanly)

    public let audio = AudioEngineManager()

    // MARK: - Private

    private var listenTask: Task<Void, Never>?
    private var logger: SessionLogger?

    private let stabilityCount  = 3
    private let stabilityCents: Float = 25
    private let amplitudeThreshold: Float = 0.02
    private let listenTimeoutSeconds: TimeInterval = 10  // per note, not total

    public init() {}

    public func startEngine() {
        audio.start()
        logger = SessionLogger(mode: "intervals")
    }

    public func stopEngine() {
        audio.stop()
        logger?.endSession()
        logger = nil
    }

    // MARK: - Control

    public func startExercise() {
        listenTask?.cancel()
        let interval = activeIntervals.randomElement() ?? .m3
        currentInterval = interval
        phase = .playing

        Task {
            let targetHz = interval.targetHz(rootHz: rootHz)
            await audio.intervalPlayer.playInterval(rootHz: rootHz, intervalHz: targetHz)
            // 500ms gate prevents sine tone from self-triggering the detector.
            try? await Task.sleep(for: .milliseconds(500))
            beginListening(for: interval)
        }
    }

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
        phase = .awaitingRoot
        listenTask = Task { [weak self] in
            guard let self else { return }

            // Step 1: detect root note
            guard let detectedRoot = await self.waitForStableNote() else {
                guard !Task.isCancelled else { return }
                self.logger?.logNoRead(interval: interval, rootHz: self.rootHz)
                self.phase = .noRead; return
            }
            guard !Task.isCancelled else { return }

            // Step 2: wait for silence between notes
            self.phase = .awaitingInterval
            await self.waitForSilence()
            guard !Task.isCancelled else { return }

            // Step 3: detect interval note
            guard let detectedInterval = await self.waitForStableNote() else {
                guard !Task.isCancelled else { return }
                self.logger?.logNoRead(interval: interval, rootHz: detectedRoot)
                self.phase = .noRead; return
            }
            guard !Task.isCancelled else { return }

            // Grade using the interval between the two played notes
            let result = ExerciseResult.grade(
                rootHz: detectedRoot,
                interval: interval,
                detectedHz: detectedInterval
            )
            self.logger?.logTrial(interval: interval,
                                   rootHz: detectedRoot,
                                   detectedHz: detectedInterval,
                                   result: result)
            self.phase = .result(result)

            let delay: TimeInterval
            switch result {
            case .correct, .close:         delay = 2.0
            case .wrong, .octaveDisplaced: delay = 4.0
            }
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self.startExercise()
        }
    }

    // MARK: - Note detection helpers

    /// Wait for a stable pitch reading. Returns the average Hz of the stable window, or nil on timeout.
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

    /// Wait until amplitude drops below threshold for at least 150ms.
    private func waitForSilence() async {
        let deadline = Date().addingTimeInterval(listenTimeoutSeconds)
        var quietFrames = 0
        let requiredFrames = 3  // 3 × 50ms = 150ms of silence

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
