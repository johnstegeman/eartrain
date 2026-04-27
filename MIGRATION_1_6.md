# Migration 1.6 — SQLite via GRDB

**Status: PENDING**

Replace the JSON file storage system (`SessionLogger` + `cumulative.json` + per-session JSON files)
with a single GRDB SQLite database (`audie.db`). All lesson primitives log to the same `trials`
table. Existing JSON data is preserved as a read-only legacy fallback so historical stats survive
the migration.

---

## Read first

- `EarTrain/Sources/EarTrainLib/SessionLogger.swift` — current data model and write paths
- `EarTrain/Sources/EarTrainLib/ProgressStore.swift` — current read paths
- `EarTrain/Sources/EarTrainLib/ContourViewModel.swift` — calls `logContourTrial`
- `EarTrain/Sources/EarTrainLib/ExerciseViewModel.swift` — calls `logTrial` / `logNoRead`
- `EarTrain/Sources/EarTrainLib/IdentificationViewModel.swift` — calls `logIdentificationTrial`
- `DESIGN_SYSTEM.md` "App architecture" — for the primitive naming convention

GRDB 6.29.3 is already resolved in `Package.swift`. Do not add it again.

---

## Why SQLite

The planned mastery engine (Phase 1.7) requires:
- **Per-trial rows** with `difficulty`, `note1_midi`, `note2_midi`, `semitone_gap`, and `ts`
- **Recency queries**: "last 20 trials for this (gap_group × octave_band) bucket"
- **Per-pair aggregate**: sparse map of specific note pairs with low recent accuracy
- **All lesson types** in one place — contour, interval-id, interval-playback, and every future primitive

None of these are feasible with per-session JSON + an aggregated cumulative JSON. SQLite gives
indexed queries, transaction safety, and a natural schema for evolving data.

---

## Database location

```
~/Library/Application Support/Audie/audie.db
```

Same directory as the existing JSON files. The JSON files are **not deleted** — they remain
as a legacy read fallback for historical counts that predate the migration.

---

## Schema

Two tables. Read the comments — they explain which fields apply to which primitives.

```sql
-- One row per trial, all primitives.
CREATE TABLE trials (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id   TEXT    NOT NULL,
    primitive    TEXT    NOT NULL,  -- 'contour'|'interval-id'|'interval-playback'|future types
    ts           INTEGER NOT NULL,  -- Unix timestamp (seconds since epoch)
    difficulty   INTEGER NOT NULL DEFAULT 0,  -- VM difficultyLevel at time of trial

    -- Pitch fields (contour + any interval primitive)
    note1_midi   INTEGER,           -- lower note MIDI number; nil if not applicable
    note2_midi   INTEGER,           -- higher note MIDI number; nil if not applicable
    semitone_gap INTEGER,           -- note2_midi - note1_midi; always positive; nil if N/A

    -- Interval primitives (interval-id, interval-playback)
    interval_name TEXT,             -- e.g. 'P5', 'm3'; nil for contour
    register      TEXT,             -- 'low'|'mid'|'high'; nil if not applicable

    -- Result
    correct      INTEGER NOT NULL,  -- 1 = correct answer, 0 = incorrect
    result_detail TEXT              -- 'correct'|'wrong'|'close'|'octave_displaced'|'no_read'
                                    -- Use 'correct'/'wrong' for listen-only primitives.
                                    -- Use all 5 values for interval-playback.
);

CREATE INDEX trials_session    ON trials(session_id);
CREATE INDEX trials_primitive  ON trials(primitive, ts);
CREATE INDEX trials_pair       ON trials(note1_midi, note2_midi);  -- for per-pair mastery queries

-- One row per session (lightweight header).
-- A "session" is one uninterrupted practice run of a single primitive.
-- Switching plans starts a new session so plan attribution is clean.
-- plan_id is null for Freeplay sessions and for sessions before plan running ships.
CREATE TABLE sessions (
    id             TEXT    PRIMARY KEY,  -- UUID string
    primitive      TEXT    NOT NULL,     -- 'contour'|'interval-id'|'interval-playback'|...
    plan_id        TEXT,                 -- identifier of the active plan at session start;
                                        --   null = Freeplay or no active plan.
                                        --   Switching plans ends the current session and
                                        --   starts a new one with the new plan_id.
    plan_step      INTEGER,             -- which step within the plan (0-indexed); null for Freeplay
    started_at     INTEGER NOT NULL,    -- Unix timestamp
    ended_at       INTEGER,
    total_trials   INTEGER NOT NULL DEFAULT 0,
    correct_trials INTEGER NOT NULL DEFAULT 0
);

-- Key-value store for app state and migration flags.
CREATE TABLE app_state (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
```

