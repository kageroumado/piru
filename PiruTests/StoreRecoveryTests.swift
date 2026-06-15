import Foundation
import SwiftData
import Testing
@testable import Piru

@Suite("StoreRecovery")
struct StoreRecoveryTests {
    /// A fresh temp directory + store URL per test.
    private func tmpStoreURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("piru-storetest-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("default.store")
    }

    /// Create a store at `url` with the current schema and seed `n` dose
    /// entries, then let the container deallocate (flushing).
    private func seedStore(at url: URL, entries n: Int) throws {
        let container = try ModelContainer(
            for: Schema(StoreRecovery.models),
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none),
        )
        let ctx = ModelContext(container)
        for i in 0 ..< n {
            ctx.insert(DoseEntry(substance: "Caffeine", amount: Double(50 + i)))
        }
        try ctx.save()
    }

    @Test
    func `A plain-Schema store reopens cleanly with no migration plan, data intact`() throws {
        let url = tmpStoreURL()
        try seedStore(at: url, entries: 3)

        // Reopen the bare current schema with no plan, exactly as the app's
        // makeContainer now does. A previously-stored file must open cleanly.
        let container = try ModelContainer(
            for: Schema(StoreRecovery.models),
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none),
        )
        let ctx = ModelContext(container)
        #expect(try ctx.fetchCount(FetchDescriptor<DoseEntry>()) == 3)
    }

    @Test
    func `userDataCount reflects rows; 0 for an absent store`() throws {
        let url = tmpStoreURL()
        #expect(StoreRecovery.userDataCount(at: url) == 0) // nothing there yet
        try seedStore(at: url, entries: 4)
        #expect(StoreRecovery.userDataCount(at: url) == 4)
    }

    @Test
    func `copyStore restores data into an empty location, source intact`() throws {
        let source = tmpStoreURL()
        let dest = tmpStoreURL()
        try seedStore(at: source, entries: 5)

        try StoreRecovery.copyStore(from: source, to: dest)

        #expect(StoreRecovery.userDataCount(at: dest) == 5) // recovered
        #expect(StoreRecovery.userDataCount(at: source) == 5) // source untouched (copy, not move)
    }

    @Test
    func `backUpStore moves the store aside — never deletes`() throws {
        let url = tmpStoreURL()
        try seedStore(at: url, entries: 2)
        #expect(FileManager.default.fileExists(atPath: url.path))

        StoreRecovery.backUpStore(at: url, reason: "test")

        // Original slot freed (moved), and a data-bearing sidecar exists.
        #expect(!FileManager.default.fileExists(atPath: url.path))
        let dir = url.deletingLastPathComponent()
        let sidecars = (try? FileManager.default.contentsOfDirectory(atPath: dir.path))?
            .filter { $0.hasPrefix("default.store.test-") && !$0.hasSuffix("-shm") && !$0.hasSuffix("-wal") } ?? []
        #expect(sidecars.count == 1)
        let recovered = dir.appendingPathComponent(sidecars[0])
        #expect(StoreRecovery.userDataCount(at: recovered) == 2)
    }

    // MARK: - Intermediate-schema regression (the data-loss root cause)

    /// A subset of the current models (`DoseEntry`, colors, daily, favorites,
    /// `Session`) but *not* every entity — an "intermediate" shape that doesn't
    /// match the full current schema. This is the shape a dev / pre-release build
    /// leaves on disk, and the one that triggered the quarantine.
    private var intermediateModels: [any PersistentModel.Type] {
        [DoseEntry.self, SubstanceColor.self, UserColor.self, DailyDoseItem.self, FavoriteSubstance.self, Session.self]
    }

    private func seedIntermediateStore(at url: URL, entries n: Int) throws {
        let container = try ModelContainer(
            for: Schema(intermediateModels),
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none),
        )
        let ctx = ModelContext(container)
        for i in 0 ..< n {
            ctx.insert(DoseEntry(substance: "Caffeine", amount: Double(50 + i)))
        }
        try ctx.save()
    }

    @Test
    func `Automatic lightweight migration absorbs an intermediate-schema store, preserving data`() throws {
        let url = tmpStoreURL()
        try seedIntermediateStore(at: url, entries: 5)
        // The makeContainer path: open the bare current schema with no plan.
        let container = try ModelContainer(
            for: Schema(StoreRecovery.models),
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none),
        )
        let ctx = ModelContext(container)
        #expect(try ctx.fetchCount(FetchDescriptor<DoseEntry>()) == 5)
    }

    @Test
    func `userDataCount reads an intermediate-schema store instead of reporting it unreadable`() throws {
        let url = tmpStoreURL()
        try seedIntermediateStore(at: url, entries: 4)
        // Must be the exact count (via the migrating-copy fallback), never -1 — a
        // -1 would let recovery write the data off as corrupt.
        #expect(StoreRecovery.userDataCount(at: url) == 4)
    }

    // MARK: - Intent-aware recovery

    @Test
    func `richestRecoverableStore prefers a corrupt quarantine over an intentional snapshot`() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("piru-intent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let canonical = dir.appendingPathComponent("default.store")

        // An intentional pre-delete snapshot (more rows) and a corrupt quarantine.
        try seedStore(at: dir.appendingPathComponent("default.store.predelete-1000"), entries: 9)
        try seedStore(at: dir.appendingPathComponent("default.store.corrupt-2000"), entries: 2)

        let best = StoreRecovery.richestRecoverableStore(excluding: canonical)
        // The predelete snapshot is excluded despite having more rows; only the
        // unintended quarantine is auto-recoverable.
        #expect(best?.url.lastPathComponent == "default.store.corrupt-2000")
        #expect(best?.count == 2)
    }

    @Test
    func `recoveryCandidates can include intentional snapshots for manual restore`() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("piru-intent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let canonical = dir.appendingPathComponent("default.store")
        try seedStore(at: dir.appendingPathComponent("default.store.predelete-1000"), entries: 9)

        let auto = StoreRecovery.recoveryCandidates(excluding: canonical, includeIntentional: false)
        let manual = StoreRecovery.recoveryCandidates(excluding: canonical, includeIntentional: true)
        #expect(!auto.contains { $0.lastPathComponent == "default.store.predelete-1000" })
        #expect(manual.contains { $0.lastPathComponent == "default.store.predelete-1000" })
    }

    @Test
    func `sidecarReason and sidecarTimestamp parse the filename`() {
        #expect(StoreRecovery.sidecarReason("default.store.corrupt-1780683124") == "corrupt")
        #expect(StoreRecovery.sidecarReason("default.store.empty-before-recovery-12-wal") == "empty-before-recovery")
        #expect(StoreRecovery.sidecarReason("default.store") == nil)
        #expect(
            StoreRecovery.sidecarTimestamp("default.store.corrupt-1780683124")
                == Date(timeIntervalSince1970: 1_780_683_124),
        )
        #expect(StoreRecovery.sidecarTimestamp("default.store") == nil)
    }
}

