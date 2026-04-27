import Accelerate
import AudioToolbox   // kAudioOutputUnitProperty_CurrentDevice
import AVFoundation
import CoreAudio
import SwiftUI

/// Manages the shared AVAudioEngine — mic input tap (pitch detection)
/// and tone/sample output on the same engine instance.
///
/// Tone output is routed through either `IntervalPlayer` (sine wave) or
/// `SamplePlayer` (guitar WAV samples) based on the current `timbre` setting.
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

    /// In-app output volume (0–1). Independent of system volume. Persisted in UserDefaults.
    /// Applied to `mainMixerNode.volume` so it affects both sine and sample playback.
    /// Uses an explicit setter (not @Published + didSet) to guarantee the side effect fires.
    public var outputVolume: Float {
        get { _outputVolume }
        set {
            objectWillChange.send()
            _outputVolume = newValue
            UserDefaults.standard.set(newValue, forKey: "outputVolume")
            engine?.mainMixerNode.outputVolume = newValue
        }
    }
    private var _outputVolume: Float = {
        let v = UserDefaults.standard.float(forKey: "outputVolume")
        return v > 0 ? v : 1.0
    }()

    /// Active timbre. Persisted in UserDefaults. Changing this reloads sample buffers.
    @Published public var timbre: GuitarTimbre = GuitarTimbre.persisted {
        didSet {
            GuitarTimbre.persisted = timbre
            samplePlayer.prepare(timbre: timbre)
        }
    }

    // MARK: - Sub-systems

    public let intervalPlayer = IntervalPlayer()
    public let samplePlayer   = SamplePlayer()

    /// CI Bluetooth keep-alive is active whenever the engine is running.
    /// AVAudioEngine keeps the macOS audio session alive even when outputting
    /// silence, which prevents the CI Bluetooth stream from suspending between
    /// exercises. Toggle lets the user opt out if they don't stream via BT.
    @Published public var keepAliveEnabled: Bool = true {
        didSet { applyKeepAlive() }
    }

    /// True when the engine is running and keepAlive is enabled.
    public var keepAliveActive: Bool { isRunning && keepAliveEnabled }

    // MARK: - Device selection

    /// UID of the preferred output device (e.g., CI Bluetooth stream).
    /// Empty string = follow the system default.
    /// Persisted in UserDefaults; changing it while running restarts the engine.
    @Published public var preferredOutputUID: String =
        UserDefaults.standard.string(forKey: "preferredOutputUID") ?? "" {
        didSet {
            UserDefaults.standard.set(preferredOutputUID, forKey: "preferredOutputUID")
            if isRunning { restart() }
        }
    }

    /// UID of the preferred input device (e.g., an audio interface).
    /// Empty string = follow the system default.
    @Published public var preferredInputUID: String =
        UserDefaults.standard.string(forKey: "preferredInputUID") ?? "" {
        didSet {
            UserDefaults.standard.set(preferredInputUID, forKey: "preferredInputUID")
            if isRunning { restart() }
        }
    }

    // MARK: - Private

    private var engine: AVAudioEngine?
    private var detector: PitchDetector?
    private var configChangeObserver: NSObjectProtocol?
    private var micTapInstalled = false
    // Ref-count so TunerView's onDisappear doesn't tear down a tap that an
    // exercise view just installed (SwiftUI fires new-view onAppear before
    // old-view onDisappear, so both can hold the tap simultaneously in flight).
    private var micTapRefCount = 0

    /// Tap buffer size — 4096 samples ≈ 93 ms at 44100 Hz.
    private let bufferSize: AVAudioFrameCount = 4096

    public init() {}

    // MARK: - Lifecycle

    public func start() {
        guard !isRunning else { return }

        let eng = AVAudioEngine()

        // Use the output node's sample rate for tone players.
        let outputRate = eng.outputNode.outputFormat(forBus: 0).sampleRate
        let sampleRate = Float(outputRate > 0 ? outputRate : 44100)

        // Pre-configure the input node BEFORE eng.start(). Accessing inputNode
        // on an already-running engine triggers AVAudioEngineConfigurationChange
        // (CoreAudio stops the engine to rewire the graph), which kills the
        // CI Bluetooth keep-alive and breaks output audio. Pre-warming it here
        // is safe: the orange mic indicator only fires when a tap is installed
        // on a running engine, not from touching the node object.
        _ = eng.inputNode

        // --- Tone output (must attach before engine.start()) ---
        intervalPlayer.attach(to: eng, sampleRate: sampleRate)
        samplePlayer.attach(to: eng)

        // --- Apply preferred output device before start ---
        if let dev = AudioDeviceList.device(forUID: preferredOutputUID) {
            applyDevice(dev.id, to: eng.outputNode)
        }
        // Preferred input device is applied lazily in enableMicTap().

        do {
            try eng.start()
            self.engine = eng
            isRunning = true
            eng.mainMixerNode.outputVolume = outputVolume
            // Load samples for the current timbre (no-op for .sine).
            samplePlayer.prepare(timbre: timbre)

            // Observe hardware config changes (device disconnect, format change,
            // or system default switch). The engine self-stops on such events;
            // we restart it so audio resumes on the new device.
            configChangeObserver = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange,
                object: eng,
                queue: nil
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.handleConfigurationChange() }
            }
        } catch {
            engineError = "Couldn't start audio engine: \(error.localizedDescription)"
        }
    }

    // MARK: - Mic tap control

    /// Install the hardware mic tap and begin pitch detection.
    /// The tap is NOT active by default — only call this while a
    /// guitar-response exercise is running so the macOS orange dot disappears
    /// when the user is on other tabs or in contour/identification mode.
    ///
    /// This is also the first point we touch `inputNode`, so the mic is never
    /// claimed until an exercise that actually needs it is active.
    public func enableMicTap() {
        micTapRefCount += 1
        guard let eng = engine, !micTapInstalled else { return }

        // Apply preferred input device now (deferred from start()).
        if let dev = AudioDeviceList.device(forUID: preferredInputUID) {
            applyDevice(dev.id, to: eng.inputNode)
        }

        let inputNode = eng.inputNode
        let format = inputNode.inputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            engineError = "No audio input device found. Check your mic in System Settings."
            return
        }

        // Create or recreate detector (sample rate can change on device switch).
        let det = PitchDetector(sampleRate: Float(format.sampleRate))
        self.detector = det

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, _ in
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
        micTapInstalled = true
    }

    /// Remove the hardware mic tap. Clears amplitude/pitch readings.
    public func disableMicTap() {
        micTapRefCount = max(0, micTapRefCount - 1)
        guard micTapRefCount == 0 else { return }
        guard let eng = engine, micTapInstalled else { return }
        eng.inputNode.removeTap(onBus: 0)
        micTapInstalled = false
        amplitude    = 0
        detectedHz   = 0
        detectedNote = "--"
    }

    // MARK: - Device application

    /// Set a specific CoreAudio device on an AVAudioEngine I/O node's underlying AudioUnit.
    /// Must be called before `engine.start()`. Silently skips if the AudioUnit isn't available.
    private func applyDevice(_ deviceID: AudioDeviceID, to node: AVAudioIONode) {
        guard let unit = node.audioUnit else { return }
        var id = deviceID
        AudioUnitSetProperty(unit,
                             kAudioOutputUnitProperty_CurrentDevice,
                             kAudioUnitScope_Global, 0,
                             &id, UInt32(MemoryLayout<AudioDeviceID>.size))
    }

    // MARK: - Config change handling

    private func handleConfigurationChange() {
        guard isRunning else { return }
        // Engine auto-stops on config change; restart it on the new device.
        engineError = nil
        let tapWasInstalled = micTapInstalled
        stop()
        start()
        if tapWasInstalled { enableMicTap() }
    }

    /// Stop and immediately restart the engine (used when preferred device changes).
    private func restart() {
        let tapWasInstalled = micTapInstalled
        stop()
        start()
        if tapWasInstalled { enableMicTap() }
    }

    // MARK: - Tuner chime

    /// Two-note ascending chime (E5 → A5) played through the sine wave player.
    /// Always uses sine regardless of timbre — a brief, clean confirmation ping.
    public func playInTuneChime() async {
        await intervalPlayer.play(hz: 659.25, duration: 0.10, amplitude: 0.35)
        try? await Task.sleep(for: .seconds(0.07))
        await intervalPlayer.play(hz: 880.00, duration: 0.18, amplitude: 0.30)
    }

    // MARK: - Timbre-routed playback

    /// Play root note then interval note, routing to sine or sample player.
    /// Reads the persisted timbre at call time so a settings change takes
    /// effect on the very next interval without restarting the engine.
    public func playInterval(rootHz: Float, intervalHz: Float,
                              noteDuration: TimeInterval = 1.5,
                              gap: TimeInterval = 0.4) async {
        let active = GuitarTimbre.persisted
        // Sync in-memory state and reload samples if the setting changed.
        if active != timbre {
            timbre = active
        }
        if active == .sine {
            await intervalPlayer.playInterval(rootHz: rootHz, intervalHz: intervalHz,
                                              noteDuration: noteDuration, gap: gap)
        } else {
            let rootMidi     = NoteConverter.midiNote(fromHz: rootHz)
            let intervalMidi = NoteConverter.midiNote(fromHz: intervalHz)
            await samplePlayer.playInterval(rootMidi: rootMidi, intervalMidi: intervalMidi,
                                            noteDuration: noteDuration, gap: gap)
        }
    }

    /// Stop all audio output (both players).
    public func stopPlayback() {
        intervalPlayer.stop()
        samplePlayer.stop()
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
        if let obs = configChangeObserver {
            NotificationCenter.default.removeObserver(obs)
            configChangeObserver = nil
        }
        stopPlayback()
        if micTapInstalled {
            engine?.inputNode.removeTap(onBus: 0)
            micTapInstalled = false
            micTapRefCount = 0
        }
        engine?.stop()
        engine = nil
        detector = nil
        isRunning = false
        amplitude    = 0
        detectedHz   = 0
        detectedNote = "--"
        // Reset sub-players so they re-attach cleanly to the next engine.
        intervalPlayer.reset()
        samplePlayer.reset()
    }
}