**Schema migrations** are managed by GRDB's `DatabaseMigrator`. The first migration creates all
three tables. Future primitives add new `result_detail` values and optionally new columns via
additional migrations — never break the existing schema.

---

## Step 1 — Create `AudieDatabase.swift`

**Goal:** Set up the GRDB database, define the schema migrations, and provide the shared
`DatabaseQueue` instance used by `SessionLogger` and `ProgressStore`.

**Create:** `EarTrain/Sources/EarTrainLib/AudieDatabase.swift`

```swift
import Foundation
import GRDB

/// Shared GRDB database. Open once at app start; inject where needed.
public final class AudieDatabase {

    public static let shared = AudieDatabase()

    public let dbQueue: DatabaseQueue

    private init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("Audie", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbURL = dir.appendingPathComponent("audie.db")

        var config = Configuration()
        config.foreignKeysEnabled = true
        dbQueue = try! DatabaseQueue(path: dbURL.path, configuration: config)

        try! applyMigrations()
    }

    private func applyMigrations() throws {
        var migrator = DatabaseMigrator()

        // v1 — initial schema (see MIGRATION_1_6.md for full DDL)
        migrator.registerMigration("v1_initial") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS trials (
                    id           INTEGER PRIMARY KEY AUTOINCREMENT,
                    session_id   TEXT    NOT NULL,
                    primitive    TEXT    NOT NULL,
                    ts           INTEGER NOT NULL,
                    difficulty   INTEGER NOT NULL DEFAULT 0,
                    note1_midi   INTEGER,
                    note2_midi   INTEGER,
                    semitone_gap INTEGER,
                    interval_name TEXT,
                    register     TEXT,
                    correct      INTEGER NOT NULL,
                    result_detail TEXT
                );
                CREATE INDEX IF NOT EXISTS trials_session   ON trials(session_id);
                CREATE INDEX IF NOT EXISTS trials_primitive ON trials(primitive, ts);
                CREATE INDEX IF NOT EXISTS trials_pair      ON trials(note1_midi, note2_midi);

                CREATE TABLE IF NOT EXISTS sessions (
                    id             TEXT    PRIMARY KEY,
                    primitive      TEXT    NOT NULL,
                    plan_id        TEXT,
                    plan_step      INTEGER,
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

    public func appStateValue(forKey key: String) throws -> String? {
        try dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM app_state WHERE key = ?", arguments: [key])
        }
    }

    public func setAppState(_ value: String, forKey key: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO app_state (key, value) VALUES (?, ?)",
                arguments: [key, value])
        }
    }
}
```

**Acceptance:** File compiles. `AudieDatabase.shared` can be called without error in a test or preview.

---

## Step 2 — Rewrite `SessionLogger` to write to GRDB

**Goal:** `SessionLogger` writes trials to the `trials` table and sessions to the `sessions` table.
Keep the JSON write path **as a parallel write** for one release (belt-and-suspenders during rollout),
then remove it in the follow-up.

**Files to modify:** `EarTrain/Sources/EarTrainLib/SessionLogger.swift`

**Changes:**

1. Add `import GRDB` at the top.

2. Add `difficulty: Int` parameter to **all three** logging methods:
   - `logTrial(interval:rootHz:detectedHz:result:difficulty:)`
   - `logNoRead(interval:rootHz:difficulty:)`
   - `logIdentificationTrial(interval:rootHz:correct:difficulty:)`
   - `logContourTrial(rootHz:semitones:direction:correct:difficulty:)`

   Each method should also accept `note1Midi: Int? = nil, note2Midi: Int? = nil` for
   contour (where the exact MIDI notes are known).