// MARK: - Legacy (pre-`id`, pre-`saltForm`) on-disk shape

/// A test-only namespace holding a `@Model` copy of `DoseEntry` in the shape
/// shipped *before* the stable-`id` and `saltForm` additions — the exact columns
/// a long-lived store on a user's device still has at launch: no `id`, no
/// `saltForm`.
///
/// The nested class is named `DoseEntry` (not `_LegacyDoseEntry`) on purpose:
/// SwiftData derives the persisted **entity name from the simple class name**,
/// ignoring the enclosing type. So `_LegacyDoseEntry.DoseEntry` registers as the
/// entity `"DoseEntry"` — the *same* entity the live ``Piru/DoseEntry`` maps to —
/// and automatic lightweight migration sees the reopened store as the same
/// entity with `id`/`saltForm` *added*, rather than two unrelated entities (which
/// would drop the legacy rows). A distinct simple name would silently lose the
/// data the test means to preserve. No `@Attribute(originalName:)` is needed:
/// every surviving column name already matches the live model.
///
/// The `session` relationship is omitted: the live `Session` declares its
/// inverse on `\DoseEntry.session`, so seeding this legacy entity *together*
/// with the live `Session` in one schema would pull the live (id-bearing)
/// `DoseEntry` into the graph and collide on the "DoseEntry" entity name. The
/// legacy seed schema therefore excludes `Session`; the live model's optional
/// `session` is simply absent on disk and added by the lightweight migration.
enum _LegacyDoseEntry {
    @Model
    final class DoseEntry {
        var substance: String
        var amount: Double
        var unit: String
        var route: RouteOfAdministration
        var timestamp: Date
        var notes: String?
        var tagsRaw: String?
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
}

// MARK: - Plan-less migration of a legacy (pre-`id`/`saltForm`) store

/// The store now opens via **automatic lightweight migration** with no explicit
/// `SchemaMigrationPlan`. These tests seed an OLD-shape store via the test-local
/// ``_LegacyDoseEntry`` (no `id`, no `saltForm`), reopen that SAME url with the
/// current ``StoreRecovery/models`` schema, and assert the upgrade preserves
/// every row + field, the post-open backfill uniquifies the shared `id` a
/// lightweight migration fills in, and `saltForm` lands `nil`.
///
/// `@MainActor` is required, not stylistic: ``StoreRecovery/backfillDuplicateEntryIDs(container:)``
/// is `@MainActor` and mutates the model on the main context.
@Suite("Legacy-store lightweight migration")
@MainActor
struct LegacyStoreMigrationTests {
    private func tmpStoreURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("piru-legacytest-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("default.store")
    }

