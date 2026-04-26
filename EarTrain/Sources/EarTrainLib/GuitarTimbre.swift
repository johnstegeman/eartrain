import Foundation

/// The four playback timbres available in Audie.
///
/// The `.sine` case uses the existing real-time `IntervalPlayer`.
/// The three guitar cases use `SamplePlayer`, which loads pre-rendered WAV
/// files extracted from the FluidR3 GM soundfont (CC-BY 3.0).
public enum GuitarTimbre: String, CaseIterable, Identifiable {
    case sine           = "sine"
    case acousticSteel  = "acoustic_steel"
    case cleanElectric  = "clean_electric"
    case overdrive      = "overdrive"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .sine:          return "Sine Wave"
        case .acousticSteel: return "Acoustic Guitar"
        case .cleanElectric: return "Clean Electric"
        case .overdrive:     return "Overdriven"
        }
    }

    public var systemImage: String {
        switch self {
        case .sine:          return "waveform"
        case .acousticSteel: return "guitars"
        case .cleanElectric: return "bolt.circle"
        case .overdrive:     return "bolt.fill"
        }
    }

    /// UserDefaults key. Also used by `@AppStorage` in Settings.
    public static let defaultsKey = "guitarTimbre"

    /// Read the persisted timbre, defaulting to `.sine`.
    public static var persisted: GuitarTimbre {
        get {
            let raw = UserDefaults.standard.string(forKey: defaultsKey) ?? ""
            return GuitarTimbre(rawValue: raw) ?? .sine
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
        }
    }
}
