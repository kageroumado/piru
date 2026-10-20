import Foundation
import GRDB
import Testing
@testable import Piru

@Suite("Wiki dose reference SQLite reader")
@MainActor
struct WikiDoseReferenceReadModelTests {
    private func database() throws -> DatabaseQueue {
        let database = try DatabaseQueue()
        try database.write { db in
            try db.execute(sql: """
                CREATE TABLE sources (id INTEGER PRIMARY KEY, slug TEXT);
                INSERT INTO sources VALUES (1, 'drug.community');
                CREATE TABLE drug_community_dose_references (
                    record_key TEXT PRIMARY KEY, substance_id INTEGER, source_id INTEGER,
                    source_name TEXT, model_json TEXT, profile_sha256 TEXT,
                    snapshot_sha256 TEXT, release_id TEXT
                );
            """)
            for index in 0 ..< 2 {
                try db.execute(sql: """
                    INSERT INTO drug_community_dose_references VALUES (?, 42, 1, ?, ?, ?, ?, ?)
                """, arguments: [
                    "profile-\(index)", "Fictional compound", WikiDoseReferenceFixtures.json(WikiDoseReferenceFixtures.model()),
                    String(repeating: "a", count: 64), String(repeating: "b", count: 64), "fictional-release",
                ])
            }
        }
        return database
    }

    @Test
    func `profiles with matching routes retain separate identities`() throws {
        let db = try database()
        let reader = SubstanceReadModel(db: db, order: ["drug.community"], language: .en)
        let records = reader.wikiDoseReferences(substanceID: 42)
        #expect(records.map(\.id) == ["profile-0", "profile-1"])
        #expect(records[0].model.groups[0].route == records[1].model.groups[0].route)
        #expect(records[0].snapshotSHA256 == String(repeating: "b", count: 64))
        #expect(reader.wikiDoseReferences(substanceID: 99).isEmpty)
    }

    @Test
    func `one malformed profile does not erase valid references`() throws {
        let db = try database()
        try db.write { database in
            try database.execute(sql: "UPDATE drug_community_dose_references SET model_json = '{}' WHERE record_key = 'profile-0'")
        }
        let reader = SubstanceReadModel(db: db, order: ["drug.community"], language: .en)
        #expect(reader.wikiDoseReferences(substanceID: 42).map(\.id) == ["profile-1"])
    }

    @Test
    func `disabled sources and older bundles remain supported`() throws {
        let db = try database()
        let disabled = SubstanceReadModel(db: db, order: ["piru-curated"], language: .en)
        #expect(disabled.wikiDoseReferences(substanceID: 42).isEmpty)
        let empty = SubstanceReadModel(db: db, order: [], language: .en)
        #expect(empty.wikiDoseReferences(substanceID: 42).isEmpty)
        let older = try SubstanceReadModel(db: DatabaseQueue(), order: ["drug.community"], language: .en)
        #expect(older.wikiDoseReferences(substanceID: 42).isEmpty)
    }
}
