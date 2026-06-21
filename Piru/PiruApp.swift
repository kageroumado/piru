import BackgroundTasks
import os
import SwiftData
import SwiftUI
import UIKit
import UserNotifications
import WidgetKit

private let appLogger = Logger(subsystem: "dev.yumeji.piru", category: "App")

/// A UIKit background-execution assertion that ends itself exactly once —
/// explicitly via ``end()`` when the protected work finishes, or from the
/// system's expiration handler if time runs out first.
@MainActor
private final class BackgroundTaskAssertion {
    private var id: UIBackgroundTaskIdentifier = .invalid

    init(name: String) {
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            self?.end()
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}

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

        // Bind the user-profile store to the shared container before any view
        // reads disclosure tier / body weight, and run the one-time migration of
        // the legacy GRDB disclosure tier into SwiftData.
        UserProfileStore.shared.configure(container: container)
        // Bind the tolerance engine to the store and load its cached per-target snapshot. Recompute
        // is driven by the dose log when a Stage-2 surface consumes it; configuring here exercises the
        // additive `ToleranceState` schema and makes the cache available.
        ToleranceStore.shared.configure(container: container)

        // Automatic lightweight migration fills the SAME UUID into every
        // pre-existing DoseEntry when it adds `id` (the default expression is
        // evaluated once) — uniquify before any UI reads. Idempotent and cheap
        // when there's nothing to do.
        StoreRecovery.backfillDuplicateEntryIDs(container: container)

        // Routes notification taps (routine reminders carry a piru:// deep
        // link). The center holds its delegate weakly — the shared instance
        // keeps it alive.
        UNUserNotificationCenter.current().delegate = DoseNotificationDelegate.shared

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
                    // Warm the inventory caches so badges/widget read fresh
                    // numbers on first paint (cheap; only touches tracked items).
                    InventoryService.recomputeAll(in: container.mainContext)
                    // If the user connected Apple Health for body weight, silently refresh it
                    // (no prompt). On a revoked/empty read we deliberately KEEP the last-known weight
                    // rather than clear it — a slightly stale real weight beats reverting to the 60 kg
                    // population default. The Body Weight screen surfaces the empty-read state so the
                    // user can re-grant access or update it.
                    if UserProfileStore.shared.weightSource == .healthKit {
                        Task { await HealthKitBodyMass.shared.syncLatest() }
                    }
                    #if DEBUG
                        DemoData.insertShowcaseData(container: container)
                    #endif
                }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            // Coming back to the foreground: re-derive inventory caches so any
            // doses logged from the widget / other surfaces while away are
            // reflected, and a crossed threshold can notify.
            if phase == .active {
                InventoryService.recomputeAll(in: container.mainContext)
            }
            // Opt-in, end-to-end encrypted iCloud backup on backgrounding. No-op
            // unless the user enabled it; debounced and change-gated internally.
            if phase == .background {
                let context = container.mainContext
                // Hold a background-execution assertion across the await so
                // iOS can't suspend the process mid-write; ended on completion
                // or expiration, whichever comes first.
                let assertion = BackgroundTaskAssertion(name: "AutomaticBackup")
                Task {
                    defer { assertion.end() }
                    await BackupManager.shared.runAutomaticBackup(context: context)
                }
            }
        }
    }

    /// Build the SwiftData `ModelContainer` on the canonical (already-recovered)
    /// store. The open path is layered so an upgrade never loses visible data:
    ///
    /// 1. **Automatic lightweight migration** — open the bare current schema with
    ///    *no* explicit `SchemaMigrationPlan`. SwiftData infers the migration from
    ///    whatever shape is on disk to ``StoreRecovery/models``. Every shipped
    ///    change has been additive (new entities, new optional/defaulted
    ///    properties), and this absorbs them all — including the *intermediate*
    ///    dev/TestFlight shapes that previously threw `SwiftDataError 1`, got
    ///    mis-classified as corruption, and stranded data behind a fresh empty
    ///    store. The one non-additive step (per-row `DoseEntry.id`) is finished
    ///    *after* open by ``StoreRecovery/backfillDuplicateEntryIDs(container:)``,
    ///    which uniquifies the shared UUID a lightweight migration fills in. The
    ///    old `PiruMigrationPlan` + frozen `PiruSchemaV1…V5` are retired; see the
    ///    schema-migration policy block in ``StoreRecovery``.
    /// 2. **Preserve + in-memory** — if the store still won't open, it is NOT
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

        // 1. Automatic lightweight migration (also the fresh-install path).
        //    SwiftData infers the migration from the on-disk shape to the current
        //    models; the post-open backfill in `init` uniquifies any shared
        //    DoseEntry.id the lightweight `id` migration filled in.
        do {
            return try ModelContainer(for: Schema(StoreRecovery.models), configurations: config)
        } catch {
            // 2. Preserve the store untouched; launch in-memory and flag the UI.
            appLogger.fault("Store open failed under automatic lightweight migration: \(error.localizedDescription, privacy: .public). Preserving the store on disk and launching in-memory; data is not lost.")
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
