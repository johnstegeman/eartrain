import SwiftUI

/// Active interval-training exercise screen (guitar playback mode).
public struct ExerciseView: View {
    @ObservedObject var vm: ExerciseViewModel
    @ObservedObject var store: ProgressStore
    @ObservedObject var audio: AudioEngineManager
    @ObservedObject var companion: CompanionEngine
    @Binding var activeMode: AppMode
    @Binding var selectedDuration: SessionDuration
    @State private var sessionSummary: SessionEndSummary? = nil

    public init(vm: ExerciseViewModel, store: ProgressStore, audio: AudioEngineManager,
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
                ExerciseReadyView(mode: .intervals, selectedDuration: $selectedDuration,
                                  volume: $audio.outputVolume) {
                    companion.sessionStarted()
                    vm.beginSession(duration: selectedDuration)
                    vm.startExercise()
                }
            } else {
                VStack(spacing: 0) {
                    endSessionBar
                    VStack(spacing: 0) {
                        Spacer(minLength: 20)
                        VStack(spacing: 28) {
                            intervalDisplay
                            statusPanel
                            controls
                        }
                        Spacer(minLength: 20)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .overlay(alignment: .bottom) {
                    AudieChatPanel(companion: companion)
                }
            }
        }
        .onAppear {
            companion.difficultyDelegate = vm
            vm.onTrialResult = { [weak companion, weak store, weak vm] correct in
                companion?.recordOutcome(correct: correct)
                guard let companion, let store, let vm else { return }
                let isNewBest = store.updateStreakIfRecord(modeKey: "intervals",
                                                          difficulty: vm.difficultyLevel,
                                                          streak: companion.currentStreak)
                if isNewBest { companion.announcePersonalBest(streak: companion.currentStreak) }
            }
        }
        .onDisappear {
            if companion.difficultyDelegate === vm { companion.difficultyDelegate = nil }
            vm.onTrialResult = nil
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
            mode: .intervals,
            totalTrials: vm.totalTrials,
            correctTrials: vm.correctTrials,
            duration: vm.sessionDuration
        )
        vm.cancel()
        sessionSummary = summary
    }

    // MARK: - Interval display

    private var intervalDisplay: some View {
        VStack(spacing: 8) {
            Text(vm.currentInterval.shortName)
                .font(.system(size: 72, weight: .black))
                .foregroundColor(EarTrainColors.textPrimary)
            Text(vm.currentInterval.displayName)
                .font(.system(size: 14))
                .foregroundColor(EarTrainColors.textSecondary)
            Text(rootLabel)
                .font(.system(size: 12))
                .foregroundColor(EarTrainColors.textDisabled)
        }
        .padding(32)
        .background(EarTrainColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var rootLabel: String {
        let noteName = NoteConverter.name(fromHz: vm.rootHz)
        let targetHz = vm.currentInterval.targetHz(rootHz: vm.rootHz)
        let targetName = NoteConverter.name(fromHz: targetHz)
        return "\(noteName) → \(targetName)"
    }

    // MARK: - Status

    private var phaseIndex: Int {
        switch vm.phase {
        case .idle:             return 0
        case .playing:          return 1
        case .awaitingRoot:     return 2
        case .awaitingInterval: return 3
        case .result:           return 4
        case .noRead:           return 5
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
            case .awaitingRoot:
                HStack(spacing: 8) {
                    Image(systemName: "mic.fill")
                    Text("Play the root note")
                }
                .foregroundColor(EarTrainColors.textPrimary)
                .font(.system(size: 16, weight: .semibold))
                .transition(.opacity)
            case .awaitingInterval:
                HStack(spacing: 8) {
                    Image(systemName: "mic.fill")
                    Text("Now play the interval")
                }
                .foregroundColor(EarTrainColors.accent)
                .font(.system(size: 16, weight: .semibold))
                .transition(.opacity)
            case .result(let result):
                resultBadge(result)
                    .transition(.opacity)
            case .noRead:
                VStack(spacing: 8) {
                    Text("Couldn't detect pitch")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(EarTrainColors.textSecondary)
                    Text("Try playing louder or check your input device")
                        .font(.system(size: 12))
                        .foregroundColor(EarTrainColors.textDisabled)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: phaseIndex)
        .frame(height: 60)
    }

    private func statusText(_ text: String, color: Color) -> some View {
        Text(text).font(.system(size: 16)).foregroundColor(color)
    }

    private func resultBadge(_ result: ExerciseResult) -> some View {
        HStack(spacing: 10) {
            Image(systemName: resultIcon(result))
                .font(.system(size: 20))
            VStack(alignment: .leading, spacing: 2) {
                Text(resultTitle(result))
                    .font(.system(size: 15, weight: .semibold))
                if let sub = resultSubtitle(result) {
                    Text(sub)
                        .font(.system(size: 12))
                        .foregroundColor(EarTrainColors.textSecondary)
                }
            }
        }
        .foregroundColor(resultColor(result))
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(resultColor(result).opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Controls

    private var controls: some View {
        let replayDisabled = vm.phase == .playing
        return HStack(spacing: 16) {
            Button("Replay") { vm.replayInterval() }
                .buttonStyle(AccentButtonStyle())
                .disabled(replayDisabled)

            if vm.phase == .noRead {
                Button("Try Again") { vm.replayInterval() }
                    .buttonStyle(AccentButtonStyle())
            }
        }
    }

    // MARK: - Result helpers

    private func resultIcon(_ r: ExerciseResult) -> String {
        switch r {
        case .correct:         return "checkmark.circle.fill"
        case .close:           return "circle.dotted"
        case .octaveDisplaced: return "arrow.up.arrow.down.circle"
        case .wrong:           return "xmark.circle.fill"
        }
    }

    private func resultTitle(_ r: ExerciseResult) -> String {
        switch r {
        case .correct:            return "Correct"
        case .close(let p):       return "Close — heard \(p.shortName)"
        case .octaveDisplaced:    return "Right interval, wrong octave"
        case .wrong(let p):       return "Wrong — played \(p.shortName)"
        }
    }

    private func resultSubtitle(_ r: ExerciseResult) -> String? {
        switch r {
        case .correct:            return nil
        case .close(let p):       return "You played \(p.displayName) instead"
        case .octaveDisplaced:    return "Same pitch class, different octave"
        case .wrong(let p):       return "You played \(p.displayName)"
        }
    }

    private func resultColor(_ r: ExerciseResult) -> Color {
        switch r {
        case .correct:            return EarTrainColors.success
        case .close:              return EarTrainColors.accent
        case .octaveDisplaced:    return EarTrainColors.accent
        case .wrong:              return EarTrainColors.error
        }
    }

}

