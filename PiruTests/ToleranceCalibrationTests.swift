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
            suppressesSerotoninSynthesis: false,
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
            suppressesSerotoninSynthesis: false,
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
            suppressesSerotoninSynthesis: false,
            targets: [
                .init(target: "5-HT2A", action: .agonist, halfMaxNanomolar: 10, kind: .ki, confidence: .high),
            ],
        )
    }

    /// A synthetic **SERT releaser** (5-HT releasing agent) for the Stage E synthesis split. PK-complete
    /// and routed to ``ReceptorClasses/ReceptorClass/serotonergicReleaser`` via the releasing-agent
    /// action; differs only in ``PharmacologyParameters/suppressesSerotoninSynthesis`` so the two test
    /// substances exercise the same class on two recovery clocks (MDMA-type weeks vs 4-MMC-type days).
    static func serotoninReleaser(
        name: String, referenceDoseMg: Double?, suppressesSynthesis: Bool, halfMaxNanomolar: Double = 200,
    ) -> PharmacologyParameters {
        PharmacologyParameters(
            substanceName: name,
            molarMassGramsPerMole: 193,
            vdLPerKg: 5,
            bioavailabilityFraction: 1,
            bioavailabilityConfidence: .high,
            doseScale: 1,
            doseScaleConfidence: .high,
            halfLifeMinutes: 420,
            vdConfidence: .high,
            referenceDoseMg: referenceDoseMg,
            suppressesSerotoninSynthesis: suppressesSynthesis,
            targets: [
                .init(target: "SERT", action: .releasingAgent, halfMaxNanomolar: halfMaxNanomolar, kind: .ec50, confidence: .high),
            ],
        )
    }

    // MARK: - Synthetic pharmacology (Stage D missing-PK fallback)

    /// A **PK-less** benzodiazepine surrogate: a GABA-A PAM target but no Vd / F / half-life / molar
    /// mass, so ``PharmacologyParameters/canComputeOccupancy`` is false. The Stage D fallback must
    /// model it as the Diazepam representative at a dose-fraction-equivalent dose.
    static func pkLessBenzo(name: String = "RC-Benzo", referenceDoseMg: Double?) -> PharmacologyParameters {
        PharmacologyParameters(
            substanceName: name,
            molarMassGramsPerMole: nil,
            vdLPerKg: nil,
            bioavailabilityFraction: nil,
            bioavailabilityConfidence: .unverified,
            doseScale: 1,
            doseScaleConfidence: .high,
            halfLifeMinutes: nil,
            vdConfidence: .unverified,
            referenceDoseMg: referenceDoseMg,
            suppressesSerotoninSynthesis: false,
            targets: [
                .init(target: "GABA-A", action: .positiveAllostericModulator, halfMaxNanomolar: 50, kind: .ki, confidence: .low),
            ],
        )
    }

    /// A PK-complete **Diazepam** representative (GABA-A PAM) — the class stand-in the GABA fallback
    /// resolves `ToleranceStore.classRepresentative[.gaba]` to.
    static func diazepam(referenceDoseMg: Double) -> PharmacologyParameters {
        PharmacologyParameters(
            substanceName: "Diazepam",
            molarMassGramsPerMole: 285,
            vdLPerKg: 1.1,
            bioavailabilityFraction: 1,
            bioavailabilityConfidence: .high,
            doseScale: 1,
            doseScaleConfidence: .high,
            halfLifeMinutes: 2_880,
            vdConfidence: .high,
            referenceDoseMg: referenceDoseMg,
            suppressesSerotoninSynthesis: false,
            targets: [
                .init(target: "GABA-A", action: .positiveAllostericModulator, halfMaxNanomolar: 50, kind: .ki, confidence: .high),
            ],
        )
    }

    /// A **PK-less** opioid surrogate named so the CDC MME table (``ToleranceStore/opioidMMEPerMg``)
    /// can recognise it — a MOR agonist with no PK. The Stage D fallback models it as Morphine.
    static func pkLessOpioid(name: String, referenceDoseMg: Double?) -> PharmacologyParameters {
        PharmacologyParameters(
            substanceName: name,
            molarMassGramsPerMole: nil,
            vdLPerKg: nil,
            bioavailabilityFraction: nil,
            bioavailabilityConfidence: .unverified,
            doseScale: 1,
            doseScaleConfidence: .high,
            halfLifeMinutes: nil,
            vdConfidence: .unverified,
            referenceDoseMg: referenceDoseMg,
            suppressesSerotoninSynthesis: false,
            targets: [
                .init(target: "MOR", action: .agonist, halfMaxNanomolar: 50, kind: .ki, confidence: .low),
            ],
        )
    }

    /// A PK-complete **Morphine** representative (MOR agonist) — `classRepresentative[.muOpioid]`.
    static func morphine(referenceDoseMg: Double) -> PharmacologyParameters {
        PharmacologyParameters(
            substanceName: "Morphine",
            molarMassGramsPerMole: 285,
            vdLPerKg: 3,
            bioavailabilityFraction: 1,
            bioavailabilityConfidence: .high,
            doseScale: 1,
            doseScaleConfidence: .high,
            halfLifeMinutes: 180,
            vdConfidence: .high,
            referenceDoseMg: referenceDoseMg,
            suppressesSerotoninSynthesis: false,
            targets: [
                .init(target: "MOR", action: .agonist, halfMaxNanomolar: 50, kind: .ki, confidence: .high),
            ],
        )
    }

    /// A **PK-less** cannabinoid surrogate (CB1 agonist) whose class has **no** representative —
    /// the unmodelable case that must stay listed as incomplete data.
    static func pkLessCannabinoid(name: String = "RC-Cannabinoid", referenceDoseMg: Double?) -> PharmacologyParameters {
        PharmacologyParameters(
            substanceName: name,
            molarMassGramsPerMole: nil,
            vdLPerKg: nil,
            bioavailabilityFraction: nil,
            bioavailabilityConfidence: .unverified,
            doseScale: 1,
            doseScaleConfidence: .high,
            halfLifeMinutes: nil,
            vdConfidence: .unverified,
            referenceDoseMg: referenceDoseMg,
            suppressesSerotoninSynthesis: false,
            targets: [
                .init(target: "CB1", action: .agonist, halfMaxNanomolar: 50, kind: .ki, confidence: .low),
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

    // MARK: - 10. PK-less benzo still builds GABA tolerance via the Diazepam representative

    @Test
    func `A PK-less benzo still accrues GABA tolerance, modeled as the Diazepam representative`() throws {
        // RC-Benzo: GABA-A PAM, 5 mg heavy ceiling, no PK. Diazepam: PK-complete, 30 mg heavy ceiling.
        // 10 mg/day RC-Benzo → dose-fraction equiv (10/5)·30 = 60 mg diazepam → real GABA right-shift.
        let params = [
            "RC-Benzo": Self.pkLessBenzo(referenceDoseMg: 5),
            "Diazepam": Self.diazepam(referenceDoseMg: 30),
        ]
        let states = ToleranceStore.simulate(
            doses: Self.dailyDoses("RC-Benzo", mg: 10, days: 14),
            params: params, now: Self.now, weightKg: 70,
        )
        let gaba = try #require(states[.gaba]) // previously dropped → only in incompleteData
        #expect(gaba.responseFraction < 1) // the surrogate exposure produced a right-shift
        #expect(gaba.shiftFactor > 1)
        #expect(gaba.confidence == .unverified) // dose-fraction surrogate → unverified floor
        #expect(gaba.contributors == ["RC-Benzo"]) // the user's logged name, not the representative's

        // And it is no longer reported as incomplete data — the fallback can model it.
        let incomplete = ToleranceStore.incompleteData(
            doses: Self.dailyDoses("RC-Benzo", mg: 10, days: 14), params: params, now: Self.now,
        )
        #expect(!incomplete.contains("RC-Benzo"))
    }

    // MARK: - 11. Dose-fraction sanity: surrogate at the heavy ceiling ≈ the representative at its own

    @Test
    func `A PK-less benzo at its own heavy ceiling matches Diazepam dosed at the representative ceiling`() throws {
        let params = [
            "RC-Benzo": Self.pkLessBenzo(referenceDoseMg: 5),
            "Diazepam": Self.diazepam(referenceDoseMg: 30),
        ]
        // RC-Benzo at 5 mg (= its heavy ceiling) ⇒ equiv (5/5)·30 = 30 mg diazepam.
        let surrogate = ToleranceStore.simulate(
            doses: Self.dailyDoses("RC-Benzo", mg: 5, days: 14),
            params: params, now: Self.now, weightKg: 70,
        )
        // Diazepam logged directly at 30 mg (= the representative's heavy ceiling).
        let direct = ToleranceStore.simulate(
            doses: Self.dailyDoses("Diazepam", mg: 30, days: 14),
            params: params, now: Self.now, weightKg: 70,
        )
        let surrogateGaba = try #require(surrogate[.gaba])
        let directGaba = try #require(direct[.gaba])
        // Same PK, same dose, same schedule ⇒ the right-shift matches (it is literally the
        // representative's contribution, only the logged name and confidence floor differ).
        #expect(abs(surrogateGaba.shiftFactor - directGaba.shiftFactor) < 1e-6)
    }

    // MARK: - 12. MME path: a named opioid uses its CDC morphine-equivalent at the .low floor

    @Test
    func `A named PK-less opioid is modeled at its CDC morphine-milligram-equivalent`() throws {
        let params = [
            "oxycodone": Self.pkLessOpioid(name: "oxycodone", referenceDoseMg: 20),
            "Morphine": Self.morphine(referenceDoseMg: 60),
        ]
        // oxycodone MME = 1.5 ⇒ a 30 mg dose is modeled as Morphine at 45 mg. The named-opioid path
        // carries the .low floor (a principled equivalence), not the .unverified dose-fraction floor.
        let states = ToleranceStore.simulate(
            doses: Self.dailyDoses("oxycodone", mg: 30, days: 14),
            params: params, now: Self.now, weightKg: 70,
        )
        let opioid = try #require(states[.muOpioid])
        #expect(opioid.shiftFactor > 1)
        #expect(opioid.confidence == .low) // MME equivalence floor, above dose-fraction's unverified
        #expect(opioid.contributors == ["oxycodone"])

        // Cross-check the morphine-equivalent magnitude: the same exposure as logging Morphine at the
        // 1.5× dose directly (45 mg) — the MME path is exactly "model as Morphine at dose × factor".
        let viaMorphine = ToleranceStore.simulate(
            doses: Self.dailyDoses("Morphine", mg: 45, days: 14),
            params: params, now: Self.now, weightKg: 70,
        )
        let morphineGaba = try #require(viaMorphine[.muOpioid])
        #expect(abs(opioid.shiftFactor - morphineGaba.shiftFactor) < 1e-6)
    }

    // MARK: - 13. No representative ⇒ stays incomplete, builds nothing

    @Test
    func `A PK-less substance whose class has no representative builds nothing and stays incomplete`() throws {
        // CB1 has no class representative, so the fallback can't model it.
        let params = ["RC-Cannabinoid": Self.pkLessCannabinoid(referenceDoseMg: 10)]
        let doses = Self.dailyDoses("RC-Cannabinoid", mg: 20, days: 14)
        let states = ToleranceStore.simulate(doses: doses, params: params, now: Self.now, weightKg: 70)
        #expect(states[.cannabinoidCB1] == nil) // no surrogate contributors → no card
        #expect(states.isEmpty)

        let incomplete = ToleranceStore.incompleteData(doses: doses, params: params, now: Self.now)
        #expect(incomplete.contains("RC-Cannabinoid")) // honestly surfaced as "can't predict yet"
    }

    // MARK: - 14. Serotonin-synthesis split: MDMA-type recovers over weeks, 4-MMC-type over days (Stage E)

    @Test
    func `A synthesis-suppressing entactogen retains a far larger right-shift than a cathinone releaser after ten days`() throws {
        // Two SERT releasers, identical PK, differing only in the synthesis flag — same class, two clocks.
        let params = [
            "TestMDMA": Self.serotoninReleaser(name: "TestMDMA", referenceDoseMg: 120, suppressesSynthesis: true),
            "TestMephedrone": Self.serotoninReleaser(name: "TestMephedrone", referenceDoseMg: 150, suppressesSynthesis: false),
        ]
        // A single dose of each, one hour before the reference instant; the SAME history is read 1 d and
        // 10 d later (pure idle decay), so the only thing that diverges is the slow synthesis pool.
        let mdmaDose = Self.dailyDoses("TestMDMA", mg: 100, days: 1)
        let mephedroneDose = Self.dailyDoses("TestMephedrone", mg: 100, days: 1)
        func shift(_ doses: [ToleranceStore.SimDose], at now: Date) throws -> Double {
            let states = ToleranceStore.simulate(doses: doses, params: params, now: now, weightKg: 70)
            return try #require(states[.serotonergicReleaser]).shiftFactor
        }
        let oneDay = Self.now.addingTimeInterval(86_400)
        let tenDays = Self.now.addingTimeInterval(10 * 86_400)
        let mdma1d = try shift(mdmaDose, at: oneDay)
        let mmc1d = try shift(mephedroneDose, at: oneDay)
        let mdma10d = try shift(mdmaDose, at: tenDays)
        let mmc10d = try shift(mephedroneDose, at: tenDays)

        #expect(mdma1d > 1 && mmc1d > 1 && mdma10d > 1 && mmc10d > 1) // residual shift remains throughout

        // Comparable when fresh: at +1 d both are dominated by the shared fast acute/adaptive pools.
        let ratioFresh = (mdma1d - 1) / (mmc1d - 1)
        #expect(ratioFresh < 2)

        // The slow synthesis pool (τ≈14 d) outlives the fast adaptive pool (τ≈4 d), so the MDMA-type
        // substance pulls proportionally further ahead as the days pass — and is absolutely larger at +10 d.
        let ratioAfterTenDays = (mdma10d - 1) / (mmc10d - 1)
        #expect(ratioAfterTenDays > ratioFresh)
        #expect(mdma10d > mmc10d)
    }

    // MARK: - 15. The synthesis pool is gated by the per-substance flag

    @Test
    func `The synthesis pool accrues only for a synthesis-suppressing substance`() throws {
        let params = [
            "TestMDMA": Self.serotoninReleaser(name: "TestMDMA", referenceDoseMg: 120, suppressesSynthesis: true),
            "TestMephedrone": Self.serotoninReleaser(name: "TestMephedrone", referenceDoseMg: 150, suppressesSynthesis: false),
        ]
        let mdma = ToleranceStore.simulate(
            doses: Self.dailyDoses("TestMDMA", mg: 100, days: 3), params: params, now: Self.now, weightKg: 70,
        )
        let mephedrone = ToleranceStore.simulate(
            doses: Self.dailyDoses("TestMephedrone", mg: 100, days: 3), params: params, now: Self.now, weightKg: 70,
        )
        let mdmaState = try #require(mdma[.serotonergicReleaser])
        let mephedroneState = try #require(mephedrone[.serotonergicReleaser])

        #expect(mdmaState.sSynthesis > 0) // the suppressor drives the slow synthesis pool
        #expect(mephedroneState.sSynthesis == 0) // the cathinone releaser spares synthesis → no slow pool
        // The fast pools build the same for both (same PK + occupancy) — only the synthesis layer differs.
        #expect(abs(mdmaState.sAdaptive - mephedroneState.sAdaptive) < 1e-9)
    }

    // MARK: - 16. A non-SERT class never accrues the synthesis pool

    @Test
    func `A non-SERT class never accrues the synthesis pool`() throws {
        // The stimulant class has `synthesisShiftMax == 0`, so its synthesis layer is inert regardless.
        let params = ["TestStimulant": Self.stimulant(referenceDoseMg: 60)]
        let states = ToleranceStore.simulate(
            doses: Self.dailyDoses("TestStimulant", mg: 40, days: 10), params: params, now: Self.now, weightKg: 70,
        )
        let stim = try #require(states[.catecholamineStimulant])
        #expect(stim.sSynthesis == 0)
    }
}
