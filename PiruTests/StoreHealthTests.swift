import Foundation
import SwiftData
import Testing
@testable import Piru

/// @MainActor to serialize with the other SwiftData container suites (see the
/// note in ``StoreRecoveryTests``): `seedStore` builds a real `ModelContainer`,
/// and SwiftData's entity registration is process-global.
@Suite("StoreHealth")
@MainActor
struct StoreHealthTests {
    private func tmpStoreURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("piru-healthtest-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("default.store")
    }

    /// Seeds a store and lets go of it before returning.
    ///
    /// The `autoreleasepool` is load-bearing: `ModelContainer` sits on a
    /// CoreData stack whose objects are ObjC-autoreleased, so without the pool
    /// the coordinator can outlive this call and still hold the `-wal` when the
    /// caller probes the same URL — which `userDataCount` reports as `-1`.
    private func seedStore(at url: URL, entries n: Int) throws {
        try autoreleasepool {
            let container = try ModelContainer(
                for: Schema(PiruSchema.models),
                configurations: ModelConfiguration(url: url, cloudKitDatabase: .none),
            )
            let ctx = ModelContext(container)
            for i in 0 ..< n {
                ctx.insert(DoseEntry(substance: "Caffeine", amount: Double(50 + i)))
            }
            try ctx.save()
        }
    }

    @Test
    func `A missing file is readable — the fresh-install path`() {
        #expect(StoreHealth.isReadable(at: tmpStoreURL()))
    }

    @Test
    func `A real SwiftData store passes the integrity probe`() throws {
        // A WAL-backed SwiftData store is read by the read-only probe without
        // being false-flagged.
        let url = tmpStoreURL()
        try seedStore(at: url, entries: 3)
        #expect(StoreHealth.isReadable(at: url))
    }

    @Test
    func `The probe leaves the WAL in place — it never checkpoints`() throws {
        // The read-write probe used to checkpoint and delete the -wal on close,
        // an fsync on the App Group store that iOS suspended the process in.
        let url = tmpStoreURL()
        try seedStore(at: url, entries: 3)
        let footprint = { () -> [String] in
            [url.path, url.path + "-wal"].map { path in
                let attributes = (try? FileManager.default.attributesOfItem(atPath: path)) ?? [:]
                return "\(attributes[.size] ?? 0)|\(attributes[.modificationDate] ?? "missing")"
            }
        }
        let before = footprint()
        #expect(StoreHealth.isReadable(at: url))
        #expect(footprint() == before)
    }

    @Test
    func `A store the process may not open is inconclusive, not corrupt`() throws {
        // Data Protection on a locked device throws EPERM at a background
        // launch; treating that as corruption would hand the recovery path a
        // reason to replace the user's store with an older candidate.
        let url = tmpStoreURL()
        try seedStore(at: url, entries: 3)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path) }
        #expect(StoreHealth.isReadable(at: url))
    }

    @Test
    func `A non-database file is unreadable, not a crash`() throws {
        let url = tmpStoreURL()
        try Data("not a sqlite file, just garbage".utf8).write(to: url)
        #expect(!StoreHealth.isReadable(at: url))
    }

    @Test
    func `A store with a corrupted header is unreadable`() throws {
        let url = tmpStoreURL()
        try seedStore(at: url, entries: 2)
        // Clobber the 16-byte SQLite magic ("SQLite format 3\0") so the file is
        // no longer recognizable as a database.
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: 0)
        handle.write(Data(repeating: 0xFF, count: 16))
        #expect(!StoreHealth.isReadable(at: url))
    }

    @Test
    func `userDataCount gates a corrupt store to -1 without reaching SwiftData`() throws {
        // The build-30 regression: a corrupt canonical store must resolve to
        // "unreadable" (-1) via the integrity gate instead of being handed to a
        // ModelContainer open, which aborts the process natively on bad SQLite.
        let url = tmpStoreURL()
        try Data(repeating: 0x00, count: 4_096).write(to: url)
        #expect(StoreRecovery.userDataCount(at: url) == -1)
    }

    @Test
    func `userDataCount still counts a healthy store through the gate`() throws {
        let url = tmpStoreURL()
        try seedStore(at: url, entries: 5)
        #expect(StoreRecovery.userDataCount(at: url) == 5)
    }
}
