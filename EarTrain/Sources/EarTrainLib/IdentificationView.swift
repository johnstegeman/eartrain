import SwiftUI

/// Identification Mode — "Is this a m3?"
///
/// Listening-only ear training. The app teaches an interval by playing and
/// labelling it, then immediately quizzes with an unlabelled pair.
public struct IdentificationView: View {
    @ObservedObject var vm: IdentificationViewModel

    public init(vm: IdentificationViewModel) { self.vm = vm }

    public var body: some View {
        VStack(spacing: 28) {
            scorePanel
            teachPanel
            statusPanel
            answerButtons
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear  { vm.startSession() }
        .onDisappear { vm.cancel() }
    }

    // MARK: - Score

    private var scorePanel: some View {
        HStack(spacing: 4) {
            Text(vm.totalTrials == 0
                 ? "—"
                 : "\(vm.correctTrials)/\(vm.totalTrials)")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(EarTrainColors.textSecondary)
            if vm.totalTrials > 0 {
                Text("(\(Int(Double(vm.correctTrials) / Double(vm.totalTrials) * 100))%)")
                    .font(.system(size: 12))
                    .foregroundColor(EarTrainColors.textDisabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    // MARK: - Teaching panel (shows focus interval name)

    private var teachPanel: some View {
        VStack(spacing: 8) {
            // Short name — big, always visible as the "thing being learned"
            Text(vm.focusInterval.shortName)
                .font(.system(size: 64, weight: .black))
                .foregroundColor(EarTrainColors.textPrimary)
            Text(vm.focusInterval.displayName)
                .font(.system(size: 14))
                .foregroundColor(EarTrainColors.textSecondary)

            // Teaching label — only shown during the teach phase
            if case .teaching = vm.phase {
                HStack(spacing: 6) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 12))
                    Text("This is a \(vm.focusInterval.displayName)")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(EarTrainColors.accent)
                .transition(.opacity)
            } else {
                // Placeholder keeps layout stable
                Text(" ")
                    .font(.system(size: 12))
            }
        }
        .padding(24)
        .background(EarTrainColors.surface)
        .cornerRadius(12)
        .animation(.easeInOut(duration: 0.2), value: phaseIsTeaching)
    }

    private var phaseIsTeaching: Bool {
        if case .teaching = vm.phase { return true }
        return false
    }

    // MARK: - Status panel (quiz prompt / result)

    private var statusPanel: some View {
        Group {
            switch vm.phase {
            case .idle:
                EmptyView()

            case .teaching:
                EmptyView()

            case .playingQuiz:
                HStack(spacing: 8) {
                    Image(systemName: "speaker.wave.2.fill")
                    Text("Is this a \(vm.focusInterval.displayName)?")
                }
                .foregroundColor(EarTrainColors.accent)
                .font(.system(size: 16, weight: .semibold))

            case .awaitingAnswer:
                VStack(spacing: 6) {
                    Text("Is this a \(vm.focusInterval.displayName)?")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(EarTrainColors.textPrimary)
                    Text("Replay")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(EarTrainColors.accent)
                        .cornerRadius(6)
                        .contentShape(Rectangle())
                        .onTapGesture { vm.replayQuiz() }
                }

            case .result(let correct, let wasTarget, let actual):
                resultBadge(correct: correct, wasTarget: wasTarget, actual: actual)
            }
        }
        .frame(height: 72)
    }

    private func resultBadge(correct: Bool, wasTarget: Bool, actual: Interval) -> some View {
        HStack(spacing: 10) {
            Image(systemName: correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 20))
            VStack(alignment: .leading, spacing: 2) {
                Text(correct ? "Correct!" : "Not quite")
                    .font(.system(size: 15, weight: .semibold))
                Text(wasTarget
                     ? "That was a \(actual.displayName)"
                     : "That was a \(actual.displayName), not a \(vm.focusInterval.displayName)")
                    .font(.system(size: 12))
                    .foregroundColor(EarTrainColors.textSecondary)
            }
        }
        .foregroundColor(correct ? EarTrainColors.success : EarTrainColors.error)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background((correct ? EarTrainColors.success : EarTrainColors.error).opacity(0.12))
        .cornerRadius(10)
    }

    // MARK: - Yes / No buttons

    private var answerButtons: some View {
        let enabled: Bool
        if case .awaitingAnswer = vm.phase { enabled = true }
        else { enabled = false }

        return HStack(spacing: 24) {
            answerButton(label: "Yes", icon: "checkmark", enabled: enabled) {
                vm.answer(true)
            }
            answerButton(label: "No", icon: "xmark", enabled: enabled) {
                vm.answer(false)
            }
        }
    }

    private func answerButton(label: String, icon: String, enabled: Bool,
                               action: @escaping () -> Void) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
            Text(label)
                .font(.system(size: 15, weight: .semibold))
        }
        .frame(width: 90, height: 72)
        .foregroundColor(EarTrainColors.textPrimary)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(EarTrainColors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(EarTrainColors.accent.opacity(0.3), lineWidth: 1.5)
                )
        )
        .opacity(enabled ? 1 : 0.4)
        .contentShape(Rectangle())
        .onTapGesture { if enabled { action() } }
    }
}

// MARK: - Reuse ContourButtonStyle

// Defined in ContourView.swift — visible within the module.
