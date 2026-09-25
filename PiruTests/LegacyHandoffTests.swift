import Foundation
import GRDB
import SwiftData
import Testing
@testable import Piru

/// The legacy → successor handoff against temp directories standing in for the two app
/// group containers and the successor's `Documents/`, with throwaway defaults suites.
/// @MainActor for the same reason as `StoreRecoveryTests`: SwiftData container builds
/// must not race the other container suites.
@Suite("LegacyHandoff")
@MainActor
struct LegacyHandoffTests {
    /// Temp containers and defaults for one test.
    final class Fixture {
        let root: URL
        let legacy: URL
        let successor: URL
        let documents: URL
        let legacyDocuments: URL
        let legacyGroupSuite = "piru-handoff-legacy-\(UUID().uuidString)"
        let successorGroupSuite = "piru-handoff-successor-\(UUID().uuidString)"
        let standardSuite = "piru-handoff-standard-\(UUID().uuidString)"
        let legacyGroupDefaults: UserDefaults
        let successorGroupDefaults: UserDefaults
        let standardDefaults: UserDefaults
        var legacyStandardDomain: [String: Any] = [:]

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("piru-handoff-\(UUID().uuidString)", isDirectory: true)
            legacy = root.appendingPathComponent("legacy-group", isDirectory: true)
            successor = root.appendingPathComponent("successor-group", isDirectory: true)
            documents = root.appendingPathComponent("successor-documents", isDirectory: true)
            legacyDocuments = root.appendingPathComponent("legacy-documents", isDirectory: true)
            for dir in [legacy, successor, documents, legacyDocuments] {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            legacyGroupDefaults = try #require(UserDefaults(suiteName: legacyGroupSuite))
            successorGroupDefaults = try #require(UserDefaults(suiteName: successorGroupSuite))
            standardDefaults = try #require(UserDefaults(suiteName: standardSuite))
        }

        deinit {
            for suite in [legacyGroupSuite, successorGroupSuite, standardSuite] {
                UserDefaults().removePersistentDomain(forName: suite)
            }
            try? FileManager.default.removeItem(at: root)
        }

        var legacyStore: URL {
            legacy.appendingPathComponent(StoreRecovery.storeName)
        }

        var successorStore: URL {
            successor.appendingPathComponent(StoreRecovery.storeName)
        }

        var importer: LegacyHandoff.Importer {
            let legacyDefaults = legacyGroupDefaults
            let suite = legacyGroupSuite
            return LegacyHandoff.Importer(
                legacyContainer: legacy,
                successorContainer: successor,
                successorDocuments: documents,
                legacyGroupDomain: { legacyDefaults.persistentDomain(forName: suite) },
                successorGroupDefaults: successorGroupDefaults,
                standardDefaults: standardDefaults,
                markLegacyImported: { legacyDefaults.set($0, forKey: LegacyHandoff.successorImportedAtKey) },
            )
        }

        var publisher: LegacyHandoff.Publisher {
            let domain = legacyStandardDomain
            return LegacyHandoff.Publisher(
                groupContainer: legacy,
                documents: legacyDocuments,
                scratch: root,
                standardDomain: { domain },
            )
        }
    }

    /// Seeds a store and lets go of it before returning, as `StoreRecoveryTests` does.
    private func seedStore(at url: URL, entries n: Int) throws {
        try autoreleasepool {
            let container = try ModelContainer(
                for: Schema(PiruSchema.models),
                configurations: ModelConfiguration(url: url, cloudKitDatabase: .none),
            )
            let context = ModelContext(container)
            for i in 0 ..< n {
                context.insert(DoseEntry(substance: "Caffeine", amount: Double(50 + i)))
            }
            try context.save()
        }
    }

    private func seedUserPrefs(at url: URL, order: [String]) throws {
        let queue = try DatabaseQueue(path: url.path)
        try queue.write { db in
            try db.execute(sql: "CREATE TABLE source_preferences (source_id TEXT PRIMARY KEY, priority INTEGER)")
            for (priority, source) in order.enumerated() {
                try db.execute(sql: "INSERT INTO source_preferences VALUES (?, ?)", arguments: [source, priority])
            }
        }
        try queue.close()
    }