3. Add a private `var sessionId: String` and `var sessionStartedAt: Date` to track the
   current session for the `sessions` table row.

4. In each `log*` method, after appending to `session.trials`, also write to GRDB:
   ```swift
   private func writeTrialToDb(_ trial: TrialRecord, difficulty: Int,
                                note1Midi: Int?, note2Midi: Int?,
                                semiGap: Int?) {
       let db = AudieDatabase.shared
       try? db.dbQueue.write { d in
           try d.execute(sql: """
               INSERT INTO trials
               (session_id, primitive, ts, difficulty,
                note1_midi, note2_midi, semitone_gap,
                interval_name, register, correct, result_detail)
               VALUES (?,?,?,?,?,?,?,?,?,?,?)
               """,
               arguments: [
                   session.id,
                   trial.exerciseType ?? "interval-playback",
                   Int(trial.timestamp.timeIntervalSince1970),
                   difficulty,
                   note1Midi, note2Midi, semiGap,
                   trial.interval,
                   trial.register.isEmpty ? nil : trial.register,
                   trial.result == "correct" ? 1 : 0,
                   trial.result
               ])
       }
   }
   ```

5. Add `planId: String?` and `planStep: Int?` parameters to `SessionLogger.init()`.
   Default both to `nil` so existing call sites compile unchanged.
   When `LessonRunner` ships (Phase 2), it will pass the active plan ID and step index.
   Switching plans calls `endSession()` on the current logger and creates a new `SessionLogger`
   instance with the new `planId` — this keeps plan attribution clean at the session level.

   In `init`, insert a row into `sessions`:
   ```swift
   try? AudieDatabase.shared.dbQueue.write { d in
       try d.execute(sql: """
           INSERT OR IGNORE INTO sessions (id, primitive, plan_id, plan_step, started_at)
           VALUES (?, ?, ?, ?, ?)
           """, arguments: [session.id, mode, planId, planStep,
                            Int(Date().timeIntervalSince1970)])
   }
   ```

6. In `endSession()`, update the sessions row before the existing JSON write:
   ```swift
   let correctCount = session.trials.filter { $0.result == "correct" }.count
   try? AudieDatabase.shared.dbQueue.write { d in
       try d.execute(sql: """
           UPDATE sessions SET ended_at = ?, total_trials = ?, correct_trials = ?
           WHERE id = ?
           """, arguments: [
               Int(Date().timeIntervalSince1970),
               session.trials.count,
               correctCount,
               session.id
           ])
   }
   ```

7. **Do not remove** the existing JSON write path yet — keep `writeSession()` and `updateCumulative()`
   intact. They run in parallel. Remove them in Phase 1.7 after the mastery engine is verified.

**Update call sites** — each ViewModel that calls `log*` must now pass `difficulty:`.
Read each ViewModel first to find the call sites:

- **ContourViewModel** (`logContourTrial`): reads `difficultyLevel` — pass `difficulty: difficultyLevel`.
  Also compute `note1Midi` and `note2Midi` from `rootHz` and `semitones` using `NoteConverter`
  (if available) or inline `Int(round(69 + 12 * log2(hz / 440)))`.

- **ExerciseViewModel** (`logTrial`, `logNoRead`): reads `difficultyLevel` — pass `difficulty: difficultyLevel`.

- **IdentificationViewModel** (`logIdentificationTrial`): reads `difficultyLevel` — pass `difficulty: difficultyLevel`.

**Acceptance:**
- All three ViewModels compile with the new `difficulty:` parameter.
- After a Contour session, rows exist in `trials` with `primitive = 'contour'` and non-null `difficulty`.
- After an Interval Playback session, rows exist with `primitive = 'interval-playback'`.
- JSON files still write (parallel path intact).

---

## Step 3 — Add GRDB-backed queries to `ProgressStore`

