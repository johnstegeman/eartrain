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
    /// Saved at start() time so enableMicTap() can reinstall with the same format.
    private var savedInputFormat: AVAudioFormat?
    private var micTapInstalled = false

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

        // Save format for enableMicTap() — tap not installed yet.
        // The mic tap is only active while a guitar-response exercise is running,
        // so the macOS microphone-in-use indicator stays off otherwise.
        savedInputFormat = inputFormat

        // --- Interval tone output (must attach before engine.start()) ---
        intervalPlayer.attach(to: eng, sampleRate: sampleRate)
        samplePlayer.attach(to: eng)

        // --- Apply preferred devices before start ---
        if let dev = AudioDeviceList.device(forUID: preferredOutputUID) {
            applyDevice(dev.id, to: eng.outputNode)
        }
        if let dev = AudioDeviceList.device(forUID: preferredInputUID) {
            applyDevice(dev.id, to: eng.inputNode)
        }

        do {
            try eng.start()
            self.engine = eng
            self.detector = det
            isRunning = true
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
    /// The tap is NOT active by default — only install it while a
    /// guitar-response exercise is running so the macOS orange dot disappears
    /// when the user is on other tabs.
    public func enableMicTap() {
        guard let eng = engine,
              let format = savedInputFormat,
              let det = detector,
              !micTapInstalled else { return }
        eng.inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, _ in
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
        stop()
        start()
    }

    /// Stop and immediately restart the engine (used when preferred device changes).
    private func restart() {
        stop()
        start()
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
        }
        engine?.stop()
        engine = nil
        detector = nil
        savedInputFormat = nil
        isRunning = false
        amplitude    = 0
        detectedHz   = 0
        detectedNote = "--"
        // Reset sub-players so they re-attach cleanly to the next engine.
        intervalPlayer.reset()
        samplePlayer.reset()
    }
}
