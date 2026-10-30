import Foundation
import GRDB
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

    /// A WAL-mode store at `url` whose `-wal` holds committed frames that were never
    /// checkpointed, and that no connection holds open.
    ///
    /// Built by copying a live writer's files rather than from a SwiftData seed: a
    /// released `ModelContainer` closes on its own schedule and truncates its WAL
    /// when it does, so a seeded store's WAL can empty itself mid-test. Copying
    /// while the writer is still open captures frames no close has checkpointed;
    /// SQLite rebuilds the WAL index from the copied `-wal` on the next open.
    private func makeStoreWithUncheckpointedWAL(at url: URL) throws {
        let source = url.deletingLastPathComponent().appendingPathComponent("source.store")
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA wal_autocheckpoint = 0")
        }
        let writer = try DatabaseQueue(path: source.path, configuration: config)
        try writer.write { db in
            try db.execute(sql: "CREATE TABLE entry (id INTEGER PRIMARY KEY, amount REAL)")
            try db.execute(sql: "INSERT INTO entry (amount) VALUES (50), (51), (52)")
        }
        try FileManager.default.copyItem(at: source, to: url)
        try FileManager.default.copyItem(atPath: source.path + "-wal", toPath: url.path + "-wal")
        try writer.close()
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
        try makeStoreWithUncheckpointedWAL(at: url)
        let footprint = { () -> [String] in
            [url.path, url.path + "-wal"].map { path in
                let attributes = (try? FileManager.default.attributesOfItem(atPath: path)) ?? [:]
                return "\(attributes[.size] ?? 0)|\(attributes[.modificationDate] ?? "missing")"
            }
        }
        let before = footprint()
        let walSize = try FileManager.default.attributesOfItem(atPath: url.path + "-wal")[.size] as? Int
        try #require((walSize ?? 0) > 0, "the fixture must hand the probe a WAL with frames to checkpoint")
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

    // MARK: - Read-only row count (the launch fast path)

    @Test
    func `Every user-data table is named the way Core Data lays out a SwiftData store`() throws {
        // The SQL count trusts `Z` + uppercased model name; a real store is the proof.
        let url = tmpStoreURL()
        try seedStore(at: url, entries: 1)
        var config = Configuration()
        config.readonly = true
        // The seeding container finishes closing asynchronously; wait as `StoreHealth.probe` does.
        config.busyMode = .timeout(2)
        let queue = try DatabaseQueue(path: url.path, configuration: config)
        let tables = StoreRecovery.userDataTables
        let schema = Set(PiruSchema.models.map { "Z" + String(describing: $0).uppercased() })
        #expect(Set(tables) == schema.subtracting(["ZTOLERANCESTATE", "ZNOTIFICATIONPREFERENCES"]))
        let missing = try queue.read { db in try tables.filter { try !db.tableExists($0) } }
        #expect(missing.isEmpty)
        try queue.close()
    }

    @Test
    func `The SQL row count agrees with the SwiftData count`() throws {
        let url = tmpStoreURL()
        try seedStore(at: url, entries: 4)
        #expect(StoreHealth.rowCount(at: url, tables: StoreRecovery.userDataTables) == 4)
        #expect(StoreRecovery.launchUserDataCount(at: url) == StoreRecovery.userDataCount(at: url))
    }

    @Test
    func `The SQL row count cannot answer for a missing file or a store SwiftData did not make`() throws {
        #expect(StoreHealth.rowCount(at: tmpStoreURL(), tables: StoreRecovery.userDataTables) == nil)
        let plain = tmpStoreURL()
        try makeStoreWithUncheckpointedWAL(at: plain)
        #expect(StoreHealth.rowCount(at: plain, tables: StoreRecovery.userDataTables) == nil)
        let garbage = tmpStoreURL()
        try Data(repeating: 0x00, count: 4_096).write(to: garbage)
        #expect(StoreHealth.rowCount(at: garbage, tables: StoreRecovery.userDataTables) == nil)
    }

    @Test
    func `The launch count is zero for an absent store and never creates one`() {
        let url = tmpStoreURL()
        #expect(StoreRecovery.launchUserDataCount(at: url) == 0)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test
    func `The SQL row count reads the WAL, counts absent tables as empty, and never checkpoints`() throws {
        // A Core Data-shaped WAL store whose rows exist only as uncheckpointed
        // frames, with one of the counted tables missing.
        let url = tmpStoreURL()
        let source = url.deletingLastPathComponent().appendingPathComponent("source.store")
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA wal_autocheckpoint = 0")
        }
        let writer = try DatabaseQueue(path: source.path, configuration: config)
        try writer.write { db in
            try db.execute(sql: "CREATE TABLE Z_METADATA (Z_VERSION INTEGER PRIMARY KEY)")
            try db.execute(sql: "CREATE TABLE ZDOSEENTRY (Z_PK INTEGER PRIMARY KEY)")
            try db.execute(sql: "CREATE TABLE ZFAVORITESUBSTANCE (Z_PK INTEGER PRIMARY KEY)")
            try db.execute(sql: "INSERT INTO ZDOSEENTRY DEFAULT VALUES")
            try db.execute(sql: "INSERT INTO ZDOSEENTRY DEFAULT VALUES")
            try db.execute(sql: "INSERT INTO ZFAVORITESUBSTANCE DEFAULT VALUES")
        }
        try FileManager.default.copyItem(at: source, to: url)
        try FileManager.default.copyItem(atPath: source.path + "-wal", toPath: url.path + "-wal")
        try writer.close()

        let footprint = { () -> [String] in
            [url.path, url.path + "-wal"].map { path in
                let attributes = (try? FileManager.default.attributesOfItem(atPath: path)) ?? [:]
                return "\(attributes[.size] ?? 0)|\(attributes[.modificationDate] ?? "missing")"
            }
        }
        let before = footprint()
        #expect(StoreHealth.rowCount(at: url, tables: StoreRecovery.userDataTables) == 3)
        #expect(footprint() == before)
    }
}
