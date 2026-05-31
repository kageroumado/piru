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
        // Recover the canonical store BEFORE opening it: if the App Group store
        // is empty/absent but a legacy or backed-up store holds the user's data,
        // restore it (backing up the empty store first; never deleting). This
        // fixes the widget-creates-empty-store race that stranded data on
        // upgrade. See StoreRecovery.
        StoreRecovery.prepareCanonicalStore()

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

    /// Build the SwiftData `ModelContainer` on the canonical (already-recovered)
    /// store, with the versioned schema + migration plan. If the store can't be
    /// opened (corruption / locked), back it up aside (never delete) and retry;
    /// last resort is an in-memory store so the app launches instead of crashing.
    private static func makeContainer() -> ModelContainer {
        let storeURL = StoreRecovery.canonicalStoreURL()
        let config = ModelConfiguration(url: storeURL)

        let schema = Schema(versionedSchema: PiruSchemaV1.self)
        func open() throws -> ModelContainer {
            try ModelContainer(for: schema, migrationPlan: PiruMigrationPlan.self, configurations: config)
        }

        do {
            return try open()
        } catch {
            appLogger.error("ModelContainer creation failed: \(error.localizedDescription, privacy: .public). Backing up store and retrying.")
            StoreRecovery.backUpStore(at: storeURL, reason: "corrupt")
            do {
                return try open()
            } catch {
                // Last resort: an in-memory store. A background launch before
                // first unlock (data-protection unavailable) or an unrecoverable
                // corruption used to `fatalError` here and crash-loop. Launching
                // with an empty, non-persisted store is strictly better than a
                // crash — foreground launches after unlock get the real store.
                appLogger.fault("ModelContainer recovery failed: \(error.localizedDescription, privacy: .public). Falling back to in-memory store.")
                do {
                    return try ModelContainer(
                        for: schema,
                        configurations: ModelConfiguration(isStoredInMemoryOnly: true),
                    )
                } catch {
                    fatalError("Failed to create even an in-memory ModelContainer: \(error)")
                }
            }
        }
    }
}
