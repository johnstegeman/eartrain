import AppKit
import SwiftUI
import EarTrainLib

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // SPM executables don't get .regular activation policy automatically
        // (no .app bundle to declare it). Set it explicitly so the app appears
        // in the Dock and responds to Cmd-Tab like a normal GUI app.
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        setDockIcon()
        // defaultSize is ignored when macOS restores saved window state.
        // Enforce size explicitly and set a sane minimum so the window is freely resizable.
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first else { return }
            window.minSize = NSSize(width: 700, height: 500)
            window.setContentSize(NSSize(width: 1000, height: 700))
            window.center()
        }
    }

    private func setDockIcon() {
        if let image = AudieAvatarView.nsImage {
            NSApp.applicationIconImage = image
        }
    }
}

@main
struct EarTrainApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 700, minHeight: 500)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.automatic)
        .defaultSize(width: 1000, height: 700)
    }
}
