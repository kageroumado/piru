import Foundation
import Testing
@testable import Piru

/// Calibration sanity gate for the **dose-relative deep tolerance gate** (Stage B). These pin the
/// headline behaviours the redesign exists to fix — the framework that "improves the math" — by
/// running the pure ``ToleranceStore/simulate(doses:params:now:weightKg:timestepMinutes:lookbackDays:)``
/// core over *synthetic* ``PharmacologyParameters`` with a known `referenceDoseMg`, so the assertions
/// depend on the model alone (not on bundled-DB numbers that may drift).
///
/// The load-bearing claim: transporter occupancy saturates, so therapeutic and heavy dosing look
/// identical at the receptor — only **dose ÷ the substance's heavy ceiling** distinguishes
/// "significant escalation". The deep layer must therefore stay off for therapeutic dosing (the
/// Stage-A bug) and engage only on sustained escalation above the heavy ceiling.
@Suite("Tolerance calibration")
@MainActor
struct ToleranceCalibrationTests {
    static let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Synthetic pharmacology

    /// A synthetic **stimulant-class** substance (DAT reuptake inhibitor) with a deep layer, so the
    /// dose-relative gate is exercisable. Tight Kᵢ + a class-typical Vd/half-life make occupancy
    /// strongly saturating (≈0.9 even at a third of the heavy dose), which is exactly the saturation
    /// that the escalation gate has to see *through*.
    static func stimulant(referenceDoseMg: Double?) -> PharmacologyParameters {
        PharmacologyParameters(
            substanceName: "TestStimulant",
            molarMassGramsPerMole: 135,
            vdLPerKg: 4,
            bioavailabilityFraction: 1,
            bioavailabilityConfidence: .high,
            doseScale: 1,
            doseScaleConfidence: .high,
            halfLifeMinutes: 600,
            vdConfidence: .high,
            referenceDoseMg: referenceDoseMg,
            targets: [
                .init(target: "DAT", action: .reuptakeInhibitor, halfMaxNanomolar: 20, kind: .ki, confidence: .high),
            ],
        )
    }

    /// A synthetic **μ-opioid** substance (MOR agonist), for the recovery half-life calibration —
    /// the opioid adaptive layer carries the months-scale τ≈20 d (recovery t½ ≈ 14 d).
    static func opioid(referenceDoseMg: Double?) -> PharmacologyParameters {
        PharmacologyParameters(
            substanceName: "TestOpioid",
            molarMassGramsPerMole: 285,
            vdLPerKg: 3,
            bioavailabilityFraction: 1,
            bioavailabilityConfidence: .high,
            doseScale: 1,
            doseScaleConfidence: .high,
            halfLifeMinutes: 180,
            vdConfidence: .high,
            referenceDoseMg: referenceDoseMg,
            targets: [
                .init(target: "MOR", action: .agonist, halfMaxNanomolar: 50, kind: .ki, confidence: .high),
            ],
        )
    }

    /// `days` once-daily doses of `substance`, the most recent ending `endingHoursBeforeNow` before
    /// the supplied reference instant.
    static func dailyDoses(
        _ substance: String, mg: Double, days: Int, endingHoursBeforeNow: Double = 1, relativeTo reference: Date = now,
    ) -> [ToleranceStore.SimDose] {
        (0 ..< days).map { dayIndex in
            let daysBack = Double(days - 1 - dayIndex)
            let timestamp = reference.addingTimeInterval(-daysBack * 86_400 - endingHoursBeforeNow * 3_600)
            return ToleranceStore.SimDose(substance: substance, amountMg: mg, timestamp: timestamp)
        }
    }

    // MARK: - 1. ADHD therapeutic → no deep

    @Test
    func `Therapeutic stimulant dosing (a third of the heavy ceiling) never engages the deep layer`() throws {
        // 20 mg daily for 30 d against a 60 mg heavy ceiling → escalation 0.33, far below the 2× gate.
        let params = ["TestStimulant": Self.stimulant(referenceDoseMg: 60)]
        let states = ToleranceStore.simulate(
            doses: Self.dailyDoses("TestStimulant", mg: 20, days: 30),
            params: params, now: Self.now, weightKg: 70,
        )
        let stim = try #require(states[.catecholamineStimulant])
        #expect(stim.sDeep < 1e-6) // the gate is closed → the deep layer stays at naïve
    }

