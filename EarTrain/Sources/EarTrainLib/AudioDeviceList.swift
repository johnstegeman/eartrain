import CoreAudio
import Foundation

/// A CoreAudio audio device available on this Mac.
public struct AudioDevice: Identifiable, Hashable {
    public let id: AudioDeviceID
    public let uid: String
    public let name: String
    public let hasInput: Bool
    public let hasOutput: Bool

    /// Sentinel meaning "use whatever the system default is."
    public static let systemDefault = AudioDevice(
        id: 0, uid: "", name: "System Default",
        hasInput: true, hasOutput: true
    )
}

/// Utilities for enumerating CoreAudio devices on this Mac.
public enum AudioDeviceList {

    /// All input devices, preceded by the system-default sentinel.
    public static func inputDevices() -> [AudioDevice] {
        [.systemDefault] + all().filter(\.hasInput)
    }

    /// All output devices, preceded by the system-default sentinel.
    public static func outputDevices() -> [AudioDevice] {
        [.systemDefault] + all().filter(\.hasOutput)
    }

    /// Find a device by its stable UID. Returns nil when the device is not connected.
    public static func device(forUID uid: String) -> AudioDevice? {
        guard !uid.isEmpty else { return nil }
        return all().first { $0.uid == uid }
    }

    // MARK: - Private

    static func all() -> [AudioDevice] {
        var prop = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &prop, 0, nil, &dataSize
        ) == noErr else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &prop, 0, nil, &dataSize, &ids
        ) == noErr else { return [] }

        return ids.compactMap(makeDevice(id:))
    }

    private static func makeDevice(id: AudioDeviceID) -> AudioDevice? {
        guard let name = stringProp(id: id, selector: kAudioDevicePropertyDeviceNameCFString),
              let uid  = stringProp(id: id, selector: kAudioDevicePropertyDeviceUID) else { return nil }
        let hasInput  = channelCount(id: id, scope: kAudioObjectPropertyScopeInput)  > 0
        let hasOutput = channelCount(id: id, scope: kAudioObjectPropertyScopeOutput) > 0
        guard hasInput || hasOutput else { return nil }
        return AudioDevice(id: id, uid: uid, name: name, hasInput: hasInput, hasOutput: hasOutput)
    }

    private static func stringProp(id: AudioDeviceID,
                                   selector: AudioObjectPropertySelector) -> String? {
        var prop = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        // CoreAudio fills in a retained CFStringRef; use Unmanaged to bridge safely.
        var ref: Unmanaged<CFString>? = nil
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &prop, 0, nil, &size, &ref) == noErr,
              let ref else { return nil }
        return ref.takeRetainedValue() as String
    }

    private static func channelCount(id: AudioDeviceID,
                                     scope: AudioObjectPropertyScope) -> Int {
        var prop = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &prop, 0, nil, &dataSize) == noErr,
              dataSize > 0 else { return 0 }
        let buf = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { buf.deallocate() }
        guard AudioObjectGetPropertyData(id, &prop, 0, nil, &dataSize, buf) == noErr else { return 0 }
        let abl = buf.assumingMemoryBound(to: AudioBufferList.self)
        return UnsafeMutableAudioBufferListPointer(abl).reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}
