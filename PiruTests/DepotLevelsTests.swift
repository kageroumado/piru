import Foundation
import Testing
@testable import Piru

/// Which doses earn the Injection Levels chart outside the tool: a depot ester
/// dose of a hormone the bundled DB draws curves for, and nothing else.
@Suite("DepotLevels")
struct DepotLevelsTests {
    private func entry(_ substance: String, route: RouteOfAdministration, saltForm: String? = nil, releaseForm: String? = nil) -> DoseEntry {
        DoseEntry(substance: substance, amount: 5, unit: "mg", route: route, saltForm: saltForm, releaseForm: releaseForm)
    }

    @Test
    func `An injected estradiol ester shows the estradiol curve`() async {
        await SubstanceStore.shared.ensureAllLoaded()
        #expect(DepotLevels.analyte(for: entry("Estradiol", route: .intramuscular, saltForm: "Valerate")) == .estradiol)
        #expect(DepotLevels.analyte(for: entry("Estradiol", route: .subcutaneous, saltForm: "Cypionate")) == .estradiol)
    }

    @Test
    func `The same ester swallowed, or the free hormone injected, is not a depot`() async {
        await SubstanceStore.shared.ensureAllLoaded()
        #expect(DepotLevels.analyte(for: entry("Estradiol", route: .oral, saltForm: "Valerate")) == nil)
        #expect(DepotLevels.analyte(for: entry("Estradiol", route: .sublingual)) == nil)
        #expect(DepotLevels.analyte(for: entry("Estradiol", route: .intramuscular)) == nil)
    }

    @Test
    func `A depot formulation without an ester curve has no analyte`() async {
        await SubstanceStore.shared.ensureAllLoaded()
        let depot = entry("Paliperidone", route: .intramuscular, releaseForm: "DEP")
        #expect(PKResolver.isDepot(entry: depot))
        #expect(DepotLevels.analyte(for: depot) == nil)
    }

    @Test
    func `The library asks by substance family`() async {
        await SubstanceStore.shared.ensureAllLoaded()
        let store = SubstanceStore.shared
        #expect(DepotLevels.analyte(forSubstanceUID: store.substanceUID(forNameOrAlias: "Estradiol")) == .estradiol)
        #expect(DepotLevels.analyte(forSubstanceUID: store.substanceUID(forNameOrAlias: "Memantine")) == nil)
        #expect(DepotLevels.analyte(forSubstanceUID: nil) == nil)
    }
}
