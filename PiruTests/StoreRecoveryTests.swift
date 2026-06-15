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

    /// Create a store at `url` (plain Schema, like the pre-versioned builds) and
    /// seed `n` dose entries, then let the container deallocate (flushing).
    ///
    /// Uses the original five-model V1 schema — the exact shape an upgrading
    /// user's on-disk store has — so the adoption test exercises the real
    /// V1→V2 lightweight migration rather than opening a store that already
    /// matches the current schema.
    private func seedStore(at url: URL, entries n: Int) throws {
        let container = try ModelContainer(
            for: Schema(PiruSchemaV1.models),
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none),
        )
        let ctx = ModelContext(container)
        for i in 0 ..< n {
            ctx.insert(DoseEntry(substance: "Caffeine", amount: Double(50 + i)))
        }
        try ctx.save()
    }

    @Test
    func `Adopting the versioned schema on a plain-Schema store preserves data`() throws {
        let url = tmpStoreURL()
        try seedStore(at: url, entries: 3)

        // Reopen with the current versioned schema + migration plan, as the app
        // now does — walking the full stage chain must preserve all data.
        // (The target must be the plan's final version: a mid-plan target like
        // V2 stopped loading once the plan continued past it to V3/V4/V5.)
        let container = try ModelContainer(
            for: Schema(versionedSchema: PiruSchemaV5.self),
            migrationPlan: PiruMigrationPlan.self,
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

    /// The five V1 models plus `Session` but *not* `QuickLogDose` — an
    /// "intermediate" shape that matches neither the V1 (5-model) nor the V2
    /// (7-model) schema the migration plan knows about. This is the shape a dev /
    /// pre-release build leaves on disk, and the one that triggered the quarantine.
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
        // The makeContainer fallback: open the bare current schema with no plan.
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

// MARK: - Schema V4 (DoseEntry stable id)

/// The V3→V4 migration adds `DoseEntry.id`. These tests build the legacy store
/// with the class-level frozen `PiruSchemaV3` copies (the exact pre-`id` shape
/// real devices have on disk), open it through the real plan, and assert the
/// invariant the whole stable-identity feature rests on: every row keeps its
/// data and gets its own unique id.
///
/// `@MainActor` is required, not stylistic: the V3→V4 stage's `didMigrate`
/// only runs its per-row UUID pass when the container is opened from the main
/// thread (matching how the app opens it — see `PiruMigrationPlan`).
@Suite("Schema V4 migration")
@MainActor
struct SchemaV4MigrationTests {
    private func tmpStoreURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("piru-v4test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("default.store")
    }

    /// Seed a store in the exact shape shipped as V3: the frozen
    /// `PiruSchemaV3.DoseEntry` (no `id` column) + `PiruSchemaV3.Session`,
    /// with `n` doses, the first two grouped into a titled session.
    private func seedV3Store(at url: URL, entries n: Int) throws {
        let container = try ModelContainer(
            for: Schema(versionedSchema: PiruSchemaV3.self),
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none),
        )
        let ctx = ModelContext(container)
        var doses: [PiruSchemaV3.DoseEntry] = []
        for i in 0 ..< n {
            let dose = PiruSchemaV3.DoseEntry(
                substance: "Caffeine",
                amount: Double(50 + i),
                timestamp: Date(timeIntervalSince1970: 1_700_000_000 + Double(i) * 60),
            )
            ctx.insert(dose)
            doses.append(dose)
        }
        if doses.count >= 2 {
            let session = PiruSchemaV3.Session(startDate: doses[0].timestamp, title: "Morning")
            ctx.insert(session)
            doses[0].session = session
            doses[1].session = session
        }
        try ctx.save()
    }

    @Test
    func `V3 store migrates through the plan with all rows preserved and unique per-row ids`() throws {
        let url = tmpStoreURL()
        try seedV3Store(at: url, entries: 5)

        let container = try ModelContainer(
            for: Schema(versionedSchema: PiruSchemaV5.self),
            migrationPlan: PiruMigrationPlan.self,
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none),
        )
        let ctx = ModelContext(container)
        let entries = try ctx.fetch(FetchDescriptor<DoseEntry>(sortBy: [SortDescriptor(\.timestamp)]))

        // Every row survived, fields untouched.
        #expect(entries.count == 5)
        #expect(entries.map(\.amount) == [50, 51, 52, 53, 54])
        #expect(entries.allSatisfy { $0.substance == "Caffeine" })

        // The whole point of V4: per-row unique ids. A plain `.lightweight`
        // stage fills ONE shared UUID into every row — the custom stage's
        // didMigrate must have reassigned them.
        #expect(Set(entries.map(\.id)).count == 5)

        // The frozen Session ↔ DoseEntry relationship mapped across.
        let sessions = try ctx.fetch(FetchDescriptor<Session>())
        let session = try #require(sessions.first { $0.title == "Morning" })
        #expect(session.orderedDoses.count == 2)
    }

    @Test
    func `A fresh V5 store round-trips ids across reopen`() throws {
        let url = tmpStoreURL()
        let fixedID = try #require(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-000000000001"))

        do {
            let container = try ModelContainer(
                for: Schema(versionedSchema: PiruSchemaV5.self),
                migrationPlan: PiruMigrationPlan.self,
                configurations: ModelConfiguration(url: url, cloudKitDatabase: .none),
            )
            let ctx = ModelContext(container)
            let entry = DoseEntry(substance: "Caffeine", amount: 100)
            entry.id = fixedID
            ctx.insert(entry)
            ctx.insert(DoseEntry(substance: "Melatonin", amount: 3))
            try ctx.save()
        }

        // Reopen with the same plan — already at V5, no migration must run and
        // the persisted ids must come back verbatim.
        let container = try ModelContainer(
            for: Schema(versionedSchema: PiruSchemaV5.self),
            migrationPlan: PiruMigrationPlan.self,
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none),
        )
        let ctx = ModelContext(container)
        let entries = try ctx.fetch(FetchDescriptor<DoseEntry>())
        #expect(entries.count == 2)
        #expect(entries.first { $0.substance == "Caffeine" }?.id == fixedID)
        #expect(Set(entries.map(\.id)).count == 2)
    }

    // MARK: - Post-open backfill (the auto-lightweight fallback path)

    @Test
    func `Backfill uniquifies all-duplicate ids without touching other fields`() throws {
        // Simulate the automatic-lightweight outcome: the store opened without
        // the staged plan, so every pre-existing row carries the SAME UUID.
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

/// The V4→V5 migration adds the optional `DoseEntry.saltForm`. These tests build
/// a store in the exact frozen V4 shape (id-bearing, pre-`saltForm`) real devices
/// have on disk, open it through the real plan, and assert the lightweight stage
/// preserves every row and id while leaving `saltForm` nil — and that the freeze
/// of V4 didn't reintroduce the "Duplicate version checksums" launch crash.
@Suite("Schema V5 migration")
@MainActor
struct SchemaV5MigrationTests {
    private func tmpStoreURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("piru-v5test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("default.store")
    }

    /// Seed a store in the exact shape shipped as V4: the frozen
    /// `PiruSchemaV4.DoseEntry` (id, no `saltForm`) with `n` doses.
    private func seedV4Store(at url: URL, entries n: Int) throws {
        let container = try ModelContainer(
            for: Schema(versionedSchema: PiruSchemaV4.self),
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none),
        )
        let ctx = ModelContext(container)
        for i in 0 ..< n {
            let dose = PiruSchemaV4.DoseEntry(
                substance: "Caffeine",
                amount: Double(50 + i),
                timestamp: Date(timeIntervalSince1970: 1_700_000_000 + Double(i) * 60),
            )
            dose.id = UUID()
            ctx.insert(dose)
        }
        try ctx.save()
    }

    @Test
    func `V4 store migrates to V5 with rows + ids preserved and saltForm nil`() throws {
        let url = tmpStoreURL()
        try seedV4Store(at: url, entries: 4)

        let container = try ModelContainer(
            for: Schema(versionedSchema: PiruSchemaV5.self),
            migrationPlan: PiruMigrationPlan.self,
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none),
        )
        let ctx = ModelContext(container)
        let entries = try ctx.fetch(FetchDescriptor<DoseEntry>(sortBy: [SortDescriptor(\.timestamp)]))

        #expect(entries.count == 4)
        #expect(entries.map(\.amount) == [50, 51, 52, 53])
        #expect(Set(entries.map(\.id)).count == 4) // ids carried over verbatim
        // The new column is nil for every pre-existing row — the whole reason
        // V4→V5 is a safe lightweight stage.
        #expect(entries.allSatisfy { $0.saltForm == nil })
    }

    @Test
    func `A logged saltForm round-trips through a V5 store`() throws {
        let url = tmpStoreURL()
        do {
            let container = try ModelContainer(
                for: Schema(versionedSchema: PiruSchemaV5.self),
                migrationPlan: PiruMigrationPlan.self,
                configurations: ModelConfiguration(url: url, cloudKitDatabase: .none),
            )
            let ctx = ModelContext(container)
            ctx.insert(DoseEntry(substance: "Magnesium", amount: 300, unit: "mg", route: .oral, saltForm: "Glycinate"))
            ctx.insert(DoseEntry(substance: "Caffeine", amount: 80, unit: "mg", route: .oral))
            try ctx.save()
        }
        let container = try ModelContainer(
            for: Schema(versionedSchema: PiruSchemaV5.self),
            migrationPlan: PiruMigrationPlan.self,
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none),
        )
        let ctx = ModelContext(container)
        let entries = try ctx.fetch(FetchDescriptor<DoseEntry>())
        #expect(entries.first { $0.substance == "Magnesium" }?.saltForm == "Glycinate")
        #expect(entries.first { $0.substance == "Caffeine" }?.saltForm == nil)
    }
}
