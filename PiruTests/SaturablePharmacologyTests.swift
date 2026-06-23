import Foundation
import Testing
@testable import Piru

@Suite("SaturablePharmacology", .tags(.pharmacokinetics))
struct SaturablePharmacologyTests {
    private static let weight = 70.0

    // MARK: - Seed shape

    @Test
    func `seed has the six curated profiles, three quantitative three qualitative`() {
        let names = Set(SaturablePharmacology.profiles.map(\.substanceName))
        #expect(names == ["Alcohol", "Phenytoin", "Gabapentin", "Codeine", "Tramadol", "GHB"])

        // Quantitative = a drawable curve: the two elimination ceilings + the gabapentin absorption ceiling.
        let quantitative = SaturablePharmacology.profiles.filter(\.isQuantitative).map(\.substanceName)
        #expect(Set(quantitative) == ["Alcohol", "Phenytoin", "Gabapentin"])
    }

    @Test
    func `gabapentin is the absorption ceiling — exposure climbs SUB-linearly (the inverse of elimination)`() throws {
        let gaba = try #require(SaturablePharmacology.profile(forSubstanceName: "Gabapentin"))
        #expect(gaba.mechanism == .absorption)
        #expect(gaba.kinetics == nil)
        let absorption = try #require(gaba.absorption)
        let chart = try #require(SaturablePharmacology.absorptionChart(for: absorption, weightKg: Self.weight))

        // Saturable absorption ⇒ bioavailability falls with dose ⇒ 4× the dose buys LESS than 4× exposure.
        #expect(chart.maxDoseMultiple == 4)
        #expect(chart.exposureMultipleAtMax < chart.maxDoseMultiple)
        // …but more dose still means more total exposure (just sublinearly), never less.
        #expect(chart.exposureMultipleAtMax > 1)
        #expect(chart.curves.map(\.doseMultiple) == [1, 2, 3, 4])
    }

    @Test
    func `gabapentin bioavailability is monotonically non-increasing in dose and clamps at the table ends`() throws {
        let a = try #require(SaturablePharmacology.profile(forSubstanceName: "Gabapentin")?.absorption)
        // Falls across the measured range.
        #expect(a.bioavailability(atDoseMg: 300) > a.bioavailability(atDoseMg: 1_600))
        // Interpolates between points (600 mg sits between 400 and 800).
        let f600 = a.bioavailability(atDoseMg: 600)
        #expect(f600 < a.bioavailability(atDoseMg: 400))
        #expect(f600 > a.bioavailability(atDoseMg: 800))
        // Clamps below/above the table.
        #expect(a.bioavailability(atDoseMg: 100) == a.bioavailability(atDoseMg: 300))
        #expect(a.bioavailability(atDoseMg: 5_000) == a.bioavailability(atDoseMg: 1_600))
    }

    @Test
    func `tramadol ships qualitative — the CYP2D6 ultra-rapid breach has no interpolable dose knee`() {
        let tramadol = SaturablePharmacology.profile(forSubstanceName: "Tramadol")
        #expect(tramadol?.mechanism == .activation)
        #expect(tramadol?.kinetics == nil)
        #expect(tramadol?.absorption == nil)
    }

    @Test
    func `gabapentinoid comparison — gabapentin F falls with dose, pregabalin stays flat and higher`() throws {
        let gaba = SaturablePharmacology.GabapentinoidComparison.gabapentin
            .sorted { $0.doseMgPerDay < $1.doseMgPerDay }
        let pre = SaturablePharmacology.GabapentinoidComparison.pregabalin

        // Gabapentin: bioavailability is non-increasing in dose, and strictly lower at the top.
        let gabaF = gaba.map(\.bioavailabilityPct)
        #expect(zip(gabaF, gabaF.dropFirst()).allSatisfy { $0 >= $1 })
        let first = try #require(gabaF.first)
        let last = try #require(gabaF.last)
        #expect(first > last)

        // Pregabalin: flat (a single F value across its whole range) and above gabapentin's best.
        #expect(Set(pre.map(\.bioavailabilityPct)).count == 1)
        let preF = try #require(pre.first?.bioavailabilityPct)
        #expect(preF > first)
    }

    @Test
    func `lookup is case-insensitive and trims whitespace`() {
        #expect(SaturablePharmacology.profile(forSubstanceName: "  alcohol ")?.substanceName == "Alcohol")
        #expect(SaturablePharmacology.profile(forSubstanceName: "CODEINE")?.substanceName == "Codeine")
        #expect(SaturablePharmacology.profile(forSubstanceName: "ibuprofen") == nil)
    }

