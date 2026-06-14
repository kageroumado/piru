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
/// Versioned schema baseline. The current models are V1; future schema changes
/// add `PiruSchemaV2` + a `MigrationStage` so SwiftData migrates the store
/// explicitly instead of relying on automatic lightweight migration (which
/// fails — and on failure strands or quarantines data — for any non-additive
/// change like a rename, type change, or new required property).
///
/// Adopting this for stores originally created with a plain `Schema(models)` is
/// seamless: the schema's structural identity is the same, so no migration runs.
/// (Verified by StoreRecoveryTests.)
/// The original five user-data models. Frozen — do not edit; later additions
/// get a new version (see ``PiruSchemaV2``) so the migration path is explicit.
enum PiruSchemaV1: VersionedSchema {
    nonisolated static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }
    nonisolated static var models: [any PersistentModel.Type] {
        [
            DoseEntry.self,
            SubstanceColor.self,
            UserColor.self,
            DailyDoseItem.self,
            FavoriteSubstance.self,
        ]
    }
}

/// Adds ``QuickLogDose`` (the curated quick-log list) and ``Session`` (the
/// Journal's session model) plus the optional ``DoseEntry/session`` /
/// ``DoseEntry/isBackgroundMed`` and ``DailyDoseItem/isBackgroundMed``
/// properties, the optional ``DoseEntry/locationName`` /
/// ``DoseEntry/latitude`` / ``DoseEntry/longitude`` location fields, and the
/// defaulted ``FavoriteSubstance/sortOrder``. All purely
/// additive — new entities and new optional/defaulted properties, no changes to
/// existing required ones — so the V1→V2 migration is lightweight (automatic)
/// and existing data is untouched. The location fields are folded into V2 in
/// place (rather than a new V3) because V2 has not shipped beyond the simulator,
/// so there is no on-disk V2 store to preserve.
///
/// `Session` folds into V2 rather than getting its own version on purpose: the
/// ``DoseEntry/session`` relationship pulls `Session` into *every* schema
/// version's object graph (SwiftData auto-includes relationship targets), so a
/// hypothetical V3-adds-Session would be structurally identical to V2 and
/// SwiftData rejects the plan with "Duplicate version checksums". The interim
/// QuickLogDose-only V2 never shipped beyond the simulator, so there is no
/// on-disk schema to preserve between "QuickLogDose" and "Session".
enum PiruSchemaV2: VersionedSchema {
    nonisolated static var versionIdentifier: Schema.Version {
        Schema.Version(2, 0, 0)
    }
    nonisolated static var models: [any PersistentModel.Type] {
        [
            DoseEntry.self,
            SubstanceColor.self,
            UserColor.self,
            DailyDoseItem.self,
            FavoriteSubstance.self,
            QuickLogDose.self,
            Session.self,
        ]
    }
}

/// Adds ``DoseRoutine`` (named multi-routine sets with optional time +
/// reminder). Purely additive — one new entity, no changes to existing
/// models — so V2→V3 is lightweight.
///
/// V3 is frozen at the **class** level, not just the list level: V4 changed a
/// *property* of `DoseEntry` (added the defaulted `id: UUID`), and a version's
/// checksum is computed from the compiled entity shapes — so a frozen V3 *list*
/// referencing the live (id-bearing) `DoseEntry` would be byte-identical to V4
/// and `ModelContainer.init` throws an uncatchable "Duplicate version
/// checksums" NSException at launch (reproduced experimentally; the V2 list
/// freeze above only works because V2 and V3 differ by entity *set*).
/// ``DoseEntry`` and ``Session`` are therefore full copies of the exact shape
/// that shipped as V3 — `Session` must come along because the
/// `DoseEntry.session` relationship pulls it into the version's object graph,
/// and a graph mixing the frozen `DoseEntry` with the live `Session` (whose
/// inverse references the live, id-bearing `DoseEntry`) would collide on the
/// entity name. The remaining six models are standalone and unchanged since V3
/// shipped, so they are shared with the live schema.
///
/// **Frozen — do not edit these copies.** A real on-device V3 store matches
/// this version's checksum only while the copies stay byte-equivalent to what
/// shipped; editing them silently diverts upgrades to the automatic-lightweight
/// fallback in `PiruApp.makeContainer` (still safe, but unstaged).
enum PiruSchemaV3: VersionedSchema {
    nonisolated static var versionIdentifier: Schema.Version {
        Schema.Version(3, 0, 0)
    }
    nonisolated static var models: [any PersistentModel.Type] {
        [
            DoseEntry.self, // frozen copy below — the pre-`id` shape
            SubstanceColor.self,
            UserColor.self,
            DailyDoseItem.self,
            FavoriteSubstance.self,
            QuickLogDose.self,
            Session.self, // frozen copy below
            DoseRoutine.self,
        ]
    }

    /// The V3 `DoseEntry` exactly as shipped — no `id` property. Stored
    /// properties (and their defaults) only; the live class's computed helpers
    /// don't affect the schema and are omitted.
    @Model
    final class DoseEntry {
        var substance: String
        var amount: Double
        var unit: String
        var route: RouteOfAdministration
        var timestamp: Date
        var notes: String?
        var tagsRaw: String?
        var session: Session?
        var isBackgroundMed: Bool = false
        var locationName: String?
        var latitude: Double?
        var longitude: Double?

