import Foundation
import SwiftData
import Testing
@testable import Piru

/// The per-ester grouping the Hormone Levels insight reads out of the dose log
/// (Specs/injection-levels-v3.md §4): each dose is bucketed by its own ester so a
/// switch or a mix sums honestly, catalog-only esters become markers not curves, and
/// a dose that names no ester falls back to the analyte default.
@Suite("HormoneLevelsLog")
struct HormoneLevelsLogTests {
    private func entry(_ substance: String, amount: Double, unit: String, route: RouteOfAdministration, daysAgo: Double) -> DoseEntry {
        DoseEntry(substance: substance, amount: amount, unit: unit, route: route, timestamp: Date.now.addingTimeInterval(-daysAgo * 86_400))
    }

    @Test
    func `A valerate to cypionate switch groups into two esters`() async {
        await SubstanceStore.shared.ensureAllLoaded()
        let entries = [
            entry("Estradiol Valerate", amount: 4, unit: "mg", route: .intramuscular, daysAgo: 28),
            entry("Estradiol Valerate", amount: 4, unit: "mg", route: .intramuscular, daysAgo: 21),
            entry("Estradiol Cypionate", amount: 3, unit: "mg", route: .intramuscular, daysAgo: 14),
            entry("Estradiol Cypionate", amount: 3, unit: "mg", route: .intramuscular, daysAgo: 7),
        ]
        let grouped = HormoneLevelsLog.grouped(from: entries, analyte: .estradiol, volumeConcentrationMgPerML: nil)
        #expect(grouped.esterGroups.count == 2)
        let ids = grouped.esterGroups.map(\.ester.esterID)
        #expect(ids.contains("estradiol_valerate"))
        #expect(ids.contains("estradiol_cypionate"))
        #expect(grouped.esterGroups.allSatisfy { $0.injections.count == 2 })
        #expect(grouped.allInjections.count == 4)
        #expect(grouped.hasModelableInjections)
    }

    @Test
    func `A dose that names no ester falls back to the logged-dominant ester`() async {
        await SubstanceStore.shared.ensureAllLoaded()
        let entries = [
            entry("Estradiol Valerate", amount: 4, unit: "mg", route: .intramuscular, daysAgo: 14),
            entry("Estradiol", amount: 4, unit: "mg", route: .intramuscular, daysAgo: 7),
        ]
        let grouped = HormoneLevelsLog.grouped(from: entries, analyte: .estradiol, volumeConcentrationMgPerML: nil)
        // Both doses land in one ester bucket: the named valerate, plus the bare dose
        // routed to the analyte default (valerate is the only ester the log names).
        #expect(grouped.esterGroups.count == 1)
        #expect(grouped.esterGroups.first?.ester.esterID == "estradiol_valerate")
        #expect(grouped.esterGroups.first?.injections.count == 2)
    }

    @Test
    func `A catalog-only ester becomes a marker, never a curve`() async {
        await SubstanceStore.shared.ensureAllLoaded()
        let entries = [
            entry("Estradiol Undecylate", amount: 10, unit: "mg", route: .intramuscular, daysAgo: 20),
        ]
        let grouped = HormoneLevelsLog.grouped(from: entries, analyte: .estradiol, volumeConcentrationMgPerML: nil)
        #expect(grouped.esterGroups.isEmpty)
        #expect(grouped.catalogOnlyMarkers.count == 1)
        #expect(grouped.catalogOnlyMarkers.first?.ester.esterID == "estradiol_undecylate")
        #expect(!grouped.hasModelableInjections)
    }

    @Test
    func `mL doses are counted until a vial strength converts them`() async {
        await SubstanceStore.shared.ensureAllLoaded()
        let entries = [
            entry("Estradiol Enanthate", amount: 0.1, unit: "ml", route: .subcutaneous, daysAgo: 14),
            entry("Estradiol Enanthate", amount: 0.1, unit: "ml", route: .subcutaneous, daysAgo: 7),
        ]
        let unset = HormoneLevelsLog.grouped(from: entries, analyte: .estradiol, volumeConcentrationMgPerML: nil)
        #expect(unset.esterGroups.isEmpty)
        #expect(unset.volumeLoggedCount == 2)

        let converted = HormoneLevelsLog.grouped(from: entries, analyte: .estradiol, volumeConcentrationMgPerML: 40)
        #expect(converted.esterGroups.count == 1)
        #expect(converted.esterGroups.first?.injections.count == 2)
        #expect(converted.esterGroups.first?.injections.allSatisfy { abs($0.doseMg - 4) < 0.0001 } == true)
    }
}
