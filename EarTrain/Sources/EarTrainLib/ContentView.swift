import Combine
import SwiftUI
import AVFoundation

/// Top-level owner of the shared audio engine, companion, and all exercise ViewModels.
@MainActor
final class AppSession: ObservableObject {
    let audio: AudioEngineManager
    let companion: CompanionEngine
    let contourVM: ContourViewModel
    let identVM: IdentificationViewModel
    let exerciseVM: ExerciseViewModel
    let progressStore = ProgressStore()

    private var cancellable: AnyCancellable?

    init() {
        let audio = AudioEngineManager()
        let companion = CompanionEngine()
        self.audio     = audio
        self.companion = companion
        contourVM  = ContourViewModel(audio: audio)
        identVM    = IdentificationViewModel(audio: audio)
        exerciseVM = ExerciseViewModel(audio: audio)

        // Forward companion changes to AppSession so ContentView re-renders
        // when hasCompletedOnboarding (or any companion state) changes.
        cancellable = companion.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
    }
}

public struct ContentView: View {
    @StateObject private var session = AppSession()
    @StateObject private var mic = MicrophonePermissionManager()
    @State private var mode: AppMode = .home
    @State private var sessionDuration: SessionDuration = .open

    public init() {}

    public var body: some View {
        Group {
            if !session.companion.hasCompletedOnboarding {
                OnboardingView(companion: session.companion)
            } else {
                VStack(spacing: 0) {
                    modePicker
                    Divider().background(EarTrainColors.surface)
                    modeContent
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EarTrainColors.bg)
        .task {
            await mic.requestIfNeeded()
            // Engine can start without mic — tap is installed lazily per-exercise.
            session.audio.start()
        }
        .onChange(of: mic.isAuthorized) { _ in
            if !session.audio.isRunning { session.audio.start() }
        }
        .onAppear {
            // Wire companion's mode-switch action to this view's mode binding.
            session.companion.onSwitchMode = { [weak session] newMode in
                self.mode = newMode
                // Cancel whatever is currently in progress when switching mode.
                session?.contourVM.cancel()
                session?.identVM.cancel()
                session?.exerciseVM.cancel()
            }
        }
    }

    private var modePicker: some View {
        HStack(spacing: 0) {
            ForEach(AppMode.allCases, id: \.self) { m in
                let selected = mode == m
                Button(m.label) { mode = m }
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundColor(selected ? .black : EarTrainColors.textSecondary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(selected ? EarTrainColors.accent : Color.clear)
                    .cornerRadius(6)
                    .buttonStyle(.plain)
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
        case .home:
            HomeView(store: session.progressStore, activeMode: $mode, selectedDuration: $sessionDuration)
        case .tuner:
            TunerView(audio: session.audio)
        case .intervals:
            if mic.isBlocked {
                MicBlockedView(openSettings: mic.openSystemSettings)
            } else if !mic.isAuthorized {
                MicRequestView()
            } else {
                ExerciseView(vm: session.exerciseVM, store: session.progressStore,
                             audio: session.audio, companion: session.companion,
                             activeMode: $mode, selectedDuration: $sessionDuration)
            }
        case .contour:
            ContourView(vm: session.contourVM, store: session.progressStore,
                        audio: session.audio, companion: session.companion,
                        activeMode: $mode, selectedDuration: $sessionDuration)
        case .identification:
            IdentificationView(vm: session.identVM, store: session.progressStore,
                               audio: session.audio, companion: session.companion,
                               activeMode: $mode, selectedDuration: $sessionDuration)
        case .progress:
            ProgressView(store: session.progressStore)
        case .settings:
            SettingsView(audio: session.audio, store: session.progressStore)
        }
    }
}

// MARK: - App mode

public enum AppMode: CaseIterable {
    case home
    case tuner
    case contour
    case intervals
    case identification
    case progress
    case settings

    public var label: String {
        switch self {
        case .home:           return "Home"
        case .tuner:          return "Tune"
        case .intervals:      return "Intervals"
        case .contour:        return "Contour"
        case .identification: return "Identify"
        case .progress:       return "Progress"
        case .settings:       return "Settings"
        }
    }

    public var icon: String {
        switch self {
        case .home:           return "house.fill"
        case .tuner:          return "tuningfork"
        case .intervals:      return "guitars.fill"
        case .contour:        return "arrow.up.arrow.down"
        case .identification: return "ear.fill"
        case .progress:       return "chart.bar.fill"
        case .settings:       return "gearshape.fill"
        }
    }

    public var exerciseDescription: String {
        switch self {
        case .home:           return ""
        case .tuner:          return "Check your tuning before you practice"
        case .intervals:      return "Play back intervals on your guitar — mic grades your response"
        case .contour:        return "Higher, lower, or same? The simplest pitch discrimination exercise"
        case .identification: return "Hear an interval and identify it by ear only"
        case .progress:       return ""
        case .settings:       return ""
        }
    }
}

// MARK: - Permission views

private struct MicRequestView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.circle")
                .font(.system(size: 48))
                .foregroundColor(EarTrainColors.accent)
            Text("Microphone Access")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(EarTrainColors.textPrimary)
            Text("Audie needs microphone access to hear your guitar playing.")
                .font(.system(size: 14))
                .foregroundColor(EarTrainColors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
    }
}

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
            Text("Open System Settings → Privacy → Microphone and enable Audie.")
                .font(.system(size: 14))
                .foregroundColor(EarTrainColors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button("Open System Settings") { openSettings() }
                .buttonStyle(AccentButtonStyle())
        }
    }
}

// MARK: - Design tokens

public enum EarTrainColors {
    public static let bg           = Color(hex: "#1a1a1a")
    public static let surface      = Color(hex: "#232323")
    public static let accent       = Color(hex: "#f5a623")
    public static let success      = Color(hex: "#4ade80")
    public static let inTuneFlash  = Color(hex: "#86efac")  // brighter green for steady in-tune
    public static let error        = Color(hex: "#ef4444")
    public static let textPrimary   = Color(hex: "#e0e0e0")
    public static let textSecondary = Color(hex: "#888888")
    public static let textDisabled  = Color(hex: "#555555")

    public static func accuracy(_ value: Double) -> Color {
        value >= 0.80 ? success : value >= 0.50 ? accent : error
    }
}

// MARK: - Button style

public struct AccentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.black)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(EarTrainColors.accent.opacity(!isEnabled ? 0.5 : configuration.isPressed ? 0.8 : 1))
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
