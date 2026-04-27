import XCTest
import GRDB
@testable import EarTrainLib

/// Tests that SessionLogger writes correct rows to the trials and sessions tables.
final class SessionLoggerDBTests: XCTestCase {

    var db: AudieDatabase!

    override func setUp() async throws {
        db = try AudieDatabase.makeInMemory()
    }

    // MARK: - Session row lifecycle

    func testSessionRowCreatedOnInit() throws {
        let logger = SessionLogger(primitive: "contour", database: db)
        let count = try db.dbQueue.read { d in
            try Int.fetchOne(d, sql: "SELECT COUNT(*) FROM sessions WHERE id = ?",
                             arguments: [logger.sessionId]) ?? 0
        }
        XCTAssertEqual(count, 1, "Session row should be created in init")
    }

    func testSessionRowContainsPrimitive() throws {
        let logger = SessionLogger(primitive: "interval-playback", database: db)
        let primitive = try db.dbQueue.read { d in
            try String.fetchOne(d,
                sql: "SELECT primitive FROM sessions WHERE id = ?",
                arguments: [logger.sessionId])
        }
        XCTAssertEqual(primitive, "interval-playback")
    }

    func testSessionRowContainsTimbre() throws {
        let logger = SessionLogger(primitive: "contour", timbre: "acoustic", database: db)
        let timbre = try db.dbQueue.read { d in
            try String.fetchOne(d,
                sql: "SELECT timbre FROM sessions WHERE id = ?",
                arguments: [logger.sessionId])
        }
        XCTAssertEqual(timbre, "acoustic")
    }

    func testSessionRowContainsPlanId() throws {
        let logger = SessionLogger(primitive: "contour", planId: "beginner-ci",
                                   planStep: 2, database: db)
        let row = try db.dbQueue.read { d in
            try Row.fetchOne(d,
                sql: "SELECT plan_id, plan_step FROM sessions WHERE id = ?",
                arguments: [logger.sessionId])
        }
        XCTAssertEqual(row.flatMap { r -> String? in r["plan_id"] }, "beginner-ci")
        XCTAssertEqual(row.flatMap { r -> Int? in r["plan_step"] }, 2)
    }

    func testEndSessionUpdatesRow() throws {
        let logger = SessionLogger(primitive: "contour", database: db)
        logger.logContourTrial(rootHz: 440, semitones: 5, direction: "higher",
                               correct: true, difficulty: 3, note1Midi: 69, note2Midi: 74)
        logger.logContourTrial(rootHz: 440, semitones: 5, direction: "higher",
                               correct: false, difficulty: 3, note1Midi: 69, note2Midi: 74)
        logger.endSession()

        let row = try db.dbQueue.read { d in
            try Row.fetchOne(d,
                sql: "SELECT total_trials, correct_trials, ended_at FROM sessions WHERE id = ?",
                arguments: [logger.sessionId])
        }
        XCTAssertEqual(row.flatMap { r -> Int? in r["total_trials"]   }, 2)
        XCTAssertEqual(row.flatMap { r -> Int? in r["correct_trials"] }, 1)
        XCTAssertNotNil(row.flatMap { r -> Int? in r["ended_at"] }, "ended_at should be set after endSession")
    }

    // MARK: - Contour trials

    func testContourTrialRowWritten() throws {
        let logger = SessionLogger(primitive: "contour", database: db)
        logger.logContourTrial(rootHz: 440, semitones: 4, direction: "higher",
                               correct: true, difficulty: 3, note1Midi: 69, note2Midi: 73)

        let count = try db.dbQueue.read { d in
            try Int.fetchOne(d,
                sql: "SELECT COUNT(*) FROM trials WHERE session_id = ?",
                arguments: [logger.sessionId]) ?? 0
        }
        XCTAssertEqual(count, 1)
    }

    func testContourTrialPrimitive() throws {
        let logger = SessionLogger(primitive: "contour", database: db)
        logger.logContourTrial(rootHz: 440, semitones: 4, direction: "higher",
                               correct: true, difficulty: 3, note1Midi: 69, note2Midi: 73)

        let primitive = try db.dbQueue.read { d in
            try String.fetchOne(d,
                sql: "SELECT primitive FROM trials WHERE session_id = ?",
                arguments: [logger.sessionId])
        }
        XCTAssertEqual(primitive, "contour")
    }

    func testContourTrialDifficulty() throws {
        let logger = SessionLogger(primitive: "contour", database: db)
        logger.logContourTrial(rootHz: 440, semitones: 4, direction: "higher",
                               correct: true, difficulty: 5, note1Midi: 69, note2Midi: 73)

        let diff = try db.dbQueue.read { d in
            try Int.fetchOne(d,
                sql: "SELECT difficulty FROM trials WHERE session_id = ?",
                arguments: [logger.sessionId]) ?? 0
        }
        XCTAssertEqual(diff, 5)
    }

