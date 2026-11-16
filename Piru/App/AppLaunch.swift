import Foundation
import SwiftData

/// The launch and lifecycle policy every host runs: recovering and opening the
/// journal store, the passes and migrations after the first frame, and what a
/// return to the foreground or a move to the background does.
///
/// `PiruApp` (iOS, macOS) and the Android host both call these, in this order:
///
/// 1. ``openStore()`` once, before any view reads the store;
/// 2. ``finishLaunching(container:hooks:)`` from the root view's `.task`;
/// 3. ``becameActive(container:)`` on every return to the foreground;
/// 4. ``enteredBackground(container:)`` on every move to the background.
///
/// A host adds only what its platform owns (widgets, Live Activities, the watch,
/// background tasks, HealthKit, StoreKit, TipKit), around these calls or through
/// ``Hooks``, so this file compiles without those frameworks.
enum AppLaunch {
    /// Platform work ``finishLaunching(container:hooks:)`` runs at fixed points.
    struct Hooks {
        /// Runs once the launch is counted and whether any dose was ever logged
        /// is known, before the migrations. iOS configures TipKit here.
        var engagementKnown: (_ hasLoggedDose: Bool) -> Void = { _ in }
        /// Runs after the migrations and the reminder sync, before the DEBUG
        /// fixtures. iOS refreshes the HealthKit body weight here.
        var passesFinished: () -> Void = {}
    }

    // MARK: - Before the first frame

    /// Recover and open the active profile's store, and bind every
    /// store-backed singleton to it. An open failure runs the app on an
    /// in-memory store and flags ``StoreLaunchState``; see
    /// ``StoreRecovery/openContainer(at:)``.
    @discardableResult
    static func openStore() -> ModelContainer {
        // The owner's store is recovered BEFORE it opens: if it is empty or
        // absent but a legacy or backed-up store holds the user's data, that is
        // restored (backing up the empty store first; never deleting). This
        // covers the widget-creates-empty-store race. Another profile's store
        // just opens. See ProfileDirectory and StoreRecovery.
        let container = ProfileDirectory.shared.openActiveStore()

        // Before any view reads the profile, the tolerance cache, custom
        // substances and units, or the notification choices the schedulers
        // gate on. Each binding's one-time migrations run here too.
        StoreBinding.bindAll(to: container)
        // Point `Skin.current` at the observable store so the semantic-color
        // shorthands in Shared/ follow a skin change, not a UserDefaults snapshot.
        SkinStore.activate()

        // Automatic lightweight migration fills the SAME UUID into every
        // pre-existing DoseEntry when it adds `id` (the default expression is
        // evaluated once) — uniquify before any UI reads. Idempotent; gated so
        // the full-log fetch runs once per build and store change.
        LaunchPassGate.run("duplicateEntryIDs", container: container) {
            StoreRecovery.backfillDuplicateEntryIDs(container: container)
        }

        // Register every notification category once, here — not as a side
        // effect of whichever type happens to schedule first.
        DoseNotificationManager.registerCategories()

        return container
    }

    /// A profile switch opened `container`: the passes a launch runs over a
    /// store, for this one, since it may never have been opened in this
    /// process (or ever). Every pass is idempotent or gated per profile.
    static func profileOpened(container: ModelContainer) async {
        LaunchPassGate.run("duplicateEntryIDs", container: container) {
            StoreRecovery.backfillDuplicateEntryIDs(container: container)
        }
        SubstanceColorStore.refreshDefaults(in: container.mainContext)
        await LaunchPassGate.runAsync("substanceColorMint", container: container) {
            await SubstanceColorStore.mintMissingRows(
                container: container, defaults: SubstanceColorStore.backgroundDefaults,
            )
        }
        runStorePasses(container: container)
        await DoseNotificationManager.syncMedRemindersIfNeeded(container: container)
    }

    // MARK: - After the first frame

