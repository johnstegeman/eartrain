import Accelerate
import AVFoundation
import SwiftUI

/// Manages the shared AVAudioEngine — mic input tap (pitch detection)
/// and IntervalPlayer (tone output) on the same engine instance.
///
/// All published properties update on the main actor.
@MainActor
public final class AudioEngineManager: ObservableObject {

    // MARK: - Published state

    @Published public var detectedHz: Float = 0
    @Published public var detectedNote: String = "--"
    @Published public var amplitude: Float = 0
    @Published public var isRunning = false
    @Published public var engineError: String?

    // MARK: - Sub-systems

    public let intervalPlayer = IntervalPlayer()

    /// CI Bluetooth keep-alive is active whenever the engine is running.
    /// AVAudioEngine keeps the macOS audio session alive even when outputting
    /// silence, which prevents the CI Bluetooth stream from suspending between
    /// exercises. Toggle lets the user opt out if they don't stream via BT.
    @Published public var keepAliveEnabled: Bool = true {
        didSet { applyKeepAlive() }
    }

    /// True when the engine is running and keepAlive is enabled.
    public var keepAliveActive: Bool { isRunning && keepAliveEnabled }

    // MARK: - Private

    private var engine: AVAudioEngine?
    private var detector: PitchDetector?

    /// Tap buffer size — 4096 samples ≈ 93 ms at 44100 Hz.
    private let bufferSize: AVAudioFrameCount = 4096

    public init() {}

    // MARK: - Lifecycle

    public func start() {
        guard !isRunning else { return }

        let eng = AVAudioEngine()
        let inputNode = eng.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0 else {
            engineError = "No audio input device found. Check your mic or interface in System Settings."
            return
        }

        let sampleRate = Float(inputFormat.sampleRate)
        let det = PitchDetector(sampleRate: sampleRate)

        // --- Mic tap for pitch detection ---
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            var rms: Float = 0
            if let data = buffer.floatChannelData {
                vDSP_rmsqv(data[0], 1, &rms, vDSP_Length(buffer.frameLength))
            }
            let result = det.detect(buffer: buffer)
            DispatchQueue.main.async {
                self.amplitude = rms
                if let (hz, _) = result {
                    self.detectedHz = hz
                    self.detectedNote = NoteConverter.name(fromHz: hz)
                }
            }
        }

        // --- Interval tone output (must attach before engine.start()) ---
        intervalPlayer.attach(to: eng, sampleRate: sampleRate)

        do {
            try eng.start()
            self.engine = eng
            self.detector = det
            isRunning = true
        } catch {
            engineError = "Couldn't start audio engine: \(error.localizedDescription)"
        }
    }

    private func applyKeepAlive() {
        // Keep-alive is implicit: engine running = audio session alive = CI stream active.
        // When disabled we stop the engine (halting mic too); re-enable restarts it.
        if keepAliveEnabled && !isRunning {
            start()
        } else if !keepAliveEnabled && isRunning {
            stop()
        }
    }

    public func stop() {
        intervalPlayer.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        detector = nil
        isRunning = false
    }
}
