import SwiftUI

/// App settings — accessible via the Settings tab in the main navigation.
public struct SettingsView: View {

    @ObservedObject var audio: AudioEngineManager
    @ObservedObject var store: ProgressStore
    @AppStorage(GuitarTimbre.defaultsKey) private var timbreRaw: String = GuitarTimbre.sine.rawValue

    @State private var inputDevices:  [AudioDevice] = []
    @State private var outputDevices: [AudioDevice] = []
    @State private var showClearStreaksConfirm = false

    private var selectedTimbre: GuitarTimbre {
        GuitarTimbre(rawValue: timbreRaw) ?? .sine
    }

    public init(audio: AudioEngineManager, store: ProgressStore) {
        self.audio = audio
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                deviceSection
                toneSection
                dataSection
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EarTrainColors.bg)
        .onAppear { reloadDevices() }
    }

    // MARK: - Device section

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Audio Devices")

            Text("Choose the output device for playback (e.g., your CI Bluetooth stream) and the input device for your guitar. Select \"System Default\" to follow macOS System Settings.")
                .font(.system(size: 13))
                .foregroundColor(EarTrainColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                deviceRow(
                    label: "Output",
                    icon: "speaker.wave.2",
                    devices: outputDevices,
                    selection: $audio.preferredOutputUID
                )
                Divider().background(EarTrainColors.border)
                deviceRow(
                    label: "Input",
                    icon: "mic",
                    devices: inputDevices,
                    selection: $audio.preferredInputUID
                )
            }
            .background(EarTrainColors.surface)
            .cornerRadius(8)

            if audio.isRunning {
                Label("Engine running — changing device restarts audio briefly.",
                      systemImage: "info.circle")
                    .font(.system(size: 11))
                    .foregroundColor(EarTrainColors.textDisabled)
            }
        }
    }

    private func deviceRow(label: String, icon: String,
                           devices: [AudioDevice],
                           selection: Binding<String>) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 15))
                .frame(width: 20)
                .foregroundColor(EarTrainColors.textSecondary)
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(EarTrainColors.textPrimary)
            Spacer()
            Picker("", selection: selection) {
                ForEach(devices) { device in
                    Text(device.name).tag(device.uid)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 200)
            .accentColor(EarTrainColors.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Tone section

    private var toneSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Tone")

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

    // MARK: - Data section

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Data")

            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Clear streak records")
                            .font(.system(size: 14))
                            .foregroundColor(EarTrainColors.textPrimary)
                        Text("Removes all personal-best streak data")
                            .font(.system(size: 11))
                            .foregroundColor(EarTrainColors.textSecondary)
                    }
                    Spacer()
                    Button("Clear") {
                        showClearStreaksConfirm = true
                    }
                    .foregroundColor(.red)
                    .confirmationDialog("Clear all streak records?",
                                        isPresented: $showClearStreaksConfirm,
                                        titleVisibility: .visible) {
                        Button("Clear Records", role: .destructive) {
                            store.clearAllStreakRecords()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This can't be undone.")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(EarTrainColors.surface)
            .cornerRadius(8)
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(EarTrainColors.textSecondary)
            .tracking(1)
    }

    private func reloadDevices() {
        inputDevices  = AudioDeviceList.inputDevices()
        outputDevices = AudioDeviceList.outputDevices()
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

private extension EarTrainColors {
    static let border = Color(hex: "#2d2d2d")
}
