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
        // now does — the V1→V2 lightweight migration must preserve all data.
        let container = try ModelContainer(
            for: Schema(versionedSchema: PiruSchemaV2.self),
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
