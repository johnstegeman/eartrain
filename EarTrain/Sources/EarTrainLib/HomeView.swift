import SwiftUI

/// App landing screen — stats at a glance, exercise shortcuts, and a Start Session CTA.
///
/// Shown by default on launch. Tapping a mode card goes straight to that exercise.
/// "Start Session" opens a sheet to pick duration and mode before diving in.
public struct HomeView: View {
    @ObservedObject var store: ProgressStore
    @Binding var activeMode: AppMode
    @Binding var selectedDuration: SessionDuration
    @State private var showingStartSheet = false

    public init(store: ProgressStore, activeMode: Binding<AppMode>, selectedDuration: Binding<SessionDuration>) {
        self.store = store
        self._activeMode = activeMode
        self._selectedDuration = selectedDuration
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header
                recommendationCard
                if store.stats.totalSessions > 0 || store.hasContourData {
                    statsRow
                }
                modeCards
                ctaSection
            }
            .padding(32)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EarTrainColors.bg)
        .onAppear { store.reload() }
        .sheet(isPresented: $showingStartSheet) {
            SessionStartSheet(activeMode: $activeMode, isPresented: $showingStartSheet,
                              selectedDuration: $selectedDuration)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            AudiePNGImage(size: 88)
            Text("Audie")
                .font(.system(size: 36, weight: .black))
                .foregroundColor(EarTrainColors.textPrimary)
            Text("Your ear training companion")
                .font(.system(size: 14))
                .foregroundColor(EarTrainColors.textSecondary)
        }
        .padding(.top, 8)
    }

    // MARK: - Recommendation card

    private var recommendationCard: some View {
        let rec = store.todayRecommendation
        let done = store.practicedToday
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if done {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(EarTrainColors.success)
                }
                Text(done ? "SESSION COMPLETE" : "TODAY'S FOCUS")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundColor(done ? EarTrainColors.success : EarTrainColors.accent)
            }

            Text(done ? "Nice work today." : rec.headline)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(EarTrainColors.textPrimary)

            Text(done ? "Come back tomorrow and keep the streak going." : rec.reason)
                .font(.system(size: 13))
                .foregroundColor(EarTrainColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if !done {
                Button(rec.cta) { activeMode = rec.mode }
                    .buttonStyle(AccentButtonStyle())
                    .padding(.top, 4)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EarTrainColors.surface)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    done ? EarTrainColors.success.opacity(0.25)
                         : EarTrainColors.accent.opacity(0.25),
                    lineWidth: 1.5
                )
        )
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack(spacing: 12) {
            statPill(label: "Sessions", value: "\(store.stats.totalSessions)")
            statPill(label: "Trials",   value: "\(store.stats.totalTrials)")
            if let acc = store.overallAccuracy {
                statPill(label: "Accuracy", value: "\(Int(acc * 100))%",
                         color: EarTrainColors.accuracy(acc))
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

    // MARK: - Mode cards (quick shortcuts)

    private var modeCards: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Exercises".uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundColor(EarTrainColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach([AppMode.contour, .intervals, .identification], id: \.self) { m in
                modeCard(m)
            }
        }
    }

    private func modeCard(_ mode: AppMode) -> some View {
        Button { activeMode = mode } label: {
            HStack(spacing: 14) {
                Image(systemName: mode.icon)
                    .font(.system(size: 18))
                    .foregroundColor(EarTrainColors.accent)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(EarTrainColors.textPrimary)
                    Text(mode.exerciseDescription)
                        .font(.system(size: 11))
                        .foregroundColor(EarTrainColors.textSecondary)
                }

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.system(size: 12))
                    .foregroundColor(EarTrainColors.textDisabled)
            }
        }
        .buttonStyle(.plain)
        .padding(14)
        .background(EarTrainColors.surface)
        .cornerRadius(10)
    }

    // MARK: - CTAs

    private var ctaSection: some View {
        VStack(spacing: 12) {
            Button("Start Session") { showingStartSheet = true }
                .buttonStyle(AccentButtonStyle())

            let eligible = store.hasDrillableData
            VStack(spacing: 4) {
                Button("Drill My Misses") { activeMode = .intervals }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(eligible ? EarTrainColors.accent : EarTrainColors.textDisabled)
                    .buttonStyle(.plain)
                    .disabled(!eligible)
                if !eligible {
                    Text("Practice a few sessions first")
                        .font(.system(size: 11))
                        .foregroundColor(EarTrainColors.textDisabled)
                }
            }
        }
    }

}

// MARK: - Session Start Sheet

private struct SessionStartSheet: View {
    @Binding var activeMode: AppMode
    @Binding var isPresented: Bool
    @Binding var selectedDuration: SessionDuration

    @State private var selectedMode: AppMode = .intervals

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            sheetHeader
            durationSection
            modeSection
            Spacer()
            startButton
        }
        .padding(24)
        .frame(width: 380, alignment: .leading)
        .background(EarTrainColors.bg)
    }

    // MARK: - Header

    private var sheetHeader: some View {
        HStack {
            Text("Start a Session")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(EarTrainColors.textPrimary)
            Spacer()
            Button("Cancel") { isPresented = false }
                .font(.system(size: 14))
                .foregroundColor(EarTrainColors.textSecondary)
        }
    }

    // MARK: - Duration

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Duration")
            HStack(spacing: 8) {
                ForEach(SessionDuration.allCases, id: \.self) { d in
                    durationPill(d)
                }
            }
        }
    }

    private func durationPill(_ duration: SessionDuration) -> some View {
        let selected = selectedDuration == duration
        return Button(duration.label) { selectedDuration = duration }
            .font(.system(size: 13, weight: selected ? .semibold : .regular))
            .lineLimit(1)
            .foregroundColor(selected ? .black : EarTrainColors.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(selected ? EarTrainColors.accent : EarTrainColors.surface)
            .cornerRadius(8)
            .buttonStyle(.plain)
    }

    // MARK: - Mode

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Exercise")
            VStack(spacing: 6) {
                ForEach([AppMode.contour, .intervals, .identification], id: \.self) { m in
                    modeRow(m)
                }
            }
        }
    }

    private func modeRow(_ mode: AppMode) -> some View {
        let selected = selectedMode == mode
        return Button { selectedMode = mode } label: {
            HStack(spacing: 12) {
                Image(systemName: mode.icon)
                    .font(.system(size: 15))
                    .foregroundColor(selected ? EarTrainColors.accent : EarTrainColors.textSecondary)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(EarTrainColors.textPrimary)
                    Text(mode.exerciseDescription)
                        .font(.system(size: 11))
                        .foregroundColor(EarTrainColors.textSecondary)
                }

                Spacer()

                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(EarTrainColors.accent)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(12)
        .background(selected ? EarTrainColors.accent.opacity(0.08) : EarTrainColors.surface)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(selected ? EarTrainColors.accent.opacity(0.4) : Color.clear,
                        lineWidth: 1.5)
        )
    }

    // MARK: - Start

    private var startButton: some View {
        Button("Let's Go") {
            activeMode = selectedMode
            isPresented = false
        }
        .buttonStyle(AccentButtonStyle())
        .frame(maxWidth: .infinity)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.5)
            .foregroundColor(EarTrainColors.textSecondary)
    }
}

// SessionDuration is defined in ExerciseReadyView.swift (shared with pre-exercise screens).