    /// Seed a store at `url` in the legacy pre-`id`/pre-`saltForm` shape: a schema
    /// whose "DoseEntry" entity is the pre-`id` ``_LegacyDoseEntry/DoseEntry``,
    /// alongside the siblings unchanged since then. `Session` is excluded (its
    /// inverse references the live `DoseEntry`, which would collide on the entity
    /// name with the legacy copy).
    private func seedLegacyStore(at url: URL, entries n: Int) throws {
        let legacySchema = Schema([
            _LegacyDoseEntry.DoseEntry.self,
            SubstanceColor.self,
            UserColor.self,
            DailyDoseItem.self,
            FavoriteSubstance.self,
            QuickLogDose.self,
            DoseRoutine.self,
        ])
        let container = try ModelContainer(
            for: legacySchema,
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none),
        )
        let ctx = ModelContext(container)
        for i in 0 ..< n {
            ctx.insert(_LegacyDoseEntry.DoseEntry(
                substance: "Caffeine",
                amount: Double(50 + i),
                timestamp: Date(timeIntervalSince1970: 1_700_000_000 + Double(i) * 60),
            ))
        }
        try ctx.save()
    }

    @Test
    func `Legacy store upgrades via lightweight migration with rows + fields preserved, ids uniquified, saltForm nil`() throws {
        let url = tmpStoreURL()
        try seedLegacyStore(at: url, entries: 5)

        // Reopen the SAME url under the current schema with no plan — automatic
        // lightweight migration adds `id` (one shared UUID) and `saltForm` (nil).
        let container = try ModelContainer(
            for: Schema(StoreRecovery.models),
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none),
        )
        let ctx = container.mainContext

        var entries = try ctx.fetch(FetchDescriptor<DoseEntry>(sortBy: [SortDescriptor(\.timestamp)]))
        // Every row survived, fields intact.
        #expect(entries.count == 5)
        #expect(entries.map(\.amount) == [50, 51, 52, 53, 54])
        #expect(entries.allSatisfy { $0.substance == "Caffeine" })
        // The new optional column defaults to nil for every pre-existing row.
        #expect(entries.allSatisfy { $0.saltForm == nil })

        // The post-open backfill uniquifies the shared id the lightweight `id`
        // migration filled into every row.
        StoreRecovery.backfillDuplicateEntryIDs(container: container)
        entries = try ctx.fetch(FetchDescriptor<DoseEntry>(sortBy: [SortDescriptor(\.timestamp)]))
        #expect(Set(entries.map(\.id)).count == 5)
        // Still nil after the backfill (it touches only id).
        #expect(entries.allSatisfy { $0.saltForm == nil })
    }
}

// MARK: - Plan-less reopen of a current (saltForm-bearing) store (de-risking)

/// De-risk the plan-less primary path: a store written under the **current**
/// schema (including a logged `saltForm`) must reopen cleanly with a plain
/// `Schema(StoreRecovery.models)` and no plan, with all rows + the salt intact.
@Suite("Current-store plan-less reopen")
@MainActor
struct CurrentStorePlanlessReopenTests {
    private func tmpStoreURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("piru-reopentest-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("default.store")
    }