    // MARK: - 2. Heavy escalation → deep engages

    @Test
    func `Heavy escalation above the heavy ceiling engages the deep layer`() throws {
        let params = ["TestStimulant": Self.stimulant(referenceDoseMg: 60)]
        // 300 mg daily for 30 d → escalation 5×, past the full gate band → the deep layer accrues.
        let heavy = ToleranceStore.simulate(
            doses: Self.dailyDoses("TestStimulant", mg: 300, days: 30),
            params: params, now: Self.now, weightKg: 70,
        )
        let therapeutic = ToleranceStore.simulate(
            doses: Self.dailyDoses("TestStimulant", mg: 20, days: 30),
            params: params, now: Self.now, weightKg: 70,
        )
        let heavyStim = try #require(heavy[.catecholamineStimulant])
        let therapeuticStim = try #require(therapeutic[.catecholamineStimulant])

        #expect(heavyStim.sDeep > 0) // escalation crosses the gate → deep entrenches
        #expect(heavyStim.sDeep > therapeuticStim.sDeep) // and far more than the therapeutic case
        #expect(heavyStim.shiftFactor > therapeuticStim.shiftFactor) // total right-shift is larger too
    }

    // MARK: - 3. Opioid recovery ≈ 14-day half-life

    @Test
    func `Opioid adaptive shift halves over roughly two weeks of abstinence`() throws {
        let params = ["TestOpioid": Self.opioid(referenceDoseMg: 30)]
        // Heavy opioid daily for 20 d, then stop. Compare the adaptive shift at cessation vs 14 d later.
        let dosesAtCessation = Self.dailyDoses("TestOpioid", mg: 150, days: 20, relativeTo: Self.now)
        let atCessation = ToleranceStore.simulate(
            doses: dosesAtCessation, params: params, now: Self.now, weightKg: 70,
        )
        // Same dose history, but read 14 d later with no further doses — a pure idle decay span.
        let twoWeeksLater = Self.now.addingTimeInterval(14 * 86_400)
        let afterBreak = ToleranceStore.simulate(
            doses: dosesAtCessation, params: params, now: twoWeeksLater, weightKg: 70,
        )
        let cessation = try #require(atCessation[.muOpioid])
        let recovered = try #require(afterBreak[.muOpioid])

        #expect(cessation.sAdaptive > 0)
        let ratio = recovered.sAdaptive / cessation.sAdaptive
        // τ≈20 d ⇒ exp(−14/20) ≈ 0.497; assert the order of magnitude, not false precision.
        #expect(ratio > 0.4 && ratio < 0.6)
    }

    // MARK: - 4. responseFraction monotonic in the shift

    @Test
    func `Response fraction decreases monotonically as the right-shift grows`() {
        let occupancy = 0.5
        var previous = PDModel.responseFraction(shiftFactor: 1, representativeOccupancy: occupancy)
        #expect(abs(previous - 1) < 1e-12) // naïve → full response
        for shift in stride(from: 1.5, through: 8, by: 0.5) {
            let current = PDModel.responseFraction(shiftFactor: shift, representativeOccupancy: occupancy)
            #expect(current < previous)
            previous = current
        }
    }

    // MARK: - 5. No reference dose ⇒ no deep (conservative fallback)

    @Test
    func `Without a reference dose the deep layer stays closed even at an enormous dose`() throws {
        let params = ["TestStimulant": Self.stimulant(referenceDoseMg: nil)]
        // 10 g daily for 30 d — but with no heavy ceiling the escalation factor is 0, so the gate
        // never opens. The conservative fallback: no deep tolerance without evidence of "heavy".
        let states = ToleranceStore.simulate(
            doses: Self.dailyDoses("TestStimulant", mg: 10_000, days: 30),
            params: params, now: Self.now, weightKg: 70,
        )
        let stim = try #require(states[.catecholamineStimulant])
        #expect(stim.sDeep < 1e-6)
    }
}
