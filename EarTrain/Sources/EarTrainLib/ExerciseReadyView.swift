import SwiftUI

/// Duration intent for a practice session.
/// Shown on the pre-exercise ready screen and in the Session Start Sheet on HomeView.
/// The value is informational for now — no automatic timer yet (that's Phase 1.5).
enum SessionDuration: CaseIterable {
    case five, ten, twenty, thirty, open

    var label: String {
        switch self {
        case .five:   return "5 min"
        case .ten:    return "10 min"
        case .twenty: return "20 min"
        case .thirty: return "30 min"
        case .open:   return "Open"
        }
    }

    var minutes: Int? {
        switch self {
        case .five:   return 5
        case .ten:    return 10
        case .twenty: return 20
        case .thirty: return 30
        case .open:   return nil
        }
    }
}

/// Pre-exercise landing screen shown when an exercise view's phase is `.idle`.
///
/// Gives the user a moment to set duration and explicitly choose to start,
/// rather than playing audio immediately on tab navigation.
struct ExerciseReadyView: View {
    let mode: AppMode
    @Binding var selectedDuration: SessionDuration
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            // Icon + title + description
            VStack(spacing: 10) {
                Image(systemName: mode.icon)
                    .font(.system(size: 44))
                    .foregroundColor(EarTrainColors.accent)
                Text(mode.label)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(EarTrainColors.textPrimary)
                Text(mode.exerciseDescription)
                    .font(.system(size: 13))
                    .foregroundColor(EarTrainColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }

            // Duration picker
            VStack(spacing: 10) {
                Text("Duration".uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundColor(EarTrainColors.textSecondary)
                HStack(spacing: 8) {
                    ForEach(SessionDuration.allCases, id: \.self) { d in
                        durationPill(d)
                    }
                }
            }

            // Start button
            Button("Start") { onStart() }
                .buttonStyle(AccentButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EarTrainColors.bg)
    }

    private func durationPill(_ duration: SessionDuration) -> some View {
        let selected = selectedDuration == duration
        return Text(duration.label)
            .font(.system(size: 13, weight: selected ? .semibold : .regular))
            .foregroundColor(selected ? .black : EarTrainColors.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(selected ? EarTrainColors.accent : EarTrainColors.surface)
            .cornerRadius(8)
            .contentShape(Rectangle())
            .onTapGesture { selectedDuration = duration }
    }
}
