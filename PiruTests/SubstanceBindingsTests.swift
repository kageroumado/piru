import Foundation
import Testing
@testable import Piru

@Suite("SubstanceStore bindings")
struct SubstanceBindingsTests {
    @Test
    @MainActor
    func `Empty for unknown substance`() {
        #expect(SubstanceStore.shared.bindings(forSubstanceName: "zzzNotARealCompound").isEmpty)
    }

    @Test
    @MainActor
    func `Returns rows for a substance with literature data`() {
        // Ketamine has rich receptor-binding literature in the bundled DB.
        let rows = SubstanceStore.shared.bindings(forSubstanceName: "Ketamine")
        #expect(!rows.isEmpty, "Expected Ketamine to have binding rows in the bundled DB")
    }

    @Test
    @MainActor
    func `Rows are sorted by Ki ascending, NULLs last`() {
        let rows = SubstanceStore.shared.bindings(forSubstanceName: "Ketamine")
        let kis = rows.compactMap(\.kiNm)
        #expect(
            kis == kis.sorted(),
            "bindings should be sorted by Ki ASC — got \(kis)",
        )
        // Once we hit a row whose Ki is nil, every subsequent row's Ki
        // should also be nil (NULLS LAST in the SQL).
        if let firstNilIndex = rows.firstIndex(where: { $0.kiNm == nil }) {
            for row in rows[firstNilIndex...] {
                #expect(row.kiNm == nil, "Rows after the first nil-Ki must also have nil Ki")
            }
        }
    }

    @Test
    @MainActor
    func `Bindings query by target filters correctly`() {
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

    @Test
    @MainActor
    func `Substance-contains filter is case-insensitive substring match`() {
        let rows = SubstanceStore.shared.bindings(substanceContains: "keta")
        // Expect Ketamine + any compound whose canonical name contains "keta".
        let hasKetamine = rows.contains { $0.substanceName.lowercased().contains("keta") }
        #expect(hasKetamine, "Expected substanceContains:'keta' to surface Ketamine et al.")
    }
}
