import Foundation
import GRDB

/// Weighted sampler for contour note-pair selection.
///
/// Weights are inverse of recent accuracy per (gap-group × octave-band) bucket.
/// Unseen buckets get a slight priority (1.5×) to encourage coverage.
/// User-flagged pairs ("Flag as tricky") get a permanent 0.8 error-rate equivalent boost.
/// Weights refresh every `refreshInterval` trials.
public final class ContourSampler {

    // MARK: - Types

    private struct BucketEntry {
        let gapRange:  ClosedRange<Int>
        let midiRange: ClosedRange<Int>
        var weight:    Double
    }

    // MARK: - State

    private let refreshInterval = 10
    private var trialsSinceRefresh = 0
    private var buckets: [BucketEntry] = []
    private var pairBoosts: [String: Double] = [:]

    // MARK: - Init

    public init() {
        refreshWeights()
    }

    // MARK: - Public API

    public func recordTrial() {
        trialsSinceRefresh += 1
        if trialsSinceRefresh >= refreshInterval {
            refreshWeights()
            trialsSinceRefresh = 0
        }
    }

    /// Returns (semitoneGap, lowerNoteMidi) sampled by weight.
    /// `lowerNoteMidi` is always the smaller of the two notes — caller determines playback order.
    public func sample(availableGapRange: ClosedRange<Int>,
                       availableMidiRange: ClosedRange<Int>) -> (gap: Int, lowerNoteMidi: Int) {
        let applicable = buckets.filter {
            overlap($0.gapRange, availableGapRange) && overlap($0.midiRange, availableMidiRange)
        }
        guard !applicable.isEmpty else {
            return (Int.random(in: availableGapRange), Int.random(in: availableMidiRange))
        }

        let chosen   = weightedRandom(from: applicable)
        let gapR     = chosen.gapRange.clamped(to: availableGapRange)
        let midiR    = chosen.midiRange.clamped(to: availableMidiRange)
        let gap      = Int.random(in: gapR)
        var midi     = Int.random(in: midiR)

        // Prefer a problem/flagged pair when one exists in this bucket
        let alt = Int.random(in: midiR)
        if (pairBoosts["\(alt)-\(alt + gap)"] ?? 0) > (pairBoosts["\(midi)-\(midi + gap)"] ?? 0) {
            midi = alt
        }

        return (gap, midi)
    }

    // MARK: - Weight refresh

    func refreshWeights() {
        let window = MasterySettings.recencyWindow
        let octaves: [ClosedRange<Int>] = [28...39, 40...51, 52...63, 64...81]

        var newBuckets: [BucketEntry] = []
        for gap in MasteryEngine.gapGroups {
            for oct in octaves {
                let acc = bucketAccuracy(gapRange: gap.range, midiRange: oct, window: window)
                let weight: Double
                if let a = acc {
                    weight = max(0.2, min(5.0, 1.0 - a + 0.5))
                } else {
                    weight = 1.5
                }
                newBuckets.append(BucketEntry(gapRange: gap.range, midiRange: oct, weight: weight))
            }
        }
        buckets = newBuckets
        buildPairBoosts(window: window)
    }

    // MARK: - Private helpers

    private func bucketAccuracy(gapRange: ClosedRange<Int>,
                                 midiRange: ClosedRange<Int>,
                                 window: Int) -> Double? {
        let rows = (try? AudieDatabase.shared.dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT correct FROM trials
                WHERE primitive     = 'contour'
                  AND semitone_gap >= ? AND semitone_gap <= ?
                  AND note1_midi   >= ? AND note1_midi   <= ?
                ORDER BY ts DESC LIMIT ?
                """,
                arguments: [gapRange.lowerBound, gapRange.upperBound,
                            midiRange.lowerBound, midiRange.upperBound, window])
        }) ?? []

        guard rows.count >= 3 else { return nil }

        let correctCount = rows.filter { row -> Bool in
            let c: Int? = row["correct"]
            return c == 1
        }.count
        return Double(correctCount) / Double(rows.count)
    }

    private func buildPairBoosts(window: Int) {
        var boosts: [String: Double] = [:]

        // DB-derived problem pairs
        let rows = (try? AudieDatabase.shared.dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT note1_midi, note2_midi,
                       1.0 - AVG(CAST(correct AS REAL)) AS error_rate
                FROM trials
                WHERE primitive = 'contour'
                  AND note1_midi IS NOT NULL AND note2_midi IS NOT NULL
                GROUP BY note1_midi, note2_midi
                HAVING COUNT(*) >= 5 AND (1.0 - AVG(CAST(correct AS REAL))) > 0.3
                ORDER BY error_rate DESC
                """)
        }) ?? []

        for row in rows {
            let n1: Int? = row["note1_midi"]
            let n2: Int? = row["note2_midi"]
            let err: Double? = row["error_rate"]
            if let n1, let n2, let err {
                boosts["\(n1)-\(n2)"] = err
            }
        }

        // User-flagged pairs get a high fixed boost
        let flagRows = (try? AudieDatabase.shared.dbQueue.read { db in
            try Row.fetchAll(db,
                sql: "SELECT key FROM app_state WHERE key LIKE 'flagged_pair_%'")
        }) ?? []

        for row in flagRows {
            let k: String? = row["key"]
            guard let k else { continue }
            let parts = k.dropFirst("flagged_pair_".count).split(separator: "_")
            guard parts.count == 2,
                  let n1 = Int(parts[0]),
                  let n2 = Int(parts[1]) else { continue }
            let key = "\(n1)-\(n2)"
            boosts[key] = max(boosts[key] ?? 0, 0.8)
        }

        pairBoosts = boosts
    }

    private func weightedRandom(from entries: [BucketEntry]) -> BucketEntry {
        let total = entries.reduce(0.0) { $0 + $1.weight }
        var r = Double.random(in: 0..<total)
        for entry in entries {
            r -= entry.weight
            if r <= 0 { return entry }
        }
        return entries.last!
    }

    private func overlap(_ a: ClosedRange<Int>, _ b: ClosedRange<Int>) -> Bool {
        a.lowerBound <= b.upperBound && b.lowerBound <= a.upperBound
    }
}