**Goal:** Add new query methods to `ProgressStore` that read from the `trials` table.
Do **not** remove the existing JSON-backed properties yet — Phase 1.7 will migrate them fully.

**Files to modify:** `EarTrain/Sources/EarTrainLib/ProgressStore.swift`

**Add these new methods:**

```swift
// MARK: - GRDB-backed queries (Phase 1.6+)

/// Total trials logged for a given primitive in the DB.
public func dbTrialCount(primitive: String) -> Int {
    (try? AudieDatabase.shared.dbQueue.read { db in
        try Int.fetchOne(db,
            sql: "SELECT COUNT(*) FROM trials WHERE primitive = ?",
            arguments: [primitive]) ?? 0
    }) ?? 0
}

/// Accuracy for a primitive over the most recent `window` trials.
/// Returns nil if fewer than 5 trials exist.
public func recentAccuracy(primitive: String, window: Int = 20) -> Double? {
    guard let rows = try? AudieDatabase.shared.dbQueue.read({ db -> [(correct: Int)] in
        let sql = """
            SELECT correct FROM trials
            WHERE primitive = ?
            ORDER BY ts DESC
            LIMIT ?
            """
        return try Row.fetchAll(db, sql: sql, arguments: [primitive, window])
            .map { (correct: $0["correct"]) }
    }), rows.count >= 5 else { return nil }
    let sum = rows.reduce(0) { $0 + $1.correct }
    return Double(sum) / Double(rows.count)
}

/// Accuracy for a specific (note1_midi, note2_midi) pair over the most recent `window` trials.
public func recentPairAccuracy(note1: Int, note2: Int, window: Int = 20) -> Double? {
    guard let rows = try? AudieDatabase.shared.dbQueue.read({ db -> [(correct: Int)] in
        let sql = """
            SELECT correct FROM trials
            WHERE note1_midi = ? AND note2_midi = ?
            ORDER BY ts DESC
            LIMIT ?
            """
        return try Row.fetchAll(db, sql: sql, arguments: [note1, note2, window])
            .map { (correct: $0["correct"]) }
    }), rows.count >= 5 else { return nil }
    let sum = rows.reduce(0) { $0 + $1.correct }
    return Double(sum) / Double(rows.count)
}

/// All (note1_midi, note2_midi) contour pairs with ≥ minTrials trials, sorted by recent error rate desc.
/// Used to build the weighted sampler in ContourViewModel.
public func contourProblemPairs(minTrials: Int = 5, window: Int = 20
) -> [(note1: Int, note2: Int, recentErrorRate: Double)] {
    guard let rows = try? AudieDatabase.shared.dbQueue.read({ db -> [Row] in
        let sql = """
            WITH recent AS (
                SELECT note1_midi, note2_midi, correct,
                       ROW_NUMBER() OVER (
                           PARTITION BY note1_midi, note2_midi
                           ORDER BY ts DESC
                       ) AS rn
                FROM trials
                WHERE primitive = 'contour'
                  AND note1_midi IS NOT NULL
                  AND note2_midi IS NOT NULL
            )
            SELECT note1_midi, note2_midi,
                   1.0 - AVG(CAST(correct AS REAL)) AS error_rate,
                   COUNT(*) AS n
            FROM recent
            WHERE rn <= ?
            GROUP BY note1_midi, note2_midi
            HAVING n >= ?
            ORDER BY error_rate DESC
            """
        return try Row.fetchAll(db, sql: sql, arguments: [window, minTrials])
    }) else { return [] }
    return rows.map {
        (note1: Int($0["note1_midi"] as Int64),
         note2: Int($0["note2_midi"] as Int64),
         recentErrorRate: $0["error_rate"] as Double)
    }
}
```

**Acceptance:**
- Methods compile without errors.
- `dbTrialCount(primitive: "contour")` returns the correct count after a Contour session.
- `recentAccuracy(primitive: "contour")` returns a value after 5+ contour trials.

---

## Step 4 — First-launch JSON migration

**Goal:** On first launch after the update, detect existing `cumulative.json` and write a flag
so historical session counts survive the migration. The JSON aggregate is preserved as a read
fallback — no data is destroyed.

