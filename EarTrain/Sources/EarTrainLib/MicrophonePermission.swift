import AVFoundation
import AppKit

/// Manages microphone authorization state and permission requests.
@MainActor
public final class MicrophonePermissionManager: ObservableObject {
    @Published public var status: AVAuthorizationStatus

    public init() {
        status = AVCaptureDevice.authorizationStatus(for: .audio)
    }

    /// Request access if not yet determined. No-op for any other status.
    public func requestIfNeeded() async {
        guard status == .notDetermined else { return }
        _ = await AVCaptureDevice.requestAccess(for: .audio)
        status = AVCaptureDevice.authorizationStatus(for: .audio)
    }

    /// Open System Settings → Privacy → Microphone.
    public func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    /// True when the user has blocked access and the app cannot request again.
    public var isBlocked: Bool {
        status == .denied || status == .restricted
    }

    /// True when access is confirmed.
    public var isAuthorized: Bool {
        status == .authorized
    }
}

// MARK: - Testable status helpers

public extension AVAuthorizationStatus {
    var isBlockingMicAccess: Bool { self == .denied || self == .restricted }
    var isAuthorizedMicAccess: Bool { self == .authorized }
}
