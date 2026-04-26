import Foundation

/// A single all-time personal-best streak record.
public struct StreakRecord: Identifiable {
    public var id: String { "\(modeKey)_\(difficulty)" }
    public let modeKey: String
    public let difficulty: Int
    public let streak: Int

    public var modeLabel: String {
        switch modeKey {
        case "contour":        return "Contour"
        case "intervals":      return "Intervals"
        case "identification": return "Identification"
        default:               return modeKey.capitalized
        }
    }
}

/// Reads cumulative session data from disk and provides it to ProgressView.
///
/// Call `reload()` on appear — no polling needed since sessions write synchronously
/// before the user ever navigates to Progress.
@MainActor
public final class ProgressStore: ObservableObject {

    @Published public private(set) var stats = SessionLogger.CumulativeStats()

    public init() {
        // Auto-reload whenever any exercise session ends, regardless of which
        // SwiftUI view is currently visible. This sidesteps the race between
        // ProgressView.onAppear and the previous tab's onDisappear.
        NotificationCenter.default.addObserver(
            forName: .earTrainSessionDidEnd,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reload() }
        }
    }

    // MARK: - Public interface

    public func reload() {
        guard let data = try? Data(contentsOf: Self.cumulativeURL),
              let loaded = try? Self.decoder.decode(SessionLogger.CumulativeStats.self,
                                                    from: data) else { return }
        stats = loaded
    }

    /// Counts for a specific (interval, register) cell. Nil if no data yet.
    public func counts(for interval: Interval,
                       register: Register) -> SessionLogger.RegisterCounts? {
        guard let byRegister = stats.matrix[interval.shortName],
              let counts = byRegister[register.rawValue],
              counts.total > 0 else { return nil }
        return counts
    }

    /// Aggregated contour counts for a specific interval across all registers.
    /// Returns nil if no trials exist for that interval.
    public func contourCounts(for intervalName: String) -> SessionLogger.ContourCounts? {
        guard let byRegister = stats.contour[intervalName] else { return nil }
        var total = SessionLogger.ContourCounts()
        for c in byRegister.values { total.correct += c.correct; total.total += c.total }
        return total.total > 0 ? total : nil
    }

    /// Contour counts for a specific interval × register cell.
    public func contourCounts(for intervalName: String,
                              register: Register) -> SessionLogger.ContourCounts? {
        guard let counts = stats.contour[intervalName]?[register.rawValue],
              counts.total > 0 else { return nil }
        return counts
    }

    /// Interval names that have at least one contour trial, sorted by shortName.
    public var contourIntervals: [String] {
        stats.contour.filter { $0.value.values.contains { $0.total > 0 } }
                     .keys.sorted()
    }

    /// True if any contour trials have been logged.
    public var hasContourData: Bool {
        stats.contour.values.contains { $0.values.contains { $0.total > 0 } }
    }

    /// Top N interval × register buckets ranked by error rate, requiring ≥ 5 trials each.
    /// Used on the End of Session screen to surface the biggest weak spots.
    public func topConfusionBuckets(limit: Int = 2)
        -> [(intervalName: String, registerName: String, errorRate: Double)]
    {
        var buckets: [(intervalName: String, registerName: String, errorRate: Double)] = []
        for (intervalName, byRegister) in stats.matrix {
            for (registerName, counts) in byRegister {
                guard counts.total >= 5, counts.errorRate > 0 else { continue }
                buckets.append((intervalName, registerName, counts.errorRate))
            }
        }
        return Array(buckets.sorted { $0.errorRate > $1.errorRate }.prefix(limit))
    }

    /// True if any (interval, register) bucket has ≥ 5 trials and an error rate > 30%.
    /// Used to enable the "Drill My Misses" shortcut.
    public var hasDrillableData: Bool {
        for byRegister in stats.matrix.values {
            for counts in byRegister.values {
                if counts.total >= 5 && counts.errorRate > 0.30 { return true }
            }
        }
        return false
    }

    /// Overall accuracy across all interval trials (playback + identification).
    public var overallAccuracy: Double? {
        var totalCorrect = 0
        var total = 0
        for byRegister in stats.matrix.values {
            for counts in byRegister.values {
                totalCorrect += counts.correct
                total        += counts.total
            }
        }
        guard total > 0 else { return nil }
        return Double(totalCorrect) / Double(total)
    }

    // MARK: - Streak records (UserDefaults-backed, keyed by "modeKey_difficulty")

    /// Returns the all-time best consecutive-correct streak for a given mode + difficulty.
    public func longestStreak(modeKey: String, difficulty: Int) -> Int {
        UserDefaults.standard.integer(forKey: streakKey(modeKey, difficulty))
    }

    /// Persists `streak` only if it beats the existing record for that mode + difficulty.
    /// Returns `true` if a new personal best was set.
    /// Safe to call on every trial — no-ops when streak ≤ current record.
    @discardableResult
    public func updateStreakIfRecord(modeKey: String, difficulty: Int, streak: Int) -> Bool {
        guard streak > 0 else { return false }
        let key = streakKey(modeKey, difficulty)
        let current = UserDefaults.standard.integer(forKey: key)
        guard streak > current else { return false }
        UserDefaults.standard.set(streak, forKey: key)
        objectWillChange.send()
        return true
    }

    /// All recorded personal-best streaks, sorted by streak count descending.
    public var allStreakRecords: [StreakRecord] {
        let prefix = "longestStreak_"
        let defaults = UserDefaults.standard.dictionaryRepresentation()
        return defaults.compactMap { key, value -> StreakRecord? in
            guard key.hasPrefix(prefix),
                  let count = value as? Int, count > 0 else { return nil }
            let rest = String(key.dropFirst(prefix.count))
            // key format: modeKey_difficulty  (difficulty is always a single digit 1-5)
            guard let lastUnderscore = rest.lastIndex(of: "_"),
                  let difficulty = Int(rest[rest.index(after: lastUnderscore)...]) else { return nil }
            let modeKey = String(rest[..<lastUnderscore])
            return StreakRecord(modeKey: modeKey, difficulty: difficulty, streak: count)
        }.sorted { $0.streak > $1.streak }
    }

    /// Removes all personal-best streak records from UserDefaults.
    public func clearAllStreakRecords() {
        let prefix = "longestStreak_"
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
        objectWillChange.send()
    }

    private func streakKey(_ modeKey: String, _ difficulty: Int) -> String {
        "longestStreak_\(modeKey)_\(difficulty)"
    }

    // MARK: - Private

    private static var cumulativeURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Audie")
            .appendingPathComponent("cumulative.json")
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
