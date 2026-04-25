import Accelerate
import AVFoundation
import SwiftUI

/// Manages the audio engine lifecycle and exposes live pitch readings.
///
/// Uses AVAudioEngine directly with an installTap for pitch detection.
/// AudioKit is used for SineOscillator playback (step 4+); mic input
/// capture is handled natively to avoid SoundpipeAudioKit's Swift 6.3
/// C/C++ interop incompatibility.
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

    // MARK: - Private

    private var engine: AVAudioEngine?
    private var detector: PitchDetector?

    /// Tap buffer size — 4096 samples ≈ 93 ms at 44100 Hz.
    /// Provides sufficient resolution for the autocorrelation algorithm
    /// while keeping latency low enough for live feedback.
    private let bufferSize: AVAudioFrameCount = 4096

    public init() {}

    // MARK: - Lifecycle

    public func start() {
        guard !isRunning else { return }

        let eng = AVAudioEngine()
        let inputNode = eng.inputNode
        let format = inputNode.inputFormat(forBus: 0)

        guard format.sampleRate > 0 else {
            engineError = "No audio input device found. Check your mic or interface in System Settings."
            return
        }

        let sampleRate = Float(format.sampleRate)
        let det = PitchDetector(sampleRate: sampleRate)

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, _ in
            guard let self else { return }

            // Amplitude (used for level meter and noise-floor gate)
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

        do {
            try eng.start()
            self.engine = eng
            self.detector = det
            isRunning = true
        } catch {
            engineError = "Couldn't start audio engine: \(error.localizedDescription)"
        }
    }

    public func stop() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        detector = nil
        isRunning = false
    }
}
