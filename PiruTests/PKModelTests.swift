import Foundation
import Testing
@testable import Piru

@Suite("PKModel")
struct PKModelTests {
    // MARK: - ke (elimination rate constant)

    @Test
    func `ke from caffeine half-life (300 min)`() {
        let ke = PKModel.ke(fromHalfLifeMinutes: 300)
        // ke = ln(2) / 300 ≈ 0.00231
        #expect(abs(ke - log(2) / 300) < 1e-10)
    }

    @Test
    func `ke from zero half-life returns zero`() {
        #expect(PKModel.ke(fromHalfLifeMinutes: 0) == 0)
    }

    @Test
    func `ke from negative half-life returns zero`() {
        #expect(PKModel.ke(fromHalfLifeMinutes: -100) == 0)
    }

    // MARK: - defaultKa

    @Test
    func `Default ka is 4x ke`() {
        let ke = PKModel.ke(fromHalfLifeMinutes: 300)
        #expect(PKModel.defaultKa(ke: ke) == 4 * ke)
    }

    // MARK: - concentration

    @Test
    func `Concentration at t=0 is zero`() {
        let ke = PKModel.ke(fromHalfLifeMinutes: 300)
        let ka = PKModel.defaultKa(ke: ke)
        #expect(PKModel.concentration(at: 0, ke: ke, ka: ka) == 0)
    }

    @Test
    func `Concentration rises then falls`() {
        let ke = PKModel.ke(fromHalfLifeMinutes: 300)
        let ka = PKModel.defaultKa(ke: ke)
        let early = PKModel.concentration(at: 30, ke: ke, ka: ka)
        let peak = PKModel.concentration(at: PKModel.tmax(ke: ke, ka: ka), ke: ke, ka: ka)
        let late = PKModel.concentration(at: 1_000, ke: ke, ka: ka)
        #expect(early > 0)
        #expect(peak > early)
        #expect(late < peak)
        #expect(late > 0)
    }

    @Test
    func `Concentration with negative time returns zero`() {
        let ke = PKModel.ke(fromHalfLifeMinutes: 300)
        let ka = PKModel.defaultKa(ke: ke)
        #expect(PKModel.concentration(at: -10, ke: ke, ka: ka) == 0)
    }

    @Test
    func `Concentration with zero ke returns zero`() {
        #expect(PKModel.concentration(at: 60, ke: 0, ka: 0.01) == 0)
    }

    @Test
    func `Concentration with zero ka returns zero`() {
        #expect(PKModel.concentration(at: 60, ke: 0.01, ka: 0) == 0)
    }

    @Test
    func `Concentration handles ka ≈ ke singularity`() {
        let ke = 0.005
        let ka = ke + 1e-12 // Nearly identical
        let c = PKModel.concentration(at: 100, ke: ke, ka: ka)
        #expect(c > 0)
        #expect(c.isFinite)
    }

    @Test
    func `Concentration is always non-negative`() {
        let ke = PKModel.ke(fromHalfLifeMinutes: 60)
        let ka = PKModel.defaultKa(ke: ke)
        for t in stride(from: 0.0, through: 5_000, by: 50) {
            #expect(PKModel.concentration(at: t, ke: ke, ka: ka) >= 0)
        }
    }

    // MARK: - tmax (time of peak)

    @Test
    func `Tmax is positive for valid parameters`() {
        let ke = PKModel.ke(fromHalfLifeMinutes: 300)
        let ka = PKModel.defaultKa(ke: ke)
        let t = PKModel.tmax(ke: ke, ka: ka)
        #expect(t > 0)
    }

    @Test
    func `Tmax returns zero when ka <= ke`() {
        #expect(PKModel.tmax(ke: 0.01, ka: 0.005) == 0)
        #expect(PKModel.tmax(ke: 0.01, ka: 0.01) == 0)
    }

    @Test
    func `Tmax returns zero for invalid parameters`() {
        #expect(PKModel.tmax(ke: 0, ka: 0.01) == 0)
        #expect(PKModel.tmax(ke: -1, ka: 0.01) == 0)
        #expect(PKModel.tmax(ke: 0.01, ka: 0) == 0)
    }

