import SwiftUI

@main
struct PiruWatchApp: App {
    @State private var sync = WatchSyncCoordinator.shared

    var body: some Scene {
        WindowGroup {
            QuickLogWatchView()
                .environment(sync)
                .task { sync.activate() }
        }
    }
}
