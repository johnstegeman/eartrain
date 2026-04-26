import Foundation

/// Reads cumulative session data from disk and provides it to ProgressView.
///
/// Call `reload()` on appear — no polling needed since sessions write synchronously
/// before the user ever navigates to Progress.
@MainActor
public final class ProgressStore: ObservableObject {

    @Published public private(set) var stats = SessionLogger.CumulativeStats()

    public init() {
        // Auto-reload whenever any exercise session ends, regardless of which
        // SwiftUI view is currently visible. This sidesteps the race between
        // ProgressView.onAppear and the previous tab's onDisappear.
        NotificationCenter.default.addObserver(
            forName: .earTrainSessionDidEnd,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reload() }
        }
    }

    // MARK: - Public interface

    public func reload() {
        guard let data = try? Data(contentsOf: Self.cumulativeURL),
              let loaded = try? Self.decoder.decode(SessionLogger.CumulativeStats.self,
                                                    from: data) else { return }
        stats = loaded
    }

    /// Counts for a specific (interval, register) cell. Nil if no data yet.
    public func counts(for interval: Interval,
                       register: Register) -> SessionLogger.RegisterCounts? {
        guard let byRegister = stats.matrix[interval.shortName],
              let counts = byRegister[register.rawValue],
              counts.total > 0 else { return nil }
        return counts
    }

    /// Aggregated contour counts for a specific interval across all registers.
    /// Returns nil if no trials exist for that interval.
    public func contourCounts(for intervalName: String) -> SessionLogger.ContourCounts? {
        guard let byRegister = stats.contour[intervalName] else { return nil }
        var total = SessionLogger.ContourCounts()
        for c in byRegister.values { total.correct += c.correct; total.total += c.total }
        return total.total > 0 ? total : nil
    }

    /// Contour counts for a specific interval × register cell.
    public func contourCounts(for intervalName: String,
                              register: Register) -> SessionLogger.ContourCounts? {
        guard let counts = stats.contour[intervalName]?[register.rawValue],
              counts.total > 0 else { return nil }
        return counts
    }

    /// Interval names that have at least one contour trial, sorted by shortName.
    public var contourIntervals: [String] {
        stats.contour.filter { $0.value.values.contains { $0.total > 0 } }
                     .keys.sorted()
    }

    /// True if any contour trials have been logged.
    public var hasContourData: Bool {
        stats.contour.values.contains { $0.values.contains { $0.total > 0 } }
    }

    /// Overall accuracy across all interval trials (playback + identification).
    public var overallAccuracy: Double? {
        var totalCorrect = 0
        var total = 0
        for byRegister in stats.matrix.values {
            for counts in byRegister.values {
                totalCorrect += counts.correct
                total        += counts.total
            }
        }
        guard total > 0 else { return nil }
        return Double(totalCorrect) / Double(total)
    }

    // MARK: - Private

    private static var cumulativeURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Audie")
            .appendingPathComponent("cumulative.json")
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
