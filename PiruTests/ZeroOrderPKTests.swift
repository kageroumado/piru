import Foundation
import Testing
@testable import Piru

/// Zero-order (capacity-limited) elimination — the alcohol curve. The defining property is that
/// **duration scales with dose** and the decline is roughly **linear**, neither of which the generic
/// fixed-width phase bell can express.
@Suite("ZeroOrderPK")
struct ZeroOrderPKTests {
    private let ethanol = PKModel.ethanolZeroOrder
    private let oneDrinkMg = 14_000.0 // one US standard drink ≈ 14 g ethanol

    private func alcohol(grams: Double, name: String = "Alcohol") -> ActiveSubstanceState {
        ActiveSubstanceState(
            substanceName: name,
            colorHex: "FF66AA",
            doseTimestamp: Date(timeIntervalSince1970: 0),
            amount: grams,
            unit: "g",
            route: "oral",
            onsetEndMinutes: 15,
            comeupEndMinutes: 30,
            peakEndMinutes: 60,
            offsetEndMinutes: 180,
            afterglowEndMinutes: nil,
            totalMinutes: 180,
            doseIntensity: 0.6,
            doseMagnitude: 0.6,
            tachyphylaxis: 0,
        )
    }

    // MARK: - Core shape

    @Test
    func `Normalized shape starts at zero, peaks at one, returns to zero`() throws {
        let peakT = PKModel.zeroOrderPeakMinutes(doseMg: oneDrinkMg, kinetics: ethanol)
        #expect(peakT > 0)
        #expect(PKModel.zeroOrderShape(doseMg: oneDrinkMg, at: 0, kinetics: ethanol) == 0)
        let peak = try #require(PKModel.zeroOrderShape(doseMg: oneDrinkMg, at: peakT, kinetics: ethanol))
        #expect(abs(peak - 1) < 1e-9)
        let cleared = PKModel.zeroOrderClearMinutes(doseMg: oneDrinkMg, kinetics: ethanol)
        let tail = try #require(PKModel.zeroOrderShape(doseMg: oneDrinkMg, at: cleared + 5, kinetics: ethanol))
        #expect(tail == 0)
    }

    @Test
    func `Peak lands roughly when absorption flux falls to the elimination rate (~30–45 min, 1 drink)`() {
        let peakT = PKModel.zeroOrderPeakMinutes(doseMg: oneDrinkMg, kinetics: ethanol)
        #expect(peakT > 25 && peakT < 50)
    }

    // MARK: - The two defining properties

    @Test
    func `Duration scales with dose — 4 drinks clears ≈ 4× longer than 1`() {
        let one = PKModel.zeroOrderClearMinutes(doseMg: oneDrinkMg, kinetics: ethanol)
        let four = PKModel.zeroOrderClearMinutes(doseMg: 4 * oneDrinkMg, kinetics: ethanol)
        #expect(one > 100 && one < 170) // ≈ F·D/Vmax = 132 min + absorption
        // Clearance time is dominated by F·D/Vmax (linear in dose); 4× dose ≈ 4× the linear part.
        let ratio = four / one
        #expect(ratio > 3.3 && ratio < 4.2)
    }

    @Test
    func `Duration scales inversely with body weight — a heavier body clears the same dose faster`() {
        let dose = 8 * oneDrinkMg // a heavy night, absorption long complete before clearance
        let at60 = PKModel.zeroOrderClearMinutes(doseMg: dose, kinetics: PKModel.ethanolZeroOrder(weightKg: 60))
        let at120 = PKModel.zeroOrderClearMinutes(doseMg: dose, kinetics: PKModel.ethanolZeroOrder(weightKg: 120))
        #expect(at120 < at60)
        // Vmax ∝ weight ⇒ clear time ≈ F·D/Vmax ∝ 1/weight; doubling weight ≈ halves it.
        let ratio = at60 / at120
        #expect(ratio > 1.8 && ratio < 2.15)
    }

