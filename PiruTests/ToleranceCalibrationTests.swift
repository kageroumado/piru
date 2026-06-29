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
    /// dose-relative gate is exercisable. The default tight Kᵢ + a class-typical Vd/half-life make
    /// occupancy strongly saturating (≈0.9 even at a third of the heavy dose), which is exactly the
    /// saturation that the escalation gate has to see *through*. `halfMaxNanomolar` is overridable so
    /// the safety-endpoint contrast test can use a looser Kᵢ — a moderate representative occupancy
    /// where ``ClassTolerance/responseFraction`` is a sensitive gauge of the right-shift.
    static func stimulant(referenceDoseMg: Double?, halfMaxNanomolar: Double = 20) -> PharmacologyParameters {
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
                .init(target: "DAT", action: .reuptakeInhibitor, halfMaxNanomolar: halfMaxNanomolar, kind: .ki, confidence: .high),
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

    /// A synthetic **psychedelic** substance (5-HT2A agonist) — an *endpoint-less* class, used to
    /// assert that classes without a differential safety endpoint report `nil` (Stage C).
    static func psychedelic(referenceDoseMg: Double?) -> PharmacologyParameters {
        PharmacologyParameters(
            substanceName: "TestPsychedelic",
            molarMassGramsPerMole: 300,
            vdLPerKg: 4,
            bioavailabilityFraction: 1,
            bioavailabilityConfidence: .high,
            doseScale: 1,
            doseScaleConfidence: .high,
            halfLifeMinutes: 180,
            vdConfidence: .high,
            referenceDoseMg: referenceDoseMg,
            targets: [
                .init(target: "5-HT2A", action: .agonist, halfMaxNanomolar: 10, kind: .ki, confidence: .high),
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

    // MARK: - 6. Opioid analgesia tolerizes more than respiratory (the safety gap)

    @Test
    func `Opioid analgesia tolerizes more than the respiratory safety endpoint`() throws {
        let params = ["TestOpioid": Self.opioid(referenceDoseMg: 30)]
        // Heavy opioid (5× the heavy ceiling) daily for 20 d → analgesia's deeper, slower-recovering
        // shift outruns the shallower respiratory endpoint (ceiling 1.0 vs 2.0, no deep layer).
        let states = ToleranceStore.simulate(
            doses: Self.dailyDoses("TestOpioid", mg: 150, days: 20),
            params: params, now: Self.now, weightKg: 70,
        )
        let opioid = try #require(states[.muOpioid])

        let safetyShiftFactor = try #require(opioid.safetyShiftFactor)
        #expect(opioid.safetyEndpointKind == .respiratory)
        // The desired (analgesic) right-shift is clearly ahead of the respiratory endpoint's.
        #expect(opioid.shiftFactor > safetyShiftFactor * 1.1)
        let safetyGap = try #require(opioid.safetyGap)
        #expect(safetyGap > 1) // analgesia more toleranced than respiratory protection
    }

    // MARK: - 7. Respiratory recovers faster than analgesia after a break

    @Test
    func `Opioid respiratory endpoint recovers faster than the analgesic adaptive shift`() throws {
        let params = ["TestOpioid": Self.opioid(referenceDoseMg: 30)]
        // Last dose 24 h before the cessation reading, so both acute layers are already negligible and
        // the readings compare the days-scale adaptive shifts cleanly.
        let doses = Self.dailyDoses("TestOpioid", mg: 150, days: 20, endingHoursBeforeNow: 24)
        let atCessation = ToleranceStore.simulate(doses: doses, params: params, now: Self.now, weightKg: 70)
        // Same history, read 12 d later with no further doses — a pure idle decay span.
        let twelveDaysLater = Self.now.addingTimeInterval(12 * 86_400)
        let afterBreak = ToleranceStore.simulate(doses: doses, params: params, now: twelveDaysLater, weightKg: 70)

        let cessation = try #require(atCessation[.muOpioid])
        let recovered = try #require(afterBreak[.muOpioid])

        // Respiratory ln-shift = log(safetyShiftFactor); analgesic ln-shift = the adaptive layer (its
        // τ-20 d partner of the τ-10 d respiratory adaptive).
        let respiratoryCessation = Foundation.log(try #require(cessation.safetyShiftFactor))
        let respiratoryAfter = Foundation.log(try #require(recovered.safetyShiftFactor))
        #expect(cessation.sAdaptive > 0)
        #expect(respiratoryCessation > 0)

        let respiratoryDecayRatio = respiratoryAfter / respiratoryCessation
        let analgesicDecayRatio = recovered.sAdaptive / cessation.sAdaptive
        // τ 10 d ⇒ exp(−12/10) ≈ 0.30 vs τ 20 d ⇒ exp(−12/20) ≈ 0.55 — respiratory has decayed to a
        // smaller fraction of its cessation value (the reset-after-break overdose raw material).
        #expect(respiratoryDecayRatio < analgesicDecayRatio)
    }

    // MARK: - 8. Stimulant: the high tolerizes, the cardiovascular pressor does not

    @Test
    func `Stimulant high tolerizes while the cardiovascular endpoint does not`() throws {
        // A looser Kᵢ gives a moderate representative occupancy, so responseFraction is a sensitive
        // gauge of the right-shift (the tight-Kᵢ default saturates the gauge ≈1 regardless of S).
        let params = ["TestStimulant": Self.stimulant(referenceDoseMg: 60, halfMaxNanomolar: 2500)]
        // Heavy escalated dosing (5× the heavy ceiling) daily 90 d → the high tolerizes (deep engages),
        // so the user feels less than the naïve effect; the pressor endpoint never tolerizes.
        let states = ToleranceStore.simulate(
            doses: Self.dailyDoses("TestStimulant", mg: 300, days: 90),
            params: params, now: Self.now, weightKg: 70,
        )
        let stim = try #require(states[.catecholamineStimulant])

        #expect(stim.responseFraction < 0.9) // the subjective high is meaningfully toleranced
        let safetyShiftFactor = try #require(stim.safetyShiftFactor)
        #expect(stim.safetyEndpointKind == .cardiovascular)
        #expect(abs(safetyShiftFactor - 1) < 1e-3) // the pressor does not tolerize ⇒ shift ≡ 1
        let safetyGap = try #require(stim.safetyGap)
        #expect(safetyGap > 1) // the high has pulled ahead of the un-toleranced pressor
        #expect(abs(safetyGap - stim.shiftFactor) < 1e-9) // safetyShiftFactor ≈ 1 ⇒ gap ≈ shiftFactor
    }

    // MARK: - 9. Endpoint-less classes report nil

    @Test
    func `A class without a safety endpoint reports nil`() throws {
        let params = ["TestPsychedelic": Self.psychedelic(referenceDoseMg: 0.2)]
        let states = ToleranceStore.simulate(
            doses: Self.dailyDoses("TestPsychedelic", mg: 1, days: 5),
            params: params, now: Self.now, weightKg: 70,
        )
        let psychedelic = try #require(states[.psychedelic5HT2A])
        #expect(psychedelic.safetyShiftFactor == nil)
        #expect(psychedelic.safetyEndpointKind == nil)
        #expect(psychedelic.safetyGap == nil)
    }
}