    @Test
    func `Faster absorption means earlier peak`() {
        let ke = PKModel.ke(fromHalfLifeMinutes: 300)
        let kaFast = 10 * ke
        let kaSlow = 3 * ke
        let tmaxFast = PKModel.tmax(ke: ke, ka: kaFast)
        let tmaxSlow = PKModel.tmax(ke: ke, ka: kaSlow)
        #expect(tmaxFast < tmaxSlow)
    }

    // MARK: - cmax

    @Test
    func `Cmax is the maximum concentration value`() {
        let ke = PKModel.ke(fromHalfLifeMinutes: 300)
        let ka = PKModel.defaultKa(ke: ke)
        let peak = PKModel.cmax(ke: ke, ka: ka)
        // Check nearby points are lower
        let tPeak = PKModel.tmax(ke: ke, ka: ka)
        let before = PKModel.concentration(at: tPeak - 10, ke: ke, ka: ka)
        let after = PKModel.concentration(at: tPeak + 10, ke: ke, ka: ka)
        #expect(peak >= before)
        #expect(peak >= after)
    }

    @Test
    func `Cmax is positive for valid parameters`() {
        let ke = PKModel.ke(fromHalfLifeMinutes: 120)
        let ka = PKModel.defaultKa(ke: ke)
        #expect(PKModel.cmax(ke: ke, ka: ka) > 0)
    }

    // MARK: - estimateKa

    @Test
    func `Estimated ka produces tmax close to target`() {
        let ke = PKModel.ke(fromHalfLifeMinutes: 300)
        let targetTmax: Double = 60 // 1 hour to peak
        let ka = PKModel.estimateKa(timeToPeak: targetTmax, ke: ke)
        let actualTmax = PKModel.tmax(ke: ke, ka: ka)
        // Should converge within 1 minute
        #expect(abs(actualTmax - targetTmax) < 1.0)
    }

    @Test
    func `estimateKa falls back with zero timeToPeak`() {
        let ke = PKModel.ke(fromHalfLifeMinutes: 300)
        let ka = PKModel.estimateKa(timeToPeak: 0, ke: ke)
        #expect(ka == PKModel.defaultKa(ke: ke))
    }

    @Test
    func `estimateKa falls back with negative timeToPeak`() {
        let ke = PKModel.ke(fromHalfLifeMinutes: 300)
        let ka = PKModel.estimateKa(timeToPeak: -10, ke: ke)
        #expect(ka == PKModel.defaultKa(ke: ke))
    }

    @Test
    func `estimateKa falls back with zero ke`() {
        let ka = PKModel.estimateKa(timeToPeak: 60, ke: 0)
        #expect(ka == 0)
    }

    @Test
    func `estimateKa always returns ka > ke`() {
        let ke = PKModel.ke(fromHalfLifeMinutes: 300)
        for ttp in [10.0, 30, 60, 120, 240] {
            let ka = PKModel.estimateKa(timeToPeak: ttp, ke: ke)
            #expect(ka >= ke)
        }
    }

    // MARK: - timeToFraction

    @Test
    func `Time to 3% is after peak`() {
        let ke = PKModel.ke(fromHalfLifeMinutes: 300)
        let ka = PKModel.defaultKa(ke: ke)
        let t3pct = PKModel.timeToFraction(0.03, ke: ke, ka: ka)
        let tPeak = PKModel.tmax(ke: ke, ka: ka)
        #expect(t3pct > tPeak)
    }

    @Test
    func `Time to 50% is before time to 3%`() {
        let ke = PKModel.ke(fromHalfLifeMinutes: 300)
        let ka = PKModel.defaultKa(ke: ke)
        let t50 = PKModel.timeToFraction(0.5, ke: ke, ka: ka)
        let t3 = PKModel.timeToFraction(0.03, ke: ke, ka: ka)
        #expect(t50 < t3)
    }

