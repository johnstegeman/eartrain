import Foundation
import GRDB
import os.log

private let progressLog = Logger(subsystem: "com.audie", category: "progress")

// MARK: - Today's recommendation

public struct TodayRecommendation {
    public let mode: AppMode
    public let headline: String
    public let reason: String
    public let cta: String
}

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

    private let db: AudieDatabase

    /// - Parameter database: Inject for testing; defaults to `AudieDatabase.shared`.
    public init(database: AudieDatabase = .shared) {
        self.db = database
        NotificationCenter.default.addObserver(
            forName: .earTrainSessionDidEnd,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                UserDefaults.standard.set(Date(), forKey: "lastSessionDate")
                self?.reload()
            }
        }
    }

    // MARK: - Public interface

    public func reload() {
        do {
            var s = SessionLogger.CumulativeStats()
            s.lastUpdated = Date()

            try db.dbQueue.read { d in
                s.totalSessions = (try Int.fetchOne(
                    d, sql: "SELECT COUNT(*) FROM sessions WHERE total_trials > 0")) ?? 0
                s.totalTrials = (try Int.fetchOne(
                    d, sql: "SELECT COUNT(*) FROM trials")) ?? 0

                // Interval matrix: playback + identification primitives
                let matrixRows = try Row.fetchAll(d, sql: """
                    SELECT interval_name, register,
                        SUM(CASE WHEN result_detail = 'correct'          THEN 1 ELSE 0 END) AS c,
                        SUM(CASE WHEN result_detail = 'close'            THEN 1 ELSE 0 END) AS cl,
                        SUM(CASE WHEN result_detail = 'octave_displaced' THEN 1 ELSE 0 END) AS od,
                        SUM(CASE WHEN result_detail = 'wrong'            THEN 1 ELSE 0 END) AS wr,
                        SUM(CASE WHEN result_detail = 'no_read'          THEN 1 ELSE 0 END) AS nr
                    FROM trials
                    WHERE primitive IN ('interval-id', 'interval-playback')
                      AND interval_name IS NOT NULL
                      AND register IS NOT NULL
                    GROUP BY interval_name, register
                    """)
                for row in matrixRows {
                    let iName: String? = row["interval_name"]
                    let reg:   String? = row["register"]
                    guard let iName, let reg else { continue }
                    var counts = SessionLogger.RegisterCounts()
                    counts.correct         = Int.fromDatabaseValue(row["c"])  ?? 0
                    counts.close           = Int.fromDatabaseValue(row["cl"]) ?? 0
                    counts.octaveDisplaced = Int.fromDatabaseValue(row["od"]) ?? 0
                    counts.wrong           = Int.fromDatabaseValue(row["wr"]) ?? 0
                    counts.noRead          = Int.fromDatabaseValue(row["nr"]) ?? 0
                    var byReg = s.matrix[iName] ?? [:]
                    byReg[reg] = counts
                    s.matrix[iName] = byReg
                }

                // Contour matrix
                let contourRows = try Row.fetchAll(d, sql: """
                    SELECT interval_name, register,
                        SUM(correct) AS c,
                        COUNT(*)     AS total
                    FROM trials
                    WHERE primitive = 'contour'
                      AND interval_name IS NOT NULL
                      AND register IS NOT NULL
                    GROUP BY interval_name, register
                    """)
                for row in contourRows {
                    let iName: String? = row["interval_name"]
                    let reg:   String? = row["register"]
                    guard let iName, let reg else { continue }
                    var counts = SessionLogger.ContourCounts()
                    counts.correct = Int.fromDatabaseValue(row["c"])     ?? 0
                    counts.total   = Int.fromDatabaseValue(row["total"]) ?? 0
                    var byReg = s.contour[iName] ?? [:]
                    byReg[reg] = counts
                    s.contour[iName] = byReg
                }
            }
            stats = s
        } catch {
            progressLog.error("reload() failed: \(error.localizedDescription, privacy: .public)")
        }
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

    /// Total contour trials logged across all intervals and registers.
    public var contourTotalTrials: Int {
        contourIntervals.reduce(0) { $0 + (contourCounts(for: $1)?.total ?? 0) }
    }

    /// Overall contour accuracy across all intervals and registers. Nil if no data.
    public var contourOverallAccuracy: Double? {
        let pairs = contourIntervals.compactMap { contourCounts(for: $0) }
        let total   = pairs.reduce(0) { $0 + $1.total }
        let correct = pairs.reduce(0) { $0 + $1.correct }
        guard total > 0 else { return nil }
        return Double(correct) / Double(total)
    }

    /// Contour is mastered when the user has enough trials at strong accuracy.
    /// Thresholds: ≥ 30 trials AND ≥ 75% accuracy.
    /// Note: does not yet gate on difficulty level — difficulty-aware mastery
    /// (requiring difficulty 5) will be added when LessonRunner ships (Phase 2).
    public var hasContourMastery: Bool {
        guard let acc = contourOverallAccuracy else { return false }
        return contourTotalTrials >= 30 && acc >= 0.75
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

    // MARK: - Today's recommendation

    /// True if the user completed at least one session today.
    public var practicedToday: Bool {
        guard let last = UserDefaults.standard.object(forKey: "lastSessionDate") as? Date else {
            return false
        }
        return Calendar.current.isDateInToday(last)
    }

    /// What Audie recommends doing right now, based on where the user is in the curriculum.
    ///
    /// Curriculum ladder: Contour → Interval Identification → Interval Playback
    /// A stage advances only when the previous one is mastered. Users are never
    /// pushed forward prematurely — mastery requires both enough trials and strong accuracy.
    ///
    /// Difficulty-gated mastery (requiring difficulty 5) is a Phase 2 addition
    /// once LessonRunner tracks per-trial difficulty.
    public var todayRecommendation: TodayRecommendation {

        // ── Stage 1: Contour ──────────────────────────────────────────────────
        // Stay here until mastered (≥ 30 trials, ≥ 75% accuracy).

        if !hasContourMastery {
            let n = contourTotalTrials
            if n == 0 {
                return TodayRecommendation(
                    mode: .contour,
                    headline: "Start with Contour",
                    reason: "Hearing whether a note goes up or down is the foundation. Start here.",
                    cta: "Begin"
                )
            }
            let accStr = contourOverallAccuracy.map { "\(Int($0 * 100))% accuracy" } ?? "keep going"
            let needed = max(0, 30 - n)
            let progressNote = needed > 0
                ? "\(n) trial\(n == 1 ? "" : "s") in, \(accStr). ~\(needed) more to reach mastery."
                : "\(n) trials in, \(accStr). Push accuracy above 75% to advance."
            return TodayRecommendation(
                mode: .contour,
                headline: "Keep Building Contour",
                reason: progressNote,
                cta: "Continue"
            )
        }

        // ── Stage 2: Interval Identification ─────────────────────────────────
        // Learn what intervals sound like before playing them back.
        // Gate: contour mastered AND no identification/interval data yet.

        if stats.matrix.isEmpty {
            return TodayRecommendation(
                mode: .identification,
                headline: "Name the Intervals",
                reason: "Contour is solid. Now learn what each interval sounds like before playing it back.",
                cta: "Start"
            )
        }

        // ── Stage 3: Interval Playback — confusion-matrix targeting ──────────

        // Specific drillable weakness (≥ 5 trials, > 35% error rate)
        if let hit = topConfusionBuckets(limit: 1).first, hit.errorRate > 0.35 {
            let pct = Int(hit.errorRate * 100)
            return TodayRecommendation(
                mode: .intervals,
                headline: "Drill \(hit.intervalName) — \(hit.registerName) register",
                reason: "\(pct)% error rate. Targeted reps here beat random practice.",
                cta: "Drill This"
            )
        }

        if let acc = overallAccuracy, acc < 0.70 {
            return TodayRecommendation(
                mode: .intervals,
                headline: "Keep Drilling Intervals",
                reason: "Accuracy at \(Int(acc * 100))% — consistent reps is how it climbs.",
                cta: "Continue"
            )
        }

        return TodayRecommendation(
            mode: .intervals,
            headline: "Keep Building",
            reason: "Steady daily practice compounds. Even 10 minutes moves the needle.",
            cta: "Continue"
        )
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

    /// Deletes all trial and session data. Resets in-memory stats immediately.
    public func clearAllProgress() {
        do {
            try db.dbQueue.write { d in
                try d.execute(sql: "DELETE FROM trials")
                try d.execute(sql: "DELETE FROM sessions")
                try d.execute(sql: "DELETE FROM app_state WHERE key != 'json_migrated'")
            }
        } catch {
            progressLog.error("clearAllProgress DB failed: \(error.localizedDescription, privacy: .public)")
        }
        UserDefaults.standard.removeObject(forKey: "lastSessionDate")
        UserDefaults.standard.removeObject(forKey: "difficultyLevel_contour")
        UserDefaults.standard.removeObject(forKey: "difficultyLevel_intervals")
        UserDefaults.standard.removeObject(forKey: "difficultyLevel_identification")
        clearAllStreakRecords()
        stats = SessionLogger.CumulativeStats()
    }

    private func streakKey(_ modeKey: String, _ difficulty: Int) -> String {
        "longestStreak_\(modeKey)_\(difficulty)"
    }

    // MARK: - GRDB-backed per-trial queries

    /// Recent accuracy for a primitive over the last `window` trials.
    /// Returns nil if fewer than 5 trials exist.
    public func recentAccuracy(primitive: String, window: Int = 20) -> Double? {
        do {
            let rows = try db.dbQueue.read { d in
                try Row.fetchAll(d, sql: """
                    SELECT correct FROM trials
                    WHERE primitive = ?
                    ORDER BY ts DESC LIMIT ?
                    """, arguments: [primitive, window])
            }
            guard rows.count >= 5 else { return nil }
            let correct = rows.reduce(0) { $0 + (Int.fromDatabaseValue($1["correct"]) ?? 0) }
            return Double(correct) / Double(rows.count)
        } catch {
            progressLog.error("recentAccuracy failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Total trial count for a primitive from the DB.
    public func dbTrialCount(primitive: String) -> Int {
        (try? db.dbQueue.read { d in
            try Int.fetchOne(d,
                sql: "SELECT COUNT(*) FROM trials WHERE primitive = ?",
                arguments: [primitive]) ?? 0
        }) ?? 0
    }

    /// Contour note pairs with ≥ `minTrials` trials, sorted by error rate descending.
    /// Used by ContourSampler (Phase 1.7) to weight problem pairs more heavily.
    ///
    /// Phase 1.6: computes over all recorded trials (no recency window).
    /// Phase 1.7 will add per-window filtering once the mastery engine is in place.
    public func contourProblemPairs(minTrials: Int = 5,
                                    window: Int = 20
    ) -> [(note1: Int, note2: Int, recentErrorRate: Double)] {
        do {
            let rows = try db.dbQueue.read { d in
                try Row.fetchAll(d, sql: """
                    SELECT note1_midi, note2_midi,
                           1.0 - AVG(CAST(correct AS REAL)) AS error_rate,
                           COUNT(*) AS n
                    FROM trials
                    WHERE primitive = 'contour'
                      AND note1_midi IS NOT NULL
                      AND note2_midi IS NOT NULL
                    GROUP BY note1_midi, note2_midi
                    HAVING COUNT(*) >= ?
                    ORDER BY error_rate DESC
                    """, arguments: [minTrials])
            }
            return rows.compactMap { row -> (Int, Int, Double)? in
                guard let n1: Int = Int.fromDatabaseValue(row["note1_midi"]),
                      let n2: Int = Int.fromDatabaseValue(row["note2_midi"]) else { return nil }
                let err: Double = Double.fromDatabaseValue(row["error_rate"]) ?? 0
                return (n1, n2, err)
            }
        } catch {
            progressLog.error("contourProblemPairs failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}
