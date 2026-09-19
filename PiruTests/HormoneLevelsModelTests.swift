import Foundation
import Testing
@testable import Piru

/// The retrospective multi-ester model behind the Hormone Levels insight: it groups
/// the log per ester, sums each ester's own depot curve into the serum total, keeps
/// the per-ester contributions, and calibrates the sum to labs
/// (Specs/injection-levels-v3.md §3–§4).
@MainActor
@Suite("HormoneLevelsModel")
struct HormoneLevelsModelTests {
    private func entry(_ substance: String, mg: Double, daysAgo: Double) -> DoseEntry {
        DoseEntry(substance: substance, amount: mg, unit: "mg", route: .intramuscular, timestamp: Date.now.addingTimeInterval(-daysAgo * 86_400))
    }

    @Test
    func `A two-ester log produces a summed serum curve and two per-ester series`() async {
        await SubstanceStore.shared.ensureAllLoaded()
        let entries = [
            entry("Estradiol Valerate", mg: 4, daysAgo: 35),
            entry("Estradiol Valerate", mg: 4, daysAgo: 28),
            entry("Estradiol Cypionate", mg: 4, daysAgo: 14),
            entry("Estradiol Cypionate", mg: 4, daysAgo: 7),
        ]
        let grouped = HormoneLevelsLog.grouped(from: entries, analyte: .estradiol, volumeConcentrationMgPerML: nil)
        let model = HormoneLevelsModel()
        model.analyte = .estradiol
        model.autoCalibrateFromLabs = false
        model.sync(grouped: grouped, measurements: [])
        model.refresh()

        #expect(model.result != nil)
        #expect(model.perEster.count == 2)
        // The serum total at any sample equals the sum of the per-ester contributions.
        if let total = model.result?.points, let a = model.perEster.first?.points, let b = model.perEster.last?.points {
            let i = total.count / 2
            #expect(abs(total[i].level - (a[i].level + b[i].level)) < 1e-6)
        }
    }

    @Test
    func `A subcutaneous testosterone cypionate log produces a serum curve`() async {
        await SubstanceStore.shared.ensureAllLoaded()
        #expect(SubstanceStore.shared.analytesWithEsterData().contains("testosterone"))
        let entries = (0 ..< 8).map { i in
            DoseEntry(
                substance: "Testosterone", amount: 100, unit: "mg", route: .subcutaneous,
                saltForm: "Cypionate", timestamp: Date.now.addingTimeInterval(-Double(i) * 7 * 86_400),
            )
        }
        let grouped = HormoneLevelsLog.grouped(from: entries, analyte: .testosterone, volumeConcentrationMgPerML: nil)
        #expect(grouped.hasModelableInjections)
        #expect(grouped.esterGroups.first?.ester.esterID == "testosterone_cypionate")

        let model = HormoneLevelsModel()
        model.analyte = .testosterone
        model.autoCalibrateFromLabs = false
        model.sync(grouped: grouped, measurements: [])
        model.refresh()
        #expect(model.result != nil)
        #expect((model.result?.peak ?? 0) > 0)
    }

    @Test
    func `A catalog-only ester log draws no curve but records a marker`() async {
        await SubstanceStore.shared.ensureAllLoaded()
        let grouped = HormoneLevelsLog.grouped(
            from: [entry("Estradiol Undecylate", mg: 10, daysAgo: 20)],
            analyte: .estradiol, volumeConcentrationMgPerML: nil,
        )
        let model = HormoneLevelsModel()
        model.autoCalibrateFromLabs = false
        model.sync(grouped: grouped, measurements: [])
        model.refresh()
        #expect(model.result == nil)
        #expect(model.perEster.isEmpty)
        #expect(model.catalogMarkers.count == 1)
    }

    @Test
    func `Testosterone ships a reference region and a clinical goal; estradiol ships neither`() {
        #expect(Analyte.testosterone.referenceRegion == 300 ... 1000)
        #expect(Analyte.testosterone.labeledGoal == 400 ... 700)
        #expect(Analyte.estradiol.referenceRegion == nil)
        #expect(Analyte.estradiol.labeledGoal == nil)
    }

    @Test
    func `Companion axes: estradiol shows T-suppression, testosterone shows E2 + blood counts`() {
        #expect(CompanionMeasurement.companions(for: .estradiol) == [.testosterone])
        #expect(CompanionMeasurement.companions(for: .testosterone) == [.estradiol, .hematocrit, .hemoglobin])
    }
}
