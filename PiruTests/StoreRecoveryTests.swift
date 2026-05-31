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
    func `Adopting the versioned schema on a plain-Schema store preserves data`() throws {
        let url = tmpStoreURL()
        try seedStore(at: url, entries: 3)

        // Reopen with the versioned schema + migration plan, as the app now does.
        let container = try ModelContainer(
            for: Schema(versionedSchema: PiruSchemaV1.self),
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
}
