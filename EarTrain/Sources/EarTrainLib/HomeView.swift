import SwiftUI

/// Home — multi-mode launcher and dashboard.
///
/// Two states:
///   A) With active plan: "Continue Plan" is the primary CTA.
///   B) No active plan (current default): "Drill My Misses" is primary when eligible.
///
/// The Audie avatar lives in onboarding, not here.
/// No ScrollView — content must fit the default window (1000×920) without scrolling.
/// See DESIGN_SYSTEM.md "Home: multi-mode launcher".
public struct HomeView: View {
    @ObservedObject var store: ProgressStore
    @Binding var activeMode: AppMode
    @Binding var selectedDuration: SessionDuration

    public init(store: ProgressStore, activeMode: Binding<AppMode>, selectedDuration: Binding<SessionDuration>) {
        self.store = store
        self._activeMode = activeMode
        self._selectedDuration = selectedDuration
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            todaysFocusCard
            if store.stats.totalSessions > 0 || store.hasContourData {
                statsRow
            } else {
                noStatsHint
            }
            actionGrid
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(EarTrainColors.bg)
        .onAppear { store.reload() }
    }

    // MARK: - Today's Focus

    private var todaysFocusCard: some View {
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

            Text(done ? "Great session. Keep going or come back tomorrow." : rec.reason)
                .font(.system(size: 13))
                .foregroundColor(EarTrainColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(done ? "Keep Going" : rec.cta) {
                activeMode = done ? .freeplay : rec.mode
            }
            .buttonStyle(AccentButtonStyle())
            .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EarTrainColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
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

    private var noStatsHint: some View {
        Text("Practice a session to see your stats here.")
            .font(.system(size: 12))
            .foregroundColor(EarTrainColors.textDisabled)
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
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Action grid

    private var actionGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 10) {
            // Continue Plan — Phase 2 placeholder; disabled until LessonRunner ships.
            actionCard(
                icon: "play.circle.fill",
                label: "Continue Plan",
                subtitle: "Coming in Phase 2",
                accentBorder: false,
                enabled: false
            ) { }

            // Drill My Misses — enabled when enough data exists.
            let eligible = store.hasDrillableData
            actionCard(
                icon: "target",
                label: "Drill My Misses",
                subtitle: eligible ? "Focus on your weakest areas" : "Practice a few sessions first",
                accentBorder: eligible,
                enabled: eligible
            ) {
                activeMode = .freeplay // TODO Phase 2: route to targeted drill session
            }

            // Freeplay — always available.
            actionCard(
                icon: "square.grid.2x2",
                label: "Freeplay",
                subtitle: "Pick any exercise",
                accentBorder: false,
                enabled: true
            ) {
                activeMode = .freeplay
            }

            // Browse Plans — always available.
            actionCard(
                icon: "book.closed",
                label: "Browse Plans",
                subtitle: "Structured curricula",
                accentBorder: false,
                enabled: true
            ) {
                activeMode = .plans
            }
        }
    }

    private func actionCard(icon: String, label: String, subtitle: String,
                            accentBorder: Bool, enabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(enabled ? EarTrainColors.accent : EarTrainColors.textDisabled)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(enabled ? EarTrainColors.textPrimary : EarTrainColors.textDisabled)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(EarTrainColors.textDisabled)
                }
                Spacer()
            }
            .padding(14)
            .background(EarTrainColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(accentBorder ? EarTrainColors.accent.opacity(0.5) : Color.clear,
                            lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }
}