    @Test
    func `A current store with a logged saltForm reopens plan-less with all rows + salt intact`() throws {
        let url = tmpStoreURL()
        let fixedID = try #require(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-000000000001"))

        do {
            let container = try ModelContainer(
                for: Schema(StoreRecovery.models),
                configurations: ModelConfiguration(url: url, cloudKitDatabase: .none),
            )
            let ctx = ModelContext(container)
            let mag = DoseEntry(substance: "Magnesium", amount: 300, unit: "mg", route: .oral, saltForm: "Glycinate")
            mag.id = fixedID
            ctx.insert(mag)
            ctx.insert(DoseEntry(substance: "Caffeine", amount: 80, unit: "mg", route: .oral))
            ctx.insert(DoseEntry(substance: "Melatonin", amount: 3))
            try ctx.save()
        }

        // Reopen with a plain current schema, no plan — proves a plan-less open
        // of a previously-stored file works and preserves saltForm + ids.
        let container = try ModelContainer(
            for: Schema(StoreRecovery.models),
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none),
        )
        let ctx = ModelContext(container)
        let entries = try ctx.fetch(FetchDescriptor<DoseEntry>())
        #expect(entries.count == 3)
        #expect(entries.first { $0.substance == "Magnesium" }?.saltForm == "Glycinate")
        #expect(entries.first { $0.substance == "Magnesium" }?.id == fixedID)
        #expect(entries.first { $0.substance == "Caffeine" }?.saltForm == nil)
        #expect(Set(entries.map(\.id)).count == 3)
    }
}

// MARK: - Post-open backfill (the lightweight `id` migration outcome)

/// ``StoreRecovery/backfillDuplicateEntryIDs(container:)`` is the sole guarantor
/// of per-row `id` uniqueness now that there's no migration plan: a lightweight
/// migration that adds `id` fills the SAME UUID into every pre-existing row, and
/// the backfill uniquifies them.
@Suite("DoseEntry id backfill")
@MainActor
struct DoseEntryBackfillTests {
    @Test
    func `Backfill uniquifies all-duplicate ids without touching other fields`() throws {
        // Simulate the automatic-lightweight outcome: every pre-existing row
        // carries the SAME UUID.
        let container = try ModelContainer(
            for: Schema(StoreRecovery.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none),
        )
        let ctx = container.mainContext
        let sharedID = try #require(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-000000000002"))
        for i in 0 ..< 4 {
            let entry = DoseEntry(
                substance: "Sub\(i)",
                amount: Double(10 + i),
                timestamp: Date(timeIntervalSince1970: 1_700_000_000 + Double(i) * 60),
            )
            entry.id = sharedID
            ctx.insert(entry)
        }
        try ctx.save()

        StoreRecovery.backfillDuplicateEntryIDs(container: container)

        let entries = try ctx.fetch(FetchDescriptor<DoseEntry>(sortBy: [SortDescriptor(\.timestamp)]))
        #expect(entries.count == 4)
        #expect(Set(entries.map(\.id)).count == 4)
        // The first occurrence keeps the original id (stable references survive).
        #expect(entries.contains { $0.id == sharedID })
        // No other field was touched.
        #expect(entries.map(\.substance) == ["Sub0", "Sub1", "Sub2", "Sub3"])
        #expect(entries.map(\.amount) == [10, 11, 12, 13])

        // Idempotent: a second run changes nothing.
        let idsAfterFirstRun = entries.map(\.id)
        StoreRecovery.backfillDuplicateEntryIDs(container: container)
        let again = try ctx.fetch(FetchDescriptor<DoseEntry>(sortBy: [SortDescriptor(\.timestamp)]))
        #expect(again.map(\.id) == idsAfterFirstRun)
    }

    @Test
    func `Backfill is a no-op when ids are already unique`() throws {
        let container = try ModelContainer(
            for: Schema(StoreRecovery.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none),
        )
        let ctx = container.mainContext
        ctx.insert(DoseEntry(substance: "Caffeine", amount: 100))
        ctx.insert(DoseEntry(substance: "Melatonin", amount: 3))
        try ctx.save()
        let before = try ctx.fetch(FetchDescriptor<DoseEntry>(sortBy: [SortDescriptor(\.amount)])).map(\.id)

        StoreRecovery.backfillDuplicateEntryIDs(container: container)

        let after = try ctx.fetch(FetchDescriptor<DoseEntry>(sortBy: [SortDescriptor(\.amount)])).map(\.id)
        #expect(after == before)
    }
}
