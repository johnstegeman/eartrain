import SwiftUI

/// Contour Mode — "Higher, Lower, or Same?"
///
/// The most basic pitch discrimination exercise: the app plays two notes and
/// the user identifies whether the second was higher, lower, or the same as
/// the first. Designed as the entry point for CI users who are not yet ready
/// for interval identification.
public struct ContourView: View {
    @ObservedObject var vm: ContourViewModel
    @ObservedObject var store: ProgressStore
    @ObservedObject var audio: AudioEngineManager
    @Binding var activeMode: AppMode

    @Binding var selectedDuration: SessionDuration
    @State private var sessionSummary: SessionEndSummary? = nil

    public init(vm: ContourViewModel, store: ProgressStore, audio: AudioEngineManager,
                activeMode: Binding<AppMode>, selectedDuration: Binding<SessionDuration>) {
        self.vm = vm
        self.store = store
        self.audio = audio
        self._activeMode = activeMode
        self._selectedDuration = selectedDuration
    }

    public var body: some View {
        Group {
            if vm.phase == .idle {
                ExerciseReadyView(mode: .contour, selectedDuration: $selectedDuration,
                                  volume: $audio.outputVolume) {
                    vm.beginSession()
                    vm.startExercise()
                }
            } else {
                VStack(spacing: 0) {
                    endSessionBar
                    VStack(spacing: 32) {
                        scorePanel
                        statusPanel
                        answerButtons
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onDisappear { vm.cancel() }
        .sheet(item: $sessionSummary) { summary in
            EndOfSessionView(summary: summary, store: store, activeMode: $activeMode)
        }
    }

    private var endSessionBar: some View {
        HStack {
            VolumeSlider(volume: $audio.outputVolume)
            Spacer()
            Button("End Session") { endSession() }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(EarTrainColors.textDisabled)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private func endSession() {
        let summary = SessionEndSummary(
            mode: .contour,
            totalTrials: vm.totalTrials,
            correctTrials: vm.correctTrials,
            duration: vm.sessionDuration
        )
        vm.cancel()
        sessionSummary = summary
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

    // MARK: - Status

    private var statusPanel: some View {
        Group {
            switch vm.phase {
            case .idle:
                statusText("Ready", color: EarTrainColors.textSecondary)

            case .playing:
                HStack(spacing: 8) {
                    Image(systemName: "speaker.wave.2.fill")
                    Text("Listen…")
                }
                .foregroundColor(EarTrainColors.accent)
                .font(.system(size: 16, weight: .semibold))

            case .awaitingAnswer:
                VStack(spacing: 4) {
                    Text("Was the second note…")
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
                        .onTapGesture { vm.replayPair() }
                }

            case .result(let correct, let answer):
                resultBadge(correct: correct, answer: answer)
            }
        }
        .frame(height: 72)
    }

    private func statusText(_ text: String, color: Color) -> some View {
        Text(text).font(.system(size: 16)).foregroundColor(color)
    }

    private func resultBadge(correct: Bool, answer: ContourViewModel.Contour) -> some View {
        HStack(spacing: 10) {
            Image(systemName: correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 20))
            VStack(alignment: .leading, spacing: 2) {
                Text(correct ? "Correct!" : "Not quite")
                    .font(.system(size: 15, weight: .semibold))
                if !correct {
                    Text("It was \(answer.label.lowercased())")
                        .font(.system(size: 12))
                        .foregroundColor(EarTrainColors.textSecondary)
                }
            }
        }
        .foregroundColor(correct ? EarTrainColors.success : EarTrainColors.error)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background((correct ? EarTrainColors.success : EarTrainColors.error).opacity(0.12))
        .cornerRadius(10)
    }

    // MARK: - Answer buttons

    private var answerButtons: some View {
        let isDisabled = vm.phase == .playing || vm.phase == .idle
        return HStack(spacing: 16) {
            ForEach(ContourViewModel.Contour.allCases, id: \.self) { contour in
                contourButton(contour, disabled: isDisabled)
            }
        }
    }

    private func contourButton(_ contour: ContourViewModel.Contour, disabled: Bool) -> some View {
        VStack(spacing: 6) {
            Image(systemName: contour.icon)
                .font(.system(size: 22))
            Text(contour.label)
                .font(.system(size: 14, weight: .semibold))
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
        .opacity(disabled ? 0.4 : 1)
        .contentShape(Rectangle())
        .onTapGesture { if !disabled { vm.answer(contour) } }
    }
}

// MARK: - Button style (internal — shared with IdentificationView)

struct ContourButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(EarTrainColors.textPrimary)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(EarTrainColors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(EarTrainColors.accent.opacity(configuration.isPressed ? 0.8 : 0.3),
                                    lineWidth: 1.5)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
    }
}
