import Foundation
import GRDB

/// Computes contour mastery state from the GRDB trials table.
///
/// The 4×4 bucket grid (semitone-gap-group × octave-band) separates two independent
/// CI difficulty axes: interval type and register/frequency. See MIGRATION_1_7.md and
/// LEARNINGS.md for the clinical rationale.
///
/// Call `evaluate()` synchronously; it's fast (small data, indexed queries).
public struct MasteryEngine {

    // MARK: - Bucket definitions

    public static let gapGroups: [(key: String, range: ClosedRange<Int>)] = [
        ("gap_1_2",  1...2),
        ("gap_3_4",  3...4),
        ("gap_5_6",  5...6),
        ("gap_7_12", 7...12),
    ]

    private static let octaveBands: [(key: String, range: ClosedRange<Int>)] = [
        ("oct_2", 28...39),
        ("oct_3", 40...51),
        ("oct_4", 52...63),
        ("oct_5", 64...127),
    ]

    public static func octaveBand(forMidi midi: Int) -> String {
        octaveBands.first { $0.range.contains(midi) }?.key ?? "oct_5"
    }

    public static func gapGroup(forSemitones gap: Int) -> String? {
        gapGroups.first { $0.range.contains(gap) }?.key
    }

    // MARK: - Result types

    public struct BucketResult {
        public let gapGroup:      String
        public let octaveBand:    String
        public let trialsAtMinDiff: Int
        public let recentAccuracy:  Double?
        public let meetsThreshold:  Bool
        public let isRequired:      Bool
    }

    public enum ContourMasteryState: Equatable {
        case notStarted
        case inProgress(bucketsMet: Int, bucketsRequired: Int, totalTrials: Int)
        case gateCleared
        case advancedEarly
    }

    // MARK: - Evaluation

    public static func evaluate() -> (state: ContourMasteryState, buckets: [BucketResult]) {
        if AudieDatabase.shared.appState(forKey: "contour_advanced_early") == "true" {
            return (.advancedEarly, [])
        }

        let totalTrials = (try? AudieDatabase.shared.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM trials WHERE primitive = 'contour'") ?? 0
        }) ?? 0

        if totalTrials == 0 { return (.notStarted, []) }

        let window    = MasterySettings.recencyWindow
        let minDiff   = MasterySettings.minDifficulty
        let minTrials = MasterySettings.minTrialsPerBucket
        let accuracy  = MasterySettings.accuracyThreshold
        let reqGap1_2 = MasterySettings.requireGap1_2

        var results: [BucketResult] = []
        for gap in gapGroups {
            for band in octaveBands {
                results.append(evaluateBucket(
                    gapKey: gap.key, gapRange: gap.range,
                    bandKey: band.key, midiRange: band.range,
                    window: window, minDiff: minDiff, minTrials: minTrials,
                    accuracy: accuracy, reqGap1_2: reqGap1_2))
            }
        }

        let required = results.filter { $0.isRequired }
        let met      = required.filter { $0.meetsThreshold }

        if met.count == required.count {
            return (.gateCleared, results)
        }
        return (.inProgress(bucketsMet: met.count,
                            bucketsRequired: required.count,
                            totalTrials: totalTrials), results)
    }

    // MARK: - Per-bucket evaluation

    private static func evaluateBucket(
        gapKey: String, gapRange: ClosedRange<Int>,
        bandKey: String, midiRange: ClosedRange<Int>,
        window: Int, minDiff: Int, minTrials: Int,
        accuracy: Double, reqGap1_2: Bool
    ) -> BucketResult {
        let isRequired = !(gapKey == "gap_1_2" && !reqGap1_2)
        let empty = BucketResult(gapGroup: gapKey, octaveBand: bandKey,
                                 trialsAtMinDiff: 0, recentAccuracy: nil,
                                 meetsThreshold: false, isRequired: isRequired)

        guard let rows = try? AudieDatabase.shared.dbQueue.read({ db -> [Row] in
            try Row.fetchAll(db, sql: """
                SELECT correct, difficulty FROM trials
                WHERE primitive     = 'contour'
                  AND semitone_gap >= ? AND semitone_gap <= ?
                  AND note1_midi   >= ? AND note1_midi   <= ?
                ORDER BY ts DESC
                LIMIT ?
                """,
                arguments: [gapRange.lowerBound, gapRange.upperBound,
                            midiRange.lowerBound, midiRange.upperBound,
                            window * 2])
        }) else { return empty }

        // Filter to trials at or above the minimum difficulty
        let atMinDiff = rows.filter { row -> Bool in
            let d: Int? = row["difficulty"]
            return (d ?? 0) >= minDiff
        }
        let recent = Array(atMinDiff.prefix(window))
        let trialsAtMinDiff = recent.count

        guard trialsAtMinDiff >= 5 else {
            return BucketResult(gapGroup: gapKey, octaveBand: bandKey,
                                trialsAtMinDiff: trialsAtMinDiff, recentAccuracy: nil,
                                meetsThreshold: false, isRequired: isRequired)
        }

        let correctCount = recent.filter { row -> Bool in
            let c: Int? = row["correct"]
            return (c ?? 0) == 1
        }.count
        let recentAcc = Double(correctCount) / Double(recent.count)
        let meets = trialsAtMinDiff >= minTrials && recentAcc >= accuracy

        return BucketResult(gapGroup: gapKey, octaveBand: bandKey,
                            trialsAtMinDiff: trialsAtMinDiff,
                            recentAccuracy: recentAcc,
                            meetsThreshold: meets,
                            isRequired: isRequired)
    }
}
