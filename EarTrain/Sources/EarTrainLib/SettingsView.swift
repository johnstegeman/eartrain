import SwiftUI

/// App settings — accessible via the Settings tab in the main navigation.
/// Timbre is persisted in UserDefaults. The AudioEngineManager in each exercise
/// tab reads the current value at start and on each play call.
public struct SettingsView: View {

    @AppStorage(GuitarTimbre.defaultsKey) private var timbreRaw: String = GuitarTimbre.sine.rawValue

    private var selectedTimbre: GuitarTimbre {
        GuitarTimbre(rawValue: timbreRaw) ?? .sine
    }

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                toneSection
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EarTrainColors.bg)
    }

    // MARK: - Tone section

    private var toneSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tone")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(EarTrainColors.textSecondary)
                .textCase(.uppercase)
                .tracking(1)

            Text("Choose the sound used to play intervals. Guitar timbres use recorded samples — pick the one that's easiest to hear with your cochlear implant.")
                .font(.system(size: 13))
                .foregroundColor(EarTrainColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                ForEach(GuitarTimbre.allCases) { timbre in
                    TimbreRow(
                        timbre: timbre,
                        isSelected: selectedTimbre == timbre,
                        onTap: { timbreRaw = timbre.rawValue }
                    )
                }
            }
        }
    }
}

// MARK: - Timbre row

private struct TimbreRow: View {
    let timbre: GuitarTimbre
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: timbre.systemImage)
                .font(.system(size: 18))
                .frame(width: 24)
                .foregroundColor(isSelected ? .black : EarTrainColors.textPrimary)

            Text(timbre.label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isSelected ? .black : EarTrainColors.textPrimary)

            Spacer()

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.black)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(isSelected ? EarTrainColors.accent : EarTrainColors.surface)
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}
