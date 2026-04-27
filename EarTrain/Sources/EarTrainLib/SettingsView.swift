import SwiftUI

/// App settings — presented as a sheet (⌘,) so the user can change
/// settings mid-session without losing their place.
public struct SettingsView: View {

    @ObservedObject var audio: AudioEngineManager
    @ObservedObject var store: ProgressStore
    @AppStorage(GuitarTimbre.defaultsKey) private var timbreRaw: String = GuitarTimbre.sine.rawValue
    @Environment(\.dismiss) private var dismiss

    @State private var inputDevices:  [AudioDevice] = []
    @State private var outputDevices: [AudioDevice] = []
    @State private var showClearStreaksConfirm = false
    @State private var showClearAllConfirm = false

    // Mastery gate controls — backed by MasterySettings / UserDefaults
    @State private var masteryAccuracy:    Double = MasterySettings.accuracyThreshold
    @State private var masteryMinTrials:   Double = Double(MasterySettings.minTrialsPerBucket)
    @State private var masteryMinDiff:     Double = Double(MasterySettings.minDifficulty)
    @State private var masteryWindow:      Double = Double(MasterySettings.recencyWindow)
    @State private var masteryReqGap12:    Bool   = MasterySettings.requireGap1_2
    @State private var masterySoftAt:      Double = Double(MasterySettings.softAdvanceAt)

    private var selectedTimbre: GuitarTimbre {
        GuitarTimbre(rawValue: timbreRaw) ?? .sine
    }

    public init(audio: AudioEngineManager, store: ProgressStore) {
        self.audio = audio
        self.store = store
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Sheet header with dismiss
            HStack {
                Text("Settings")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(EarTrainColors.textPrimary)
                Spacer()
                Button("Done") { dismiss() }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(EarTrainColors.accent)
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .padding(.bottom, 16)

            Divider().background(Color(hex: "#2d2d2d"))

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    deviceSection
                    toneSection
                    masterySection
                    dataSection
                }
                .padding(32)
            }
        }
        .frame(width: 540, height: 700)
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
            .clipShape(RoundedRectangle(cornerRadius: 8))

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

    // MARK: - Mastery gates section

    private var masterySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Mastery Gates")

            // Accuracy — slider (wide enough to be usable)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Accuracy required (per bucket)")
                        .font(.system(size: 13))
                        .foregroundColor(EarTrainColors.textPrimary)
                    Spacer()
                    Text("\(Int(masteryAccuracy * 100))%")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(EarTrainColors.accent)
                        .frame(width: 36, alignment: .trailing)
                }
                Slider(value: $masteryAccuracy, in: 0.60...0.95, step: 0.05)
                    .tint(EarTrainColors.accent)
                    .onChange(of: masteryAccuracy) { MasterySettings.accuracyThreshold = $0 }
            }
            .padding(.vertical, 2)

            // Steppers replaced with +/− buttons for dark-mode visibility
            masteryStepRow(label: "Min trials per bucket",
                           value: Int(masteryMinTrials), unit: nil,
                           range: 5...30, step: 1) { masteryMinTrials += $0
                MasterySettings.minTrialsPerBucket = Int(masteryMinTrials) }

            masteryStepRow(label: "Min difficulty to count",
                           value: Int(masteryMinDiff), unit: "/ 5",
                           range: 1...5, step: 1) { masteryMinDiff += $0
                MasterySettings.minDifficulty = Int(masteryMinDiff) }

            masteryStepRow(label: "Recency window",
                           value: Int(masteryWindow), unit: "trials",
                           range: 10...50, step: 5) { masteryWindow += $0
                MasterySettings.recencyWindow = Int(masteryWindow) }

            masteryStepRow(label: "\"Advance anyway\" after",
                           value: Int(masterySoftAt), unit: "trials",
                           range: 40...200, step: 10) { masterySoftAt += $0
                MasterySettings.softAdvanceAt = Int(masterySoftAt) }

            // Toggle
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Require 1–2 semitone buckets")
                        .font(.system(size: 13))
                        .foregroundColor(EarTrainColors.textPrimary)
                    Text("Off by default — very hard for CI users")
                        .font(.system(size: 11))
                        .foregroundColor(EarTrainColors.textDisabled)
                }
                Spacer()
                Toggle("", isOn: $masteryReqGap12)
                    .toggleStyle(.switch)
                    .tint(EarTrainColors.accent)
                    .onChange(of: masteryReqGap12) { MasterySettings.requireGap1_2 = $0 }
            }
            .padding(.vertical, 2)

            Text("These thresholds control when the curriculum advances. The difficulty gate is a floor — you can always keep working at higher difficulty in Freeplay.")
                .font(.system(size: 11))
                .foregroundColor(EarTrainColors.textDisabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A row with visible +/− buttons instead of the nearly-invisible macOS Stepper.
    private func masteryStepRow(label: String, value: Int, unit: String?,
                                 range: ClosedRange<Double>, step: Double,
                                 onChange: @escaping (Double) -> Void) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(EarTrainColors.textPrimary)
            Spacer()
            HStack(spacing: 0) {
                stepButton("−", enabled: Double(value) > range.lowerBound) { onChange(-step) }
                Text(unit != nil ? "\(value) \(unit!)" : "\(value)")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(EarTrainColors.accent)
                    .frame(minWidth: 56, alignment: .center)
                stepButton("+", enabled: Double(value) < range.upperBound) { onChange(step) }
            }
            .background(EarTrainColors.bg)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(.vertical, 2)
    }

    private func stepButton(_ label: String, enabled: Bool,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 32, height: 28)
                .foregroundColor(enabled ? EarTrainColors.textPrimary : EarTrainColors.textDisabled)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: - Data section

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Data")

            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reset all progress")
                            .font(.system(size: 14))
                            .foregroundColor(EarTrainColors.textPrimary)
                        Text("Deletes sessions, accuracy data, and streaks")
                            .font(.system(size: 11))
                            .foregroundColor(EarTrainColors.textSecondary)
                    }
                    Spacer()
                    Button("Reset") { showClearAllConfirm = true }
                        .foregroundColor(.red)
                        .confirmationDialog("Reset all progress?",
                                            isPresented: $showClearAllConfirm,
                                            titleVisibility: .visible) {
                            Button("Reset Everything", role: .destructive) {
                                store.clearAllProgress()
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("This permanently deletes your session history, accuracy data, and streak records. It can't be undone.")
                        }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider().background(EarTrainColors.border)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Clear streak records only")
                            .font(.system(size: 14))
                            .foregroundColor(EarTrainColors.textPrimary)
                        Text("Keeps session history, removes personal bests")
                            .font(.system(size: 11))
                            .foregroundColor(EarTrainColors.textSecondary)
                    }
                    Spacer()
                    Button("Clear") { showClearStreaksConfirm = true }
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
            .clipShape(RoundedRectangle(cornerRadius: 8))
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
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

private extension EarTrainColors {
    static let border = Color(hex: "#2d2d2d")
}
