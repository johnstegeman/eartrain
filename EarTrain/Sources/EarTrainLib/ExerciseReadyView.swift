import SwiftUI

/// Duration intent for a practice session.
/// Shown on the pre-exercise ready screen and in the Session Start Sheet on HomeView.
/// The value is informational for now — no automatic timer yet (that's Phase 1.5).
public enum SessionDuration: CaseIterable {
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
    @Binding var volume: Float
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            // Icon + title + description
            VStack(spacing: 10) {
                AudiePNGImage(size: 72)
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

            // Volume slider
            VolumeSlider(volume: $volume)

            // Start button
            Button("Start") { onStart() }
                .buttonStyle(AccentButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EarTrainColors.bg)
    }

    private func durationPill(_ duration: SessionDuration) -> some View {
        let selected = selectedDuration == duration
        return Button(duration.label) { selectedDuration = duration }
            .font(.system(size: 13, weight: selected ? .semibold : .regular))
            .lineLimit(1)
            .foregroundColor(selected ? .black : EarTrainColors.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(selected ? EarTrainColors.accent : EarTrainColors.surface)
            .cornerRadius(8)
            .buttonStyle(.plain)
    }
}

// MARK: - Difficulty indicator

/// Five dots showing current difficulty level (1–5).
/// Filled dots = at or below current level; empty = above.
struct DifficultyDots: View {
    let level: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(1...5), id: \.self) { i in
                Circle()
                    .fill(i <= level
                          ? EarTrainColors.accent
                          : EarTrainColors.textDisabled.opacity(0.4))
                    .frame(width: 6, height: 6)
            }
        }
    }
}

/// Tappable difficulty indicator. Shows 5 dots; tapping opens a popover to pick a level.
/// Used in the running-exercise header bar.
struct DifficultyControl: View {
    let level: Int
    let descriptions: [String]   // 5 strings, index 0 = level 1
    let onSelect: (Int) -> Void
    @State private var showPopover = false

    var body: some View {
        DifficultyDots(level: level)
            .contentShape(Rectangle())
            .onTapGesture { showPopover = true }
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                difficultyPopover
                    .background(EarTrainColors.bg)
            }
    }

    private var difficultyPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("DIFFICULTY")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundColor(EarTrainColors.textSecondary)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            ForEach(Array(1...5), id: \.self) { lvl in
                HStack(spacing: 10) {
                    HStack(spacing: 2) {
                        ForEach(Array(1...5), id: \.self) { i in
                            Circle()
                                .fill(i <= lvl
                                      ? EarTrainColors.accent
                                      : EarTrainColors.textDisabled.opacity(0.3))
                                .frame(width: 5, height: 5)
                        }
                    }
                    Text(lvl - 1 < descriptions.count ? descriptions[lvl - 1] : "Level \(lvl)")
                        .font(.system(size: 13))
                        .foregroundColor(lvl == level
                                         ? EarTrainColors.textPrimary
                                         : EarTrainColors.textSecondary)
                    Spacer()
                    if lvl == level {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(EarTrainColors.accent)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(lvl == level ? EarTrainColors.surface : Color.clear)
                .contentShape(Rectangle())
                .onTapGesture {
                    onSelect(lvl)
                    showPopover = false
                }
            }
            .padding(.bottom, 10)
        }
        .frame(width: 280)
    }
}

// MARK: - Shared volume slider

/// Compact speaker-icon + slider control. Used on both the ready screen and
/// the running-exercise header. Binds directly to AudioEngineManager.outputVolume.
struct VolumeSlider: View {
    @Binding var volume: Float

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 12))
                .foregroundColor(EarTrainColors.textDisabled)
            Slider(value: $volume, in: 0...1)
                .frame(maxWidth: 200)
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 12))
                .foregroundColor(EarTrainColors.textDisabled)
        }
    }
}
