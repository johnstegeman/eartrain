import XCTest
@testable import EarTrainLib

/// End-to-end tests simulating complete exercise sessions.
///
/// Both SessionLogger and ProgressStore are created with the same in-memory database.
/// endSession() posts earTrainSessionDidEnd, which triggers ProgressStore.reload().
/// These tests verify that the full flow produces correct observable state.
@MainActor
final class SessionIntegrationTests: XCTestCase {

    var db: AudieDatabase!
    var store: ProgressStore!

    override func setUp() async throws {
        db    = try AudieDatabase.makeInMemory()
        store = ProgressStore(database: db)
    }

    // MARK: - Contour session

    func testContourSessionFlowUpdatesStats() async throws {
        let logger = SessionLogger(primitive: "contour", database: db)

        for i in 0..<10 {
            logger.logContourTrial(
                rootHz: 440, semitones: 4 + (i % 3), direction: "higher",
                correct: i % 3 != 0,  // 7 correct, 3 wrong
                difficulty: 3,
                note1Midi: 69, note2Midi: 69 + 4 + (i % 3)
            )
        }
        logger.endSession()

        // Reload happens synchronously since we call it directly here.
        // In production it's triggered by the notification.
        store.reload()

        XCTAssertEqual(store.stats.totalTrials,   10)
        XCTAssertEqual(store.stats.totalSessions, 1)
        XCTAssertTrue(store.hasContourData)
        XCTAssertFalse(store.stats.matrix.isEmpty == false,
                       "Contour trials should not appear in interval matrix")
        XCTAssertTrue(store.stats.contour.values
            .flatMap { $0.values }
            .reduce(0) { $0 + $1.total } == 10)
    }

    func testContourSessionDoesNotPollutematrix() async throws {
        let logger = SessionLogger(primitive: "contour", database: db)
        for _ in 0..<5 {
            logger.logContourTrial(rootHz: 440, semitones: 5, direction: "higher",
                                   correct: true, difficulty: 3, note1Midi: 69, note2Midi: 74)
        }
        logger.endSession()
        store.reload()
        XCTAssertTrue(store.stats.matrix.isEmpty,
                      "Contour trials must not appear in interval matrix")
    }

    // MARK: - Interval playback session

    func testIntervalPlaybackSessionFlowUpdatesMatrix() async throws {
        let logger = SessionLogger(primitive: "interval-playback", database: db)
        // Root E4 (330 Hz) → mid register (175–440 Hz exclusive)
        logger.logTrial(interval: .P5, rootHz: 330, detectedHz: 494,
                        result: .correct, difficulty: 3)
        logger.logTrial(interval: .P5, rootHz: 330, detectedHz: 420,
                        result: .wrong(played: .m3), difficulty: 3)
        logger.logTrial(interval: .P5, rootHz: 330, detectedHz: 460,
                        result: .close(played: .M6), difficulty: 3)
        logger.logNoRead(interval: .P5, rootHz: 330, difficulty: 3)
        logger.endSession()
        store.reload()

        XCTAssertEqual(store.stats.totalTrials, 4)
        let counts = store.counts(for: .P5, register: .mid)
        XCTAssertNotNil(counts)
        XCTAssertEqual(counts?.correct, 1)
        XCTAssertEqual(counts?.wrong,   1)
        XCTAssertEqual(counts?.close,   1)
        XCTAssertEqual(counts?.noRead,  1)
        XCTAssertEqual(counts?.total,   4)
    }

    func testPlaybackSessionDoesNotPollutContour() async throws {
        let logger = SessionLogger(primitive: "interval-playback", database: db)
        logger.logTrial(interval: .P5, rootHz: 440, detectedHz: 659.3,
                        result: .correct, difficulty: 3)
        logger.endSession()
        store.reload()
        XCTAssertFalse(store.hasContourData)
    }

    // MARK: - Mixed primitives

