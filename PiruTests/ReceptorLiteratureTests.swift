import Foundation
import Testing
@testable import Piru

/// Pins the Receptor Literature relevance rules and the CYP2D6 classification
/// to the outputs the substance page shows.
@Suite("ReceptorLiterature")
@MainActor
struct ReceptorLiteratureTests {
    private func bind(
        _ target: String,
        _ action: String = "agonist",
        ki: Double? = nil,
        ec50: Double? = nil,
        ic50: Double? = nil,
        species: String? = "human",
        id: Int64 = 0,
    ) -> BindingHit {
        BindingHit(
            id: id,
            substanceName: "x",
            target: target,
            targetBase: nil,
            action: action,
            kiNm: ki,
            ec50Nm: ec50,
            ic50Nm: ic50,
            species: species,
            sourceSlug: "peer-review-primary",
            doi: nil,
            pmid: nil,
        )
    }

    private func metabolism(
        _ enzyme: String,
        active: Bool? = true,
        potencyPct: Double? = nil,
        mechanism: SubstanceStore.MetaboliteMechanism = .unknown,
    ) -> SubstanceStore.MetabolismHit {
        SubstanceStore.MetabolismHit(
            id: 0, enzyme: enzyme, fractionOfClearancePct: nil,
            metaboliteName: "m", metaboliteSubstanceName: nil,
            metaboliteActive: active, metabolitePotencyVsParentPct: potencyPct,
            metabolitePotencyBasis: nil, metabolitePotencyTarget: nil,
            metaboliteMechanismVsParent: mechanism,
            metaboliteHalfLifeMinutes: nil, formationFractionPct: nil,
            route: nil, conditionalCombinationID: nil,
            sourceSlug: "test", doi: nil, pmid: nil,
        )
    }

    // MARK: - The 10 µM cap

    @Test
    func `A Ki at or past 10 µM drops when a tighter binding exists`() {
        let rows = [bind("NMDA", ki: 500), bind("σ1", ki: 10_000), bind("MOR", ki: 25_000)]
        #expect(ReceptorLiterature.visibleBindings(from: rows).map(\.target) == ["NMDA"])
    }

    @Test
    func `A weak Ki within 10× of the tightest binding is kept`() {
        let rows = [bind("A1", ki: 12_000), bind("A2A", ki: 24_000), bind("A3", ki: 200_000)]
        #expect(ReceptorLiterature.visibleBindings(from: rows).map(\.target) == ["A1", "A2A"])
    }

    @Test
    func `A functional EC50 is never capped`() {
        let rows = [bind("SERT", "releasingAgent", ki: 100), bind("DAT", "releasingAgent", ec50: 22_000)]
        #expect(ReceptorLiterature.visibleBindings(from: rows).map(\.target) == ["SERT", "DAT"])
    }

    @Test
    func `A row with no measured value is dropped`() {
        let rows = [bind("5-HT2A", ki: 50), bind("D2")]
        #expect(ReceptorLiterature.visibleBindings(from: rows).map(\.target) == ["5-HT2A"])
    }

    @Test
    func `Rows sort by strength tier, then by potency within a tier`() {
        let rows = [
            bind("weak", ki: 2_000),
            bind("moderate", ki: 400),
            bind("strongLoose", ki: 90),
            bind("strongTight", ki: 5),
            bind("functionalStrong", ec50: 800),
        ]
        #expect(ReceptorLiterature.visibleBindings(from: rows).map(\.target)
            == ["strongTight", "strongLoose", "functionalStrong", "moderate", "weak"])
    }

    // MARK: - Dedup

    @Test
    func `Human rows displace non-human rows for the same target and action`() {
        let rows = [
            bind("5-HT2A", ki: 100, species: "rat", id: 1),
            bind("5-HT2A", ki: 200, species: "human", id: 2),
            bind("DAT", ki: 300, species: "rat", id: 3),
        ]
        #expect(ReceptorLiterature.deduped(rows).map(\.id) == [2, 3])
    }

    @Test
    func `Repeated measurements of one value collapse to the first`() {
        let rows = [
            bind("5-HT2A", ki: 7_800, id: 1),
            bind("5-HT2A", ki: 7_800, id: 2),
            bind("5-HT2A", ec50: 7_800, id: 3),
        ]
        #expect(ReceptorLiterature.deduped(rows).map(\.id) == [1, 3])
    }

    // MARK: - CYP2D6

    @Test
    func `No leading CYP2D6 pathway gives no note`() {
        #expect(CYP2D6Info.from(metabolismRows: [metabolism("CYP3A4 / CYP2D6")]) == nil)
        #expect(CYP2D6Info.from(metabolismRows: []) == nil)
    }

    @Test
    func `A divergent active metabolite is a prodrug pattern`() {
        let info = CYP2D6Info.from(metabolismRows: [metabolism("CYP2D6", mechanism: .divergent)])
        #expect(info == CYP2D6Info(hasProdrugPattern: true))
    }

    @Test
    func `A metabolite at 500 % of the parent is a prodrug pattern, below it is not`() {
        #expect(CYP2D6Info.from(metabolismRows: [metabolism("CYP2D6 (major)", potencyPct: 500)])?.hasProdrugPattern == true)
        #expect(CYP2D6Info.from(metabolismRows: [metabolism("CYP2D6 (major)", potencyPct: 499)])?.hasProdrugPattern == false)
    }

    @Test
    func `An inactive metabolite only clears the parent`() {
        let info = CYP2D6Info.from(metabolismRows: [metabolism(" CYP2D6", active: false, potencyPct: 20_000)])
        #expect(info == CYP2D6Info(hasProdrugPattern: false))
    }
}
