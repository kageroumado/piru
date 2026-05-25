import Testing
import Foundation
@testable import Piru

@Suite("SubstanceStore bindings")
struct SubstanceBindingsTests {

    @Test("Empty for unknown substance")
    @MainActor
    func unknownEmpty() {
        #expect(SubstanceStore.shared.bindings(forSubstanceName: "zzzNotARealCompound").isEmpty)
    }

    @Test("Returns rows for a substance with literature data")
    @MainActor
    func knownReturnsRows() {
        // Ketamine has rich receptor-binding literature in the bundled DB.
        let rows = SubstanceStore.shared.bindings(forSubstanceName: "Ketamine")
        #expect(!rows.isEmpty, "Expected Ketamine to have binding rows in the bundled DB")
    }

    @Test("Rows are sorted by Ki ascending, NULLs last")
    @MainActor
    func sortedByKi() {
        let rows = SubstanceStore.shared.bindings(forSubstanceName: "Ketamine")
        let kis = rows.compactMap(\.kiNm)
        #expect(kis == kis.sorted(),
                "bindings should be sorted by Ki ASC — got \(kis)")
        // Once we hit a row whose Ki is nil, every subsequent row's Ki
        // should also be nil (NULLS LAST in the SQL).
        if let firstNilIndex = rows.firstIndex(where: { $0.kiNm == nil }) {
            for row in rows[firstNilIndex...] {
                #expect(row.kiNm == nil, "Rows after the first nil-Ki must also have nil Ki")
            }
        }
    }

    @Test("Bindings query by target filters correctly")
    @MainActor
    func filterByTarget() {
        // Pick a target known to exist in the bundled data, query for it,
        // assert every row matches.
        let allTargets = SubstanceStore.shared.availableBindingTargets()
        guard let probe = allTargets.first else {
            Issue.record("No targets in bundled DB")
            return
        }
        let rows = SubstanceStore.shared.bindings(target: probe.target)
        #expect(!rows.isEmpty)
        for row in rows {
            #expect(row.target == probe.target)
        }
    }

    @Test("Substance-contains filter is case-insensitive substring match")
    @MainActor
    func substanceContainsFilter() {
        let rows = SubstanceStore.shared.bindings(substanceContains: "keta")
        // Expect Ketamine + any compound whose canonical name contains "keta".
        let hasKetamine = rows.contains { $0.substanceName.lowercased().contains("keta") }
        #expect(hasKetamine, "Expected substanceContains:'keta' to surface Ketamine et al.")
    }
}
