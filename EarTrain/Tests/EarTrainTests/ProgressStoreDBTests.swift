import XCTest
import GRDB
@testable import EarTrainLib

/// Tests that ProgressStore.reload() correctly builds CumulativeStats from the DB,
/// and that per-trial query methods return accurate results.
@MainActor
final class ProgressStoreDBTests: XCTestCase {

    var db: AudieDatabase!
    var store: ProgressStore!

    override func setUp() async throws {
        db    = try AudieDatabase.makeInMemory()
        store = ProgressStore(database: db)
    }

    // MARK: - Totals

    func testReloadEmptyDatabase() {
        store.reload()
        XCTAssertEqual(store.stats.totalTrials,   0)
        XCTAssertEqual(store.stats.totalSessions, 0)
    }

    func testReloadTotalTrials() throws {
        let logger = SessionLogger(primitive: "contour", database: db)
        for _ in 0..<5 {
            logger.logContourTrial(rootHz: 440, semitones: 5, direction: "higher",
                                   correct: true, difficulty: 3, note1Midi: 69, note2Midi: 74)
        }
        logger.endSession()
        store.reload()
        XCTAssertEqual(store.stats.totalTrials, 5)
    }

    func testReloadTotalSessions() throws {
        let logger1 = SessionLogger(primitive: "contour", database: db)
        logger1.logContourTrial(rootHz: 440, semitones: 5, direction: "higher",
                                correct: true, difficulty: 3, note1Midi: 69, note2Midi: 74)
        logger1.endSession()

        let logger2 = SessionLogger(primitive: "contour", database: db)
        logger2.logContourTrial(rootHz: 440, semitones: 5, direction: "higher",
                                correct: false, difficulty: 3, note1Midi: 69, note2Midi: 74)
        logger2.endSession()

        store.reload()
        XCTAssertEqual(store.stats.totalSessions, 2)
    }

    // MARK: - Contour matrix

    func testReloadContourCorrectCounts() throws {
        let logger = SessionLogger(primitive: "contour", database: db)
        // 3 correct, 1 wrong for m3 in mid register
        for _ in 0..<3 {
            logger.logContourTrial(rootHz: 261.6, semitones: 3, direction: "higher",
                                   correct: true, difficulty: 3, note1Midi: 60, note2Midi: 63)
        }
        logger.logContourTrial(rootHz: 261.6, semitones: 3, direction: "higher",
                               correct: false, difficulty: 3, note1Midi: 60, note2Midi: 63)
        logger.endSession()
        store.reload()

        let counts = store.contourCounts(for: "m3")
        XCTAssertNotNil(counts)
        XCTAssertEqual(counts?.total,   4)
        XCTAssertEqual(counts?.correct, 3)
        XCTAssertEqual(counts?.accuracy ?? 0, 0.75, accuracy: 0.01)
    }

    func testHasContourDataTrueAfterContourSession() throws {
        let logger = SessionLogger(primitive: "contour", database: db)
        logger.logContourTrial(rootHz: 440, semitones: 5, direction: "higher",
                               correct: true, difficulty: 3, note1Midi: 69, note2Midi: 74)
        logger.endSession()
        store.reload()
        XCTAssertTrue(store.hasContourData)
    }

    func testHasContourDataFalseForEmptyDB() {
        store.reload()
        XCTAssertFalse(store.hasContourData)
    }

    // MARK: - Interval matrix

    func testReloadMatrixPlayback() throws {
        let logger = SessionLogger(primitive: "interval-playback", database: db)
        // Root E4 (330 Hz) → mid register (175–440 Hz exclusive upper bound)
        logger.logTrial(interval: .P5, rootHz: 330, detectedHz: 494.0,
                        result: .correct, difficulty: 3)
        logger.logTrial(interval: .P5, rootHz: 330, detectedHz: 420,
                        result: .wrong(played: .m3), difficulty: 3)
        logger.logTrial(interval: .P5, rootHz: 330, detectedHz: 460,
                        result: .close(played: .M6), difficulty: 3)
        logger.endSession()
        store.reload()

        let counts = store.counts(for: .P5, register: .mid)
        XCTAssertNotNil(counts)
        XCTAssertEqual(counts?.correct, 1)
        XCTAssertEqual(counts?.wrong,   1)
        XCTAssertEqual(counts?.close,   1)
        XCTAssertEqual(counts?.total,   3)
    }

