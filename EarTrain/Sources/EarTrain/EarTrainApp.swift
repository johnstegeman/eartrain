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
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1000, height: 920)
    }
}
