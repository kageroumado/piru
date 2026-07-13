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
    func `A missing file is readable — the fresh-install path`() {
        #expect(StoreHealth.isReadable(at: tmpStoreURL()))
    }

    @Test
    func `A real SwiftData store passes the read-write integrity probe`() throws {
        // Empirically confirms the read-write probe reads a WAL-backed SwiftData
        // store without false-flagging it (the reason `isReadable` does not open
        // read-only).
        let url = tmpStoreURL()
        try seedStore(at: url, entries: 3)
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
