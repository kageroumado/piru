import SwiftUI
import SwiftData
import BackgroundTasks

// MARK: - App

@main
struct PiruApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(
                for: DoseEntry.self, SubstanceColor.self, UserColor.self,
                DailyDoseItem.self, FavoriteSubstance.self
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: LiveActivityManager.backgroundTaskIdentifier,
            using: nil
        ) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            Task { @MainActor in
                LiveActivityManager.shared.handleBackgroundRefresh(task)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(Theme.accent)
                .task {
                    SubstanceLibrary.fetchFromAPIs()
                    LiveActivityManager.shared.recoverSession(container: container)
                }
        }
        .modelContainer(container)
    }
}
