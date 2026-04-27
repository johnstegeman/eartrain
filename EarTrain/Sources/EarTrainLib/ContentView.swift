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
                HStack(spacing: 0) {
                    sidebar
                    Divider()
                        .background(Color(hex: "#2d2d2d"))
                    modeContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(AppMode.allCases, id: \.self) { m in
                Button {
                    mode = m
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: m.icon)
                            .font(.system(size: 14))
                            .frame(width: 18, alignment: .center)
                        Text(m.label)
                            .font(.system(size: 13, weight: mode == m ? .semibold : .regular))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(mode == m ? EarTrainColors.accent.opacity(0.15) : Color.clear)
                    .foregroundColor(mode == m ? EarTrainColors.accent : EarTrainColors.textSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .frame(width: 200)
        .frame(maxHeight: .infinity)
        .background(EarTrainColors.surface)
    }

    @ViewBuilder
    private var modeContent: some View {
        switch mode {
        case .home:
            HomeView(store: session.progressStore, activeMode: $mode, selectedDuration: $sessionDuration)
        case .tuner:
            TunerView(audio: session.audio)
        case .plans:
            PlansView(activeMode: $mode)
        case .freeplay:
            FreeplayView(contourVM: session.contourVM, identVM: session.identVM,
                         exerciseVM: session.exerciseVM, store: session.progressStore,
                         audio: session.audio, companion: session.companion,
                         activeMode: $mode, selectedDuration: $sessionDuration,
                         mic: mic)
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
    // Sidebar destinations
    case home
    case tuner
    case plans
    case freeplay
    case progress
    case settings
    // Primitive modes — not sidebar items; reached via FreeplayView or direct routing.
    // Kept as AppMode cases so exercise views, SessionEndSummary, and CompanionEngine
    // can reference them without a separate type.
    case contour
    case intervals
    case identification

    // Only the 6 sidebar destinations appear in the nav list.
    public static var allCases: [AppMode] {
        [.home, .tuner, .plans, .freeplay, .progress, .settings]
    }

    public var label: String {
        switch self {
        case .home:           return "Home"
        case .tuner:          return "Tune"
        case .plans:          return "Plans"
        case .freeplay:       return "Freeplay"
        case .progress:       return "Progress"
        case .settings:       return "Settings"
        case .intervals:      return "Intervals"
        case .contour:        return "Contour"
        case .identification: return "Identify"
        }
    }

    public var icon: String {
        switch self {
        case .home:           return "house.fill"
        case .tuner:          return "tuningfork"
        case .plans:          return "book.closed"
        case .freeplay:       return "square.grid.2x2"
        case .progress:       return "chart.bar.fill"
        case .settings:       return "gearshape.fill"
        case .intervals:      return "guitars.fill"
        case .contour:        return "arrow.up.arrow.down"
        case .identification: return "ear.fill"
        }
    }

    public var exerciseDescription: String {
        switch self {
        case .home:           return ""
        case .tuner:          return "Check your tuning before you practice"
        case .plans:          return "Browse and manage lesson plans"
        case .freeplay:       return "Pick any exercise to drill directly"
        case .progress:       return ""
        case .settings:       return ""
        case .intervals:      return "Play back intervals on your guitar — mic grades your response"
        case .contour:        return "Higher, lower, or same? The simplest pitch discrimination exercise"
        case .identification: return "Hear an interval and identify it by ear only"
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
            .clipShape(RoundedRectangle(cornerRadius: 6))
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
