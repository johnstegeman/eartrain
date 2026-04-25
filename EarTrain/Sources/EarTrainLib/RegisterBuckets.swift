import Foundation

/// Maps a root frequency to a register label for confusion-matrix bucketing.
///
/// Thresholds are configurable so the user can adjust them to their playing
/// style or instrument. The defaults are guitar-optimised: both Low and Mid
/// support the full interval set (including P8); the High bucket is valid but
/// limits practical intervals to m3/M3/P4 because P5/P8 go off the neck above
/// roughly E4.
public struct RegisterBuckets: Codable, Equatable {

    /// Hz below which a root is classified as Low.
    public var lowMidHz: Float

    /// Hz below which a root is classified as Mid (above `lowMidHz`).
    public var midHighHz: Float

    public init(lowMidHz: Float, midHighHz: Float) {
        self.lowMidHz  = lowMidHz
        self.midHighHz = midHighHz
    }

    /// Default guitar register split.
    ///
    /// - Low:  E2–E3  (82–175 Hz)  — bass strings (6th/5th string area)
    /// - Mid:  F3–A4  (175–440 Hz) — main playing range; P5 reachable throughout
    ///                                (A4 root → E5 at 12th fret); P8 borderline above ~E4
    /// - High: A#4+   (466+ Hz)    — upper register; m3/M3/P4 practical only
    ///
    /// A4 (5th fret high E) is the practical root ceiling for most exercises.
    public static let guitarDefault = RegisterBuckets(lowMidHz: 175, midHighHz: 440)

    // MARK: - Classification

    public func register(for hz: Float) -> Register {
        if hz < lowMidHz  { return .low }
        if hz < midHighHz { return .mid }
        return .high
    }
}

// MARK: - Register

public enum Register: String, Codable, CaseIterable {
    case low, mid, high

    public var displayName: String {
        switch self {
        case .low:  return "Low"
        case .mid:  return "Mid"
        case .high: return "High"
        }
    }
}
