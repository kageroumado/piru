import Foundation
import GRDB
import Testing
@testable import Piru

@Suite("Wiki reference SQLite reader")
@MainActor
struct WikiTimingReadModelTests {
    private func database() throws -> DatabaseQueue {
        let database = try DatabaseQueue()
        try database.write { db in
            try db.execute(sql: """
                CREATE TABLE sources (id INTEGER PRIMARY KEY, slug TEXT);
                INSERT INTO sources VALUES (1, 'drug.community');
                CREATE TABLE drug_community_timelines (
                    record_key TEXT PRIMARY KEY, substance_id INTEGER, source_id INTEGER,
                    source_name TEXT, route TEXT, kind TEXT, entry_index INTEGER,
                    release_id TEXT, entry_json TEXT, duration_text_json TEXT,
                    modeling_exclusion TEXT
                );
            """)
            for index in 0 ..< 2 {
                try db.execute(sql: """
                    INSERT INTO drug_community_timelines VALUES (?, 42, 1, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                    "entry-\(index)", "Fictional compound", "ophthalmic",
                    "partial_duration_curve", index, "fictional-release",
                    #"{"formulation":"Fictional ointment","partial_duration_curve":{"units":"days","onset":{"start":null,"end":null},"peak":{"start":1,"end":2},"after_effects":{"start":3,"end":20}}}"#,
                    #"{"onset":"Unknown in this fictional fixture"}"#,
                    index == 0 ? "reference_only" : "source_exception",
                ])
            }
        }
        return database
    }

    @Test
    func `reads duplicate routes without combining their identity`() throws {
        let db = try database()
        let reader = SubstanceReadModel(db: db, order: ["drug.community"], language: .en)
        let records = reader.wikiTimings(substanceID: 42)
        #expect(records.count == 2)
        #expect(records.map(\.id) == ["entry-0", "entry-1"])
        #expect(records[0].route == "ophthalmic")
        #expect(records[0].formulation == "Fictional ointment")
        #expect(records[0].curve?.onset?.end == nil)
        #expect(records[0].curve?.afterEffects?.end == 20)
        #expect(records[1].hasSourceException)
    }

    @Test
    func `disabled sources stay disabled`() throws {
        let db = try database()
        let reader = SubstanceReadModel(db: db, order: ["piru-curated"], language: .en)
        #expect(reader.wikiTimings(substanceID: 42).isEmpty)
        let empty = SubstanceReadModel(db: db, order: [], language: .en)
        #expect(empty.wikiTimings(substanceID: 42).isEmpty)
    }

    @Test
    func `an older bundle remains readable`() throws {
        let reader = try SubstanceReadModel(db: DatabaseQueue(), order: ["drug.community"], language: .en)
        #expect(reader.wikiTimings(substanceID: 42).isEmpty)
    }
}