    @Test
    func `Concentration at timeToFraction is approximately the target`() {
        let ke = PKModel.ke(fromHalfLifeMinutes: 300)
        let ka = PKModel.defaultKa(ke: ke)
        let fraction = 0.1
        let t = PKModel.timeToFraction(fraction, ke: ke, ka: ka)
        let peak = PKModel.cmax(ke: ke, ka: ka)
        let actual = PKModel.concentration(at: t, ke: ke, ka: ka)
        // Should be within 1% of target
        #expect(abs(actual - peak * fraction) / (peak * fraction) < 0.01)
    }

    @Test
    func `timeToFraction returns zero for invalid parameters`() {
        #expect(PKModel.timeToFraction(0.5, ke: 0, ka: 0) == 0)
    }

    // MARK: - Absolute exposure (Foundation A)

    /// The flaw-closing gate: the normalized curve makes 5 mg and 50 mg identical; the absolute
    /// curve must scale linearly with dose at *every* time point. Without this, dose-dependent
    /// tolerance is inexpressible.
    @Test(.tags(.pharmacokinetics))
    func `Absolute concentration is linear in dose`() {
        let ke = PKModel.ke(fromHalfLifeMinutes: 300)
        let ka = PKModel.estimateKa(timeToPeak: 45, ke: ke)
        for t in [10.0, 45, 120, 600, 2_000] {
            let low = PKModel.concentrationAbsolute(dose: 5, bioavailability: 1, vdPerKg: 0.6, weightKg: 70, ke: ke, ka: ka, at: t)
            let high = PKModel.concentrationAbsolute(dose: 50, bioavailability: 1, vdPerKg: 0.6, weightKg: 70, ke: ke, ka: ka, at: t)
            #expect(low > 0)
            #expect(abs(high / low - 10) < 1e-9)
        }
    }

    @Test
    func `Absolute concentration is inverse in body weight`() {
        let ke = PKModel.ke(fromHalfLifeMinutes: 120)
        let ka = PKModel.defaultKa(ke: ke)
        let light = PKModel.concentrationAbsolute(dose: 20, bioavailability: 1, vdPerKg: 0.6, weightKg: 60, ke: ke, ka: ka, at: 60)
        let heavy = PKModel.concentrationAbsolute(dose: 20, bioavailability: 1, vdPerKg: 0.6, weightKg: 120, ke: ke, ka: ka, at: 60)
        // Twice the mass → half the concentration for the same dose.
        #expect(abs(heavy / light - 0.5) < 1e-9)
    }

    @Test
    func `Absolute concentration scales with bioavailability`() {
        let ke = PKModel.ke(fromHalfLifeMinutes: 120)
        let ka = PKModel.defaultKa(ke: ke)
        let lowF = PKModel.concentrationAbsolute(dose: 20, bioavailability: 0.4, vdPerKg: 0.6, weightKg: 70, ke: ke, ka: ka, at: 60)
        let highF = PKModel.concentrationAbsolute(dose: 20, bioavailability: 0.8, vdPerKg: 0.6, weightKg: 70, ke: ke, ka: ka, at: 60)
        #expect(abs(lowF / highF - 0.5) < 1e-9)
    }

    @Test
    func `Absolute concentration equals prefactor times shape`() {
        let ke = PKModel.ke(fromHalfLifeMinutes: 300)
        let ka = PKModel.estimateKa(timeToPeak: 45, ke: ke)
        let dose = 80.0, f = 0.7, vdPerKg = 5.0, weight = 68.0, t = 90.0
        let expected = (f * dose / (vdPerKg * weight)) * PKModel.concentration(at: t, ke: ke, ka: ka)
        let actual = PKModel.concentrationAbsolute(dose: dose, bioavailability: f, vdPerKg: vdPerKg, weightKg: weight, ke: ke, ka: ka, at: t)
        #expect(abs(actual - expected) < 1e-12)
    }

