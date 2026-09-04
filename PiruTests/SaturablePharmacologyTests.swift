import Foundation
import Testing
@testable import Piru

@Suite("SaturablePharmacology", .tags(.pharmacokinetics))
@MainActor
struct SaturablePharmacologyTests {
    private static let weight = 70.0

    /// The profiles are assembled from `saturable_kinetics` and `bioavailability_by_dose`, so this
    /// suite needs the store up rather than relying on another suite having warmed it.
    init() {
        _ = SubstanceStore.shared
    }

    // MARK: - Shape

    @Test
    func `five profiles ship, two quantitative three qualitative`() {
        let names = Set(SaturablePharmacology.profiles.map(\.substanceName))
        #expect(names == ["Alcohol", "Gabapentin", "Codeine", "Tramadol", "GHB"])

        // Quantitative = a drawable curve: the ethanol elimination ceiling + the gabapentin absorption ceiling.
        let quantitative = SaturablePharmacology.profiles.filter(\.isQuantitative).map(\.substanceName)
        #expect(Set(quantitative) == ["Alcohol", "Gabapentin"])
    }

    @Test
    func `every profile carries a source line and rests on at least medium-confidence data`() {
        let rows = Dictionary(
            SubstanceStore.shared.saturableKinetics().map { ($0.substanceName, $0) },
            uniquingKeysWith: { first, _ in first },
        )
        for profile in SaturablePharmacology.profiles {
            #expect(!profile.citation.isEmpty, "\(profile.substanceName) ships no citation")
            let grade = rows[profile.substanceName].map { ConfidenceTier(grade: $0.confidence) }
            #expect(grade.map { $0 >= .medium } == true, "\(profile.substanceName) is below the shipping floor")
        }
    }

    @Test
    func `every quantitative profile's parameters are positive and physically plausible`() {
        for profile in SaturablePharmacology.profiles {
            if let k = profile.kinetics {
                #expect(k.kmMgPerL > 0, "\(profile.substanceName) Km")
                #expect(k.vmax.mgPerLPerMin(weightKg: Self.weight, vdPerKg: k.vdPerKg) > 0)
                // Body water is ~0.6 L/kg and no small molecule distributes into nothing, so a
                // saturable-elimination Vd outside this band is a unit slip, not a measurement.
                #expect(k.vdPerKg > 0.1 && k.vdPerKg < 10, "\(profile.substanceName) Vd")
                #expect(k.bioavailability > 0 && k.bioavailability <= 1, "\(profile.substanceName) F")
                #expect(k.ka > 0, "\(profile.substanceName) ka")
            }
            if let a = profile.absorption {
                #expect(a.vdPerKg > 0.1 && a.vdPerKg < 10, "\(profile.substanceName) Vd")
                #expect(a.halfLifeMin > 0, "\(profile.substanceName) half-life")
                #expect(a.ka > 0, "\(profile.substanceName) ka")
                #expect(!a.fByDose.isEmpty, "\(profile.substanceName) F-vs-dose")
                #expect(a.fByDose.allSatisfy { $0.f > 0 && $0.f <= 1 })
            }
        }
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
        // A whole-body rate is simply divided by the volume it distributes into.
        let wholeBody = SaturablePharmacology.Kinetics.VmaxBasis.wholeBodyMgPerMin(100)
        #expect(abs(wholeBody.mgPerLPerMin(weightKg: 50, vdPerKg: 0.5) - 100 / 25) < 1e-9)

        // A weight-scaled rate is weight-independent once divided by a weight-scaled Vd.
        let perKg = SaturablePharmacology.Kinetics.VmaxBasis.mgPerKgPerDay(10)
        let at70 = perKg.mgPerLPerMin(weightKg: 70, vdPerKg: 0.5)
        let at100 = perKg.mgPerLPerMin(weightKg: 100, vdPerKg: 0.5)
        #expect(abs(at70 - at100) < 1e-9)
        #expect(abs(at70 - 10 / (1_440 * 0.5)) < 1e-9)
    }

    @Test
    func `an unknown Vmax basis yields nothing rather than a rate in the wrong units`() {
        #expect(SaturablePharmacology.Kinetics.VmaxBasis(rawBasis: "mg_per_hour", value: 7) == nil)
        #expect(SaturablePharmacology.Kinetics.VmaxBasis(rawBasis: nil, value: 7) == nil)
    }

    // MARK: - Per-day → single dose

    @Test
    func `a quantitative profile's F is the substance's resolved pk_routes bioavailability`() throws {
        // `saturable_kinetics` deliberately carries no F column, so a correction to a substance's
        // bioavailability reaches this tool without a second copy to update.
        let kinetics = try #require(SaturablePharmacology.profile(forSubstanceName: "Alcohol")?.kinetics)
        let resolved = SubstanceStore.shared.pharmacologyParameters(forSubstanceName: "Alcohol")
        #expect(kinetics.bioavailability == (resolved.bioavailabilityFraction ?? 1))
    }

    @Test
    func `gabapentin's absorption table is its per-day series divided by the label's three doses`() throws {
        let perDay = SubstanceStore.shared.bioavailabilityByDose()["gabapentin"] ?? []
        let absorption = try #require(SaturablePharmacology.profile(forSubstanceName: "Gabapentin")?.absorption)
        #expect(perDay.count == absorption.fByDose.count)
        for (daily, single) in zip(perDay, absorption.fByDose) {
            #expect(abs(single.doseMg - daily.doseMg / 3) < 1e-9)
            #expect(abs(single.f - daily.bioavailabilityPct / 100) < 1e-9)
        }
        // The reference dose the curves are drawn against is the smallest of those single doses,
        // so "1 unit" on the chart is one administration and not one day.
        #expect(absorption.referenceDoseMg == absorption.fByDose.first?.doseMg)
    }
}
