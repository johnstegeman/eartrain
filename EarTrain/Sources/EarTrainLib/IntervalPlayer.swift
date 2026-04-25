import AVFoundation
import SwiftUI

/// Plays pure sine tones for interval training.
///
/// Uses AVAudioSourceNode attached to the shared AVAudioEngine so playback
/// shares the same output device as the CI keep-alive signal (step 5).
///
/// **Click and distortion elimination**: the render callback uses a one-pole
/// amplitude smoother — `currentAmplitude` glides toward `targetAmplitude`
/// at a ~20 ms time constant. This means amplitude changes (on/off, frequency
/// changes) never produce a discontinuity in the waveform, which eliminates
/// both end-of-note clicks and hard-attack distortion.
///
/// All public methods are @MainActor. RenderState is @unchecked Sendable
/// because Float reads/writes are atomic on ARM64.
public final class IntervalPlayer: ObservableObject {

    @Published public var isPlaying = false

    // MARK: - Render state (shared with audio thread)

    private final class RenderState: @unchecked Sendable {
        var phase: Float = 0
        var frequency: Float = 440
        var targetAmplitude: Float = 0      // written by main thread
        var currentAmplitude: Float = 0     // written by audio thread only
        var smoothingCoeff: Float = 0       // set once on attach
        var sampleRate: Float = 44100
    }

    private let state = RenderState()
    private var sourceNode: AVAudioSourceNode?

    public init() {}

    // MARK: - Setup

    /// Attach to the AVAudioEngine before it starts.
    public func attach(to engine: AVAudioEngine, sampleRate: Float) {
        state.sampleRate = sampleRate
        // One-pole smoothing coefficient for ~20 ms time constant.
        // τ = -1 / (sr * ln(1 - coeff))  →  coeff = 1 - e^(-1 / (sr * 0.02))
        state.smoothingCoeff = 1 - exp(-1.0 / (sampleRate * 0.020))

        let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate),
                                   channels: 2)!
        let s = state

        let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let phaseIncrement = (2 * Float.pi * s.frequency) / s.sampleRate
            for frame in 0..<Int(frameCount) {
                // Smooth amplitude toward target — eliminates clicks on any change.
                s.currentAmplitude += (s.targetAmplitude - s.currentAmplitude) * s.smoothingCoeff
                let value = sin(s.phase) * s.currentAmplitude
                s.phase += phaseIncrement
                if s.phase > 2 * Float.pi { s.phase -= 2 * Float.pi }
                for buffer in ablPointer {
                    UnsafeMutableBufferPointer<Float>(buffer)[frame] = value
                }
            }
            return noErr
        }

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        sourceNode = node
    }

    // MARK: - Playback

    /// Play a single tone at `hz` for `duration` seconds.
    /// The smoother handles fade-in and fade-out automatically.
    @MainActor
    public func play(hz: Float, duration: TimeInterval, amplitude: Float = 0.35) async {
        state.frequency = hz
        state.targetAmplitude = amplitude
        isPlaying = true
        try? await Task.sleep(for: .seconds(duration))
        state.targetAmplitude = 0
        // Wait for the fade-out to complete (~3× time constant = 60 ms).
        try? await Task.sleep(for: .seconds(0.06))
        isPlaying = false
    }

    /// Play root note, short gap, then interval note — the core ear-training loop.
    @MainActor
    public func playInterval(rootHz: Float, intervalHz: Float,
                              noteDuration: TimeInterval = 1.5,
                              gap: TimeInterval = 0.4) async {
        await play(hz: rootHz, duration: noteDuration)
        try? await Task.sleep(for: .seconds(gap))
        await play(hz: intervalHz, duration: noteDuration)
    }

    /// Fade to silence immediately.
    public func stop() {
        state.targetAmplitude = 0
        isPlaying = false
    }
}