    @Test
    func `Absolute concentration returns zero for invalid inputs`() {
        let ke = PKModel.ke(fromHalfLifeMinutes: 120)
        let ka = PKModel.defaultKa(ke: ke)
        #expect(PKModel.concentrationAbsolute(dose: 10, bioavailability: 0, vdPerKg: 0.6, weightKg: 70, ke: ke, ka: ka, at: 60) == 0)
        #expect(PKModel.concentrationAbsolute(dose: 10, bioavailability: 1, vdPerKg: 0, weightKg: 70, ke: ke, ka: ka, at: 60) == 0)
        #expect(PKModel.concentrationAbsolute(dose: 10, bioavailability: 1, vdPerKg: 0.6, weightKg: 0, ke: ke, ka: ka, at: 60) == 0)
        #expect(PKModel.concentrationAbsolute(dose: -5, bioavailability: 1, vdPerKg: 0.6, weightKg: 70, ke: ke, ka: ka, at: 60) == 0)
    }

    /// Ethanol on a mass basis *is* the Widmark equation: peak BAC ≈ Dose / (r · weight). One US
    /// standard drink (14 g) in a 70 kg person with r ≈ 0.6 → ~0.33 g/L ≈ 0.033 g/dL, a realistic
    /// single-drink peak. With fast (ethanol-like) absorption the modeled peak approaches that ideal.
    @Test(.tags(.pharmacokinetics))
    func `Ethanol absolute concentration approximates Widmark BAC`() {
        let ke = PKModel.ke(fromHalfLifeMinutes: 90)
        let ka = 100 * ke // fast absorption
        let doseMg = 14_000.0 // 14 g standard drink
        let prefactor = 1.0 * doseMg / (0.6 * 70) // mg/L, ≈ 333
        #expect(abs(prefactor - 333.33) < 1)

        let peak = PKModel.concentrationAbsolute(dose: doseMg, bioavailability: 1, vdPerKg: 0.6, weightKg: 70, ke: ke, ka: ka, at: PKModel.tmax(ke: ke, ka: ka))
        // Fast-absorption peak sits just under the instantaneous-distribution ideal.
        #expect(peak <= prefactor)
        #expect(peak > 0.88 * prefactor)

        let gPerDL = peak / 1_000 / 10 // mg/L → g/L → g/dL
        #expect(gPerDL > 0.02)
        #expect(gPerDL < 0.05)
    }

    // MARK: - Molar concentration

    @Test
    func `Molar concentration is mass over molar mass`() {
        let ke = PKModel.ke(fromHalfLifeMinutes: 300)
        let ka = PKModel.estimateKa(timeToPeak: 45, ke: ke)
        let mw = 194.19 // caffeine g/mol
        let mass = PKModel.concentrationAbsolute(dose: 100, bioavailability: 1, vdPerKg: 0.6, weightKg: 70, ke: ke, ka: ka, at: 45)
        let molar = PKModel.concentrationMolar(dose: 100, bioavailability: 1, vdPerKg: 0.6, weightKg: 70, molarMassGramsPerMole: mw, ke: ke, ka: ka, at: 45)
        #expect(abs(molar - mass / 1_000 / mw) < 1e-15)
        #expect(molar > 0)
    }

    @Test
    func `Molar concentration returns zero for non-positive molar mass`() {
        let ke = PKModel.ke(fromHalfLifeMinutes: 300)
        let ka = PKModel.defaultKa(ke: ke)
        #expect(PKModel.concentrationMolar(dose: 100, bioavailability: 1, vdPerKg: 0.6, weightKg: 70, molarMassGramsPerMole: 0, ke: ke, ka: ka, at: 45) == 0)
        #expect(PKModel.concentrationMolar(dose: 100, bioavailability: 1, vdPerKg: 0.6, weightKg: 70, molarMassGramsPerMole: -1, ke: ke, ka: ka, at: 45) == 0)
    }

    // MARK: - Real-world substance parameters