    func testReloadMatrixIdentification() throws {
        let logger = SessionLogger(primitive: "interval-id", database: db)
        // 330 Hz → mid register
        logger.logIdentificationTrial(interval: .m3, rootHz: 330,
                                      correct: true, difficulty: 2)
        logger.logIdentificationTrial(interval: .m3, rootHz: 330,
                                      correct: false, difficulty: 2)
        logger.endSession()
        store.reload()

        let counts = store.counts(for: .m3, register: .mid)
        XCTAssertNotNil(counts)
        XCTAssertEqual(counts?.correct, 1)
        XCTAssertEqual(counts?.wrong,   1)
    }

    // MARK: - Derived stats

    func testOverallAccuracyNilForEmptyDB() {
        store.reload()
        XCTAssertNil(store.overallAccuracy)
    }

    func testOverallAccuracy() throws {
        let logger = SessionLogger(primitive: "interval-playback", database: db)
        for _ in 0..<7 {
            logger.logTrial(interval: .P5, rootHz: 440, detectedHz: 660,
                            result: .correct, difficulty: 3)
        }
        for _ in 0..<3 {
            logger.logTrial(interval: .P5, rootHz: 440, detectedHz: 600,
                            result: .wrong(played: .m3), difficulty: 3)
        }
        logger.endSession()
        store.reload()

        let acc = store.overallAccuracy
        XCTAssertNotNil(acc)
        XCTAssertEqual(acc!, 0.70, accuracy: 0.01)
    }

    func testHasDrillableDataFalseForFewTrials() throws {
        let logger = SessionLogger(primitive: "interval-playback", database: db)
        // Only 3 trials — below the 5-trial minimum
        for _ in 0..<3 {
            logger.logTrial(interval: .m3, rootHz: 440, detectedHz: 500,
                            result: .wrong(played: .M3), difficulty: 3)
        }
        logger.endSession()
        store.reload()
        XCTAssertFalse(store.hasDrillableData)
    }

    func testHasDrillableDataTrueWhenHighErrorRate() throws {
        let logger = SessionLogger(primitive: "interval-playback", database: db)
        // 6 wrong, 0 correct → 100% error rate, above 5-trial threshold
        for _ in 0..<6 {
            logger.logTrial(interval: .m3, rootHz: 440, detectedHz: 500,
                            result: .wrong(played: .M3), difficulty: 3)
        }
        logger.endSession()
        store.reload()
        XCTAssertTrue(store.hasDrillableData)
    }

    // MARK: - GRDB per-trial queries

    func testDbTrialCountPerPrimitive() throws {
        let c = SessionLogger(primitive: "contour", database: db)
        let p = SessionLogger(primitive: "interval-playback", database: db)
        for _ in 0..<4 {
            c.logContourTrial(rootHz: 440, semitones: 5, direction: "higher",
                              correct: true, difficulty: 3, note1Midi: 69, note2Midi: 74)
        }
        for _ in 0..<7 {
            p.logTrial(interval: .P5, rootHz: 440, detectedHz: 660,
                       result: .correct, difficulty: 3)
        }
        XCTAssertEqual(store.dbTrialCount(primitive: "contour"),           4)
        XCTAssertEqual(store.dbTrialCount(primitive: "interval-playback"), 7)
        XCTAssertEqual(store.dbTrialCount(primitive: "interval-id"),       0)
    }

    func testRecentAccuracyNilForFewTrials() throws {
        let logger = SessionLogger(primitive: "contour", database: db)
        for _ in 0..<3 {
            logger.logContourTrial(rootHz: 440, semitones: 5, direction: "higher",
                                   correct: true, difficulty: 3, note1Midi: 69, note2Midi: 74)
        }
        XCTAssertNil(store.recentAccuracy(primitive: "contour", window: 20))
    }

