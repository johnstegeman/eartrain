import Foundation

/// Configurable mastery gate thresholds stored in UserDefaults.
/// All keys are prefixed `mastery_` to avoid collisions.
/// Agents: see MIGRATION_1_7.md for the design rationale of each threshold.
public struct MasterySettings {

    public static var accuracyThreshold: Double {
        get { UserDefaults.standard.double(forKey: "mastery_accuracy").nonZero ?? 0.80 }
        set { UserDefaults.standard.set(newValue, forKey: "mastery_accuracy") }
    }
    public static var minTrialsPerBucket: Int {
        get { UserDefaults.standard.integer(forKey: "mastery_min_trials").nonZero ?? 10 }
        set { UserDefaults.standard.set(newValue, forKey: "mastery_min_trials") }
    }
    public static var minDifficulty: Int {
        get { UserDefaults.standard.integer(forKey: "mastery_min_difficulty").nonZero ?? 3 }
        set { UserDefaults.standard.set(newValue, forKey: "mastery_min_difficulty") }
    }
    public static var recencyWindow: Int {
        get { UserDefaults.standard.integer(forKey: "mastery_recency_window").nonZero ?? 20 }
        set { UserDefaults.standard.set(newValue, forKey: "mastery_recency_window") }
    }
    /// Whether 1–2 semitone buckets are required for gate clearance.
    /// Off by default: this range is genuinely hard for CI users and should not block advancement.
    public static var requireGap1_2: Bool {
        get { UserDefaults.standard.bool(forKey: "mastery_require_gap_1_2") }
        set { UserDefaults.standard.set(newValue, forKey: "mastery_require_gap_1_2") }
    }
    public static var softAdvanceAt: Int {
        get { UserDefaults.standard.integer(forKey: "mastery_soft_advance_at").nonZero ?? 80 }
        set { UserDefaults.standard.set(newValue, forKey: "mastery_soft_advance_at") }
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
private extension Double {
    var nonZero: Double? { self == 0.0 ? nil : self }
}
