import AVFoundation

/// Plays pre-rendered guitar WAV samples for interval training.
///
/// WAV files live in `Samples/{timbre}/note_0XX.wav` inside the module bundle.
/// They are loaded into `AVAudioPCMBuffer` objects at `prepare(timbre:)` time
/// so playback is glitch-free (no disk I/O on the audio thread).
///
/// MIDI range: notes 40–81 (E2–A5).
public final class SamplePlayer {

    // MARK: - Constants

    public static let midiLow  = 40
    public static let midiHigh = 81

    /// Amplitude scaling applied at load time to match the sine-wave IntervalPlayer's
    /// perceived loudness (which uses base amplitude 0.35 on a [0, 1] scale).
    private static let gainFactor: Float = 0.7

    // MARK: - Private state

    private var playerNode: AVAudioPlayerNode?
    private var mixerNode: AVAudioMixerNode?
    private var buffers: [Int: AVAudioPCMBuffer] = [:]   // keyed by MIDI note

    public init() {}

    // MARK: - Engine attachment

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
        mixer.outputVolume = Self.gainFactor

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
                    subdirectory: "Samples/\(timbre.rawValue)")
            else { continue }

            guard let file   = try? AVAudioFile(forReading: url),
                  let buffer = AVAudioPCMBuffer(
                    pcmFormat: file.processingFormat,
                    frameCapacity: AVAudioFrameCount(file.length))
            else { continue }

            try? file.read(into: buffer)
            loaded[midi] = buffer
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

        await node.scheduleBuffer(buffer, at: nil, options: .interrupts)
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
