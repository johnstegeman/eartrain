import SwiftUI

// MARK: - Session summary data

/// Per-session stats captured at the moment the user taps "End Session".
/// Conforms to Identifiable so it can drive .sheet(item:).
struct SessionEndSummary: Identifiable {
    let id = UUID()
    let mode: AppMode
    let totalTrials: Int
    let correctTrials: Int
    let duration: TimeInterval

    var accuracy: Double {
        guard totalTrials > 0 else { return 0 }
        return Double(correctTrials) / Double(totalTrials)
    }

    var formattedDuration: String {
        let total = Int(duration)
        let m = total / 60
        let s = total % 60
        return m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }
}

// MARK: - End of Session sheet

/// Shown after the user ends a session. Displays accuracy, duration, and top confusion
/// buckets, with CTAs to view Progress or start another round.
struct EndOfSessionView: View {
    let summary: SessionEndSummary
    @ObservedObject var store: ProgressStore
    @Binding var activeMode: AppMode
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            if summary.totalTrials > 0 {
                statsCard
            } else {
                Text("No trials recorded — tap Start on the exercise screen to begin.")
                    .font(.system(size: 13))
                    .foregroundColor(EarTrainColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            let buckets = store.topConfusionBuckets()
            if !buckets.isEmpty {
                confusionCard(buckets)
            }
            Spacer()
            buttonRow
        }
        .padding(24)
        .frame(width: 360, alignment: .leading)
        .background(EarTrainColors.bg)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Session Complete")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(EarTrainColors.textPrimary)
            Text(summary.mode.label)
                .font(.system(size: 13))
                .foregroundColor(EarTrainColors.textSecondary)
        }
    }

    // MARK: - Stats card

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Big accuracy readout
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(Int(summary.accuracy * 100))%")
                    .font(.system(size: 52, weight: .black))
                    .foregroundColor(accuracyColor(summary.accuracy))
                VStack(alignment: .leading, spacing: 2) {
                    Text("accuracy")
                        .font(.system(size: 13))
                        .foregroundColor(EarTrainColors.textSecondary)
                    Text("\(summary.correctTrials) / \(summary.totalTrials) correct")
                        .font(.system(size: 11))
                        .foregroundColor(EarTrainColors.textDisabled)
                }
            }

            Divider().background(Color(hex: "#2d2d2d"))

            // Duration + vs. overall
            HStack(spacing: 24) {
                statItem(label: "Duration", value: summary.formattedDuration)
                if let overall = store.overallAccuracy {
                    let delta = summary.accuracy - overall
                    statItem(
                        label: "vs. overall",
                        value: "\(delta >= 0 ? "+" : "")\(Int(delta * 100))%",
                        color: delta >= 0 ? EarTrainColors.success : EarTrainColors.error
                    )
                }
            }
        }
        .padding(16)
        .background(EarTrainColors.surface)
        .cornerRadius(12)
    }

    private func statItem(label: String, value: String,
                          color: Color = EarTrainColors.textPrimary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundColor(EarTrainColors.textSecondary)
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(color)
        }
    }

    // MARK: - Confusion card

    private func confusionCard(
        _ buckets: [(intervalName: String, registerName: String, errorRate: Double)]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Needs Work".uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundColor(EarTrainColors.textSecondary)

            ForEach(Array(buckets.enumerated()), id: \.offset) { _, bucket in
                HStack {
                    Text(bucket.intervalName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(EarTrainColors.textPrimary)
                        .frame(width: 36, alignment: .leading)
                    Text(bucket.registerName.capitalized)
                        .font(.system(size: 12))
                        .foregroundColor(EarTrainColors.textSecondary)
                    Spacer()
                    Text("\(Int((1 - bucket.errorRate) * 100))%")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(EarTrainColors.error)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(EarTrainColors.surface)
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Buttons

    private var buttonRow: some View {
        VStack(spacing: 10) {
            Button("View Progress") {
                activeMode = .progress
                dismiss()
            }
            .buttonStyle(AccentButtonStyle())
            .frame(maxWidth: .infinity)

            Button("Done") { dismiss() }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(EarTrainColors.textSecondary)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Helpers

    private func accuracyColor(_ accuracy: Double) -> Color {
        if accuracy >= 0.80 { return EarTrainColors.success }
        if accuracy >= 0.50 { return EarTrainColors.accent }
        return EarTrainColors.error
    }
}