    @Test(
        .tags(.pharmacokinetics),
    )
    func `Caffeine PK curve is realistic`() {
        // Caffeine: half-life ~5 hours (300 min), time-to-peak ~45 min oral
        let ke = PKModel.ke(fromHalfLifeMinutes: 300)
        let ka = PKModel.estimateKa(timeToPeak: 45, ke: ke)
        let tPeak = PKModel.tmax(ke: ke, ka: ka)
        let t5hl = PKModel.timeToFraction(0.03, ke: ke, ka: ka)

        // Peak should be around 45 min
        #expect(abs(tPeak - 45) < 2)
        // Should be mostly eliminated after ~5 half-lives (25 hours = 1500 min)
        #expect(t5hl < 2_000)
        #expect(t5hl > 1_000)
    }

    // MARK: - Receptor occupancy / engagement (PK → PD bridge)

    @Test
    func `Occupancy is zero for non-positive inputs`() {
        #expect(PKModel.occupancy(concentration: 0, halfMax: 100) == 0)
        #expect(PKModel.occupancy(concentration: -1, halfMax: 100) == 0)
        #expect(PKModel.occupancy(concentration: 100, halfMax: 0) == 0)
        #expect(PKModel.occupancy(concentration: 100, halfMax: 100, hillCoefficient: 0) == 0)
    }

    @Test
    func `Occupancy is half at C equals halfMax`() {
        #expect(abs(PKModel.occupancy(concentration: 250, halfMax: 250) - 0.5) < 1e-12)
    }

    @Test
    func `Occupancy is bounded in 0 to 1 and rises with concentration`() {
        var last = 0.0
        for c in stride(from: 1.0, through: 10_000, by: 250) {
            let o = PKModel.occupancy(concentration: c, halfMax: 500)
            #expect(o > 0 && o < 1)
            #expect(o > last) // strictly monotonic increasing
            last = o
        }
    }

    @Test
    func `Occupancy is unit-invariant when concentration and halfMax share a unit`() {
        // Same ratio in nM and in mol/L must give the same occupancy.
        let inNanomolar = PKModel.occupancy(concentration: 300, halfMax: 200)
        let inMolar = PKModel.occupancy(concentration: 300e-9, halfMax: 200e-9)
        #expect(abs(inNanomolar - inMolar) < 1e-12)
    }

    @Test
    func `Hill coefficient above one sharpens the response`() {
        // Below halfMax, cooperativity (h > 1) lowers occupancy (steeper threshold);
        // above halfMax it raises it. h = 1 sits between.
        let below1 = PKModel.occupancy(concentration: 100, halfMax: 500, hillCoefficient: 1)
        let below2 = PKModel.occupancy(concentration: 100, halfMax: 500, hillCoefficient: 2)
        #expect(below2 < below1)
        let above1 = PKModel.occupancy(concentration: 2_000, halfMax: 500, hillCoefficient: 1)
        let above2 = PKModel.occupancy(concentration: 2_000, halfMax: 500, hillCoefficient: 2)
        #expect(above2 > above1)
    }

    /// **The Stage 0 gate (model property): low-dose vs high-dose of the same substance produce
    /// DIFFERENT receptor occupancy.** This is the headline correctness requirement of the whole
    /// pharmacology axis — the normalized-shape model could not express it (every dose normalized to
    /// the same `[0,1]` curve → identical occupancy → dose-independent tolerance, which is wrong).
    /// Driving occupancy from the *absolute* molar pathway closes the flaw: occupancy is a strictly
    /// increasing function of dose, low therapeutic exposure sits in the near-linear low-engagement
    /// regime, and a recreational multiple climbs toward saturation.
    ///
    /// Parameters are representative stimulant-like values chosen to exercise the regime, NOT a claim
    /// about a specific drug's measured EC₅₀ — the real-data version lands with the flagship DB seed.
    @Test(.tags(.pharmacokinetics))
    func `Occupancy is dose-dependent (the normalized-PK flaw is closed)`() {
        let halfLife = 660.0 // ~11 h, stimulant-like
        let ke = PKModel.ke(fromHalfLifeMinutes: halfLife)
        let ka = PKModel.estimateKa(timeToPeak: 120, ke: ke)
        let peakTime = PKModel.tmax(ke: ke, ka: ka)
        let mw = 135.2 // amphetamine-like g/mol
        let releaseEC50nM = 1_000.0 // functional release EC₅₀ at the transporter (representative)

        func peakOccupancy(doseMg: Double) -> Double {
            let molar = PKModel.concentrationMolar(
                dose: doseMg, bioavailability: 0.9, vdPerKg: 4.0, weightKg: 70,
                molarMassGramsPerMole: mw, ke: ke, ka: ka, at: peakTime,
            )
            let nanomolar = molar * 1e9 // mol/L → nM, matching the EC₅₀ unit
            return PKModel.occupancy(concentration: nanomolar, halfMax: releaseEC50nM)
        }

        let low = peakOccupancy(doseMg: 5) // therapeutic-ish
        let high = peakOccupancy(doseMg: 50) // recreational-ish (10×)

        // The flaw: a normalized model would make these EQUAL. They must differ, strongly.
        #expect(low > 0)
        #expect(high > low)
        #expect(high / low > 3) // dose drives engagement, not just curve shape
        // Low dose sits in the low-engagement regime (little allostatic drive); high dose climbs.
        #expect(low < 0.2)
        #expect(high > 0.35)
    }
}

