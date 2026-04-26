import SwiftUI

/// Confusion matrix heatmap showing per-(interval, register) accuracy.
///
/// Color coding: green ≥ 80%, amber ≥ 50%, red < 50%.
/// Cells with < 5 trials are shown muted — not enough data to be meaningful.
/// Tapping a cell shows a drill-down sheet with trial breakdown.
public struct ProgressView: View {

    @ObservedObject var store: ProgressStore
    @State private var selectedCell: CellID? = nil

    public init(store: ProgressStore) { self.store = store }

    // MARK: - Body

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                summaryBar
                if !store.allStreakRecords.isEmpty { streakSection }
                if store.hasContourData { contourSection }
                heatmap
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EarTrainColors.bg)
        .onAppear { store.reload() }
        .overlay {
            if store.stats.totalTrials == 0 && !store.hasContourData {
                emptyState
            }
        }
        .sheet(item: $selectedCell) { cell in
            DrillDownSheet(cell: cell, store: store)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 40))
                .foregroundColor(EarTrainColors.textDisabled)
            Text("No data yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(EarTrainColors.textPrimary)
            Text("Practice any exercise and your progress will appear here.")
                .font(.system(size: 13))
                .foregroundColor(EarTrainColors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EarTrainColors.bg)
    }

    // MARK: - Streak records section

    private var streakSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("BEST STREAKS")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundColor(EarTrainColors.textSecondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220))], spacing: 8) {
                ForEach(store.allStreakRecords) { record in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.modeLabel)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(EarTrainColors.textPrimary)
                                .fixedSize()
                            HStack(spacing: 6) {
                                DifficultyDots(level: record.difficulty)
                                Text("Level \(record.difficulty)")
                                    .font(.system(size: 11))
                                    .foregroundColor(EarTrainColors.textSecondary)
                                    .fixedSize()
                            }
                        }
                        Spacer(minLength: 8)
                        HStack(alignment: .lastTextBaseline, spacing: 4) {
                            Text("\(record.streak)")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(EarTrainColors.accent)
                            Text("in a row")
                                .font(.system(size: 10))
                                .foregroundColor(EarTrainColors.textSecondary)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(EarTrainColors.surface)
                    .cornerRadius(10)
                }
            }
        }
    }

    // MARK: - Contour section

    private var contourSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Contour")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.5)
                .foregroundColor(EarTrainColors.textSecondary)
                .textCase(.uppercase)

            ForEach(store.contourIntervals, id: \.self) { name in
                contourIntervalRow(name)
            }
        }
        .padding(16)
        .background(EarTrainColors.surface)
        .cornerRadius(12)
    }

    private func contourIntervalRow(_ intervalName: String) -> some View {
        let counts  = store.contourCounts(for: intervalName)
        let hasData = (counts?.total ?? 0) >= 5

        return HStack(spacing: 12) {
            Text(intervalName)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(EarTrainColors.textPrimary)
                .frame(width: 36, alignment: .leading)

            if hasData, let c = counts {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(EarTrainColors.bg)
                            .frame(height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(accuracyColor(c.accuracy))
                            .frame(width: geo.size.width * CGFloat(c.accuracy), height: 8)
                    }
                }
                .frame(height: 8)

                Text("\(Int(c.accuracy * 100))%")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(accuracyColor(c.accuracy))
                    .frame(width: 36, alignment: .trailing)

                Text("\(c.total)")
                    .font(.system(size: 11))
                    .foregroundColor(EarTrainColors.textDisabled)
                    .frame(width: 28, alignment: .trailing)

            } else if let c = counts, c.total > 0 {
                // Has data but < 5 trials — show trial count, muted
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(EarTrainColors.bg)
                            .frame(height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(EarTrainColors.textDisabled)
                            .frame(width: geo.size.width * CGFloat(c.accuracy), height: 8)
                    }
                }
                .frame(height: 8)

                Text("few")
                    .font(.system(size: 11))
                    .foregroundColor(EarTrainColors.textDisabled)
                    .frame(width: 36, alignment: .trailing)

                Text("\(c.total)")
                    .font(.system(size: 11))
                    .foregroundColor(EarTrainColors.textDisabled)
                    .frame(width: 28, alignment: .trailing)
            } else {
                Spacer()
                Text("—")
                    .font(.system(size: 13))
                    .foregroundColor(EarTrainColors.textDisabled)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Summary bar

    private var summaryBar: some View {
        HStack(spacing: 24) {
            statPill(label: "Sessions",
                     value: "\(store.stats.totalSessions)")
            statPill(label: "Trials",
                     value: "\(store.stats.totalTrials)")
            if let acc = store.overallAccuracy {
                statPill(label: "Overall",
                         value: "\(Int(acc * 100))%",
                         color: accuracyColor(acc))
            }
            Spacer()
        }
    }

    private func statPill(label: String, value: String,
                          color: Color = EarTrainColors.textPrimary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundColor(EarTrainColors.textSecondary)
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(color)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(EarTrainColors.surface)
        .cornerRadius(10)
    }

    // MARK: - Heatmap

    private var heatmap: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                Text("")
                    .frame(width: 52)
                ForEach(Register.allCases, id: \.self) { reg in
                    Text(reg.displayName)
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.5)
                        .foregroundColor(EarTrainColors.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            // Interval rows
            ForEach(Interval.allCases, id: \.self) { interval in
                intervalRow(interval)
                    .padding(.vertical, 3)
            }

            // Legend
            legend
                .padding(.top, 16)
        }
        .padding(16)
        .background(EarTrainColors.surface)
        .cornerRadius(12)
    }

    private func intervalRow(_ interval: Interval) -> some View {
        HStack(spacing: 0) {
            // Interval label
            VStack(alignment: .leading, spacing: 1) {
                Text(interval.shortName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(EarTrainColors.textPrimary)
                Text(interval.displayName)
                    .font(.system(size: 9))
                    .foregroundColor(EarTrainColors.textDisabled)
            }
            .frame(width: 52, alignment: .leading)

            ForEach(Register.allCases, id: \.self) { register in
                cell(interval: interval, register: register)
                    .padding(3)
            }
        }
        .padding(.horizontal, 12)
    }

    private func cell(interval: Interval, register: Register) -> some View {
        let counts = store.counts(for: interval, register: register)
        let hasData = (counts?.total ?? 0) >= 5
        let accuracy = counts.map { c in
            c.total > 0 ? Double(c.correct) / Double(c.total) : 0.0
        }

        return Button {
            selectedCell = CellID(interval: interval, register: register)
        } label: {
            VStack(spacing: 2) {
                if hasData, let acc = accuracy {
                    Text("\(Int(acc * 100))%")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.black.opacity(0.8))
                    Text("\(counts!.total)")
                        .font(.system(size: 9))
                        .foregroundColor(.black.opacity(0.5))
                } else if let c = counts, c.total > 0 {
                    // Has data but < 5 trials
                    Text("\(c.total)")
                        .font(.system(size: 12))
                        .foregroundColor(EarTrainColors.textDisabled)
                    Text("few")
                        .font(.system(size: 9))
                        .foregroundColor(EarTrainColors.textDisabled)
                } else {
                    Text("—")
                        .font(.system(size: 15))
                        .foregroundColor(EarTrainColors.textDisabled)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(cellBackground(accuracy: hasData ? accuracy : nil))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    private func cellBackground(accuracy: Double??) -> Color {
        guard let acc = accuracy ?? nil else {
            return EarTrainColors.surface.opacity(0.6)  // no data
        }
        return accuracyColor(acc).opacity(0.85)
    }

    // MARK: - Legend

    private var legend: some View {
        HStack(spacing: 16) {
            legendDot(color: EarTrainColors.success,  label: "≥ 80%")
            legendDot(color: EarTrainColors.accent,   label: "50–79%")
            legendDot(color: EarTrainColors.error,    label: "< 50%")
            legendDot(color: EarTrainColors.surface,  label: "< 5 trials")
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 12, height: 12)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(EarTrainColors.textSecondary)
        }
    }

    // MARK: - Helpers

    private func accuracyColor(_ accuracy: Double) -> Color {
        if accuracy >= 0.80 { return EarTrainColors.success }
        if accuracy >= 0.50 { return EarTrainColors.accent }
        return EarTrainColors.error
    }
}

// MARK: - Cell identity (for sheet)

struct CellID: Identifiable {
    let interval: Interval
    let register: Register
    var id: String { "\(interval.shortName)-\(register.rawValue)" }
}

// MARK: - Drill-down sheet

private struct DrillDownSheet: View {
    let cell: CellID
    @ObservedObject var store: ProgressStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let counts = store.counts(for: cell.interval, register: cell.register)

        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(cell.interval.shortName) · \(cell.register.displayName)")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(EarTrainColors.textPrimary)
                    Text(cell.interval.displayName)
                        .font(.system(size: 13))
                        .foregroundColor(EarTrainColors.textSecondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(EarTrainColors.accent)
            }

            Divider().background(EarTrainColors.border)

            if let c = counts, c.total > 0 {
                // Breakdown
                VStack(spacing: 8) {
                    breakdownRow(label: "Correct",          value: c.correct,         color: EarTrainColors.success)
                    breakdownRow(label: "Close",            value: c.close,           color: EarTrainColors.accent)
                    breakdownRow(label: "Octave displaced", value: c.octaveDisplaced,  color: EarTrainColors.accent)
                    breakdownRow(label: "Wrong",            value: c.wrong,           color: EarTrainColors.error)
                    breakdownRow(label: "No read",          value: c.noRead,          color: EarTrainColors.textDisabled)
                }

                Divider().background(EarTrainColors.border)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accuracy")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(0.5)
                            .foregroundColor(EarTrainColors.textSecondary)
                        let acc = Double(c.correct) / Double(c.total)
                        Text("\(Int(acc * 100))% (\(c.correct)/\(c.total))")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(accuracyColor(Double(c.correct) / Double(c.total)))
                    }
                    Spacer()
                }

                // Drill This placeholder
                if c.total >= 5 {
                    Text("Drill This")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(EarTrainColors.accent)
                        .cornerRadius(6)
                        .opacity(0.5)  // greyed — Drill My Misses not yet implemented
                        .overlay(
                            Text("Available in a future update")
                                .font(.system(size: 10))
                                .foregroundColor(EarTrainColors.textSecondary)
                                .offset(y: 22)
                        )
                }

            } else {
                Text("No trials recorded yet for this cell.\nPractice this interval in the \(cell.register.displayName) register to see data here.")
                    .font(.system(size: 13))
                    .foregroundColor(EarTrainColors.textSecondary)
                    .multilineTextAlignment(.leading)
            }

            Spacer()
        }
        .padding(24)
        .frame(width: 320, alignment: .leading)
        .background(EarTrainColors.bg)
    }

    private func breakdownRow(label: String, value: Int, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(EarTrainColors.textSecondary)
            Spacer()
            Text("\(value)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(color)
        }
    }

    private func accuracyColor(_ accuracy: Double) -> Color {
        if accuracy >= 0.80 { return EarTrainColors.success }
        if accuracy >= 0.50 { return EarTrainColors.accent }
        return EarTrainColors.error
    }
}

private extension EarTrainColors {
    static let border = Color(hex: "#2d2d2d")
}
