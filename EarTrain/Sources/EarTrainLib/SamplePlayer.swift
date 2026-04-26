import Accelerate
import AVFoundation

/// Plays pre-rendered guitar WAV samples for interval training.
///
/// WAV files live in `Samples_normalized/{timbre}/note_0XX.wav` inside the module bundle.
/// They are ISO 226:2003 equal-loudness normalized — all notes sound equally loud to a
/// normal-hearing listener regardless of register. See scripts/normalize_samples.py.
///
/// They are loaded into `AVAudioPCMBuffer` objects at `prepare(timbre:)` time
/// so playback is glitch-free (no disk I/O on the audio thread).
///
/// MIDI range: notes 40–81 (E2–A5).
public final class SamplePlayer {

    // MARK: - Constants

    public static let midiLow  = 40
    public static let midiHigh = 81

    /// Linear gain applied to every loaded sample buffer.
    /// Compensates for conservative recording levels so guitar samples
    /// match the sine wave in perceived loudness. 3.0 ≈ +9.5 dB.
    private static let sampleGain: Float = 3.0

    // MARK: - Private state

    private var playerNode: AVAudioPlayerNode?
    private var mixerNode: AVAudioMixerNode?
    private var buffers: [Int: AVAudioPCMBuffer] = [:]   // keyed by MIDI note

    public init() {}

    // MARK: - Engine attachment

    /// Release node references so the next `attach(to:)` creates fresh nodes on
    /// the new engine. Loaded sample buffers are preserved — no need to reload.
    /// Call this from `AudioEngineManager.stop()` before discarding the old engine.
    public func reset() {
        playerNode = nil
        mixerNode  = nil
    }

    /// Attach the player node to the engine before `engine.start()`.
    /// Routes through a dedicated mixer node so gain can be adjusted without
    /// modifying buffer data.
    public func attach(to engine: AVAudioEngine) {
        guard playerNode == nil else { return }

        let player = AVAudioPlayerNode()
        let mixer  = AVAudioMixerNode()
        engine.attach(player)
        engine.attach(mixer)

        if let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2) {
            engine.connect(player, to: mixer,              format: format)
            engine.connect(mixer,  to: engine.mainMixerNode, format: format)
        }

        playerNode = player
        mixerNode  = mixer
    }

    // MARK: - Sample loading

    /// Load all samples for `timbre` into memory buffers.
    /// No-op for `.sine` (handled by `IntervalPlayer`).
    /// Returns silently if no bundle resources are found (e.g., in unit tests).
    public func prepare(timbre: GuitarTimbre) {
        guard timbre != .sine else {
            buffers = [:]
            return
        }
        var loaded: [Int: AVAudioPCMBuffer] = [:]
        for midi in Self.midiLow...Self.midiHigh {
            let name = String(format: "note_%03d", midi)
            guard let url = Bundle.module.url(
                    forResource: name,
                    withExtension: "wav",
                    subdirectory: "Samples_normalized/\(timbre.rawValue)")
            else { continue }

            guard let file   = try? AVAudioFile(forReading: url),
                  let buffer = AVAudioPCMBuffer(
                    pcmFormat: file.processingFormat,
                    frameCapacity: AVAudioFrameCount(file.length))
            else { continue }

            try? file.read(into: buffer)

            // The engine connection uses stereo format; upmix mono WAVs to stereo.
            if buffer.format.channelCount == 1,
               let stereoFmt = AVAudioFormat(standardFormatWithSampleRate: buffer.format.sampleRate, channels: 2),
               let stereo = AVAudioPCMBuffer(pcmFormat: stereoFmt, frameCapacity: buffer.frameCapacity),
               let src = buffer.floatChannelData, let dst = stereo.floatChannelData {
                stereo.frameLength = buffer.frameLength
                let count = Int(buffer.frameLength)
                memcpy(dst[0], src[0], count * MemoryLayout<Float>.size)
                memcpy(dst[1], src[0], count * MemoryLayout<Float>.size)
                // Boost gain and clamp to [-1, 1] to avoid clipping artifacts.
                var gain = Self.sampleGain
                var lo: Float = -1, hi: Float = 1
                let n = vDSP_Length(count)
                vDSP_vsmul(dst[0], 1, &gain, dst[0], 1, n)
                vDSP_vclip(dst[0], 1, &lo, &hi, dst[0], 1, n)
                vDSP_vsmul(dst[1], 1, &gain, dst[1], 1, n)
                vDSP_vclip(dst[1], 1, &lo, &hi, dst[1], 1, n)
                loaded[midi] = stereo
            } else {
                loaded[midi] = buffer
            }
        }
        buffers = loaded
    }

    // MARK: - Playback

    /// Play a MIDI note for `duration` seconds.
    /// Falls through silently if the note is out of range or buffers aren't loaded.
    @MainActor
    public func play(midiNote: Int, duration: TimeInterval) async {
        guard let node   = playerNode,
              let buffer = buffers[midiNote] else { return }

        // Use completionHandler: nil to select the synchronous overload.
        // The async overload of scheduleBuffer waits for the buffer to *finish*
        // playing, so calling it before node.play() deadlocks the Task forever
        // and eventually corrupts Swift Concurrency's executor state.
        node.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        node.play()
        try? await Task.sleep(for: .seconds(duration))
        node.stop()
    }

    /// Play root note, gap, then interval note — mirrors `IntervalPlayer.playInterval`.
    @MainActor
    public func playInterval(rootMidi: Int, intervalMidi: Int,
                              noteDuration: TimeInterval = 1.5,
                              gap: TimeInterval = 0.4) async {
        await play(midiNote: rootMidi, duration: noteDuration)
        try? await Task.sleep(for: .seconds(gap))
        await play(midiNote: intervalMidi, duration: noteDuration)
    }

    /// Stop playback immediately.
    public func stop() {
        playerNode?.stop()
    }
}