    private func sourceOrder(at url: URL) throws -> [String] {
        let queue = try DatabaseQueue(path: url.path)
        defer { try? queue.close() }
        return try queue.read { try String.fetchAll($0, sql: "SELECT source_id FROM source_preferences ORDER BY priority") }
    }

    // MARK: - Store

    @Test
    func `A fresh successor imports the legacy store and marks both sides`() throws {
        let fixture = try Fixture()
        try seedStore(at: fixture.legacyStore, entries: 4)

        let outcome = fixture.importer.run()

        #expect(outcome == .imported(journalEntries: 4))
        #expect(StoreRecovery.userDataCount(at: fixture.successorStore) == 4)
        #expect(StoreRecovery.userDataCount(at: fixture.legacyStore) == 4)
        #expect(fixture.standardDefaults.integer(forKey: LegacyHandoff.importedJournalEntriesKey) == 4)
        #expect(fixture.standardDefaults.object(forKey: LegacyHandoff.completedAtKey) is Date)
        #expect(fixture.legacyGroupDefaults.object(forKey: LegacyHandoff.successorImportedAtKey) is Date)
        // The staging folder is gone and the store is one self-contained file.
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: fixture.successor.path)
            .filter { $0.hasPrefix(".legacy-handoff") }
        #expect(leftovers.isEmpty)
    }

    @Test
    func `An empty store the widget created is set aside, then replaced`() throws {
        let fixture = try Fixture()
        try seedStore(at: fixture.legacyStore, entries: 2)
        try seedStore(at: fixture.successorStore, entries: 0)

        #expect(fixture.importer.run() == .imported(journalEntries: 2))
        #expect(StoreRecovery.userDataCount(at: fixture.successorStore) == 2)
        let setAside = try FileManager.default.contentsOfDirectory(atPath: fixture.successor.path)
            .filter { $0.hasPrefix("default.store.empty-before-handoff-") }
        #expect(!setAside.isEmpty)
    }

    @Test
    func `A successor with its own data is left untouched`() throws {
        let fixture = try Fixture()
        try seedStore(at: fixture.legacyStore, entries: 5)
        try seedStore(at: fixture.successorStore, entries: 1)
        fixture.legacyGroupDefaults.set("tsuki", forKey: "skin")

        #expect(fixture.importer.run() == .successorHasData)
        #expect(StoreRecovery.userDataCount(at: fixture.successorStore) == 1)
        #expect(fixture.successorGroupDefaults.object(forKey: "skin") == nil)
        #expect(fixture.standardDefaults.integer(forKey: LegacyHandoff.importedJournalEntriesKey) == 0)
        // Marked done, so later launches skip the store probe.
        #expect(fixture.importer.run() == .alreadyDone)
    }

    @Test
    func `A set marker makes the import a no-op`() throws {
        let fixture = try Fixture()
        try seedStore(at: fixture.legacyStore, entries: 3)
        fixture.standardDefaults.set(Date(), forKey: LegacyHandoff.completedAtKey)

        #expect(fixture.importer.run() == .alreadyDone)
        #expect(!FileManager.default.fileExists(atPath: fixture.successorStore.path))
    }

    @Test
    func `No legacy store means no import and no marker`() throws {
        let fixture = try Fixture()
        fixture.legacyGroupDefaults.set("tsuki", forKey: "skin")

        #expect(fixture.importer.run() == .noLegacyStore)
        #expect(fixture.successorGroupDefaults.object(forKey: "skin") == nil)
        #expect(fixture.standardDefaults.object(forKey: LegacyHandoff.completedAtKey) == nil)
    }

    @Test
    func `An unreadable legacy store fails without a marker and leaves the successor empty`() throws {
        let fixture = try Fixture()
        try Data("not a database".utf8).write(to: fixture.legacyStore)

        #expect(fixture.importer.run() == .failed)
        #expect(!FileManager.default.fileExists(atPath: fixture.successorStore.path))
        #expect(fixture.standardDefaults.object(forKey: LegacyHandoff.completedAtKey) == nil)
    }

    // MARK: - Defaults and published state

    @Test
    func `Group defaults come across without overwriting the successor's own`() throws {
        let fixture = try Fixture()
        try seedStore(at: fixture.legacyStore, entries: 1)
        fixture.legacyGroupDefaults.set("tsuki", forKey: "skin")
        fixture.legacyGroupDefaults.set(6, forKey: "dayBoundaryHour")
        fixture.legacyGroupDefaults.set(Date(), forKey: LegacyHandoff.successorImportedAtKey)
        fixture.successorGroupDefaults.set(3, forKey: "dayBoundaryHour")

        _ = fixture.importer.run()

        #expect(fixture.successorGroupDefaults.string(forKey: "skin") == "tsuki")
        #expect(fixture.successorGroupDefaults.integer(forKey: "dayBoundaryHour") == 3)
        #expect(fixture.successorGroupDefaults.object(forKey: LegacyHandoff.successorImportedAtKey) == nil)
    }

    @Test
    func `Published standard defaults and source priorities are restored`() throws {
        let fixture = try Fixture()
        try seedStore(at: fixture.legacyStore, entries: 1)
        try seedUserPrefs(
            at: fixture.legacyDocuments.appendingPathComponent(LegacyHandoff.userPrefsFile),
            order: ["dosewiki", "psychonautwiki", "tripsit"],
        )
        fixture.legacyStandardDomain = [
            "quickLogFixedOrder": true,
            "hasCompletedOnboarding": true,
            "install.firstBuild": 40,
            "com.apple.something": "system",
            LegacyHandoff.completedAtKey: Date(),
        ]
        fixture.standardDefaults.set(false, forKey: "hasCompletedOnboarding")

        try fixture.publisher.publish()
        _ = fixture.importer.run()

        #expect(fixture.standardDefaults.bool(forKey: "quickLogFixedOrder"))
        #expect(fixture.standardDefaults.integer(forKey: "install.firstBuild") == 40)
        #expect(fixture.standardDefaults.bool(forKey: "hasCompletedOnboarding") == false)
        #expect(fixture.standardDefaults.object(forKey: "com.apple.something") == nil)
        let restored = fixture.documents.appendingPathComponent(LegacyHandoff.userPrefsFile)
        #expect(try sourceOrder(at: restored) == ["dosewiki", "psychonautwiki", "tripsit"])
    }

    @Test
    func `An existing source-priority database is kept`() throws {
        let fixture = try Fixture()
        try seedStore(at: fixture.legacyStore, entries: 1)
        try seedUserPrefs(at: fixture.legacyDocuments.appendingPathComponent(LegacyHandoff.userPrefsFile), order: ["tripsit"])
        let own = fixture.documents.appendingPathComponent(LegacyHandoff.userPrefsFile)
        try seedUserPrefs(at: own, order: ["psychonautwiki"])

        try fixture.publisher.publish()
        _ = fixture.importer.run()

        #expect(try sourceOrder(at: own) == ["psychonautwiki"])
    }

    @Test
    func `Publishing twice is idempotent and picks up changes`() throws {
        let fixture = try Fixture()
        let prefs = fixture.legacyDocuments.appendingPathComponent(LegacyHandoff.userPrefsFile)
        try seedUserPrefs(at: prefs, order: ["tripsit"])
        fixture.legacyStandardDomain = ["quickLogFixedOrder": true]

        try fixture.publisher.publish()
        try fixture.publisher.publish()
        let queue = try DatabaseQueue(path: prefs.path)
        try queue.write { try $0.execute(sql: "INSERT INTO source_preferences VALUES ('dosewiki', 1)") }
        try queue.close()
        try fixture.publisher.publish()

        let folder = fixture.legacy.appendingPathComponent(LegacyHandoff.handoffFolder)
        #expect(try sourceOrder(at: folder.appendingPathComponent(LegacyHandoff.userPrefsFile)) == ["tripsit", "dosewiki"])
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        #expect(names == [LegacyHandoff.userPrefsFile, LegacyHandoff.standardDefaultsFile].sorted())
    }
}
