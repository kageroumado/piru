import Foundation
import Observation
import os
import SwiftData

private nonisolated let recoveryLogger = Logger(subsystem: "dev.yumeji.piru", category: "StoreRecovery")

/// Owns the on-disk SwiftData store: where it lives, recovering orphaned data
/// into it, and backing it up before anything destructive.
///
/// The data-loss this guards against: the App Group store and the widgets
/// shipped together. A widget timeline refresh can open (and thus CREATE an
/// empty) App Group store before the app's first launch — so a naive
/// "migrate only if the destination doesn't exist" check skips the copy and
/// strands the real data in the old app-sandbox store. This component instead
/// decides by *whether the destination actually has data*, and recovers from
/// any data-bearing legacy / backup / quarantined store it can find.
///
/// Invariant: this code NEVER deletes a store. It copies (recovery) and moves
/// aside to timestamped sidecars (backup). The only removals of user data in
/// the app are the explicit Settings → "Delete All" action (which backs up
/// first) and the DEBUG-only demo seeder.
nonisolated enum StoreRecovery {
    static let appGroupID = "group.dev.yumeji.piru"
    static let storeName = "default.store"
    /// Sibling files a SwiftData/SQLite store is made of.
    static let storeSuffixes = ["", "-shm", "-wal"]

    /// Sidecar reasons that represent a deliberate user choice (Delete Everything,
    /// or the pre-restore snapshot). These are NEVER auto-recovered — resurrecting
    /// them would undo an intentional delete. They remain visible for *manual*
    /// recovery in the Data & Storage screen. Everything else (``corrupt``,
    /// ``empty-before-recovery``) is an unintended quarantine and IS auto-recovered.
    static let intentionalReasons: Set<String> = ["predelete", "prerestore", "prepsid"]

    // MARK: - Schema-migration policy

    //
    // The app opens the store with **automatic lightweight migration** and *no*
    // explicit `SchemaMigrationPlan`. SwiftData infers the migration from the
    // on-disk shape to the current ``models``, which covers every shipped change
    // so far — they were all additive (new entities, new optional/defaulted
    // properties). The one historically non-additive step (per-row `DoseEntry.id`)
    // is handled *after* open by ``backfillDuplicateEntryIDs(container:)``: a
    // lightweight migration fills one shared UUID into every existing row, and
    // the backfill then uniquifies them. This deliberately retires the old
    // `PiruSchemaV1…V5` + `PiruMigrationPlan`: holding multiple `VersionedSchema`s
    // that reference the same live `@Model` collides on SwiftData's compiled-shape
    // checksum ("Duplicate version checksums", uncatchable at launch) and forces
    // byte-frozen copies of every changed entity — the trap we removed.
    //
    // **Reintroduce a plan ONLY for a genuinely non-additive change** — a property
    // rename, a type change, or a new *required* (non-optional, non-defaulted)
    // field that lightweight migration cannot infer. When that happens, add a
    // scoped one-shot `VersionedSchema` pair + a `.custom` `MigrationStage`,
    // freezing **only the changed entity** (a byte-identical copy of its pre-change
    // shape), and **retire the stage** once no pre-change store can still exist in
    // the wild. Do not reconstruct a full V1→Vn ladder; the additive history needs
    // no plan.

    /// The user-data models, in one place so counting and recovery agree.
    nonisolated static var models: [any PersistentModel.Type] {
        [
            DoseEntry.self,
            SubstanceColor.self,
            UserColor.self,
            DailyDoseItem.self,
            FavoriteSubstance.self,
            QuickLogDose.self,
            Session.self,
            DoseRoutine.self,
            InventoryItem.self,
            UserProfileRecord.self,
            ToleranceState.self,
            CustomSubstanceRecord.self,
            CustomDrinkPreset.self,
            CustomUnitPreset.self,
            NotificationPreferences.self,
            RoutineOccurrence.self,
        ]
    }

    // MARK: - Locations

    /// Canonical store location (shared App Group container), with the same
    /// fallbacks the app uses so a misconfigured entitlement still launches.
    nonisolated static func canonicalStoreURL() -> URL {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent(storeName)
    }

    /// The pre-App-Group location (app sandbox Application Support).
    static func legacyStoreURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent(storeName)
    }

    // MARK: - Recovery (run before opening the main container)

    /// Ensure the canonical store holds the user's data. If it's empty/absent but
    /// a data-bearing legacy or *unintentionally-quarantined* store exists,
    /// recover the richest one (backing up the empty canonical first). Returns the
    /// canonical URL to open.
    ///
    /// Correctness no longer hinges on a "completed" flag — the earlier flag-gated
    /// design stranded data when a prior run set the flag and then a later failure
    /// quarantined the real store behind it. Instead, intent is encoded in the
    /// sidecar *name*: ``intentionalReasons`` (a deliberate Delete Everything /
    /// pre-restore snapshot) are excluded from auto-recovery, so an empty store the
    /// user chose stays empty, while a `corrupt-*` quarantine is always reclaimed.
    @discardableResult
    static func prepareCanonicalStore() -> URL {
        let canonical = canonicalStoreURL()

        // Canonical already holds data → nothing to do (the common, fast path).
        if userDataCount(at: canonical) > 0 { return canonical }

        // Empty / absent / unreadable: recover the richest *unintended* candidate.
        guard let (source, count) = richestRecoverableStore(excluding: canonical), count > 0 else {
            recoveryLogger.info("No data-bearing store to recover; canonical stays as-is.")
            return canonical
        }
        // Never overwrite: move the current (empty/unreadable) canonical aside first.
        if anyFileExists(at: canonical) {
            backUpStore(at: canonical, reason: "empty-before-recovery")
        }
        do {
            try copyStore(from: source, to: canonical)
            recoveryLogger.notice(
                "Recovered \(count, privacy: .public) entries into the canonical store from \(source.lastPathComponent, privacy: .public)",
            )
        } catch {
            recoveryLogger.error("Store recovery copy failed: \(error.localizedDescription, privacy: .public)")
        }
        return canonical
    }

    /// Ensure every ``DoseEntry`` carries its own unique `id`, reassigning
    /// duplicates in place. Call once right after the container opens.
    ///
    /// LEGACY — plan to remove. This only does work for a store upgraded from the **pre-`id`** shape,
    /// which predates the last shipped release (`v2.2-b21` / c3b79c4); current TestFlight installs have
    /// long since migrated, after which this is a no-op full fetch every launch. Remove it (and the
    /// disabled `LegacyStoreMigrationTests`) once ASC telemetry confirms no pre-`id` install remains.
    /// See the legacy-removal tracking note. Until then it stays as a cheap, idempotent safety net.
    ///
    /// This is the sole guarantor of per-row `id` uniqueness now that the store
    /// opens via automatic lightweight migration with no explicit plan: a
    /// lightweight migration that adds `DoseEntry.id` evaluates the default
    /// expression **once** and fills the *same* UUID into every pre-existing row,
    /// so any store upgraded from a pre-`id` shape arrives here with duplicates to
    /// uniquify.
    ///
    /// Runs a single full `DoseEntry` fetch on every launch rather than gating
    /// on a "done" flag — a flag would go stale the moment the user restores an
    /// older sidecar store (Data & Storage screen) or the store is swapped by
    /// recovery, silently reintroducing duplicates behind it. The journal is at
    /// most a few thousand rows and launch already fetches it elsewhere
    /// (session backfill, journal model), so the no-op case is one cheap fetch
    /// + a `Set` insert per row, with no writes.
    ///
    /// First occurrence keeps its id (stable references like ramp-down keys and
    /// open routes survive); later duplicates get fresh UUIDs. Never deletes,
    /// never touches any other field.
    @MainActor
    static func backfillDuplicateEntryIDs(container: ModelContainer) {
        let context = container.mainContext
        do {
            let entries = try context.fetch(FetchDescriptor<DoseEntry>())
            var seen = Set<UUID>()
            seen.reserveCapacity(entries.count)
            var reassigned = 0
            for entry in entries where !seen.insert(entry.id).inserted {
                entry.id = UUID()
                seen.insert(entry.id)
                reassigned += 1
            }
            guard reassigned > 0 else { return }
            try context.save()
            recoveryLogger.notice("Backfilled \(reassigned, privacy: .public) duplicate DoseEntry ids")
        } catch {
            recoveryLogger.error("DoseEntry id backfill failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The data-bearing recovery candidate with the most rows, or `nil` if none
    /// hold data. Excludes intentional snapshots (see ``intentionalReasons``).
    static func richestRecoverableStore(excluding canonical: URL) -> (url: URL, count: Int)? {
        var best: (url: URL, count: Int)?
        for candidate in recoveryCandidates(excluding: canonical, includeIntentional: false) {
            let n = userDataCount(at: candidate)
            if n > (best?.count ?? 0) { best = (candidate, n) }
        }
        return best
    }

    /// Stores we might recover from: the legacy sandbox store, plus any
    /// timestamped sidecars (quarantined / backed-up / superseded) in either the
    /// canonical or the legacy directory. When `includeIntentional` is false,
    /// deliberate snapshots (`predelete` / `prerestore`) are omitted so they are
    /// never auto-resurrected.
    static func recoveryCandidates(excluding canonical: URL, includeIntentional: Bool) -> [URL] {
        var out: [URL] = []
        if let legacy = legacyStoreURL(), legacy.path != canonical.path {
            out.append(legacy)
        }
        let dirs = Set([
            canonical.deletingLastPathComponent(),
            legacyStoreURL()?.deletingLastPathComponent(),
        ].compactMap { $0?.path })
        let fm = FileManager.default
        for dirPath in dirs {
            let dir = URL(fileURLWithPath: dirPath)
            guard let entries = try? fm.contentsOfDirectory(atPath: dirPath) else { continue }
            for name in entries {
                // Sidecar main files only (skip their -shm/-wal): default.store.<tag>-<ts>
                guard name.hasPrefix(storeName + "."), !name.hasSuffix("-shm"), !name.hasSuffix("-wal")
                else { continue }
                if !includeIntentional, let reason = sidecarReason(name), intentionalReasons.contains(reason) {
                    continue
                }
                out.append(dir.appendingPathComponent(name))
            }
        }
        return out
    }

    /// Extract the `<reason>` from a sidecar filename `default.store.<reason>-<ts>`
    /// (ignoring a trailing `-shm`/`-wal`). Returns `nil` for a non-sidecar name.
    static func sidecarReason(_ fileName: String) -> String? {
        let prefix = storeName + "."
        guard fileName.hasPrefix(prefix) else { return nil }
        var tag = String(fileName.dropFirst(prefix.count))
        for suffix in ["-shm", "-wal"] where tag.hasSuffix(suffix) {
            tag = String(tag.dropLast(suffix.count))
        }
        // Drop the trailing `-<timestamp>`.
        guard let dash = tag.lastIndex(of: "-") else { return tag }
        return String(tag[tag.startIndex ..< dash])
    }

    // MARK: - Backup

    /// Move a store and its siblings aside to `<name>.<reason>-<timestamp>`.
    /// A move (not copy) so the slot is freed for a fresh store, and a move
    /// (not delete) so the bytes are always preserved.
    static func backUpStore(at storeURL: URL, reason: String) {
        let fm = FileManager.default
        let dir = storeURL.deletingLastPathComponent()
        let base = storeURL.lastPathComponent
        let stamp = Int(Date().timeIntervalSince1970)
        for suffix in storeSuffixes {
            let src = dir.appendingPathComponent(base + suffix)
            guard fm.fileExists(atPath: src.path) else { continue }
            let dst = dir.appendingPathComponent("\(base).\(reason)-\(stamp)\(suffix)")
            do {
                try fm.moveItem(at: src, to: dst)
                recoveryLogger.notice("Backed up store file → \(dst.lastPathComponent, privacy: .public)")
            } catch {
                recoveryLogger.error("Backup of \(src.lastPathComponent, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Copy (not move) the canonical store and its siblings to a timestamped
    /// sidecar, leaving the live store in place. Used before a destructive but
    /// intentional action (Settings → Delete All) so it's always recoverable.
    static func snapshotStore(reason: String) {
        let fm = FileManager.default
        let store = canonicalStoreURL()
        let dir = store.deletingLastPathComponent()
        let base = store.lastPathComponent
        let stamp = Int(Date().timeIntervalSince1970)
        for suffix in storeSuffixes {
            let src = dir.appendingPathComponent(base + suffix)
            guard fm.fileExists(atPath: src.path) else { continue }
            let dst = dir.appendingPathComponent("\(base).\(reason)-\(stamp)\(suffix)")
            do {
                try fm.copyItem(at: src, to: dst)
            } catch {
                recoveryLogger.error("Snapshot of \(src.lastPathComponent, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        recoveryLogger.notice("Snapshot taken before \(reason, privacy: .public)")
    }

    // MARK: - Helpers

    /// Count user-data rows in the store at `url`. Returns 0 if the store is
    /// absent/empty, or -1 if it exists but no strategy can read it (genuine
    /// corruption, locked/encrypted, or an irreconcilable schema).
    ///
    /// Two strategies, cheapest first:
    /// 1. Read-only open under the *current* schema (works once the store is at
    ///    the latest version — the common, fast path).
    /// 2. A migrating copy: clone the store to scratch and open it with automatic
    ///    lightweight migration (which a read-only probe cannot do), then count.
    ///    This absorbs *any* older or intermediate on-disk shape — the case that
    ///    caused the quarantine bug — so recovery can see its data instead of
    ///    writing it off as unreadable.
    static func userDataCount(at url: URL) -> Int {
        guard anyFileExists(at: url) else { return 0 }
        // Integrity gate: a corrupt store must never be handed to a SwiftData
        // `ModelContainer` open, which aborts the process *natively* (below the
        // Swift error layer) on malformed SQLite rather than throwing — the
        // build-30 launch crash. `quick_check` fails throwably, so corruption
        // resolves to "unreadable" (-1), which recovery already handles by
        // recovering from a data-bearing candidate instead.
        guard StoreHealth.isReadable(at: url) else {
            recoveryLogger.error("Store at \(url.lastPathComponent, privacy: .public) failed the integrity pre-check; treating as unreadable")
            return -1
        }
        if let count = countUserRows(at: url, schema: Schema(models)) { return count }
        if let count = countViaMigratingCopy(at: url) { return count }
        return -1
    }

    /// Strategy 2 of ``userDataCount(at:)``: copy the store to a scratch location
    /// and open it with automatic lightweight migration (allowing saves, since
    /// migration writes), then count. Operates on a *copy* so the original is
    /// never mutated by the probe. Returns `nil` if even this fails.
    private static func countViaMigratingCopy(at url: URL) -> Int? {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory
            .appendingPathComponent("piru-count-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: scratch) }
        do {
            try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
            let dest = scratch.appendingPathComponent(storeName)
            try copyStore(from: url, to: dest)
            // No migration plan → SwiftData infers a lightweight migration from the
            // store's on-disk shape to the current models. Additive intermediate
            // schemas migrate cleanly; the count is then exact.
            return countUserRows(at: dest, schema: Schema(models), allowsSave: true)
        } catch {
            return nil
        }
    }

    private static func countUserRows(at url: URL, schema: Schema, allowsSave: Bool = false) -> Int? {
        do {
            // .none — never let the iCloud entitlement pull this probe into CloudKit
            // setup (the schema is CloudKit-incompatible). See PiruApp.makeContainer.
            let config = ModelConfiguration(url: url, allowsSave: allowsSave, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: config)
            let context = ModelContext(container)
            // DoseEntry is the journal — the data "No Entries" refers to — plus
            // the other user-authored models. Colors are cosmetic but counted too.
            let counts = [
                (try? context.fetchCount(FetchDescriptor<DoseEntry>())) ?? 0,
                (try? context.fetchCount(FetchDescriptor<DailyDoseItem>())) ?? 0,
                (try? context.fetchCount(FetchDescriptor<FavoriteSubstance>())) ?? 0,
                (try? context.fetchCount(FetchDescriptor<SubstanceColor>())) ?? 0,
                (try? context.fetchCount(FetchDescriptor<UserColor>())) ?? 0,
            ]
            return counts.reduce(0, +)
        } catch {
            return nil
        }
    }

    private static func anyFileExists(at storeURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: storeURL.path)
    }

    /// Copy a store and its siblings to `dest` (overwriting only after the
    /// caller has backed up any existing dest). Copies -shm/-wal too so an
    /// uncheckpointed WAL is preserved and replayed on open.
    static func copyStore(from source: URL, to dest: URL) throws {
        let fm = FileManager.default
        let srcDir = source.deletingLastPathComponent()
        let srcBase = source.lastPathComponent
        let dstDir = dest.deletingLastPathComponent()
        let dstBase = dest.lastPathComponent
        for suffix in storeSuffixes {
            let src = srcDir.appendingPathComponent(srcBase + suffix)
            guard fm.fileExists(atPath: src.path) else { continue }
            let dst = dstDir.appendingPathComponent(dstBase + suffix)
            if fm.fileExists(atPath: dst.path) {
                try fm.removeItem(at: dst) // safe: caller backed it up first
            }
            try fm.copyItem(at: src, to: dst)
        }
    }

    // MARK: - Inventory & manual recovery (Data & Storage screen)

    /// Total on-disk size of the canonical store and its `-wal`/`-shm` siblings.
    static func canonicalStoreBytes() -> Int64 {
        byteSize(of: canonicalStoreURL())
    }

    /// Combined byte size of a store main file plus its `-wal`/`-shm` siblings.
    static func byteSize(of storeURL: URL) -> Int64 {
        let fm = FileManager.default
        let dir = storeURL.deletingLastPathComponent()
        let base = storeURL.lastPathComponent
        var total: Int64 = 0
        for suffix in storeSuffixes {
            let path = dir.appendingPathComponent(base + suffix).path
            if let size = (try? fm.attributesOfItem(atPath: path))?[.size] as? NSNumber {
                total += size.int64Value
            }
        }
        return total
    }

    /// Every sidecar store on disk that could be restored — quarantined
    /// (`corrupt`), pre-recovery, *and* intentional snapshots (`predelete` /
    /// `prerestore`) — each with its row count, size, and timestamp, newest first.
    /// Unlike auto-recovery, this lists intentional snapshots too so the user can
    /// deliberately roll back from the Data & Storage screen.
    static func recoverableStores() -> [RecoverableStore] {
        let canonical = canonicalStoreURL()
        return recoveryCandidates(excluding: canonical, includeIntentional: true)
            .map { url in
                let name = url.lastPathComponent
                return RecoverableStore(
                    url: url,
                    reason: sidecarReason(name) ?? "backup",
                    rowCount: userDataCount(at: url),
                    timestamp: sidecarTimestamp(name),
                    bytes: byteSize(of: url),
                )
            }
            // Only real files on disk: a candidate path that doesn't exist (e.g. the
            // legacy store on a fresh install) has zero bytes and is not a "copy" to
            // surface. Unreadable-but-present stores (bytes > 0, rowCount -1) stay —
            // the user can still send their logs from them.
            .filter { $0.bytes > 0 }
            .sorted { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) }
    }

    /// Restore a specific sidecar into the canonical slot, snapshotting the
    /// current canonical aside first (never destructive). The app must be
    /// relaunched afterwards so a fresh `ModelContainer` opens the restored store.
    static func restore(from sidecar: URL) throws {
        let canonical = canonicalStoreURL()
        if anyFileExists(at: canonical) {
            backUpStore(at: canonical, reason: "before-manual-restore")
        }
        try copyStore(from: sidecar, to: canonical)
        recoveryLogger.notice("Manually restored canonical store from \(sidecar.lastPathComponent, privacy: .public)")
    }

    /// Parse the trailing `-<unix-seconds>` timestamp from a sidecar filename.
    static func sidecarTimestamp(_ fileName: String) -> Date? {
        var tag = fileName
        for suffix in ["-shm", "-wal"] where tag.hasSuffix(suffix) {
            tag = String(tag.dropLast(suffix.count))
        }
        guard let dash = tag.lastIndex(of: "-") else { return nil }
        let stamp = tag[tag.index(after: dash)...]
        guard let seconds = TimeInterval(stamp) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}

// MARK: - Launch state

/// Observable launch-time health of the on-disk store. Set by
/// ``PiruApp/makeContainer()`` when it cannot open the persistent store and has
/// fallen back to a transient in-memory store. The UI watches this to show a
/// reassuring "data temporarily unavailable" alert — the bytes are preserved on
/// disk and a later launch / app version restores them; nothing is deleted.
@MainActor
@Observable
final class StoreLaunchState {
    static let shared = StoreLaunchState()

    /// `true` when the app is running on an in-memory fallback store because the
    /// persistent store could not be opened this launch.
    var storeUnavailable = false

    /// The underlying open-failure description, surfaced only in the diagnostics
    /// report sent to the developer (never shown raw to the user).
    var failureDetail: String?

    private init() {}
}

// MARK: - Recoverable store descriptor

/// A restorable on-disk sidecar store surfaced in the Data & Storage screen.
struct RecoverableStore: Identifiable {
    let id = UUID()
    let url: URL
    /// Why it was set aside: `corrupt`, `empty-before-recovery`, `predelete`, …
    let reason: String
    /// User-data row count (`-1` if it can't be read).
    let rowCount: Int
    /// When it was set aside, parsed from the filename.
    let timestamp: Date?
    /// On-disk size in bytes (main + `-wal`/`-shm`).
    let bytes: Int64

    /// A deliberate user snapshot (Delete Everything / pre-restore) rather than an
    /// automatic quarantine.
    var isIntentional: Bool {
        StoreRecovery.intentionalReasons.contains(reason)
    }
}
