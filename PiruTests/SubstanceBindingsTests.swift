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

    @Test
    func `Binding-target normalization strips assay parentheticals and receptor suffix`() {
        // The graded flagship layer uses bare target names ("DAT"); the enrichment
        // layer appends the assay in parens ("DAT (release, [3H]-DA …)"). Both must
        // collapse to one summary row so a substance doesn't show duplicate DAT/NET/SERT.
        let cases: [(String, String)] = [
            ("DAT", "dat"),
            ("DAT (release, [3H]-DA from rat synaptosomes)", "dat"),
            ("α2δ-1", "α2δ-1"),
            ("α2δ-1 (porcine cerebral cortex)", "α2δ-1"),
            ("NMDA", "nmda"),
            ("NMDA receptor (PCP site)", "nmda"),
            ("5-HT3 receptor", "5-ht3"),
        ]
        for (input, expected) in cases {
            #expect(
                SubstanceStore.normalizedBindingTarget(input) == expected,
                "normalizedBindingTarget(\(input)) → \(SubstanceStore.normalizedBindingTarget(input)), expected \(expected)",
            )
        }
        // The two DAT spellings must normalize identically (the collapse guarantee).
        #expect(
            SubstanceStore.normalizedBindingTarget("DAT")
                == SubstanceStore.normalizedBindingTarget("DAT (release, [3H]-DA from rat synaptosomes)"),
        )
    }
}
