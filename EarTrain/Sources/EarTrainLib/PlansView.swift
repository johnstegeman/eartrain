import SwiftUI

/// Plans library — browse bundled and user-imported lesson plans.
///
/// Phase 2 placeholder: shows bundled plan cards and an active-plan slot.
/// Actual .etplan parsing, LessonRunner, and plan execution arrive in Phase 2.
/// See PLAN.md Phase 2 and DESIGN_SYSTEM.md "Plans library".
public struct PlansView: View {
    @Binding var activeMode: AppMode
    @State private var selectedPlan: PlaceholderPlan? = nil

    public init(activeMode: Binding<AppMode>) {
        self._activeMode = activeMode
    }

    // MARK: - Placeholder plan data

    struct PlaceholderPlan: Identifiable {
        let id = UUID()
        let name: String
        let tagline: String
        let stepCount: Int
        let estimatedSessions: Int
        let icon: String
    }

    private let bundledPlans: [PlaceholderPlan] = [
        PlaceholderPlan(
            name: "Beginner CI",
            tagline: "Start from the very beginning — melodic direction, then intervals.",
            stepCount: 12,
            estimatedSessions: 6,
            icon: "1.circle.fill"
        ),
        PlaceholderPlan(
            name: "Intermediate",
            tagline: "Build on the basics with harmonic intervals and scale degrees.",
            stepCount: 18,
            estimatedSessions: 10,
            icon: "2.circle.fill"
        ),
    ]

    // MARK: - Body

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                activePlanSection
                availablePlansSection
            }
            .padding(24)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EarTrainColors.bg)
        .sheet(item: $selectedPlan) { plan in
            planDetailSheet(plan)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Plans")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(EarTrainColors.textPrimary)
            Text("Structured curricula for guided practice. Import a custom .etplan from your audiologist or guitar teacher.")
                .font(.system(size: 13))
                .foregroundColor(EarTrainColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Active plan

    private var activePlanSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Active Plan")

            HStack(spacing: 16) {
                Image(systemName: "play.circle")
                    .font(.system(size: 28))
                    .foregroundColor(EarTrainColors.textDisabled)

                VStack(alignment: .leading, spacing: 4) {
                    Text("No active plan")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(EarTrainColors.textPrimary)
                    Text("Plan running comes in Phase 2. For now, use Freeplay or Drill My Misses on Home.")
                        .font(.system(size: 12))
                        .foregroundColor(EarTrainColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .padding(16)
            .background(EarTrainColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(EarTrainColors.textDisabled.opacity(0.3), lineWidth: 1)
            )
        }
    }

    // MARK: - Available plans

    private var availablePlansSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionLabel("Available Plans")
                Spacer()
                Button {
                    // TODO Phase 2: open NSOpenPanel for .etplan import
                } label: {
                    Label("Import .etplan", systemImage: "square.and.arrow.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(EarTrainColors.accent)
                }
                .buttonStyle(.plain)
                .disabled(true)
                .opacity(0.5)
            }

            ForEach(bundledPlans) { plan in
                planCard(plan)
            }
        }
    }

    private func planCard(_ plan: PlaceholderPlan) -> some View {
        Button {
            selectedPlan = plan
        } label: {
            HStack(spacing: 16) {
                Image(systemName: plan.icon)
                    .font(.system(size: 22))
                    .foregroundColor(EarTrainColors.accent)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(EarTrainColors.textPrimary)
                    Text(plan.tagline)
                        .font(.system(size: 12))
                        .foregroundColor(EarTrainColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Text("\(plan.stepCount) steps")
                        Text("·")
                        Text("~\(plan.estimatedSessions) sessions")
                    }
                    .font(.system(size: 11))
                    .foregroundColor(EarTrainColors.textDisabled)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(EarTrainColors.textDisabled)
            }
            .padding(16)
            .background(EarTrainColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Plan detail sheet

    private func planDetailSheet(_ plan: PlaceholderPlan) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.name)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(EarTrainColors.textPrimary)
                    Text("\(plan.stepCount) steps · ~\(plan.estimatedSessions) sessions")
                        .font(.system(size: 13))
                        .foregroundColor(EarTrainColors.textSecondary)
                }
                Spacer()
                Button("Done") { selectedPlan = nil }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(EarTrainColors.accent)
            }

            Divider().background(Color(hex: "#2d2d2d"))

            Text(plan.tagline)
                .font(.system(size: 14))
                .foregroundColor(EarTrainColors.textSecondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Plan running coming in Phase 2")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(EarTrainColors.textPrimary)
                Text("The LessonRunner engine that executes .etplan files is tracked in PLAN.md Phase 2. In the meantime, use Freeplay to drill specific exercises or Drill My Misses on Home for targeted weakness practice.")
                    .font(.system(size: 13))
                    .foregroundColor(EarTrainColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(EarTrainColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 12) {
                Button("Go to Freeplay") {
                    selectedPlan = nil
                    activeMode = .freeplay
                }
                .buttonStyle(AccentButtonStyle())

                Button("Go to Home") {
                    selectedPlan = nil
                    activeMode = .home
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(EarTrainColors.textSecondary)
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(24)
        .frame(width: 400, alignment: .leading)
        .background(EarTrainColors.bg)
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.8)
            .foregroundColor(EarTrainColors.textSecondary)
            .textCase(.uppercase)
    }
}