    /// The launch passes: warm the substance catalog, count the launch, run the
    /// store's migrations and backfills, restore the active session, and roll
    /// the reminder horizon forward. Call once from the root view's `.task`.
    static func finishLaunching(container: ModelContainer, hooks: Hooks = Hooks()) async {
        // Touch the store so its singleton init runs (opens the SQLite, seeds
        // preferences) before the first view query — then await the batch
        // prefill it kicked off. Everything below (session backfill's per-dose
        // duration resolve, the PSID backfill, demo seeding) resolves
        // substances, and a resolve against a cold batch builds it
        // synchronously on the main actor.
        _ = SubstanceStore.shared.count
        await SubstanceStore.shared.ensureAllLoaded()
        // Building the product-med map publishes its mirror, which the widgets
        // and the off-main adherence scans read.
        _ = CustomSubstanceStore.shared.productMeds
        // Publish every substance's class color, bring the stored default rows
        // in line with it, and mint rows for substances logged where there was
        // no catalog (watch, widget intent).
        SubstanceColorStore.installCatalogTints()
        SubstanceColorStore.refreshDefaults(in: container.mainContext)
        Task(name: "Mint substance color rows") {
            await LaunchPassGate.runAsync("substanceColorMint", container: container) {
                await SubstanceColorStore.mintMissingRows(
                    container: container, defaults: SubstanceColorStore.backgroundDefaults,
                )
            }
        }
        // First-run nudge sequencing: bump the launch counter and record whether a dose
        // has ever been logged, so the tips ladder (log a dose → where settings live) and
        // the Discord invite only surface once the user is genuinely engaged.
        let launches = UserDefaults.standard.integer(forKey: "appLaunchCount") + 1
        UserDefaults.standard.set(launches, forKey: "appLaunchCount")
        let hasDose = ((try? container.mainContext.fetchCount(FetchDescriptor<DoseEntry>())) ?? 0) > 0
        hooks.engagementKnown(hasDose)
        // Warm the search-history store (opens its App Group suite + decodes the
        // recent list) at launch so the first Search-tab open doesn't pay the
        // cold first-touch on its hot path.
        _ = SearchHistoryStore.shared.recent

        runStorePasses(container: container)

        // Roll the routine follow-up horizon forward (they're materialized as
        // one-shots over a few days) and drop today's re-asks for routines
        // already logged.
        await DoseNotificationManager.syncMedRemindersIfNeeded(container: container)
        await syncOtherProfilesReminders()
        // Shared items' stock follows every profile's dose log from here on.
        SharedInventory.shared.start()
        hooks.passesFinished()
        #if DEBUG
            runDebugFixtures(container: container)
        #endif
    }

    /// The migrations, backfills and cache warm-ups over the journal, in the
    /// order they depend on each other. Needs the substance catalog warm.
    private static func runStorePasses(container: ModelContainer) {
        // Backfill sessions for any pre-session-model history. Idempotent
        // and failure-isolated (only sets the optional relationship).
        SessionService.ensureSessionsPopulated(in: container.mainContext)
        // One-time: break up multi-day sessions that the flat-ceiling
        // heuristic chained together (nonstop redosing / long-acting tails).
        SessionService.resplitOverlongSessions(in: container.mainContext)
        // Give every pre-notes summary its place on the session
        // timeline (additive; idempotent). Gated: its walk over every
        // session with a summary only finds new work after a restore
        // or an import, both of which bump the store generation.
        LaunchPassGate.run("sessionNoteSummaries", container: container) {
            SessionNoteService.migrateLegacySummaries(in: container.mainContext)
        }
        // One-time: remap every logged dose onto its stable PSID identity
        // (substanceUID + displayNameSnapshot). Backup-first, additive,
        // never-drop, guarded once — see PSIDBackfillMigration. Runs here
        // (post-launch, off the critical path) because nothing reads the
        // new fields yet; the batch cache was awaited warm above.
        PSIDBackfillMigration.runIfNeeded(container: container)
        // Same identity onto the curated rows (recents, favorites,
        // daily meds), so they key on substance identity instead of a
        // name — additive, never-drop, guarded once. See D.2.3.
        CuratedIdentityBackfillMigration.runIfNeeded(container: container)
        // One-time: re-pin the 15 families corrected on 2026-09-12 so a
        // dose stamped with the OLD family (which the name-gated backfills
        // never revisit) doesn't split from a freshly logged one — see
        // PSIDRepinMigration. Runs after the backfills so any row they
        // just stamped (already the corrected family from this build's DB)
        // is untouched and only legacy rows are rewritten.
        PSIDRepinMigration.runIfNeeded(container: container)
        // One-time: reclassify rows typed as an ester name ("Estradiol
        // Valerate") onto the base substance + ester facet, so they title,
        // feed the Injection Levels tool, and dedup like a picker-logged
        // ester. Snapshot-first for dose history — see EsterIdentityBackfillMigration.
        // Gated on the store token: its scan of every `saltForm == nil`
        // row only finds new work after a dose write or an app update.
        LaunchPassGate.run("esterIdentityBackfill", container: container) {
            EsterIdentityBackfillMigration.runIfNeeded(container: container)
        }
        // Restore the active session (accessory pill, Active Now card, Live
        // Activity) after the process was killed, once sessions are populated.
        ActiveSessionManager.shared.recoverSession(container: container)
        // One-time: fold inventory items that share a substance
        // identity (two scanned boxes, an alias and its canonical
        // name) into one, before the recompute below replays the
        // survivors. `create` enforces the identity at the write,
        // so this only finds work in a store older than that.
        LaunchPassGate.run("inventoryIdentityMerge", container: container) {
            for id in InventoryService.mergeDuplicateItems(in: container.mainContext) {
                DoseNotificationManager.cancelInventoryLowStock(itemID: id)
            }
        }
        // Warm the inventory caches so badges/widget read fresh
        // numbers on first paint. Stock edits recompute their own item
        // as they save, so only a dose-log change can leave a stale
        // quantity behind; the gate skips the replay otherwise.
        LaunchPassGate.run("inventoryRecompute", container: container) {
            InventoryService.recomputeAll(in: container.mainContext)
        }
        // Meds redesign cutover: fold the routine layer (time,
        // remind, follow-up cadence) into per-med fields once.
        // Runs before the reminder sync so folded state is what
        // gets scheduled. See Specs/meds-reminders-redesign.md.
        MedsMigrator.foldRoutinesIfNeeded(context: container.mainContext)
    }

