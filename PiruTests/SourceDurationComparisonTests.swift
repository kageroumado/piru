import Foundation
import GRDB
import Testing
@testable import Piru

/// The source comparison sheet's duration rows, read against the bundled
/// database: one profile per source, holding exactly the phases that source
/// states for the route.
@Suite("Source duration comparison")
@MainActor
struct SourceDurationComparisonTests {
    private let store = SubstanceStore.shared

    @Test
    func `Every source with MDMA oral durations gets one profile`() throws {
        let profiles = store.durationProfiles(forSubstanceName: "MDMA", route: .oral)
        let slugs = profiles.map(\.sourceSlug)
        #expect(Set(slugs).count == slugs.count)
        #expect(try Set(slugs) == rawSourceSlugs(substance: "MDMA", route: "oral"))
        #expect(slugs.contains("tripsit"))
        #expect(slugs.contains("dosewiki"))
    }

    @Test
    func `A source keeps only the phases it states`() throws {
        let profiles = store.durationProfiles(forSubstanceName: "MDMA", route: .oral)
        let tripsit = try #require(profiles.first { $0.sourceSlug == "tripsit" })
        #expect(tripsit.duration.onset == DurationRange(min: 20, max: 70))
        #expect(tripsit.duration.total == DurationRange(min: 180, max: 300))
        #expect(tripsit.duration.peak == nil)
        #expect(tripsit.duration.comeup == nil)

        let totalOnly = try #require(profiles.first { $0.sourceSlug == "erowid-pihkal" })
        #expect(totalOnly.duration.total == DurationRange(min: 240, max: 360))
        #expect(totalOnly.duration.onset == nil)
        #expect(totalOnly.duration.peak == nil)
    }

    @Test
    func `The source the card attributes leads and is the only one in use`() {
        let profiles = store.durationProfiles(forSubstanceName: "MDMA", route: .oral)
        let attributed = store.provenance(forSubstanceName: "MDMA")?.routesBySource[.oral]?.durationSource
        #expect(profiles.filter(\.isActive).count == (attributed == nil ? 0 : 1))
        if let attributed {
            #expect(profiles.first?.sourceSlug == attributed)
            #expect(profiles.first?.isActive == true)
        }
    }

    @Test
    func `An unknown substance has no profiles`() {
        #expect(store.durationProfiles(forSubstanceName: "Not A Substance", route: .oral).isEmpty)
        #expect(store.comparisonSourceCount(forSubstanceName: "Not A Substance", route: .oral) == 0)
    }

    @Test
    func `The compare link counts every source with a ladder or durations`() {
        let ladders = Set(store.doseLadders(forSubstanceName: "MDMA", route: .oral).map(\.sourceSlug))
        let durations = Set(store.durationProfiles(forSubstanceName: "MDMA", route: .oral).map(\.sourceSlug))
        let count = store.comparisonSourceCount(forSubstanceName: "MDMA", route: .oral)
        #expect(count == ladders.union(durations).count)
        #expect(count >= max(ladders.count, durations.count))
    }

    /// The sources with a base-form (no salt, no isomer) duration row, straight
    /// from the table.
    private func rawSourceSlugs(substance: String, route: String) throws -> Set<String> {
        try store.substancesDB.read { db in
            try Set(String.fetchAll(db, sql: """
                SELECT DISTINCT src.slug
                  FROM durations du
                  JOIN sources src ON src.id = du.source_id
                  JOIN substances s ON s.id = du.substance_id
                 WHERE s.canonical_name = ? AND du.route = ?
                   AND du.salt_form IS NULL AND du.isomer IS NULL
            """, arguments: [substance, route]))
        }
    }
}
