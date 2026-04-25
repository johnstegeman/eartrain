import Foundation

/// The eight intervals present in major and minor pentatonic scales.
/// Raw value = semitone count, used directly for pitch arithmetic.
public enum Interval: Int, CaseIterable, Codable, Hashable {
    case M2 = 2
    case m3 = 3
    case M3 = 4
    case P4 = 5
    case P5 = 7
    case M6 = 9
    case m7 = 10
    case P8 = 12

    public var semitones: Int { rawValue }

    public var displayName: String {
        switch self {
        case .M2: return "Major 2nd"
        case .m3: return "Minor 3rd"
        case .M3: return "Major 3rd"
        case .P4: return "Perfect 4th"
        case .P5: return "Perfect 5th"
        case .M6: return "Major 6th"
        case .m7: return "Minor 7th"
        case .P8: return "Octave"
        }
    }

    public var shortName: String {
        switch self {
        case .M2: return "M2"
        case .m3: return "m3"
        case .M3: return "M3"
        case .P4: return "P4"
        case .P5: return "P5"
        case .M6: return "M6"
        case .m7: return "m7"
        case .P8: return "P8"
        }
    }

    /// Frequency of the interval note above `rootHz`.
    public func targetHz(rootHz: Float) -> Float {
        rootHz * pow(2, Float(semitones) / 12)
    }

    /// Nearest interval to `semitones` (fractional OK).
    public static func nearest(toSemitones semitones: Double) -> Interval {
        allCases.min { abs(Double($0.semitones) - semitones) < abs(Double($1.semitones) - semitones) }!
    }
}
