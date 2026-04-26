import SwiftUI

/// Active interval-training exercise screen.
/// Wired to ExerciseViewModel for state; AudioEngineManager is owned by the parent.
public struct ExerciseView: View {
    @ObservedObject var vm: ExerciseViewModel

    public init(vm: ExerciseViewModel) { self.vm = vm }

    public var body: some View {
        VStack(spacing: 32) {
            intervalDisplay
            statusPanel
            controls
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            vm.beginSession()
            vm.startExercise()
        }
        .onDisappear { vm.cancel() }
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
        .cornerRadius(12)
    }

    private var rootLabel: String {
        let noteName = NoteConverter.name(fromHz: vm.rootHz)
        let targetHz = vm.currentInterval.targetHz(rootHz: vm.rootHz)
        let targetName = NoteConverter.name(fromHz: targetHz)
        return "\(noteName) → \(targetName)"
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

            case .awaitingRoot:
                HStack(spacing: 8) {
                    Image(systemName: "mic.fill")
                    Text("Play the root note")
                }
                .foregroundColor(EarTrainColors.textPrimary)
                .font(.system(size: 16, weight: .semibold))

            case .awaitingInterval:
                HStack(spacing: 8) {
                    Image(systemName: "mic.fill")
                    Text("Now play the interval")
                }
                .foregroundColor(EarTrainColors.accent)
                .font(.system(size: 16, weight: .semibold))

            case .result(let result):
                resultBadge(result)

            case .noRead:
                VStack(spacing: 8) {
                    Text("Couldn't detect pitch")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(EarTrainColors.textSecondary)
                    Text("Try playing louder or check your input device")
                        .font(.system(size: 12))
                        .foregroundColor(EarTrainColors.textDisabled)
                }
            }
        }
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
        .cornerRadius(10)
    }

    // MARK: - Controls

    private var controls: some View {
        let replayDisabled = vm.phase == .playing
        return HStack(spacing: 16) {
            Text("Replay")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.black)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(EarTrainColors.accent.opacity(replayDisabled ? 0.5 : 1))
                .cornerRadius(6)
                .contentShape(Rectangle())
                .onTapGesture { if !replayDisabled { vm.replayInterval() } }

            if vm.phase == .noRead {
                Text("Try Again")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(EarTrainColors.accent)
                    .cornerRadius(6)
                    .contentShape(Rectangle())
                    .onTapGesture { vm.replayInterval() }
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
        case .close:              return EarTrainColors.warning
        case .octaveDisplaced:    return EarTrainColors.warning
        case .wrong:              return EarTrainColors.error
        }
    }
}

private extension EarTrainColors {
    static let warning = Color(hex: "#f5a623")   // same as accent per design system
}
