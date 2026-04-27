import Foundation
import GRDB
import os.log

private let dbLog = Logger(subsystem: "com.audie", category: "database")

// MARK: - AudieDatabase

/// Wraps the GRDB DatabaseQueue for the app's SQLite store.
///
/// Production: `AudieDatabase.shared` opens `~/Library/Application Support/Audie/audie.db`.
/// Tests: `AudieDatabase.makeInMemory()` returns an isolated in-memory instance.
public final class AudieDatabase {

    // MARK: - Shared instance

    public static let shared: AudieDatabase = {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("Audie", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("audie.db").path
        do {
            return try AudieDatabase(path: path)
        } catch {
            dbLog.error("Failed to open audie.db: \(error.localizedDescription, privacy: .public)")
            fatalError("Cannot open database: \(error)")
        }
    }()

    // MARK: - Factory for tests

    /// Returns an isolated in-memory database. Safe to create multiple times in tests.
    public static func makeInMemory() throws -> AudieDatabase {
        try AudieDatabase(path: nil)
    }

    // MARK: - Core

    public let dbQueue: DatabaseQueue

    init(path: String?) throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        if let path {
            dbQueue = try DatabaseQueue(path: path, configuration: config)
        } else {
            dbQueue = try DatabaseQueue(configuration: config)
        }
        try applyMigrations()
    }

    // MARK: - Migrations

    private func applyMigrations() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS trials (
                    id            INTEGER PRIMARY KEY AUTOINCREMENT,
                    session_id    TEXT    NOT NULL,
                    primitive     TEXT    NOT NULL,
                    ts            INTEGER NOT NULL,
                    difficulty    INTEGER NOT NULL DEFAULT 0,
                    note1_midi    INTEGER,
                    note2_midi    INTEGER,
                    semitone_gap  INTEGER,
                    interval_name TEXT,
                    register      TEXT,
                    correct       INTEGER NOT NULL,
                    result_detail TEXT
                );
                CREATE INDEX IF NOT EXISTS idx_trials_session
                    ON trials(session_id);
                CREATE INDEX IF NOT EXISTS idx_trials_primitive_ts
                    ON trials(primitive, ts);
                CREATE INDEX IF NOT EXISTS idx_trials_pair
                    ON trials(note1_midi, note2_midi);

                CREATE TABLE IF NOT EXISTS sessions (
                    id             TEXT    PRIMARY KEY,
                    primitive      TEXT    NOT NULL,
                    plan_id        TEXT,
                    plan_step      INTEGER,
                    timbre         TEXT,
                    started_at     INTEGER NOT NULL,
                    ended_at       INTEGER,
                    total_trials   INTEGER NOT NULL DEFAULT 0,
                    correct_trials INTEGER NOT NULL DEFAULT 0
                );

                CREATE TABLE IF NOT EXISTS app_state (
                    key   TEXT PRIMARY KEY,
                    value TEXT NOT NULL
                );
                """)
        }

        try migrator.migrate(dbQueue)
    }

    // MARK: - app_state helpers

    public func appState(forKey key: String) -> String? {
        do {
            return try dbQueue.read { db in
                try String.fetchOne(db,
                    sql: "SELECT value FROM app_state WHERE key = ?",
                    arguments: [key])
            }
        } catch {
            dbLog.error("app_state read failed for '\(key, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    public func setAppState(_ value: String, forKey key: String) {
        do {
            try dbQueue.write { db in
                try db.execute(
                    sql: "INSERT OR REPLACE INTO app_state (key, value) VALUES (?, ?)",
                    arguments: [key, value])
            }
        } catch {
            dbLog.error("app_state write failed for '\(key, privacy: .public)': \(error.localizedDescription, privacy: .public)")
        }
    }
}
