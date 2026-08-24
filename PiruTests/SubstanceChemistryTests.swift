import Foundation
import Testing
@testable import Piru

/// Stage 4 — physicochemical decode + pharmacokinetics/metabolism surfacing.
@Suite("Substance chemistry & pharmacokinetics")
struct SubstanceChemistryTests {
    // MARK: - Physicochemical decode

    @Test
    @MainActor
    func `Caffeine decodes its physicochemical descriptors`() {
        guard let caffeine = SubstanceStore.shared.lookup("Caffeine") else {
            Issue.record("Caffeine missing from bundled DB")
            return
        }
        #expect(caffeine.smiles != nil, "Expected a SMILES string")
        #expect(caffeine.iupacName != nil, "Expected an IUPAC name")
        guard let phys = caffeine.physicochemical else {
            Issue.record("Expected Caffeine to carry physicochemical data")
            return
        }
        #expect(phys.logP != nil)
        #expect(phys.tpsa != nil)
        #expect(phys.hba != nil)
        // Caffeine carries a rodent oral LD50 in the bundled data.
        #expect(phys.ld50OralMgPerKg != nil)
        #expect(phys.hasLD50)
        #expect(phys.hasAnyValue)
    }

    @Test
    @MainActor
    func `Physicochemical is nil when no column is populated`() {
        // Aspirin carries no physicochemical columns in the bundled DB, so the
        // resolver collapses the all-nil struct to nil (the card stays hidden).
        guard let aspirin = SubstanceStore.shared.lookup("Aspirin") else {
            Issue.record("Aspirin missing from bundled DB")
            return
        }
        #expect(aspirin.physicochemical == nil)
    }

    @Test
    func `hasAnyValue and hasLD50 reflect populated fields`() {
        let empty = Physicochemical(
            logP: nil, tpsa: nil, hba: nil, hbd: nil,
            ld50OralMgPerKg: nil, ld50DermalMgPerKg: nil, meltingPointC: nil, boilingPointC: nil,
        )
        #expect(!empty.hasAnyValue)
        #expect(!empty.hasLD50)

        let logpOnly = Physicochemical(
            logP: 2.2, tpsa: nil, hba: nil, hbd: nil,
            ld50OralMgPerKg: nil, ld50DermalMgPerKg: nil, meltingPointC: nil, boilingPointC: nil,
        )
        #expect(logpOnly.hasAnyValue)
        #expect(!logpOnly.hasLD50, "logP alone must not trigger the LD50 footnote")

        let ld50Only = Physicochemical(
            logP: nil, tpsa: nil, hba: nil, hbd: nil,
            ld50OralMgPerKg: 367.7, ld50DermalMgPerKg: nil, meltingPointC: nil, boilingPointC: nil,
        )
        #expect(ld50Only.hasAnyValue)
        #expect(ld50Only.hasLD50)
    }

    // MARK: - Pharmacokinetics

    @Test
    @MainActor
    func `Pharmacokinetics empty for unknown substance`() {
        #expect(SubstanceStore.shared.pharmacokinetics(forSubstanceName: "zzzNotARealCompound").isEmpty)
        #expect(SubstanceStore.shared.metabolism(forSubstanceName: "zzzNotARealCompound").isEmpty)
    }

    @Test
    @MainActor
    func `Ketamine returns per-route PK with attribution`() {
        let routes = SubstanceStore.shared.pharmacokinetics(forSubstanceName: "Ketamine")
        #expect(!routes.isEmpty, "Expected Ketamine to have pk_routes in the bundled DB")
        // Every row is sourced (the JOIN to sources is mandatory).
        #expect(routes.allSatisfy { !$0.sourceSlug.isEmpty })
        // At least one row carries a usable numeric metric.
        #expect(routes.contains { $0.bioavailabilityPct != nil || $0.tmaxMin != nil || $0.halfLifeMin != nil })
    }

    @Test
    @MainActor
    func `Ketamine returns CYP metabolism with an active metabolite`() {
        let rows = SubstanceStore.shared.metabolism(forSubstanceName: "Ketamine")
        #expect(!rows.isEmpty, "Expected Ketamine to have metabolism rows in the bundled DB")
        #expect(rows.allSatisfy { !$0.enzyme.isEmpty })
        // Norketamine is an active metabolite — the active flag must decode.
        #expect(rows.contains { $0.metaboliteActive == true })
    }

    @Test
    @MainActor
    func `Metabolism rows ordered by fraction of clearance, NULLs last`() {
        let fracs = SubstanceStore.shared.metabolism(forSubstanceName: "Ketamine").compactMap(\.fractionOfClearancePct)
        #expect(fracs == fracs.sorted(by: >), "Metabolism should be sorted by fraction DESC — got \(fracs)")
    }
}
