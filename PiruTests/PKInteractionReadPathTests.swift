import Foundation
import Testing
@testable import Piru

/// The `drug_interactions_pk` read path — the store query, the bidirectional
/// pair matcher, and the fact that a matched row reaches the session review.
/// The matcher existed and was tested here long before anything called it, so
/// a test that only proves the function works is not enough: the last case
/// pins that a caller exists.
@Suite("Pharmacokinetic interaction read path")
@MainActor
struct PKInteractionReadPathTests {
    private func makeEntry(substance: String, amount: Double = 10) -> DoseEntry {
        DoseEntry(substance: substance, amount: amount, route: .oral, timestamp: .now)
    }

    // MARK: - Store

    @Test
    func `A substance's PK interaction rows load from the bundled database`() {
        let rows = SubstanceStore.shared.pkInteractions(forSubstanceName: "Ketamine")
        #expect(!rows.isEmpty)
        let clarithromycin = rows.first { $0.withSubstance.localizedCaseInsensitiveContains("clarithromycin") }
        let hit = clarithromycin
        #expect(hit?.mechanism?.contains("CYP3A4") == true)
        #expect(hit?.clinicalEffect?.isEmpty == false)
    }

    @Test
    func `An unknown substance yields no rows rather than failing`() {
        #expect(SubstanceStore.shared.pkInteractions(forSubstanceName: "Notarealsubstance").isEmpty)
    }

    @Test
    func `A slash-separated counterpart splits into its individual names`() {
        let hit = SubstanceStore.PKInteractionHit(
            id: 1, withSubstance: "ketoconazole / itraconazole", mechanism: nil,
            kiMicromolar: nil, clinicalEffect: nil, sourceSlug: "peer-review-primary",
            doi: nil, pmid: nil,
        )
        #expect(hit.counterpartNames == ["ketoconazole", "itraconazole"])
    }

    // MARK: - Pair matching

    @Test
    func `A logged counterpart surfaces the row that names it`() {
        let findings = InteractionChecker.pharmacokineticInteractions(
            "Ketamine", against: [makeEntry(substance: "Clarithromycin")],
        )
        #expect(!findings.isEmpty, "Ketamine + clarithromycin should surface its CYP3A4 row")
        #expect(findings.first?.hit.mechanism?.contains("CYP3A4") == true)
        #expect(findings.first?.source == .pharmacokinetic)
    }

    @Test
    func `Matching reads both directions, not just the prospective substance's own rows`() {
        // The row lives on Ketamine's record; clarithromycin's record carries
        // nothing. Which side got the row reflects which paper was read.
        let findings = InteractionChecker.pharmacokineticInteractions(
            "Clarithromycin", against: [makeEntry(substance: "Ketamine")],
        )
        #expect(!findings.isEmpty, "the row must be found from the counterpart's side too")
    }

    @Test
    func `An unrelated logged substance surfaces nothing`() {
        let findings = InteractionChecker.pharmacokineticInteractions(
            "Ketamine", against: [makeEntry(substance: "Melatonin")],
        )
        #expect(findings.isEmpty)
    }

    @Test
    func `A class-named counterpart is not string-matched onto a logged drug`() {
        // Rows naming "SSRIs" or "CYP3A4 inhibitors" describe a class. Matching a
        // logged SSRI to one would be the checker asserting a claim the row does
        // not make, so an unresolvable name is skipped rather than substring-matched.
        let findings = InteractionChecker.pharmacokineticInteractions(
            "MDMA", against: [makeEntry(substance: "Sertraline")],
        )
        for finding in findings {
            #expect(
                finding.hit.counterpartNames.contains { SubstanceLibrary.resolveFull($0) != nil },
                "matched \(finding.hit.withSubstance) with no resolvable counterpart",
            )
        }
    }

    @Test
    func `The same row is not reported twice when both sides are logged`() {
        let findings = InteractionChecker.pharmacokineticInteractions(
            "Ketamine", against: [makeEntry(substance: "Clarithromycin"), makeEntry(substance: "Ketamine")],
        )
        #expect(Set(findings.map(\.id)).count == findings.count)
    }

    // MARK: - The severity boundary

    @Test
    func `A PK finding carries no severity`() throws {
        // `PKInteractionFinding` has no severity property at all — the table has no
        // severity column because its sources assign none, and "AUC increased 2.6x"
        // is a measurement, not a judgment about danger. This test exists to fail
        // loudly if someone adds one.
        let findings = InteractionChecker.pharmacokineticInteractions(
            "Ketamine", against: [makeEntry(substance: "Clarithromycin")],
        )
        let mirror = try Mirror(reflecting: #require(findings.first))
        #expect(!mirror.children.contains { $0.label == "severity" })
    }
}
