import SwiftUI

/// Identification Mode — "Is this a m3?"
public struct IdentificationView: View {
    @ObservedObject var vm: IdentificationViewModel
    @ObservedObject var store: ProgressStore
    @ObservedObject var audio: AudioEngineManager
    @ObservedObject var companion: CompanionEngine
    @Binding var activeMode: AppMode
    @Binding var selectedDuration: SessionDuration
    @State private var sessionSummary: SessionEndSummary? = nil

    public init(vm: IdentificationViewModel, store: ProgressStore, audio: AudioEngineManager,
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
                ExerciseReadyView(mode: .identification, selectedDuration: $selectedDuration,
                                  volume: $audio.outputVolume) {
                    companion.sessionStarted()
                    vm.beginSession(duration: selectedDuration)
                    vm.startSession()
                }
            } else {
                VStack(spacing: 0) {
                    endSessionBar
                    VStack(spacing: 28) {
                        scorePanel
                        teachPanel
                        statusPanel
                        answerButtons
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .overlay(alignment: .bottom) {
                    AudieChatPanel(companion: companion)
                }
            }
        }
        .onAppear  { companion.difficultyDelegate = vm }
        .onDisappear {
            if companion.difficultyDelegate === vm { companion.difficultyDelegate = nil }
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
            mode: .identification,
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

    // MARK: - Teaching panel

    private var teachPanel: some View {
        VStack(spacing: 8) {
            Text(vm.focusInterval.shortName)
                .font(.system(size: 64, weight: .black))
                .foregroundColor(EarTrainColors.textPrimary)
            Text(vm.focusInterval.displayName)
                .font(.system(size: 14))
                .foregroundColor(EarTrainColors.textSecondary)
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
                Text(" ").font(.system(size: 12))
            }
        }
        .padding(24)
        .background(EarTrainColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .animation(.easeInOut(duration: 0.2), value: phaseIsTeaching)
    }

    private var phaseIsTeaching: Bool {
        if case .teaching = vm.phase { return true }
        return false
    }

    // MARK: - Status panel

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
                    Button("Replay") { vm.replayQuiz() }
                        .buttonStyle(AccentButtonStyle())
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
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Yes / No buttons

    private var answerButtons: some View {
        let enabled: Bool
        if case .awaitingAnswer = vm.phase { enabled = true }
        else { enabled = false }

        return HStack(spacing: 24) {
            answerButton(label: "Yes", icon: "checkmark", enabled: enabled) {
                vm.answer(true) { correct in
                    companion.recordOutcome(correct: correct)
                    let isNewBest = store.updateStreakIfRecord(modeKey: "identification",
                                                              difficulty: vm.difficultyLevel,
                                                              streak: companion.currentStreak)
                    if isNewBest { companion.announcePersonalBest(streak: companion.currentStreak) }
                }
            }
            answerButton(label: "No", icon: "xmark", enabled: enabled) {
                vm.answer(false) { correct in
                    companion.recordOutcome(correct: correct)
                    let isNewBest = store.updateStreakIfRecord(modeKey: "identification",
                                                              difficulty: vm.difficultyLevel,
                                                              streak: companion.currentStreak)
                    if isNewBest { companion.announcePersonalBest(streak: companion.currentStreak) }
                }
            }
        }
    }

    private func answerButton(label: String, icon: String, enabled: Bool,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                Text(label)
                    .font(.system(size: 15, weight: .semibold))
            }
            .frame(width: 90, height: 72)
            .contentShape(Rectangle())
        }
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
        .opacity(enabled ? 1 : 0.4)
        .disabled(!enabled)
    }

}
