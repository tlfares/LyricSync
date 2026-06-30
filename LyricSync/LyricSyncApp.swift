import SwiftUI

@main
struct LyricSyncApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 700, height: 500)
        #endif
    }
}
