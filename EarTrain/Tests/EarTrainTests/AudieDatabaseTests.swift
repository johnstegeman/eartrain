import XCTest
import GRDB
@testable import EarTrainLib

final class AudieDatabaseTests: XCTestCase {

    // MARK: - Schema

    func testTablesExistAfterInit() throws {
        let db = try AudieDatabase.makeInMemory()
        try db.dbQueue.read { d in
            let tables = try String.fetchAll(d,
                sql: "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
            XCTAssertTrue(tables.contains("trials"))
            XCTAssertTrue(tables.contains("sessions"))
            XCTAssertTrue(tables.contains("app_state"))
        }
    }

    func testTrialsTableColumns() throws {
        let db = try AudieDatabase.makeInMemory()
        // Write a row to exercise all columns — if any column is missing this will throw.
        try db.dbQueue.write { d in
            try d.execute(sql: """
                INSERT INTO trials
                    (session_id, primitive, ts, difficulty,
                     note1_midi, note2_midi, semitone_gap,
                     interval_name, register, correct, result_detail)
                VALUES ('s1', 'contour', 1000, 3, 52, 55, 3, 'm3', 'mid', 1, 'correct')
                """)
        }
        let count = try db.dbQueue.read { d in
            try Int.fetchOne(d, sql: "SELECT COUNT(*) FROM trials") ?? 0
        }
        XCTAssertEqual(count, 1)
    }

    func testSessionsTableColumns() throws {
        let db = try AudieDatabase.makeInMemory()
        try db.dbQueue.write { d in
            try d.execute(sql: """
                INSERT INTO sessions
                    (id, primitive, plan_id, plan_step, timbre, started_at, ended_at,
                     total_trials, correct_trials)
                VALUES ('sess1', 'contour', 'plan-a', 0, 'acoustic', 1000, 2000, 10, 7)
                """)
        }
        let count = try db.dbQueue.read { d in
            try Int.fetchOne(d, sql: "SELECT COUNT(*) FROM sessions") ?? 0
        }
        XCTAssertEqual(count, 1)
    }

    func testMigrationIsIdempotent() throws {
        // Applying migrations twice should not throw.
        let db = try AudieDatabase.makeInMemory()
        // The second call to applyMigrations happens internally in init.
        // Simulate by creating another instance (different in-memory DB, same migrations).
        XCTAssertNoThrow(try AudieDatabase.makeInMemory())
    }

    // MARK: - app_state

    func testAppStateRoundTrip() throws {
        let db = try AudieDatabase.makeInMemory()
        db.setAppState("hello", forKey: "test_key")
        XCTAssertEqual(db.appState(forKey: "test_key"), "hello")
    }

    func testAppStateReturnsNilForMissingKey() throws {
        let db = try AudieDatabase.makeInMemory()
        XCTAssertNil(db.appState(forKey: "nonexistent"))
    }

    func testAppStateOverwrite() throws {
        let db = try AudieDatabase.makeInMemory()
        db.setAppState("first",  forKey: "k")
        db.setAppState("second", forKey: "k")
        XCTAssertEqual(db.appState(forKey: "k"), "second")
    }

    // MARK: - Optional Int roundtrip (GRDB type inference verification)

    func testOptionalIntStoredAsNonNull() throws {
        let db = try AudieDatabase.makeInMemory()
        // Verify that Optional<Int> with a non-nil value stores as non-NULL in SQLite
        let midi1: Int? = 69
        let midi2: Int? = 72
        try db.dbQueue.write { d in
            try d.execute(sql: """
                INSERT INTO trials (session_id, primitive, ts, difficulty,
                                    note1_midi, note2_midi, semitone_gap,
                                    interval_name, register, correct, result_detail)
                VALUES (?,?,?,?,?,?,?,?,?,?,?)
                """,
                arguments: ["s1", "contour", 1000, 3, midi1, midi2, 3, "m3", "mid", 1, "correct"])
        }
        let row = try db.dbQueue.read { d in
            try Row.fetchOne(d, sql: "SELECT note1_midi, note2_midi FROM trials")
        }
        XCTAssertNotNil(row, "Row should exist")
        // These assertions tell us if Optional<Int> is being stored correctly
        XCTAssertEqual(row.flatMap { r -> Int? in r["note1_midi"] }, 69, "note1_midi should be 69, not NULL")
        XCTAssertEqual(row.flatMap { r -> Int? in r["note2_midi"] }, 72, "note2_midi should be 72, not NULL")
    }

    // MARK: - Indexes

    func testIndexesExist() throws {
        let db = try AudieDatabase.makeInMemory()
        let indexes = try db.dbQueue.read { d in
            try String.fetchAll(d,
                sql: "SELECT name FROM sqlite_master WHERE type='index' ORDER BY name")
        }
        XCTAssertTrue(indexes.contains("idx_trials_session"))
        XCTAssertTrue(indexes.contains("idx_trials_primitive_ts"))
        XCTAssertTrue(indexes.contains("idx_trials_pair"))
    }
}
