import Foundation
import GRDB
import os.log

private let sessionLog = Logger(subsystem: "com.audie", category: "session")

/// Logs exercise trials to the GRDB SQLite database.
///
/// One instance = one practice session. Create at session start; call `endSession()` when done.
/// Each `log*` call writes immediately — no batching, no JSON files.
///
/// Inject a custom `AudieDatabase` for testing.
public final class SessionLogger {

    // MARK: - Codable aggregate types (retained for ProgressStore.CumulativeStats)

    public struct ContourCounts: Codable {
        public var correct: Int = 0
        public var total:   Int = 0
        public var accuracy: Double { total > 0 ? Double(correct) / Double(total) : 0 }
    }

    public struct RegisterCounts: Codable {
        public var correct:         Int = 0
        public var close:           Int = 0
        public var octaveDisplaced: Int = 0
        public var wrong:           Int = 0
        public var noRead:          Int = 0

        public var total: Int { correct + close + octaveDisplaced + wrong + noRead }
        public var errorRate: Double {
            guard total > 0 else { return 0 }
            return Double(close + octaveDisplaced + wrong) / Double(total)
        }
    }

    public struct CumulativeStats: Codable {
        public var lastUpdated:   Date = Date()
        public var totalSessions: Int  = 0
        public var totalTrials:   Int  = 0
        /// Interval confusion matrix (playback + identification):
        /// matrix[interval.shortName][register.rawValue] → counts
        public var matrix: [String: [String: RegisterCounts]] = [:]
        /// Contour accuracy: contour[intervalName][register.rawValue] → counts
        public var contour: [String: [String: ContourCounts]] = [:]
    }

    // MARK: - State

    public let sessionId: String
    private let startedAt: Date
    private let primitive: String
    private let planId: String?
    private let planStep: Int?
    private let timbre: String?
    private let db: AudieDatabase

    private var trialCount   = 0
    private var correctCount = 0

    // MARK: - Init

    /// - Parameters:
    ///   - primitive: One of `"contour"`, `"interval-id"`, `"interval-playback"`, etc.
    ///   - planId: Active plan identifier, or nil for Freeplay sessions.
    ///   - planStep: 0-indexed step within the plan, or nil for Freeplay.
    ///   - timbre: `GuitarTimbre.rawValue` in use at session start.
    ///   - database: Inject for testing; defaults to `AudieDatabase.shared`.
    public init(primitive: String,
                planId: String? = nil,
                planStep: Int? = nil,
                timbre: String? = GuitarTimbre.persisted.rawValue,
                database: AudieDatabase = .shared) {
        self.sessionId  = UUID().uuidString
        self.startedAt  = Date()
        self.primitive  = primitive
        self.planId     = planId
        self.planStep   = planStep
        self.timbre     = timbre
        self.db         = database

        insertSessionRow()
    }

    // MARK: - Trial logging

    /// Log one interval-playback trial.
    public func logTrial(interval: Interval,
                         rootHz: Float,
                         detectedHz: Float,
                         result: ExerciseResult,
                         difficulty: Int) {
        let note1 = NoteConverter.midiNote(fromHz: rootHz)
        let note2 = note1 + interval.semitones
        writeTrial(
            intervalName: interval.shortName,
            register:     RegisterBuckets.guitarDefault.register(for: rootHz).rawValue,
            note1Midi:    note1,
            note2Midi:    note2,
            semitoneGap:  interval.semitones,
            correct:      result == .correct ? 1 : 0,
            resultDetail: resultKey(result),
            difficulty:   difficulty
        )
    }

    /// Log a no-read event (mic couldn't detect pitch).
    public func logNoRead(interval: Interval, rootHz: Float, difficulty: Int) {
        let note1 = NoteConverter.midiNote(fromHz: rootHz)
        writeTrial(
            intervalName: interval.shortName,
            register:     RegisterBuckets.guitarDefault.register(for: rootHz).rawValue,
            note1Midi:    note1,
            note2Midi:    note1 + interval.semitones,
            semitoneGap:  interval.semitones,
            correct:      0,
            resultDetail: "no_read",
            difficulty:   difficulty
        )
    }

    /// Log one interval-identification trial (listening-only).
    public func logIdentificationTrial(interval: Interval,
                                       rootHz: Float,
                                       correct: Bool,
                                       difficulty: Int) {
        let note1 = NoteConverter.midiNote(fromHz: rootHz)
        writeTrial(
            intervalName: interval.shortName,
            register:     RegisterBuckets.guitarDefault.register(for: rootHz).rawValue,
            note1Midi:    note1,
            note2Midi:    note1 + interval.semitones,
            semitoneGap:  interval.semitones,
            correct:      correct ? 1 : 0,
            resultDetail: correct ? "correct" : "wrong",
            difficulty:   difficulty
        )
    }