    func testMultiplePrimitivesTrackedSeparately() async throws {
        let contour  = SessionLogger(primitive: "contour", database: db)
        let playback = SessionLogger(primitive: "interval-playback", database: db)
        let ident    = SessionLogger(primitive: "interval-id", database: db)

        for _ in 0..<5 {
            contour.logContourTrial(rootHz: 440, semitones: 5, direction: "higher",
                                    correct: true, difficulty: 3, note1Midi: 69, note2Midi: 74)
        }
        for _ in 0..<3 {
            playback.logTrial(interval: .m3, rootHz: 330, detectedHz: 393,
                              result: .correct, difficulty: 3)
        }
        for _ in 0..<4 {
            ident.logIdentificationTrial(interval: .P4, rootHz: 330,
                                         correct: true, difficulty: 2)
        }
        contour.endSession()
        playback.endSession()
        ident.endSession()
        store.reload()

        XCTAssertEqual(store.stats.totalTrials,   12)  // 5 + 3 + 4
        XCTAssertEqual(store.stats.totalSessions, 3)
        XCTAssertTrue(store.hasContourData)

        // Matrix should contain both playback and identification
        let m3counts = store.counts(for: .m3, register: .mid)
        let p4counts = store.counts(for: .P4, register: .mid)
        XCTAssertNotNil(m3counts, "interval-playback m3 should appear in matrix")
        XCTAssertNotNil(p4counts, "interval-id P4 should appear in matrix")
        XCTAssertEqual(m3counts?.correct, 3)
        XCTAssertEqual(p4counts?.correct, 4)

        // DB trial count per primitive
        XCTAssertEqual(store.dbTrialCount(primitive: "contour"),           5)
        XCTAssertEqual(store.dbTrialCount(primitive: "interval-playback"), 3)
        XCTAssertEqual(store.dbTrialCount(primitive: "interval-id"),       4)
    }

    // MARK: - Notification triggers reload

    func testEndSessionNotificationTriggersReload() async throws {
        let logger = SessionLogger(primitive: "contour", database: db)
        for _ in 0..<6 {
            logger.logContourTrial(rootHz: 440, semitones: 5, direction: "higher",
                                   correct: true, difficulty: 3, note1Midi: 69, note2Midi: 74)
        }

        XCTAssertEqual(store.stats.totalTrials, 0, "Should be 0 before endSession")

        // endSession posts the notification; ProgressStore observer calls reload()
        logger.endSession()

        // Give the main RunLoop a tick to process the notification
        await Task.yield()
        await MainActor.run { }  // flush any pending main-actor work

        XCTAssertEqual(store.stats.totalTrials, 6,
                       "Stats should update after earTrainSessionDidEnd notification")
    }

    // MARK: - Mastery helpers integration

    func testContourMasteryNotReachedAfterFewTrials() async throws {
        let logger = SessionLogger(primitive: "contour", database: db)
        for _ in 0..<10 {
            logger.logContourTrial(rootHz: 440, semitones: 5, direction: "higher",
                                   correct: true, difficulty: 3, note1Midi: 69, note2Midi: 74)
        }
        logger.endSession()
        store.reload()

        // 10 trials is below any mastery gate threshold
        let (state, _) = MasteryEngine.evaluate()
        XCTAssertNotEqual(state, .gateCleared)
    }

    func testContourTotalTrialsAggregatesAcrossIntervals() async throws {
        let logger = SessionLogger(primitive: "contour", database: db)
        // 8 trials of m3, 7 trials of P4
        for _ in 0..<8 {
            logger.logContourTrial(rootHz: 261.6, semitones: 3, direction: "higher",
                                   correct: true, difficulty: 3, note1Midi: 60, note2Midi: 63)
        }
        for _ in 0..<7 {
            logger.logContourTrial(rootHz: 261.6, semitones: 5, direction: "higher",
                                   correct: true, difficulty: 3, note1Midi: 60, note2Midi: 65)
        }
        logger.endSession()
        store.reload()

        XCTAssertEqual(store.dbTrialCount(primitive: "contour"), 15)
    }
}
