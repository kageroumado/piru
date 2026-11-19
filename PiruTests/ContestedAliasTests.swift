import Foundation
import GRDB
import SwiftData
import Testing
@testable import Piru

/// An alias several substances list resolves to one of them, chosen by the
/// build, and a dose's title is never resolved back into a substance.
///
/// "K" is Ketamine's street name and, on dose.wiki, also Clonazepam's. The
/// active-session pill showed "Clonazepam" over a ketamine dose: the index kept
/// the alphabetically first claimant, and the pill re-resolved the dose's
/// already-resolved title through it.
@Suite("Contested aliases")
@MainActor
struct ContestedAliasTests {
    private let tint = P3Color(red: 0.917, green: 0.200, blue: 0.139)

    private func makeCustoms() throws -> (CustomSubstanceStore, ModelContainer) {
        let container = try ModelContainer(
            for: Schema(PiruSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none),
        )
        return (CustomSubstanceStore.forTesting(context: container.mainContext), container)
    }

    private func state(title: String, canonical: String) -> ActiveSubstanceState {
        ActiveSubstanceState(
            substanceName: title, canonicalName: canonical, tint: tint, doseTimestamp: .now,
            amount: 50, unit: "mg", route: "Insufflated", onsetEndMinutes: 5, comeupEndMinutes: 15,
            peakEndMinutes: 45, offsetEndMinutes: 90, afterglowEndMinutes: nil, totalMinutes: 120,
        )
    }

    // MARK: - Data path

    @Test
    func `K resolves to Ketamine on both name indexes`() async {
        await SubstanceStore.shared.ensureAllLoaded()
        #expect(SubstanceLibrary.lookup("K")?.name == "Ketamine")
        #expect(SubstanceStore.shared.lookupByNameOrAlias("K")?.name == "Ketamine")
        // The claim stays on Clonazepam's row for its header and for search.
        #expect(SubstanceLibrary.lookup("Clonazepam")?.aliases.contains("K") == true)
    }

    @Test
    func `A dose logged as K draws a Ketamine curve`() async {
        await SubstanceStore.shared.ensureAllLoaded()
        let entry = DoseEntry(substance: "K", amount: 50, unit: "mg", route: .insufflation)
        let state = ActiveSubstanceState.from(entry: entry, tint: tint)
        #expect(state?.canonicalName == "Ketamine")
    }

    @Test
    func `Every contested alias resolves to the owner the build chose`() async throws {
        await SubstanceStore.shared.ensureAllLoaded()
        let store = SubstanceStore.shared
        let owners = try await store.substancesDB.read { db in
            try Row.fetchAll(db, sql: """
                SELECT a.alias_normalized AS key, s.canonical_name AS owner
                  FROM aliases a JOIN substances s ON s.id = a.substance_id
                 WHERE a.owns_key = 1 AND a.alias_normalized IN (
                       SELECT alias_normalized FROM aliases
                        GROUP BY alias_normalized HAVING COUNT(DISTINCT substance_id) > 1)
                 GROUP BY a.alias_normalized
            """).map { ($0["key"] as String, $0["owner"] as String) }
        }
        #expect(owners.count > 50, "expected the build to mark dozens of contested keys, found \(owners.count)")
        for (key, owner) in owners where store.nameIndex[key] == nil {
            let ownerID = store.nameIndex[owner.lowercased()]
            #expect(store.substanceID(forNameOrAlias: key) == ownerID, "\(key) → \(owner) on the alias index")
            #expect(store.timelineRow(key)?.name == owner, "\(key) → \(owner) on the batch index")
        }
    }

    // MARK: - Display path

    @Test
    func `A relabel to K labels the Ketamine pill K`() throws {
        let (customs, _) = try makeCustoms()
        customs.add(CustomSubstanceEntry(name: "Ketamine", displayName: "K"))
        #expect(state(title: "K", canonical: "Ketamine").displayLabel(customs: customs) == "K")
    }

    @Test
    func `A title naming another substance never re-resolves to it`() throws {
        // Clonazepam relabeled "K": the title is now Ketamine's alias, so
        // resolving it would rename the pill to Ketamine.
        let (customs, _) = try makeCustoms()
        customs.add(CustomSubstanceEntry(name: "Clonazepam", displayName: "K"))
        #expect(state(title: "K", canonical: "Clonazepam").displayLabel(customs: customs) == "K")
        // A title that is another substance's canonical name, with no relabel.
        #expect(state(title: "Ketamine", canonical: "Esketamine").displayLabel(customs: customs) == "Ketamine")
    }

    @Test
    func `A Live Activity payload from an older build keeps its title as the name`() throws {
        let json = #"""
        {"substanceName":"K","tint":[1,0,0],"doseTimestamp":0,
         "amount":50,"unit":"mg","route":"Insufflated","onsetEndMinutes":5,"comeupEndMinutes":15,
         "peakEndMinutes":45,"offsetEndMinutes":90,"totalMinutes":120}
        """#
        let decoded = try JSONDecoder().decode(ActiveSubstanceState.self, from: Data(json.utf8))
        #expect(decoded.canonicalName == "K")
        let roundTrip = try JSONDecoder().decode(
            ActiveSubstanceState.self,
            from: JSONEncoder().encode(state(title: "K", canonical: "Ketamine")),
        )
        #expect(roundTrip.canonicalName == "Ketamine")
        #expect(roundTrip.substanceName == "K")
    }
}