    #if DEBUG
        /// Launch-argument fixtures for development and UI capture.
        private static func runDebugFixtures(container: ModelContainer) {
            // A `-piruImportFile <path>` launch wipes + imports an
            // exported JSON; a `-piruPersona <name>` launch wipes +
            // reseeds a user archetype for UI-state testing;
            // otherwise an empty store fills with the "week"
            // persona (`-piruNoDemoData` suppresses that).
            if !DemoData.insertImportFileData(container: container),
               !DemoData.insertPersonaData(container: container) {
                DemoData.insertDefaultData(container: container)
            }
            // `-piruScanFixture <name>` opens Tools ▸ Identify a Box
            // with a canned reading resolved (ScanFixtures).
            // Warm the batch cache first: the Tools tab's cards
            // resolve substances on render, and a cold cache
            // asserts in DEBUG.
            if ScanFixtures.isRequested {
                Task {
                    // Source prefs load after launch and republish
                    // the cache; wait them out, then warm it.
                    try? await Task.sleep(for: .seconds(1))
                    await SubstanceStore.shared.ensureAllLoaded()
                    AppNavigator.shared.open(.tool(.identify), home: .tools)
                }
            }
            // `-piruSpreadsheetFile <path>` opens the spreadsheet import
            // with that file read (SpreadsheetImportModel).
            if SpreadsheetImportModel.debugPreloadPath != nil {
                Task(name: "Spreadsheet import fixture") {
                    try? await Task.sleep(for: .seconds(1))
                    await SubstanceStore.shared.ensureAllLoaded()
                    AppNavigator.shared.present(.spreadsheetImport)
                }
            }
            // `-piruScreenshots <dir>` walks every screen for
            // pipeline/screenshots.py to capture (ScreenshotTour).
            if ScreenshotTour.isRequested {
                Task(name: "Screenshot tour") {
                    await ScreenshotTour.run(container: container)
                }
            }
        }
    #endif

    // MARK: - Lifecycle

    /// A return to the foreground: re-derive the inventory caches and roll the
    /// reminder horizon, so doses logged from the widget or other surfaces
    /// while away are reflected and a crossed threshold can notify.
    static func becameActive(container: ModelContainer) {
        // The gate shares its name with the launch pass, so the first
        // activation after a launch that already replayed the log is skipped,
        // and a later one replays only when the dose count or generation moved.
        LaunchPassGate.run("inventoryRecompute", container: container) {
            InventoryService.recomputeAll(in: container.mainContext)
        }
        // Same horizon-roll as launch: doses logged from other surfaces while
        // away may have satisfied a routine. The sync resolves med names, so it
        // waits for the substance cache — a fast relaunch can reach here before
        // the launch task has warmed it, and a cold `SubstanceStore.all`
        // asserts in DEBUG.
        Task(name: "Sync med reminders") {
            await SubstanceStore.shared.ensureAllLoaded()
            await DoseNotificationManager.syncMedRemindersIfNeeded(container: container)
            await syncOtherProfilesReminders()
            await SharedInventory.shared.refresh()
        }
    }

    /// Roll every other profile's med reminders forward too, each in its own
    /// store and under its own identifiers, so a person's reminders keep
    /// firing while someone else's journal is open.
    static func syncOtherProfilesReminders(directory: ProfileDirectory = .shared) async {
        guard directory.hasMultipleProfiles else { return }
        for profile in directory.profiles where profile.id != directory.activeProfileID {
            // A journal nobody has opened holds no meds; leave its file uncreated.
            guard FileManager.default.fileExists(atPath: directory.storeURL(for: profile).path),
                  let container = directory.container(for: profile.id, writable: true) else { continue }
            await ProfileScope.$pinned.withValue(profile.id) {
                await DoseNotificationManager.syncMedRemindersIfNeeded(container: container)
            }
        }
    }

    /// A move to the background: the opt-in, end-to-end encrypted automatic
    /// backup, which returns at once unless the user enabled it (debounced and
    /// change-gated internally). A host that can be suspended keeps the process
    /// alive until this returns.
    static func enteredBackground(container: ModelContainer) async {
        await BackupManager.shared.runAutomaticBackup(context: container.mainContext)
    }
}