extension Tag {
    @Tag static var pharmacokinetics: Self
}

@Suite("PKModel saturable kinetics", .tags(.pharmacokinetics))
struct PKModelSaturableTests {
    // Body / Vd shared by the synthetic cases below.
    private static let weight = 70.0
    private static let vdPerKg = 0.6 // 42 L

    // MARK: - Reduces to first-order at C ≪ Km

    @Test
    func `At C ≪ Km saturable elimination matches the closed-form first-order curve`() {
        let ke = PKModel.ke(fromHalfLifeMinutes: 300)
        let ka = PKModel.defaultKa(ke: ke)
        // Huge Km so the dose never approaches it; Vmax = ke·Km makes the effective rate = ke.
        let km = 1e7
        let vmax = ke * km
        let curve = PKModel.saturableCurve(
            dose: 100, bioavailability: 1, vdPerKg: Self.vdPerKg, weightKg: Self.weight,
            ka: ka, saturation: .elimination(km: km, vmax: vmax),
            durationMinutes: 1_200, stepMinutes: 1,
        )
        let vd = Self.vdPerKg * Self.weight
        let analyticPeak = (1.0 * 100 / vd) * PKModel.cmax(ke: ke, ka: ka)
        let relErr = abs(curve.peakParent - analyticPeak) / analyticPeak
        #expect(relErr < 0.01) // RK4 vs analytic agree to <1%
    }

    // MARK: - Saturable elimination (the dangerous ceiling)

    /// Ethanol-like zero-order kinetics: Vmax ≈ 2.5 mg/L/min (~0.15 g/L/h BAC fall), Km ≈ 90 mg/L.
    private static let ethanol = PKModel.Saturation.elimination(km: 90, vmax: 2.5)

    @Test
    func `Above Km, elimination is zero-order — concentration declines at a constant ≈ Vmax slope`() {
        let curve = PKModel.saturableCurve(
            dose: 40_000, bioavailability: 1, vdPerKg: Self.vdPerKg, weightKg: Self.weight,
            ka: 0.05, saturation: Self.ethanol, durationMinutes: 1_200, stepMinutes: 1,
        )
        // Sample the descending limb where C is well above Km and absorption is finished (t ≈ 300 min).
        let i = 300
        let c = curve.parent[i]
        let slope = curve.parent[i + 1] - curve.parent[i] // mg/L per minute
        #expect(c > 90 * 3) // still firmly in the zero-order regime
        // Capacity-limited: the decline is capped at ≈ Vmax and far slower than first-order would give.
        #expect(abs(slope) > 1.8 && abs(slope) <= 2.5) // near the zero-order ceiling (Vmax = 2.5)
        let firstOrderRate = (2.5 / 90) * c // what a first-order drug (ke = Vmax/Km) would shed here
        #expect(abs(slope) < firstOrderRate * 0.5) // dramatically slower — the supralinear danger
    }

