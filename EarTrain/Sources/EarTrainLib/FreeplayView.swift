import SwiftUI

/// Freeplay — direct primitive access for testing and casual drilling.
///
/// Shows every built primitive as a card. Tapping a card routes to that
/// primitive's existing exercise view via the shared activeMode binding.
/// Sessions log to the confusion matrix but don't affect any active plan.
///
/// New primitives appear here automatically once they have an AppMode case
/// and an entry in the primitiveCards array below.
public struct FreeplayView: View {
    let contourVM: ContourViewModel
    let identVM: IdentificationViewModel
    let exerciseVM: ExerciseViewModel
    @ObservedObject var store: ProgressStore
    @ObservedObject var audio: AudioEngineManager
    @ObservedObject var companion: CompanionEngine
    @Binding var activeMode: AppMode
    @Binding var selectedDuration: SessionDuration
    let mic: MicrophonePermissionManager

    public init(contourVM: ContourViewModel, identVM: IdentificationViewModel,
                exerciseVM: ExerciseViewModel, store: ProgressStore,
                audio: AudioEngineManager, companion: CompanionEngine,
                activeMode: Binding<AppMode>, selectedDuration: Binding<SessionDuration>,
                mic: MicrophonePermissionManager) {
        self.contourVM = contourVM
        self.identVM = identVM
        self.exerciseVM = exerciseVM
        self.store = store
        self.audio = audio
        self.companion = companion
        self._activeMode = activeMode
        self._selectedDuration = selectedDuration
        self.mic = mic
    }

    // MARK: - Primitive descriptors (extend as new primitives ship)

    private struct PrimitiveCard {
        let mode: AppMode
        let name: String
        let description: String
        let icon: String
        let inputMode: String   // "Listen only" or "Guitar + mic"
        let status: String      // "Built" — only built primitives appear here
    }

    private let primitives: [PrimitiveCard] = [
        PrimitiveCard(
            mode: .contour,
            name: "Contour",
            description: "Two notes — higher, lower, or same?",
            icon: "arrow.up.arrow.down",
            inputMode: "Listen only",
            status: "Built"
        ),
        PrimitiveCard(
            mode: .identification,
            name: "Interval ID",
            description: "Hear an interval and identify it by name.",
            icon: "ear.fill",
            inputMode: "Listen only",
            status: "Built"
        ),
        PrimitiveCard(
            mode: .intervals,
            name: "Interval Playback",
            description: "Hear an interval, then play it back on guitar.",
            icon: "guitars.fill",
            inputMode: "Guitar + mic",
            status: "Built"
        ),
    ]

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            primitiveGrid
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(EarTrainColors.bg)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Freeplay")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(EarTrainColors.textPrimary)
            Text("Pick any exercise to drill directly. Sessions log to your stats but don't affect any active plan.")
                .font(.system(size: 13))
                .foregroundColor(EarTrainColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var primitiveGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260, maximum: 400))], spacing: 12) {
            ForEach(primitives, id: \.mode) { card in
                primitiveCard(card)
            }
        }
    }

    private func primitiveCard(_ card: PrimitiveCard) -> some View {
        Button {
            activeMode = card.mode
        } label: {
            HStack(spacing: 16) {
                Image(systemName: card.icon)
                    .font(.system(size: 22))
                    .foregroundColor(EarTrainColors.accent)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text(card.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(EarTrainColors.textPrimary)
                    Text(card.description)
                        .font(.system(size: 12))
                        .foregroundColor(EarTrainColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 4) {
                        Image(systemName: card.inputMode == "Guitar + mic" ? "mic.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 10))
                        Text(card.inputMode)
                            .font(.system(size: 11))
                    }
                    .foregroundColor(EarTrainColors.textDisabled)
                }

                Spacer()

                Image(systemName: "play.fill")
                    .font(.system(size: 14))
                    .foregroundColor(EarTrainColors.accent)
            }
            .padding(16)
            .background(EarTrainColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(EarTrainColors.accent.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