**Files to modify:** `EarTrain/Sources/EarTrainLib/ProgressStore.swift`

**Add to `ProgressStore.init()`:**
```swift
performLegacyMigrationIfNeeded()
```

**Add private method:**
```swift
private func performLegacyMigrationIfNeeded() {
    guard (try? AudieDatabase.shared.appStateValue(forKey: "json_migrated")) == nil else { return }
    // cumulative.json exists — record the session count so totalSessions stays accurate
    if let data = try? Data(contentsOf: Self.cumulativeURL),
       let legacy = try? Self.decoder.decode(SessionLogger.CumulativeStats.self, from: data) {
        let count = String(legacy.totalSessions)
        try? AudieDatabase.shared.setAppState(count, forKey: "legacy_session_count")
    }
    try? AudieDatabase.shared.setAppState("true", forKey: "json_migrated")
}
```

Then update `stats.totalSessions` in `ProgressStore` to include the legacy count:
```swift
public var totalSessionsIncludingLegacy: Int {
    let dbCount = dbTrialCount(primitive: "contour") > 0
        ? (try? AudieDatabase.shared.dbQueue.read { db in
               try Int.fetchOne(db, sql: "SELECT COUNT(DISTINCT session_id) FROM trials") ?? 0
           }) ?? 0
        : 0
    let legacyStr = try? AudieDatabase.shared.appStateValue(forKey: "legacy_session_count")
    let legacy = Int(legacyStr ?? "0") ?? 0
    return stats.totalSessions + dbCount + legacy
}
```

Update `HomeView` and `ProgressView` to use `totalSessionsIncludingLegacy` where they
currently use `store.stats.totalSessions` for display.

**Note:** `stats.totalSessions` still reads from `cumulative.json` (via `reload()`). The new
property combines both sources. Remove this split in Phase 1.7 when JSON reads are retired.

**Acceptance:**
- Fresh install: `app_state` gets `json_migrated = "true"` on first launch.
- Existing install with cumulative.json: `legacy_session_count` is set correctly.
- Home stats row shows the correct combined session count.

---

## Step 5 — Build and verify

```bash
cd EarTrain && swift build 2>&1 | grep -E "error:|Build complete"
```

Must produce `Build complete!`. If there are errors:
- Missing `difficulty:` parameter at a call site → find it with `grep -rn "logContourTrial\|logTrial\|logIdentificationTrial" Sources/`
- GRDB import errors → verify Package.swift has GRDB in `EarTrainLib` dependencies (already done)
- Window function errors → GRDB 6 supports SQLite window functions; if the `contourProblemPairs`
  query fails at runtime, simplify with a subquery instead

**Commit:**
```
feat(storage): replace JSON session files with GRDB SQLite (Phase 1.6)

Adds AudieDatabase.swift with GRDB-backed schema: trials, sessions,
app_state tables. SessionLogger now writes to SQLite in parallel with
the existing JSON path (JSON path removed in Phase 1.7).

All primitives log to the same trials table with difficulty, note MIDI,
semitone_gap, and result_detail columns — enabling Phase 1.7 mastery
engine queries.

ProgressStore gains GRDB-backed query methods: dbTrialCount,
recentAccuracy, recentPairAccuracy, contourProblemPairs.

First-launch migration reads legacy cumulative.json session count so
historical stats survive the transition. JSON files are preserved.

See MIGRATION_1_6.md.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
```

---

## After this step

Phase 1.7 (mastery engine) can begin. It depends on:
- `trials` rows with populated `difficulty` and `note1_midi` / `note2_midi`
- `ProgressStore.contourProblemPairs()` working correctly
- `ProgressStore.recentAccuracy(primitive:window:)` working correctly

JSON path removal is deferred to Phase 1.7 to reduce risk.

---

## What is NOT in scope

- Removing JSON write path (Phase 1.7)
- Mastery engine logic (Phase 1.7)
- Weighted sampler in ContourViewModel (Phase 1.7)
- Settings UI for thresholds (Phase 1.7)
- Any other primitive's data model changes