    @Test
    func `Saturable elimination accumulates supralinearly — doubling dose more than doubles exposure`() {
        func auc(dose: Double) -> Double {
            PKModel.saturableCurve(
                dose: dose, bioavailability: 1, vdPerKg: Self.vdPerKg, weightKg: Self.weight,
                ka: 0.05, saturation: Self.ethanol, durationMinutes: 2_000, stepMinutes: 1,
            ).effectAUC
        }
        let single = auc(dose: 20_000)
        let doubled = auc(dose: 40_000)
        // First-order would give exactly 2×; capacity-limited clearance makes it markedly supralinear.
        #expect(doubled / single > 2.5)
    }

    // MARK: - Saturable activation (the effect ceiling)

    /// Synthetic prodrug → active metabolite: formation saturates at Km = 5 mg/L. Conversion is a
    /// *minor* parent-clearance route (Vmax ≪ parentKe·Km), like codeine→morphine (~10%) — so the
    /// parent stays first-order/linear while the metabolite's formation hits its capacity ceiling.
    private static func activation() -> PKModel.Saturation {
        .activation(
            km: 5,
            vmax: 0.005,
            fractionConverted: 0.1,
            parentEliminationKe: PKModel.ke(fromHalfLifeMinutes: 180),
            metaboliteKe: PKModel.ke(fromHalfLifeMinutes: 120),
        )
    }

    private static func activationCurve(dose: Double) -> PKModel.SaturableCurve {
        PKModel.saturableCurve(
            dose: dose, bioavailability: 1, vdPerKg: vdPerKg, weightKg: weight,
            ka: 0.02, saturation: activation(), durationMinutes: 1_500, stepMinutes: 1,
        )
    }

    @Test
    func `Parent peak scales linearly with dose; metabolite peak ceilings (sublinear past the knee)`() throws {
        let low = Self.activationCurve(dose: 100) // C peak ≪ Km
        let mid = Self.activationCurve(dose: 1_000) // C peak ≈ 5× Km
        let parentRatio = mid.peakParent / low.peakParent
        let metRatio = try (#require(mid.metabolite?.max())) / #require(low.metabolite?.max())
        // Parent is linear (no saturable step on it): ~10× for a 10× dose.
        #expect(parentRatio > 9 && parentRatio < 11)
        // Metabolite formation is capacity-limited, so its peak grows much less than 10×.
        #expect(metRatio < parentRatio)
        #expect(metRatio < 7)
    }

    @Test
    func `Past the knee, extra dose buys metabolite duration (AUC), not peak`() {
        let mid = Self.activationCurve(dose: 1_000)
        let high = Self.activationCurve(dose: 4_000) // 4× dose, both above the knee
        let peakRatio = high.peakEffect / mid.peakEffect
        let aucRatio = high.effectAUC / mid.effectAUC
        #expect(peakRatio < 4) // peak plateaus (would be 4× if linear)
        #expect(aucRatio > peakRatio) // the tail lengthens — duration outgrows peak
    }

    // MARK: - Guards & invariants

    @Test
    func `Saturable curve is non-negative everywhere`() {
        let curve = PKModel.saturableCurve(
            dose: 40_000, bioavailability: 1, vdPerKg: Self.vdPerKg, weightKg: Self.weight,
            ka: 0.05, saturation: Self.ethanol, durationMinutes: 1_200, stepMinutes: 1,
        )
        #expect(curve.parent.allSatisfy { $0 >= 0 })
    }

    @Test
    func `Invalid inputs and .none return a degenerate curve`() {
        #expect(PKModel.saturableCurve(dose: 0, bioavailability: 1, vdPerKg: 0.6, weightKg: 70, ka: 0.05, saturation: Self.ethanol, durationMinutes: 600).parent == [0])
        #expect(PKModel.saturableCurve(dose: 100, bioavailability: 1, vdPerKg: 0.6, weightKg: 70, ka: 0.05, saturation: .none, durationMinutes: 600).parent == [0])
        #expect(PKModel.saturableCurve(dose: 100, bioavailability: 0, vdPerKg: 0.6, weightKg: 70, ka: 0.05, saturation: Self.ethanol, durationMinutes: 600).parent == [0])
    }
}
