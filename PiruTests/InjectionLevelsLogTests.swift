import Foundation
import SwiftData
import Testing
@testable import Piru

/// What the Injection Levels tool reads out of the dose log: mg doses join as is,
/// mL doses join once a vial concentration is known, and the ester named in a
/// legacy substance string still picks the default ester.
@Suite("InjectionLevelsLog")
struct InjectionLevelsLogTests {
    private func entry(_ substance: String, amount: Double, unit: String, route: RouteOfAdministration, daysAgo: Double) -> DoseEntry {
        DoseEntry(substance: substance, amount: amount, unit: unit, route: route, timestamp: Date.now.addingTimeInterval(-daysAgo * 86_400))
    }

    @Test
    func `mL-logged injections wait for a concentration, then convert at it`() async {
        await SubstanceStore.shared.ensureAllLoaded()
        let entries = [
            entry("Estradiol Enanthate", amount: 0.1, unit: "ml", route: .subcutaneous, daysAgo: 14),
            entry("Estradiol Enanthate", amount: 0.1, unit: "ml", route: .subcutaneous, daysAgo: 7),
            entry("Estradiol Valerate", amount: 1, unit: "mg", route: .sublingual, daysAgo: 3),
        ]
        let unset = InjectionLevelsView.injections(from: entries, analyte: .estradiol)
        #expect(unset.injections.isEmpty)
        #expect(unset.volumeLoggedCount == 2)

        let converted = InjectionLevelsView.injections(from: entries, analyte: .estradiol, volumeConcentrationMgPerML: 40)
        #expect(converted.injections.count == 2)
        #expect(converted.volumeLoggedCount == 2)
        #expect(converted.injections.allSatisfy { abs($0.doseMg - 4) < 0.0001 })
    }

    @Test
    func `A mg dose joins without any concentration`() async {
        await SubstanceStore.shared.ensureAllLoaded()
        let log = InjectionLevelsView.injections(
            from: [entry("Estradiol Valerate", amount: 4, unit: "mg", route: .intramuscular, daysAgo: 5)],
            analyte: .estradiol,
        )
        #expect(log.injections.count == 1)
        #expect(log.injections[0].doseMg == 4)
        #expect(log.volumeLoggedCount == 0)
    }

    @Test
    func `The ester named in a legacy substance string picks the default ester`() async {
        await SubstanceStore.shared.ensureAllLoaded()
        let entries = [
            entry("Estradiol Enanthate", amount: 0.1, unit: "ml", route: .subcutaneous, daysAgo: 14),
            entry("Estradiol Enanthate", amount: 0.1, unit: "ml", route: .subcutaneous, daysAgo: 7),
        ]
        #expect(InjectionLevelsView.dominantEsterID(from: entries, analyte: .estradiol) == "estradiol_enanthate")
    }
}
