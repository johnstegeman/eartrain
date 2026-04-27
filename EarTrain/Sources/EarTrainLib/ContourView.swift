import SwiftUI

/// Contour Mode — "Higher, Lower, or Same?"
public struct ContourView: View {
    @ObservedObject var vm: ContourViewModel
    @ObservedObject var store: ProgressStore
    @ObservedObject var audio: AudioEngineManager
    @ObservedObject var companion: CompanionEngine
    @Binding var activeMode: AppMode
    @Binding var selectedDuration: SessionDuration
    @State private var sessionSummary: SessionEndSummary? = nil

    public init(vm: ContourViewModel, store: ProgressStore, audio: AudioEngineManager,
                companion: CompanionEngine, activeMode: Binding<AppMode>,
                selectedDuration: Binding<SessionDuration>) {
        self.vm = vm
        self.store = store
        self.audio = audio
        self.companion = companion
        self._activeMode = activeMode
        self._selectedDuration = selectedDuration
    }

    public var body: some View {
        Group {
            if vm.phase == .idle {
                ExerciseReadyView(mode: .contour, selectedDuration: $selectedDuration,
                                  volume: $audio.outputVolume) {
                    companion.sessionStarted()
                    vm.beginSession(duration: selectedDuration)
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
                    AudieChatPanel(companion: companion)
                }
            }
        }
        .onAppear {
            companion.difficultyDelegate = vm
            companion.onFocusArea = { [weak vm] area in vm?.focusRegister(named: area) }
        }
        .onDisappear {
            if companion.difficultyDelegate === vm { companion.difficultyDelegate = nil }
            companion.onFocusArea = nil
            vm.clearRegisterFocus()
            vm.cancel()
        }
        .onChange(of: vm.sessionExpired) { expired in
            if expired { endSession() }
        }
        .sheet(item: $sessionSummary) { summary in
            EndOfSessionView(summary: summary, store: store, activeMode: $activeMode)
        }
    }

    private var endSessionBar: some View {
        ExerciseSessionBar(
            volume: $audio.outputVolume,
            difficultyLevel: vm.difficultyLevel,
            difficultyDescriptions: vm.difficultyDescriptions,
            timeRemainingSeconds: vm.timeRemainingSeconds,
            onDifficultyChange: { vm.difficultyLevel = $0 },
            onEnd: endSession
        )
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
            Text(vm.totalTrials == 0 ? "—" : "\(vm.correctTrials)/\(vm.totalTrials)")
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

    private var phaseIndex: Int {
        switch vm.phase {
        case .idle:           return 0
        case .playing:        return 1
        case .awaitingAnswer: return 2
        case .result:         return 3
        }
    }

    private var statusPanel: some View {
        Group {
            switch vm.phase {
            case .idle:
                statusText("Ready", color: EarTrainColors.textSecondary)
                    .transition(.opacity)
            case .playing:
                HStack(spacing: 8) {
                    Image(systemName: "speaker.wave.2.fill")
                    Text("Listen…")
                }
                .foregroundColor(EarTrainColors.accent)
                .font(.system(size: 16, weight: .semibold))
                .transition(.opacity)
            case .awaitingAnswer:
                VStack(spacing: 4) {
                    Text("Was the second note…")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(EarTrainColors.textPrimary)
                    Button("Replay") { vm.replayPair() }
                        .buttonStyle(AccentButtonStyle())
                }
                .transition(.opacity)
            case .result(let correct, let answer):
                VStack(spacing: 8) {
                    resultBadge(correct: correct, answer: answer)
                    if !correct {
                        Text("Hear it again")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(EarTrainColors.accent)
                            .contentShape(Rectangle())
                            .onTapGesture { vm.replayAfterResult() }
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: phaseIndex)
        .frame(minHeight: 72)
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
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
        Button {
            vm.answer(contour) { correct in
                let context = TrialContext(areaName: vm.currentRegisterName)
                companion.recordOutcome(correct: correct, context: context)
                let isNewBest = store.updateStreakIfRecord(modeKey: "contour",
                                                          difficulty: vm.difficultyLevel,
                                                          streak: companion.currentStreak)
                if isNewBest { companion.announcePersonalBest(streak: companion.currentStreak) }
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: contour.icon)
                    .font(.system(size: 22))
                Text(contour.label)
                    .font(.system(size: 14, weight: .semibold))
            }
        }
        .frame(width: 90, height: 72)
        .foregroundColor(EarTrainColors.textPrimary)
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(EarTrainColors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(EarTrainColors.accent.opacity(0.3), lineWidth: 1.5)
                )
        )
        .opacity(disabled ? 0.4 : 1)
        .disabled(disabled)
    }

}

// MARK: - Button style (shared with IdentificationView)

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