    func testContourTrialMidiNotes() throws {
        let logger = SessionLogger(primitive: "contour", database: db)
        logger.logContourTrial(rootHz: 440, semitones: 3, direction: "higher",
                               correct: true, difficulty: 2, note1Midi: 69, note2Midi: 72)

        let row = try db.dbQueue.read { d in
            try Row.fetchOne(d,
                sql: "SELECT note1_midi, note2_midi, semitone_gap FROM trials WHERE session_id = ?",
                arguments: [logger.sessionId])
        }
        XCTAssertEqual(row.flatMap { r -> Int? in r["note1_midi"]   }, 69)
        XCTAssertEqual(row.flatMap { r -> Int? in r["note2_midi"]   }, 72)
        XCTAssertEqual(row.flatMap { r -> Int? in r["semitone_gap"] }, 3)
    }

    func testContourCorrectFlag() throws {
        let logger = SessionLogger(primitive: "contour", database: db)
        logger.logContourTrial(rootHz: 440, semitones: 4, direction: "higher",
                               correct: true, difficulty: 3, note1Midi: 69, note2Midi: 73)
        logger.logContourTrial(rootHz: 440, semitones: 4, direction: "higher",
                               correct: false, difficulty: 3, note1Midi: 69, note2Midi: 73)

        let rows = try db.dbQueue.read { d in
            try Row.fetchAll(d,
                sql: "SELECT correct FROM trials WHERE session_id = ? ORDER BY id",
                arguments: [logger.sessionId])
        }
        let v0: Int? = rows[0]["correct"]
        let v1: Int? = rows[1]["correct"]
        XCTAssertEqual(v0, 1)
        XCTAssertEqual(v1, 0)
    }

    // MARK: - Playback trials

    func testPlaybackTrialCorrectResultDetail() throws {
        let logger = SessionLogger(primitive: "interval-playback", database: db)
        logger.logTrial(interval: .P5, rootHz: 440, detectedHz: 660,
                        result: .correct, difficulty: 3)

        let detail = try db.dbQueue.read { d in
            try String.fetchOne(d,
                sql: "SELECT result_detail FROM trials WHERE session_id = ?",
                arguments: [logger.sessionId])
        }
        XCTAssertEqual(detail, "correct")
    }

    func testPlaybackTrialCloseResultDetail() throws {
        let logger = SessionLogger(primitive: "interval-playback", database: db)
        logger.logTrial(interval: .P5, rootHz: 440, detectedHz: 650,
                        result: .close(played: .P4), difficulty: 3)

        let detail = try db.dbQueue.read { d in
            try String.fetchOne(d,
                sql: "SELECT result_detail FROM trials WHERE session_id = ?",
                arguments: [logger.sessionId])
        }
        XCTAssertEqual(detail, "close")
    }

    func testPlaybackTrialNoRead() throws {
        let logger = SessionLogger(primitive: "interval-playback", database: db)
        logger.logNoRead(interval: .m3, rootHz: 440, difficulty: 2)

        let detail = try db.dbQueue.read { d in
            try String.fetchOne(d,
                sql: "SELECT result_detail FROM trials WHERE session_id = ?",
                arguments: [logger.sessionId])
        }
        XCTAssertEqual(detail, "no_read")
    }

    func testPlaybackTrialIntervalName() throws {
        let logger = SessionLogger(primitive: "interval-playback", database: db)
        logger.logTrial(interval: .m3, rootHz: 440, detectedHz: 523,
                        result: .correct, difficulty: 3)

        let name = try db.dbQueue.read { d in
            try String.fetchOne(d,
                sql: "SELECT interval_name FROM trials WHERE session_id = ?",
                arguments: [logger.sessionId])
        }
        XCTAssertEqual(name, "m3")
    }

    // MARK: - Identification trials

    func testIdentificationTrialPrimitive() throws {
        let logger = SessionLogger(primitive: "interval-id", database: db)
        logger.logIdentificationTrial(interval: .P4, rootHz: 440,
                                      correct: true, difficulty: 2)

        let primitive = try db.dbQueue.read { d in
            try String.fetchOne(d,
                sql: "SELECT primitive FROM trials WHERE session_id = ?",
                arguments: [logger.sessionId])
        }
        XCTAssertEqual(primitive, "interval-id")
    }

    func testIdentificationTrialResultDetail() throws {
        let logger = SessionLogger(primitive: "interval-id", database: db)
        logger.logIdentificationTrial(interval: .P4, rootHz: 440,
                                      correct: false, difficulty: 2)

        let detail = try db.dbQueue.read { d in
            try String.fetchOne(d,
                sql: "SELECT result_detail FROM trials WHERE session_id = ?",
                arguments: [logger.sessionId])
        }
        XCTAssertEqual(detail, "wrong")
    }

    // MARK: - Helper

    func testIntervalNameForSemitones() {
        XCTAssertEqual(SessionLogger.intervalName(forSemitones: 3),  "m3")
        XCTAssertEqual(SessionLogger.intervalName(forSemitones: 7),  "P5")
        XCTAssertEqual(SessionLogger.intervalName(forSemitones: 12), "P8")
        XCTAssertEqual(SessionLogger.intervalName(forSemitones: 1),  "m2")
    }
}
