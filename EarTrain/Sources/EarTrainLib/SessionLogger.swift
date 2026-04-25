import Foundation

/// Logs exercise trials to disk for confusion-matrix analysis.
///
/// Files are written to:
///   ~/Library/Application Support/EarTrainCI/sessions/{uuid}.json  (one per session)
///   ~/Library/Application Support/EarTrainCI/cumulative.json       (running totals)
///
/// All methods are synchronous and lightweight — JSON payloads are tiny
/// (<10 KB) so main-thread writes are acceptable.
public final class SessionLogger {

    // MARK: - Codable types

    public struct TrialRecord: Codable {
        public let timestamp: Date
        public let interval: String     // Interval.shortName, e.g. "m3"
        public let register: String     // Register.rawValue
        public let rootHz: Float
        public let detectedHz: Float
        public let result: String       // "correct" | "close" | "octave_displaced" | "wrong" | "no_read"
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
        /// matrix[interval.shortName][register.rawValue] → counts
        public var matrix: [String: [String: RegisterCounts]] = [:]
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
        baseURL = appSupport.appendingPathComponent("EarTrainCI", isDirectory: true)

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
            timestamp:   Date(),
            interval:    interval.shortName,
            register:    reg.rawValue,
            rootHz:      rootHz,
            detectedHz:  detectedHz,
            result:      resultKey(result)
        )
        session.trials.append(trial)
    }

    public func logNoRead(interval: Interval, rootHz: Float) {
        let reg = buckets.register(for: rootHz)
        let trial = TrialRecord(
            timestamp:  Date(),
            interval:   interval.shortName,
            register:   reg.rawValue,
            rootHz:     rootHz,
            detectedHz: 0,
            result:     "no_read"
        )
        session.trials.append(trial)
    }

    public func endSession() {
        session.endedAt = Date()
        writeSession()
        updateCumulative()
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
