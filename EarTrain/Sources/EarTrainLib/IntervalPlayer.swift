import AVFoundation
import SwiftUI

/// Plays pure sine tones for interval training.
///
/// Uses AVAudioSourceNode attached to the shared AVAudioEngine so playback
/// shares the same output device as the CI keep-alive signal (step 5).
/// Amplitude envelope: hard attack, hard release (appropriate for sine tones
/// used in CI interval training — no need for fade).
///
/// All public methods are @MainActor. Render state is a separate class
/// annotated @unchecked Sendable so it can safely cross the audio thread
/// boundary (Float reads/writes are atomic on ARM64).
public final class IntervalPlayer: ObservableObject {

    @Published public var isPlaying = false

    // MARK: - Render state (shared with audio thread)

    private final class RenderState: @unchecked Sendable {
        var phase: Float = 0
        var frequency: Float = 440
        var amplitude: Float = 0     // 0 = silent, >0 = playing
        var sampleRate: Float = 44100
    }

    private let state = RenderState()
    private var sourceNode: AVAudioSourceNode?

    public init() {}

    // MARK: - Setup

    /// Attach to a running (or not-yet-started) AVAudioEngine.
    /// Must be called before `engine.start()`.
    public func attach(to engine: AVAudioEngine, sampleRate: Float) {
        state.sampleRate = sampleRate
        let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate),
                                   channels: 2)!
        let s = state   // capture by reference

        let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let phaseIncrement = (2 * Float.pi * s.frequency) / s.sampleRate
            for frame in 0..<Int(frameCount) {
                let value = sin(s.phase) * s.amplitude
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
    @MainActor
    public func play(hz: Float, duration: TimeInterval, amplitude: Float = 0.45) async {
        state.frequency = hz
        state.amplitude = amplitude
        isPlaying = true
        try? await Task.sleep(for: .seconds(duration))
        state.amplitude = 0
        isPlaying = false
    }

    /// Play root note, short gap, then interval note — the core ear-training loop.
    @MainActor
    public func playInterval(rootHz: Float, intervalHz: Float,
                              noteDuration: TimeInterval = 1.5,
                              gap: TimeInterval = 0.3) async {
        await play(hz: rootHz, duration: noteDuration)
        try? await Task.sleep(for: .seconds(gap))
        await play(hz: intervalHz, duration: noteDuration)
    }

    /// Stop immediately.
    public func stop() {
        state.amplitude = 0
        isPlaying = false
    }
}
