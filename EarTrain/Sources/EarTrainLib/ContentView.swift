import SwiftUI
import AVFoundation

/// Top-level owner of the shared audio engine and all freeplay ViewModels.
/// One AudioEngineManager instance is created here and injected into each VM,
/// ensuring all modes share a single engine (CI keep-alive stays active across
/// tab switches; no redundant mic taps).
@MainActor
final class AppSession: ObservableObject {
    let audio: AudioEngineManager
    let contourVM: ContourViewModel
    let identVM: IdentificationViewModel
    let exerciseVM: ExerciseViewModel

    init() {
        let audio = AudioEngineManager()
        self.audio    = audio
        contourVM     = ContourViewModel(audio: audio)
        identVM       = IdentificationViewModel(audio: audio)
        exerciseVM    = ExerciseViewModel(audio: audio)
    }
}

public struct ContentView: View {
    @StateObject private var session = AppSession()
    @StateObject private var mic = MicrophonePermissionManager()
    @State private var mode: AppMode = .intervals

    public init() {}

    public var body: some View {
        Group {
            if mic.isAuthorized {
                VStack(spacing: 0) {
                    modePicker
                    Divider().background(EarTrainColors.surface)
                    modeContent
                }
            } else if mic.isBlocked {
                MicBlockedView(openSettings: mic.openSystemSettings)
            } else {
                MicRequestView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EarTrainColors.bg)
        .task {
            await mic.requestIfNeeded()
            if mic.isAuthorized { session.audio.start() }
        }
        .onChange(of: mic.isAuthorized) { authorized in
            if authorized { session.audio.start() }
        }
    }

    private var modePicker: some View {
        HStack(spacing: 0) {
            ForEach(AppMode.allCases, id: \.self) { m in
                let selected = mode == m
                Text(m.label)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundColor(selected ? .black : EarTrainColors.textSecondary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(selected ? EarTrainColors.accent : Color.clear)
                    .cornerRadius(6)
                    .contentShape(Rectangle())
                    .onTapGesture { mode = m }
            }
        }
        .padding(4)
        .background(EarTrainColors.surface)
        .cornerRadius(8)
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var modeContent: some View {
        switch mode {
        case .intervals:      ExerciseView(vm: session.exerciseVM)
        case .contour:        ContourView(vm: session.contourVM)
        case .identification: IdentificationView(vm: session.identVM)
        case .settings:       SettingsView()
        }
    }
}

// MARK: - App mode

public enum AppMode: CaseIterable {
    case intervals
    case contour
    case identification
    case settings

    public var label: String {
        switch self {
        case .intervals:      return "Intervals"
        case .contour:        return "Contour"
        case .identification: return "Identify"
        case .settings:       return "Settings"
        }
    }
}

// MARK: - Permission request state

private struct MicRequestView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.circle")
                .font(.system(size: 48))
                .foregroundColor(EarTrainColors.accent)
            Text("Microphone Access")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(EarTrainColors.textPrimary)
            Text("EarTrain CI needs microphone access to hear your guitar playing.")
                .font(.system(size: 14))
                .foregroundColor(EarTrainColors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
    }
}

// MARK: - Permission blocked state

private struct MicBlockedView: View {
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.slash.circle")
                .font(.system(size: 48))
                .foregroundColor(EarTrainColors.error)
            Text("Microphone Access Denied")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(EarTrainColors.textPrimary)
            Text("Open System Settings → Privacy → Microphone and enable EarTrain CI.")
                .font(.system(size: 14))
                .foregroundColor(EarTrainColors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Text("Open System Settings")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.black)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(EarTrainColors.accent)
                .cornerRadius(6)
                .contentShape(Rectangle())
                .onTapGesture { openSettings() }
        }
    }
}

// MARK: - Design tokens

public enum EarTrainColors {
    public static let bg       = Color(hex: "#1a1a1a")
    public static let surface  = Color(hex: "#232323")
    public static let accent   = Color(hex: "#f5a623")
    public static let success  = Color(hex: "#4ade80")
    public static let error    = Color(hex: "#ef4444")
    public static let textPrimary   = Color(hex: "#e0e0e0")
    public static let textSecondary = Color(hex: "#888888")
    public static let textDisabled  = Color(hex: "#555555")
}

// MARK: - Button style

public struct AccentButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.black)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(EarTrainColors.accent.opacity(configuration.isPressed ? 0.8 : 1))
            .cornerRadius(6)
    }
}

// MARK: - Hex color helper

public extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
