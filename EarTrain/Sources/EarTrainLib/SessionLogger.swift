import Foundation

/// Logs exercise trials to disk for confusion-matrix analysis.
///
/// Files are written to:
///   ~/Library/Application Support/Audie/sessions/{uuid}.json  (one per session)
///   ~/Library/Application Support/Audie/cumulative.json       (running totals)
///
/// All methods are synchronous and lightweight — JSON payloads are tiny
/// (<10 KB) so main-thread writes are acceptable.
public final class SessionLogger {

    // MARK: - Codable types

    public struct TrialRecord: Codable {
        public let timestamp:    Date
        /// "playback" | "identification" | "contour". Nil in legacy records = "playback".
        public let exerciseType: String?
        public let interval:     String  // Interval.shortName, or contour direction for contour trials
        public let register:     String  // Register.rawValue, or "" for contour trials
        public let rootHz:       Float
        public let detectedHz:   Float
        public let result:       String  // "correct" | "close" | "octave_displaced" | "wrong" | "no_read"
    }

    /// Simple correct/total counts for the contour exercise.
    public struct ContourCounts: Codable {
        public var correct: Int = 0
        public var total:   Int = 0
        public var accuracy: Double { total > 0 ? Double(correct) / Double(total) : 0 }
    }

    public struct SessionRecord: Codable {
        public let id: String
        public let startedAt: Date
        public var endedAt: Date?
        public let mode: String
        public var trials: [TrialRecord]
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
        public var lastUpdated:    Date = Date()
        public var totalSessions:  Int  = 0
        public var totalTrials:    Int  = 0
        /// Interval confusion matrix (playback + identification):
        /// matrix[interval.shortName][register.rawValue] → counts
        public var matrix: [String: [String: RegisterCounts]] = [:]
        /// Contour accuracy: contour[intervalName][register.rawValue] → counts
        /// intervalName uses the same shortName convention as Interval (e.g. "m3", "P5").
        /// Semitones without a named interval use "TT", "m6", "M7" etc.
        public var contour: [String: [String: ContourCounts]] = [:]
    }

    // MARK: - State

    private var session: SessionRecord
    private let baseURL:  URL
    private let buckets:  RegisterBuckets

    // MARK: - Init

    public init(mode: String = "intervals",
                buckets: RegisterBuckets = .guitarDefault) {
        self.buckets = buckets

        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        baseURL = appSupport.appendingPathComponent("Audie", isDirectory: true)

        let sessionsDir = baseURL.appendingPathComponent("sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: sessionsDir,
                                                 withIntermediateDirectories: true)

        session = SessionRecord(id: UUID().uuidString,
                                startedAt: Date(),
                                endedAt: nil,
                                mode: mode,
                                trials: [])
    }

    // MARK: - Logging

    public func logTrial(interval: Interval,
                         rootHz: Float,
                         detectedHz: Float,
                         result: ExerciseResult) {
        let reg = buckets.register(for: rootHz)
        let trial = TrialRecord(
            timestamp:    Date(),
            exerciseType: "playback",
            interval:     interval.shortName,
            register:     reg.rawValue,
            rootHz:       rootHz,
            detectedHz:   detectedHz,
            result:       resultKey(result)
        )
        session.trials.append(trial)
    }

    public func logNoRead(interval: Interval, rootHz: Float) {
        let reg = buckets.register(for: rootHz)
        let trial = TrialRecord(
            timestamp:    Date(),
            exerciseType: "playback",
            interval:     interval.shortName,
            register:     reg.rawValue,
            rootHz:       rootHz,
            detectedHz:   0,
            result:       "no_read"
        )
        session.trials.append(trial)
    }

    /// Log one identification trial (listening-only yes/no quiz).
    /// Both playback and identification land in the same confusion matrix —
    /// they measure the same underlying skill.
    public func logIdentificationTrial(interval: Interval,
                                       rootHz: Float,
                                       correct: Bool) {
        let reg = buckets.register(for: rootHz)
        let trial = TrialRecord(
            timestamp:    Date(),
            exerciseType: "identification",
            interval:     interval.shortName,
            register:     reg.rawValue,
            rootHz:       rootHz,
            detectedHz:   0,
            result:       correct ? "correct" : "wrong"
        )
        session.trials.append(trial)
    }

    /// Log one contour trial (higher / lower / same).
    ///
    /// Records the actual interval (by semitone count) and register so the
    /// data can drive adaptive difficulty: "user struggles with m2 in low register."
    public func logContourTrial(rootHz: Float, semitones: Int,
                                direction: String, correct: Bool) {
        let reg = buckets.register(for: rootHz)
        let trial = TrialRecord(
            timestamp:    Date(),
            exerciseType: "contour",
            interval:     Self.intervalName(forSemitones: semitones),
            register:     reg.rawValue,
            rootHz:       rootHz,
            detectedHz:   0,
            result:       correct ? "correct" : "wrong"
        )
        session.trials.append(trial)
    }

    /// Human-readable interval name for a raw semitone count.
    /// Covers the full chromatic scale so contour exercises with any gap are labelled correctly.
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

    public func endSession() {
        session.endedAt = Date()
        writeSession()
        updateCumulative()
        NotificationCenter.default.post(name: .earTrainSessionDidEnd, object: nil)
    }

    // MARK: - Private

    private func resultKey(_ r: ExerciseResult) -> String {
        switch r {
        case .correct:         return "correct"
        case .close:           return "close"
        case .octaveDisplaced: return "octave_displaced"
        case .wrong:           return "wrong"
        }
    }

    private func writeSession() {
        let url = baseURL
            .appendingPathComponent("sessions")
            .appendingPathComponent("\(session.id).json")
        if let data = try? Self.encoder.encode(session) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func updateCumulative() {
        let url = baseURL.appendingPathComponent("cumulative.json")
        var stats = (try? JSONDecoder().decode(CumulativeStats.self,
                                              from: Data(contentsOf: url)))
                    ?? CumulativeStats()

        stats.lastUpdated   = Date()
        stats.totalSessions += 1
        stats.totalTrials   += session.trials.count

        for trial in session.trials {
            switch trial.exerciseType ?? "playback" {

            case "contour":
                var byRegister = stats.contour[trial.interval] ?? [:]
                var counts     = byRegister[trial.register]   ?? ContourCounts()
                counts.total += 1
                if trial.result == "correct" { counts.correct += 1 }
                byRegister[trial.register]      = counts
                stats.contour[trial.interval]   = byRegister

            default:  // "playback" and "identification" share the interval matrix
                var byRegister = stats.matrix[trial.interval] ?? [:]
                var counts     = byRegister[trial.register]  ?? RegisterCounts()
                switch trial.result {
                case "correct":          counts.correct         += 1
                case "close":            counts.close           += 1
                case "octave_displaced": counts.octaveDisplaced += 1
                case "no_read":          counts.noRead          += 1
                default:                 counts.wrong           += 1
                }
                byRegister[trial.register]   = counts
                stats.matrix[trial.interval] = byRegister
            }
        }

        if let data = try? Self.encoder.encode(stats) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting    = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

// MARK: - Notification name

public extension Notification.Name {
    /// Posted on the main queue after every session is written to disk.
    /// ProgressStore observes this to auto-reload without a timing dependency
    /// on SwiftUI's onAppear/onDisappear ordering.
    static let earTrainSessionDidEnd = Notification.Name("EarTrainSessionDidEnd")
}
