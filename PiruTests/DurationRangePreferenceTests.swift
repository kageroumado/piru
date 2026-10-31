import Foundation
import GRDB
import Testing
@testable import Piru

/// Each duration phase prefers a range: among enabled sources in priority order
/// the first one that states an interval wins, and a single figure wins only
/// when no source gives a range — then it is shown as approximate.
@Suite("Duration phases prefer ranges")
struct DurationRangePreferenceTests {
    private static let substanceID: Int64 = 42

    /// A minimal `durations` schema with three sources and no per-field
    /// overrides, so the user's order alone ranks them.
    private func database(
        _ rows: [(source: String, phase: String, min: Double, max: Double)],
        fieldPriority: [(source: String, priority: Int)] = [],
    ) throws -> DatabaseQueue {
        let database = try DatabaseQueue()
        try database.write { db in
            try db.execute(sql: """
                CREATE TABLE sources (id INTEGER PRIMARY KEY, slug TEXT);
                INSERT INTO sources VALUES (1, 'drug.community'), (2, 'psychonautwiki'), (3, 'tripsit');
                CREATE TABLE source_field_priority (
                    field TEXT, source_id INTEGER, priority INTEGER, note TEXT
                );
                CREATE TABLE durations (
                    id INTEGER PRIMARY KEY, substance_id INTEGER, route TEXT, source_id INTEGER,
                    phase TEXT, min_minutes REAL, max_minutes REAL, salt_form TEXT, isomer TEXT,
                    citation_id INTEGER
                );
            """)
            for row in rows {
                try db.execute(sql: """
                    INSERT INTO durations (substance_id, route, source_id, phase, min_minutes, max_minutes)
                    VALUES (?, 'oral', (SELECT id FROM sources WHERE slug = ?), ?, ?, ?)
                """, arguments: [Self.substanceID, row.source, row.phase, row.min, row.max])
            }
            for override in fieldPriority {
                try db.execute(sql: """
                    INSERT INTO source_field_priority
                    VALUES ('durations', (SELECT id FROM sources WHERE slug = ?), ?, NULL)
                """, arguments: [override.source, override.priority])
            }
        }
        return database
    }

    private func profile(_ db: DatabaseQueue, order: [String]) throws -> DurationProfile? {
        try db.read { db in
            try SubstanceReadModel.resolveDurations(
                db: db, idListSQL: String(Self.substanceID), order: order,
            )
        }[SubstanceReadModel.RouteSaltKey(sid: Self.substanceID, route: "oral", salt: nil, isomer: nil)]
    }

    @Test
    func `A higher-priority point loses to a lower-priority range`() throws {
        let db = try database([
            ("drug.community", "comeup", 29.5, 29.5),
            ("psychonautwiki", "comeup", 20, 40),
        ])
        let comeup = try #require(try profile(db, order: ["drug.community", "psychonautwiki"])?.comeup)
        #expect(comeup == DurationRange(min: 20, max: 40))
        #expect(!comeup.isPoint)
    }

    @Test
    func `A point with no range anywhere wins and reads as approximate`() throws {
        let db = try database([("drug.community", "peak", 29.5, 29.5)])
        let peak = try #require(try profile(db, order: ["drug.community", "psychonautwiki"])?.peak)
        #expect(peak == DurationRange(min: 29.5, max: 29.5))
        #expect(peak.isPoint)
        #expect(peak.displayString == "≈30 minutes")
        #expect(peak.compactString == "≈30m")
    }

    @Test
    func `The user's order picks among ranges, then among points`() throws {
        let db = try database([
            ("psychonautwiki", "peak", 60, 120),
            ("tripsit", "peak", 90, 180),
            ("psychonautwiki", "offset", 45, 45),
            ("tripsit", "offset", 70, 70),
        ])
        let wikiFirst = try #require(try profile(db, order: ["psychonautwiki", "tripsit"]))
        #expect(wikiFirst.peak == DurationRange(min: 60, max: 120))
        #expect(wikiFirst.offset == DurationRange(min: 45, max: 45))

        let tripsitFirst = try #require(try profile(db, order: ["tripsit", "psychonautwiki"]))
        #expect(tripsitFirst.peak == DurationRange(min: 90, max: 180))
        #expect(tripsitFirst.offset == DurationRange(min: 70, max: 70))
    }

    @Test
    func `A disabled source's range does not displace an enabled point`() throws {
        let db = try database([
            ("drug.community", "comeup", 30, 30),
            ("tripsit", "comeup", 15, 45),
        ])
        let comeup = try #require(try profile(db, order: ["drug.community", "psychonautwiki"])?.comeup)
        #expect(comeup == DurationRange(min: 30, max: 30))
    }

    @Test
    func `Each phase resolves on its own`() throws {
        let db = try database([
            ("drug.community", "comeup", 29.5, 29.5),
            ("drug.community", "peak", 90, 90),
            ("tripsit", "peak", 60, 120),
            ("drug.community", "offset", 60, 90),
            ("psychonautwiki", "offset", 120, 180),
        ])
        let duration = try #require(try profile(db, order: ["drug.community", "psychonautwiki", "tripsit"]))
        #expect(duration.comeup == DurationRange(min: 29.5, max: 29.5))
        #expect(duration.peak == DurationRange(min: 60, max: 120))
        // Both offsets are ranges, so plain priority decides.
        #expect(duration.offset == DurationRange(min: 60, max: 90))
        // A point phase still draws the curve: it has a real length.
        #expect(duration.phaseBoundaries.comeupEnd == 29.5)
    }

    @Test
    func `A per-field demotion still orders the ranges`() throws {
        let db = try database(
            [
                ("drug.community", "peak", 60, 90),
                ("tripsit", "peak", 120, 240),
            ],
            fieldPriority: [("drug.community", 99)],
        )
        let peak = try #require(try profile(db, order: ["drug.community", "tripsit"])?.peak)
        #expect(peak == DurationRange(min: 120, max: 240))
    }

    @Test
    @MainActor
    func `The source list ranks the source whose range is shown first`() throws {
        let db = try database([
            ("drug.community", "comeup", 29.5, 29.5),
            ("psychonautwiki", "comeup", 20, 40),
        ])
        let reader = SubstanceReadModel(db: db, order: ["drug.community", "psychonautwiki"], language: .en)
        let sources = reader.sourcesProviding(.duration(.oral), substanceID: Self.substanceID)
        #expect(sources == ["psychonautwiki", "drug.community"])
    }
}
