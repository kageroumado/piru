import BackgroundTasks
import os
import SwiftData
import SwiftUI
import WidgetKit

private let appLogger = Logger(subsystem: "dev.yumeji.piru", category: "App")

// MARK: - App

@main
struct PiruApp: App {
    static let appGroupID = "group.dev.yumeji.piru"
    let container: ModelContainer

    init() {
        Self.migrateStoreToAppGroupIfNeeded()

        container = Self.makeContainer()

        // Register on the main queue so the launch handler runs on the MainActor
        // executor. Otherwise — under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` —
        // this closure is inferred as @MainActor, and BGTaskScheduler invoking it
        // from a background queue (the default for `using: nil`) trips the Swift
        // runtime's entry isolation guard and crashes.
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: LiveActivityManager.backgroundTaskIdentifier,
            using: .main,
        ) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            LiveActivityManager.shared.handleBackgroundRefresh(task)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(Theme.accent)
                .task {
                    WidgetCenter.shared.reloadAllTimelines()
                    // Touch the store so its singleton init runs (opens the
                    // SQLite, seeds preferences) before the first view query.
                    _ = SubstanceStore.shared.count
                    ActiveSessionManager.shared.recoverSession(container: container)
                    #if DEBUG
                        DemoData.insertShowcaseData(container: container)
                    #endif
                }
        }
        .modelContainer(container)
    }

    /// Build the SwiftData `ModelContainer`. If the store is corrupt and fails
    /// to open, move the offending files aside and try once more so the user
    /// at least gets a working (empty) database instead of a launch crash.
    private static func makeContainer() -> ModelContainer {
        // Don't force-unwrap the app-group URL: if the entitlement is ever
        // misconfigured this would be a launch crash. Fall back to Application
        // Support so the app still launches with a (non-shared) store.
        let groupBase = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let groupURL = groupBase.appendingPathComponent("default.store")
        let config = ModelConfiguration(url: groupURL)
        let models: [any PersistentModel.Type] = [
            DoseEntry.self, SubstanceColor.self, UserColor.self,
            DailyDoseItem.self, FavoriteSubstance.self,
        ]

        do {
            return try ModelContainer(for: Schema(models), configurations: config)
        } catch {
            appLogger.error("ModelContainer creation failed: \(error.localizedDescription, privacy: .public). Attempting store recovery.")
            quarantineCorruptStore(at: groupURL)
            do {
                return try ModelContainer(for: Schema(models), configurations: config)
            } catch {
                // Last resort: an in-memory store. A background launch before
                // first unlock (data-protection unavailable) or an unrecoverable
                // corruption used to `fatalError` here and crash-loop. Launching
                // with an empty, non-persisted store is strictly better than a
                // crash — foreground launches after unlock get the real store.
                appLogger.fault("ModelContainer recovery failed: \(error.localizedDescription, privacy: .public). Falling back to in-memory store.")
                do {
                    return try ModelContainer(
                        for: Schema(models),
                        configurations: ModelConfiguration(isStoredInMemoryOnly: true),
                    )
                } catch {
                    fatalError("Failed to create even an in-memory ModelContainer: \(error)")
                }
            }
        }
    }

    /// Rename `default.store{,-shm,-wal}` to `default.store.corrupt-<timestamp>{,-shm,-wal}`
    /// so SwiftData can create a fresh store on the next attempt.
    private static func quarantineCorruptStore(at storeURL: URL) {
        let fm = FileManager.default
        let directory = storeURL.deletingLastPathComponent()
        let timestamp = Int(Date().timeIntervalSince1970)
        let suffixes = ["", "-shm", "-wal"]

        for suffix in suffixes {
            let source = directory.appendingPathComponent("default.store\(suffix)")
            guard fm.fileExists(atPath: source.path) else { continue }
            let destination = directory.appendingPathComponent("default.store.corrupt-\(timestamp)\(suffix)")
            do {
                try fm.moveItem(at: source, to: destination)
                appLogger.notice("Quarantined corrupt store file: \(destination.lastPathComponent, privacy: .public)")
            } catch {
                appLogger.error("Failed to quarantine \(source.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
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
                    to: groupDir.appendingPathComponent(file),
                )
            }
        } catch {
            // If migration fails, the app will start with an empty store in the group container
        }
    }
}