    /// Log one contour trial (higher / lower / same).
    /// `note1Midi` and `note2Midi` should be the lower and higher notes respectively.
    public func logContourTrial(rootHz: Float,
                                semitones: Int,
                                direction: String,
                                correct: Bool,
                                difficulty: Int,
                                note1Midi: Int,
                                note2Midi: Int) {
        writeTrial(
            intervalName: Self.intervalName(forSemitones: semitones),
            register:     RegisterBuckets.guitarDefault.register(for: rootHz).rawValue,
            note1Midi:    note1Midi,
            note2Midi:    note2Midi,
            semitoneGap:  semitones,
            correct:      correct ? 1 : 0,
            resultDetail: correct ? "correct" : "wrong",
            difficulty:   difficulty
        )
    }

    // MARK: - Session lifecycle

    public func endSession() {
        updateSessionRow()
        NotificationCenter.default.post(name: .earTrainSessionDidEnd, object: nil)
        sessionLog.info("Session ended: \(self.sessionId, privacy: .public) primitive=\(self.primitive, privacy: .public) trials=\(self.trialCount)")
    }

    // MARK: - Helpers

    public static func intervalName(forSemitones n: Int) -> String {
        switch n {
        case 1:  return "m2"
        case 2:  return "M2"
        case 3:  return "m3"
        case 4:  return "M3"
        case 5:  return "P4"
        case 6:  return "TT"
        case 7:  return "P5"
        case 8:  return "m6"
        case 9:  return "M6"
        case 10: return "m7"
        case 11: return "M7"
        case 12: return "P8"
        default: return "\(n)st"
        }
    }

    private func resultKey(_ r: ExerciseResult) -> String {
        switch r {
        case .correct:         return "correct"
        case .close:           return "close"
        case .octaveDisplaced: return "octave_displaced"
        case .wrong:           return "wrong"
        }
    }

    // MARK: - Private DB writes

    private func insertSessionRow() {
        do {
            try db.dbQueue.write { d in
                try d.execute(sql: """
                    INSERT OR IGNORE INTO sessions
                        (id, primitive, plan_id, plan_step, timbre, started_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [sessionId, primitive, planId, planStep,
                                timbre, Int(startedAt.timeIntervalSince1970)])
            }
        } catch {
            sessionLog.error("Failed to insert session row: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func writeTrial(intervalName: String?,
                            register: String?,
                            note1Midi: Int?,
                            note2Midi: Int?,
                            semitoneGap: Int?,
                            correct: Int,
                            resultDetail: String,
                            difficulty: Int) {
        trialCount += 1
        if correct == 1 { correctCount += 1 }

        // Build arguments explicitly so Swift doesn't lose Optional<Int> type info.
        // GRDB array literals infer Optional<Int> as null; using .databaseValue is reliable.
        let args: StatementArguments = [
            sessionId, primitive,
            Int(Date().timeIntervalSince1970), difficulty,
            note1Midi?.databaseValue   ?? DatabaseValue.null,
            note2Midi?.databaseValue   ?? DatabaseValue.null,
            semitoneGap?.databaseValue ?? DatabaseValue.null,
            intervalName?.databaseValue ?? DatabaseValue.null,
            register?.databaseValue    ?? DatabaseValue.null,
            correct, resultDetail
        ]
        do {
            try db.dbQueue.write { d in
                try d.execute(sql: """
                    INSERT INTO trials
                        (session_id, primitive, ts, difficulty,
                         note1_midi, note2_midi, semitone_gap,
                         interval_name, register, correct, result_detail)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: args)
            }
        } catch {
            sessionLog.error("Failed to write trial: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func updateSessionRow() {
        do {
            try db.dbQueue.write { d in
                try d.execute(sql: """
                    UPDATE sessions
                    SET ended_at = ?, total_trials = ?, correct_trials = ?
                    WHERE id = ?
                    """,
                    arguments: [Int(Date().timeIntervalSince1970),
                                trialCount, correctCount, sessionId])
            }
        } catch {
            sessionLog.error("Failed to update session row: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - Notification name

public extension Notification.Name {
    static let earTrainSessionDidEnd = Notification.Name("EarTrainSessionDidEnd")
}