    func testRecentAccuracyRespectsWindow() throws {
        let logger = SessionLogger(primitive: "contour", database: db)
        // Log 15 wrong trials, then 10 correct — with window=10, only correct trials are seen
        for _ in 0..<15 {
            logger.logContourTrial(rootHz: 440, semitones: 5, direction: "higher",
                                   correct: false, difficulty: 3, note1Midi: 69, note2Midi: 74)
        }
        for _ in 0..<10 {
            logger.logContourTrial(rootHz: 440, semitones: 5, direction: "higher",
                                   correct: true, difficulty: 3, note1Midi: 69, note2Midi: 74)
        }
        // window=10 should see only the 10 correct (most recent), so accuracy = 1.0
        let acc = store.recentAccuracy(primitive: "contour", window: 10)
        XCTAssertNotNil(acc)
        XCTAssertEqual(acc!, 1.0, accuracy: 0.01)
    }

    func testContourProblemPairsRankedByErrorRate() throws {
        let logger = SessionLogger(primitive: "contour", database: db)
        // Pair (69, 72): 1/5 correct = 80% error rate
        for _ in 0..<1 {
            logger.logContourTrial(rootHz: 440, semitones: 3, direction: "higher",
                                   correct: true, difficulty: 3, note1Midi: 69, note2Midi: 72)
        }
        for _ in 0..<4 {
            logger.logContourTrial(rootHz: 440, semitones: 3, direction: "higher",
                                   correct: false, difficulty: 3, note1Midi: 69, note2Midi: 72)
        }
        // Pair (60, 65): 4/5 correct = 20% error rate
        for _ in 0..<4 {
            logger.logContourTrial(rootHz: 261.6, semitones: 5, direction: "higher",
                                   correct: true, difficulty: 3, note1Midi: 60, note2Midi: 65)
        }
        for _ in 0..<1 {
            logger.logContourTrial(rootHz: 261.6, semitones: 5, direction: "higher",
                                   correct: false, difficulty: 3, note1Midi: 60, note2Midi: 65)
        }

        // Verify the trials are actually in the DB before querying pairs
        let trialCount = try db.dbQueue.read { d in
            try Int.fetchOne(d,
                sql: "SELECT COUNT(*) FROM trials WHERE primitive = 'contour' AND note1_midi IS NOT NULL") ?? 0
        }
        XCTAssertEqual(trialCount, 10, "Must have 10 contour trials with note1_midi set before testing pairs")

        // Verify the GROUP BY query works at all (no HAVING)
        let allPairRows = try db.dbQueue.read { d in
            try Row.fetchAll(d, sql: """
                SELECT note1_midi, note2_midi, COUNT(*) AS n
                FROM trials WHERE primitive = 'contour' AND note1_midi IS NOT NULL
                GROUP BY note1_midi, note2_midi
                """)
        }
        XCTAssertEqual(allPairRows.count, 2, "Should have 2 distinct note pairs in GROUP BY")

        let pairs = store.contourProblemPairs(minTrials: 5, window: 20)
        XCTAssertEqual(pairs.count, 2)
        // Pair (69,72) should be first — highest error rate
        XCTAssertEqual(pairs[0].note1, 69)
        XCTAssertEqual(pairs[0].note2, 72)
        XCTAssertGreaterThan(pairs[0].recentErrorRate, pairs[1].recentErrorRate)
    }

    // MARK: - clearAllProgress

    func testClearAllProgressWipesDB() throws {
        let logger = SessionLogger(primitive: "contour", database: db)
        for _ in 0..<5 {
            logger.logContourTrial(rootHz: 440, semitones: 5, direction: "higher",
                                   correct: true, difficulty: 3, note1Midi: 69, note2Midi: 74)
        }
        logger.endSession()
        store.reload()
        XCTAssertEqual(store.stats.totalTrials, 5)

        store.clearAllProgress()
        XCTAssertEqual(store.stats.totalTrials,   0)
        XCTAssertEqual(store.stats.totalSessions, 0)

        // Verify DB is also empty
        let trialCount = try db.dbQueue.read { d in
            try Int.fetchOne(d, sql: "SELECT COUNT(*) FROM trials") ?? 0
        }
        XCTAssertEqual(trialCount, 0)
    }
}
