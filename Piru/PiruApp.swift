import SwiftUI
import SwiftData
import BackgroundTasks
import WidgetKit

// MARK: - App

@main
struct PiruApp: App {
    static let appGroupID = "group.dev.yumeji.piru"
    let container: ModelContainer

    init() {
        Self.migrateStoreToAppGroupIfNeeded()

        do {
            let groupURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: Self.appGroupID
            )!.appendingPathComponent("default.store")
            let config = ModelConfiguration(url: groupURL)
            container = try ModelContainer(
                for: DoseEntry.self, SubstanceColor.self, UserColor.self,
                DailyDoseItem.self, FavoriteSubstance.self,
                configurations: config
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
                    WidgetCenter.shared.reloadAllTimelines()
                    SubstanceLibrary.fetchFromAPIs()
                    ActiveSessionManager.shared.recoverSession(container: container)
                    #if DEBUG
                    DemoData.insertShowcaseData(container: container)
                    #endif
                }
        }
        .modelContainer(container)
    }

    /// One-time migration: copies the old app-sandbox SwiftData store to the shared App Group container.
    private static func migrateStoreToAppGroupIfNeeded() {
        let fm = FileManager.default
        guard let groupDir = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else { return }
        let destStore = groupDir.appendingPathComponent("default.store")

        // Already migrated
        guard !fm.fileExists(atPath: destStore.path) else { return }

        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let oldStore = appSupport.appendingPathComponent("default.store")

        // Nothing to migrate
        guard fm.fileExists(atPath: oldStore.path) else { return }

        // Copy all SQLite files (default.store, default.store-shm, default.store-wal)
        do {
            let storeFiles = try fm.contentsOfDirectory(atPath: appSupport.path)
                .filter { $0.hasPrefix("default.store") }
            for file in storeFiles {
                try fm.copyItem(
                    at: appSupport.appendingPathComponent(file),
                    to: groupDir.appendingPathComponent(file)
                )
            }
        } catch {
            // If migration fails, the app will start with an empty store in the group container
        }
    }
}