        init(
            substance: String,
            amount: Double,
            unit: String = "mg",
            route: RouteOfAdministration = .oral,
            timestamp: Date = .now,
        ) {
            self.substance = substance
            self.amount = amount
            self.unit = unit
            self.route = route
            self.timestamp = timestamp
        }
    }

    /// The V3 `Session` exactly as shipped (unchanged in V4, but duplicated so
    /// its `doses` inverse points at the frozen `DoseEntry` above).
    @Model
    final class Session {
        @Attribute(.unique) var id: UUID
        var startDate: Date
        var title: String?
        var note: String?
        @Relationship(deleteRule: .nullify, inverse: \DoseEntry.session)
        var doses: [DoseEntry]?

        init(id: UUID = UUID(), startDate: Date, title: String? = nil, note: String? = nil) {
            self.id = id
            self.startDate = startDate
            self.title = title
            self.note = note
        }
    }
}

/// Adds the defaulted ``DoseEntry/id`` (stable identity for routes, deep
/// links, notification keys, and exports). Takes the live `StoreRecovery.models`
/// alias; V3 above holds the frozen pre-`id` copies that keep the two
/// versions' checksums distinct.
///
/// The V3→V4 stage is `.custom`, not `.lightweight`, because a lightweight
/// migration evaluates the property's default expression **once** and fills
/// the same UUID into every existing row (reproduced experimentally) — the
/// `didMigrate` pass reassigns a fresh per-row UUID. Stores that bypass the
/// staged plan (the automatic-lightweight fallback in `PiruApp.makeContainer`)
/// are uniquified by ``StoreRecovery/backfillDuplicateEntryIDs(container:)``
/// right after open instead.
enum PiruSchemaV4: VersionedSchema {
    nonisolated static var versionIdentifier: Schema.Version {
        Schema.Version(4, 0, 0)
    }
    nonisolated static var models: [any PersistentModel.Type] {
        StoreRecovery.models
    }
}

enum PiruMigrationPlan: SchemaMigrationPlan {
    nonisolated static var schemas: [any VersionedSchema.Type] {
        [PiruSchemaV1.self, PiruSchemaV2.self, PiruSchemaV3.self, PiruSchemaV4.self]
    }
    nonisolated static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: PiruSchemaV1.self, toVersion: PiruSchemaV2.self),
            .lightweight(fromVersion: PiruSchemaV2.self, toVersion: PiruSchemaV3.self),
            .custom(
                fromVersion: PiruSchemaV3.self,
                toVersion: PiruSchemaV4.self,
                willMigrate: nil,
                didMigrate: { context in
                    // The schema migration itself filled ONE shared UUID into
                    // every pre-existing row (the default expression is
                    // evaluated once); give each row its own.
                    //
                    // Stage closures run synchronously on the thread that opens
                    // the container (verified empirically), and the app opens it
                    // on the main thread — `assumeIsolated` is what lets this
                    // `@Sendable` closure touch the MainActor-isolated model. If
                    // a future SwiftData ever ran this off-main, skip rather
                    // than crash or deadlock: `backfillDuplicateEntryIDs` runs
                    // right after open and uniquifies as the second line of
                    // defense.
                    guard Thread.isMainThread else { return }
                    // Safe: the context is used only inside this synchronous
                    // closure, on this (main) thread — the unsafe transfer just
                    // bridges region-isolation analysis into `assumeIsolated`.
                    nonisolated(unsafe) let context = context
                    try MainActor.assumeIsolated {
                        let entries = try context.fetch(FetchDescriptor<DoseEntry>())
                        for entry in entries {
                            entry.id = UUID()
                        }
                        try context.save()
                    }
                },
            ),
        ]
    }
}

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
    static let intentionalReasons: Set<String> = ["predelete", "prerestore"]

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
        ]
    }

    // MARK: - Locations

    /// Canonical store location (shared App Group container), with the same
    /// fallbacks the app uses so a misconfigured entitlement still launches.
    static func canonicalStoreURL() -> URL {
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
    /// Covers the stores the staged V3→V4 migration can't: anything that opened
    /// through the automatic-lightweight fallback in `PiruApp.makeContainer`
    /// (pre-V3 shapes, intermediate dev schemas) gets the *same* UUID filled
    /// into every pre-existing row, because a lightweight migration evaluates
    /// the property's default expression once.
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
    /// Three strategies, cheapest first:
    /// 1. Read-only open under the *current* schema (works once the store is at
    ///    the latest version).
    /// 2. Read-only open under the original *V1* schema — the shape an upgrading
    ///    user's on-disk store has at launch, before the main container migrates.
    /// 3. A migrating copy: clone the store to scratch and open it with automatic
    ///    lightweight migration (which a read-only probe cannot do), then count.
    ///    This is what makes an *intermediate* dev schema — neither exactly V1 nor
    ///    V2, the shape that caused the quarantine bug — countable, so recovery
    ///    can see its data instead of writing it off as unreadable.
    static func userDataCount(at url: URL) -> Int {
        guard anyFileExists(at: url) else { return 0 }
        if let count = countUserRows(at: url, schema: Schema(models)) { return count }
        if let count = countUserRows(at: url, schema: Schema(PiruSchemaV2.models)) { return count }
        if let count = countUserRows(at: url, schema: Schema(PiruSchemaV1.models)) { return count }
        if let count = countViaMigratingCopy(at: url) { return count }
        return -1
    }

    /// Strategy 3 of ``userDataCount(at:)``: copy the store to a scratch location
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