    @Test
    func `Reference weight reproduces the canonical 95 mg per min kinetics`() {
        #expect(PKModel.ethanolZeroOrder(weightKg: 60) == PKModel.ethanolZeroOrder)
        #expect(abs(PKModel.ethanolZeroOrder(weightKg: 60).vmaxMgPerMin - 95) < 1e-9)
        // Out-of-range weights clamp to the 20–300 kg band rather than producing a degenerate curve.
        #expect(PKModel.ethanolZeroOrder(weightKg: 5).vmaxMgPerMin == PKModel.ethanolZeroOrder(weightKg: 20).vmaxMgPerMin)
        #expect(PKModel.ethanolZeroOrder(weightKg: 999).vmaxMgPerMin == PKModel.ethanolZeroOrder(weightKg: 300).vmaxMgPerMin)
    }

    @Test
    func `Decline is linear — second difference on the descending limb is ≈ 0`() throws {
        // Four drinks: clears in ~9 h, so 200/300/400 min all sit on the post-absorption descending limb.
        let dose = 4 * oneDrinkMg
        let a = try #require(PKModel.zeroOrderShape(doseMg: dose, at: 200, kinetics: ethanol))
        let b = try #require(PKModel.zeroOrderShape(doseMg: dose, at: 300, kinetics: ethanol))
        let c = try #require(PKModel.zeroOrderShape(doseMg: dose, at: 400, kinetics: ethanol))
        #expect(a > b && b > c) // monotone decline
        // Linear ⇒ equal spacing has equal drops ⇒ curvature (b - (a+c)/2) ≈ 0.
        let curvature = abs(b - (a + c) / 2)
        #expect(curvature < 0.01)
    }

    @Test
    func `Contrast: a first-order exponential decline is visibly convex, not linear`() {
        // Sanity anchor — an exponential over the same window has non-trivial curvature, proving the
        // linearity assertion above is a real property of the zero-order model, not a loose tolerance.
        let ke = PKModel.ke(fromHalfLifeMinutes: 120)
        func exp01(_ t: Double) -> Double {
            exp(-ke * t)
        }
        let curvature = abs(exp01(300) - (exp01(200) + exp01(400)) / 2)
        #expect(curvature > 0.025) // ≈ 0.030 — a clear 3× the zero-order limb's < 0.01
    }

    // MARK: - Timeline integration

    @Test
    func `effectShape uses the zero-order curve for alcohol, scaling extent with dose`() {
        let one = alcohol(grams: 14)
        let four = alcohol(grams: 56)
        let extentOne = TimelineCurveModel.curveExtent(for: one)
        let extentFour = TimelineCurveModel.curveExtent(for: four)
        // Phase windows are identical for both states; only the zero-order dose differs.
        #expect(extentFour > extentOne * 3)
        // Both peak at full strength (normalized), and the larger dose still has effect where the
        // smaller has cleared — the duration difference is real, not just a height difference.
        let peakOne = (stride(from: 0.0, through: extentOne, by: 2).map {
            TimelineCurveModel.effectShape(at: $0, for: one)
        }.max() ?? 0)
        #expect(peakOne > 0.99)
        #expect(TimelineCurveModel.effectShape(at: extentOne + 30, for: one) == 0)
        #expect(TimelineCurveModel.effectShape(at: extentOne + 30, for: four) > 0.1)
    }

    @Test
    func `Non-mass units fall back rather than mistaking drink mL for ethanol mg`() {
        #expect(TimelineCurveModel.zeroOrderDoseMilligrams(amount: 500, unit: "mL") == nil)
        #expect(TimelineCurveModel.zeroOrderDoseMilligrams(amount: 14, unit: "g") == 14_000)
        #expect(TimelineCurveModel.zeroOrderDoseMilligrams(amount: 14_000, unit: "mg") == 14_000)
    }

    @Test
    func `ethanol kinetics stay in lockstep with the ceiling tool's SaturablePharmacology profile`() throws {
        let profile = try #require(SaturablePharmacology.profile(forSubstanceName: "Alcohol")?.kinetics)
        #expect(profile.bioavailability == ethanol.bioavailability)
        #expect(profile.ka == ethanol.ka)
        if case let .wholeBodyMgPerMin(vmax) = profile.vmax {
            #expect(vmax == ethanol.vmaxMgPerMin)
        } else {
            Issue.record("ethanol Vmax should be expressed whole-body mg/min")
        }
    }
}