    @Test
    func `codeine is activation and ships no curve — its ceiling is phenotype-limited, not substrate-saturable`() {
        let codeine = SaturablePharmacology.profile(forSubstanceName: "Codeine")
        #expect(codeine?.mechanism == .activation)
        #expect(codeine?.kinetics == nil)
    }

    @Test
    func `GHB ships qualitative — no reliable human Km Vmax`() {
        let ghb = SaturablePharmacology.profile(forSubstanceName: "GHB")
        #expect(ghb?.mechanism == .elimination)
        #expect(ghb?.kinetics == nil)
    }

    // MARK: - Quantitative exposure curve

    @Test
    func `ethanol exposure climbs supralinearly — the largest curve holds far more than its dose-multiple of exposure`() throws {
        let kinetics = try #require(SaturablePharmacology.profile(forSubstanceName: "Alcohol")?.kinetics)
        let chart = try #require(SaturablePharmacology.concentrationChart(for: kinetics, weightKg: Self.weight))

        // Zero-order clearance ⇒ exposure grows ~quadratically, so 4 drinks ≫ 4× one drink's exposure.
        #expect(chart.maxDoseMultiple == 4)
        #expect(chart.exposureMultipleAtMax > chart.maxDoseMultiple * 1.5)
        // One curve per example dose, drawn over the display window.
        #expect(chart.curves.map(\.doseMultiple) == [1, 2, 3, 4])
    }

    @Test
    func `higher-dose curve is taller AND wider — peak rises and the tail lingers`() throws {
        let kinetics = try #require(SaturablePharmacology.profile(forSubstanceName: "Alcohol")?.kinetics)
        let chart = try #require(SaturablePharmacology.concentrationChart(for: kinetics, weightKg: Self.weight))
        let one = try #require(chart.curves.first { $0.doseMultiple == 1 })
        let four = try #require(chart.curves.first { $0.doseMultiple == 4 })

        // Taller: peak normalized level scales up with dose.
        let onePeak = one.points.map(\.level).max() ?? 0
        let fourPeak = four.points.map(\.level).max() ?? 0
        #expect(fourPeak > onePeak * 2)

        // Wider: time spent above the one-drink peak is much longer at four drinks (zero-order tail).
        func minutesAbove(_ curve: SaturablePharmacology.DoseCurve, _ level: Double) -> Double {
            Double(curve.points.count(where: { $0.level >= level })) * (curve.points.count > 1 ? curve.points[1].minutes : 0)
        }
        #expect(minutesAbove(four, onePeak) > minutesAbove(one, onePeak) * 2)
    }

    @Test
    func `phenytoin curve family also shows supralinear exposure within the dose range`() throws {
        let kinetics = try #require(SaturablePharmacology.profile(forSubstanceName: "Phenytoin")?.kinetics)
        let chart = try #require(SaturablePharmacology.concentrationChart(for: kinetics, weightKg: Self.weight))
        #expect(chart.exposureMultipleAtMax > chart.maxDoseMultiple)
    }

    @Test
    func `heavier body weight dilutes concentration but the supralinear shape persists`() throws {
        let kinetics = try #require(SaturablePharmacology.profile(forSubstanceName: "Alcohol")?.kinetics)
        let light = try #require(SaturablePharmacology.concentrationChart(for: kinetics, weightKg: 50))
        let heavy = try #require(SaturablePharmacology.concentrationChart(for: kinetics, weightKg: 100))
        // Both are normalized to their own reference dose, so the relative shape — supralinearity — holds
        // regardless of weight.
        #expect(light.exposureMultipleAtMax > light.maxDoseMultiple)
        #expect(heavy.exposureMultipleAtMax > heavy.maxDoseMultiple)
    }

    @Test
    func `Vmax basis conversion — whole-body vs mg per kg per day`() {
        // Ethanol: 95 mg/min ÷ (0.55·70 = 38.5 L) ≈ 2.468 mg/L/min.
        let ethanol = SaturablePharmacology.Kinetics.VmaxBasis.wholeBodyMgPerMin(95)
        #expect(abs(ethanol.mgPerLPerMin(weightKg: 70, vdPerKg: 0.55) - 95 / 38.5) < 1e-6)

        // Phenytoin: 7 mg/kg/day is weight-independent once divided by a weight-scaled Vd.
        let phenytoin = SaturablePharmacology.Kinetics.VmaxBasis.mgPerKgPerDay(7)
        let at70 = phenytoin.mgPerLPerMin(weightKg: 70, vdPerKg: 0.65)
        let at100 = phenytoin.mgPerLPerMin(weightKg: 100, vdPerKg: 0.65)
        #expect(abs(at70 - at100) < 1e-9)
        #expect(abs(at70 - 7 / (1_440 * 0.65)) < 1e-9)
    }
}
