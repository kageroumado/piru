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
    @Environment(\.scenePhase) private var scenePhase

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
                    // Backfill sessions for any pre-session-model history. Idempotent
                    // and failure-isolated (only sets the optional relationship).
                    SessionService.ensureSessionsPopulated(in: container.mainContext)
                    ActiveSessionManager.shared.recoverSession(container: container)
                    #if DEBUG
                        DemoData.insertShowcaseData(container: container)
                    #endif
                }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            // Opt-in, end-to-end encrypted iCloud backup on backgrounding. No-op
            // unless the user enabled it; debounced and change-gated internally.
            if phase == .background {
                let context = container.mainContext
                Task { await BackupManager.shared.runAutomaticBackup(context: context) }
            }
        }
    }

    /// Build the SwiftData `ModelContainer` on the canonical (already-recovered)
    /// store. The open path is layered so an upgrade never loses visible data:
    ///
    /// 1. **Versioned migration** — the explicit `PiruMigrationPlan`. Succeeds for
    ///    a fresh install (creates the store) and for any store already at V1/V2.
    /// 2. **Automatic lightweight migration** — open the bare current schema with
    ///    *no* plan. SwiftData then infers a migration from whatever shape is on
    ///    disk. This absorbs *intermediate* dev/TestFlight schemas that match
    ///    neither V1 nor V2 exactly — the case that previously threw
    ///    `SwiftDataError 1`, got mis-classified as corruption, and stranded the
    ///    user's data behind a fresh empty store.
    /// 3. **Preserve + in-memory** — if the store still won't open, it is NOT
    ///    replaced. The bytes stay on disk untouched (a future version can recover
    ///    them), ``StoreLaunchState`` is flagged so the UI shows a reassuring
    ///    "temporarily unavailable" alert, and the app launches on a transient
    ///    in-memory store rather than crashing or silently resetting.
    ///
    /// The old behaviour — quarantine-on-any-error then open a fresh empty store —
    /// is gone: an empty store the user could write fresh data into is the
    /// worst outcome, fragmenting data across two stores.
    private static func makeContainer() -> ModelContainer {
        let storeURL = StoreRecovery.canonicalStoreURL()
        // .none is critical: the app carries iCloud (CloudDocuments) entitlements
        // for encrypted file backups, and SwiftData would otherwise auto-enable
        // CloudKit mirroring — which this schema can't satisfy (non-optional
        // attributes, .unique constraints), failing every container open.
        let config = ModelConfiguration(url: storeURL, cloudKitDatabase: .none)

        // 1. Explicit versioned migration (also the fresh-install path).
        do {
            return try ModelContainer(
                for: Schema(versionedSchema: PiruSchemaV3.self),
                migrationPlan: PiruMigrationPlan.self,
                configurations: config,
            )
        } catch {
            appLogger.error("Versioned-plan open failed: \(error.localizedDescription, privacy: .public). Trying automatic lightweight migration.")
        }

        // 2. Automatic lightweight migration — absorbs intermediate schemas.
        do {
            let container = try ModelContainer(for: Schema(StoreRecovery.models), configurations: config)
            appLogger.notice("Opened store via automatic lightweight migration after the versioned plan failed.")
            return container
        } catch {
            // 3. Preserve the store untouched; launch in-memory and flag the UI.
            appLogger.fault("Store open failed under both the versioned plan and automatic migration: \(error.localizedDescription, privacy: .public). Preserving the store on disk and launching in-memory; data is not lost.")
            StoreLaunchState.shared.storeUnavailable = true
            StoreLaunchState.shared.failureDetail = error.localizedDescription
            do {
                return try ModelContainer(
                    for: Schema(StoreRecovery.models),
                    configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none),
                )
            } catch {
                fatalError("Failed to create even an in-memory ModelContainer: \(error)")
            }
        }
    }
}
