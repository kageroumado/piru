import Foundation
import GRDB
import Testing
@testable import Piru

/// The locking discipline behind the `0xdead10cc` fix: substance connections
/// open lock-free through an `immutable` URI, the prefs store runs in WAL so
/// its reads survive suspension, and ``DatabaseSuspension`` really does gate
/// GRDB connections that observe it.
@Suite("Database locking & suspension")
@MainActor
struct DatabaseLockingTests {
    private func makeTempDir(named name: String) throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var bundledDBURL: URL {
        get throws {
            try #require(
                Bundle(for: SubstanceStore.self).url(forResource: "piru-substances", withExtension: "sqlite"),
                "Bundled piru-substances.sqlite missing from the test host bundle",
            )
        }
    }

    @Test
    func `The immutable URI percent-encodes the characters the URI grammar reserves`() {
        let url = URL(fileURLWithPath: "/tmp/piru store/100% real?.sqlite")
        #expect(SubstanceStore.immutableSQLiteURI(for: url) == "file:/tmp/piru%20store/100%25%20real%3F.sqlite?immutable=1")
    }

    @Test
    func `A substances DB on a path with spaces and percent signs opens through the immutable URI`() throws {
        let tempDir = try makeTempDir(named: "piru locking 100% tests")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let copy = tempDir.appendingPathComponent("substances copy.sqlite")
        try FileManager.default.copyItem(at: bundledDBURL, to: copy)

        let store = SubstanceStore(
            substancesDBURL: copy,
            userPrefsDBURL: tempDir.appendingPathComponent("piru-user-prefs.sqlite"),
            prewarmsAllCache: false,
        )
        defer { store.closeUserPrefsForTesting() }
        #expect(store.count > 1_000)
        // Immutable connections read no WAL and create no shm beside the file.
        #expect(!FileManager.default.fileExists(atPath: copy.path + "-shm"))
    }

    @Test
    func `The user-prefs store runs in WAL mode`() throws {
        let (store, tempDir) = try makeIsolatedSubstanceStore()
        defer { tearDownIsolatedSubstanceStore(store, tempDir: tempDir) }
        #expect(store.userPrefsJournalModeForTesting() == "wal")
    }

    @Test
    func `Suspension refuses writes, keeps WAL reads, and resume restores writes`() throws {
        let tempDir = try makeTempDir(named: "piru-suspension")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        var config = Configuration()
        config.journalMode = .wal
        config.observesSuspensionNotifications = true
        let queue = try DatabaseQueue(path: tempDir.appendingPathComponent("prefs.sqlite").path, configuration: config)
        defer { try? queue.close() }
        try queue.write { db in
            try db.execute(sql: "CREATE TABLE t(x INTEGER); INSERT INTO t VALUES (1)")
        }

        DatabaseSuspension.suspend()
        defer { DatabaseSuspension.resume() }
        #expect(DatabaseSuspension.isSuspended)
        #expect(throws: DatabaseError.self) {
            try queue.write { db in try db.execute(sql: "INSERT INTO t VALUES (2)") }
        }
        #expect(try queue.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM t") } == 1)

        DatabaseSuspension.resume()
        #expect(!DatabaseSuspension.isSuspended)
        try queue.write { db in try db.execute(sql: "INSERT INTO t VALUES (3)") }
        #expect(try queue.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM t") } == 2)
    }

    @Test
    func `withResumed runs its body unsuspended and restores the prior state`() async {
        DatabaseSuspension.suspend()
        defer { DatabaseSuspension.resume() }
        let insideWasSuspended = await DatabaseSuspension.withResumed { DatabaseSuspension.isSuspended }
        #expect(!insideWasSuspended)
        #expect(DatabaseSuspension.isSuspended)

        DatabaseSuspension.resume()
        let stillResumed = await DatabaseSuspension.withResumed { DatabaseSuspension.isSuspended }
        #expect(!stillResumed)
        #expect(!DatabaseSuspension.isSuspended)
    }
}
