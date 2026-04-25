import SwiftUI
import EarTrainLib

@main
struct EarTrainApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1000, height: 700)
    }
}
