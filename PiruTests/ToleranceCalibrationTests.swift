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
    static func stimulant(
        referenceDoseMg: Double?, halfMaxNanomolar: Double = 20,
        tmaxMinutes: Double? = nil, tmaxConfidence: ConfidenceTier = .unverified,
    ) -> PharmacologyParameters {
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
            tmaxMinutes: tmaxMinutes,
            tmaxConfidence: tmaxConfidence,
        )
    }

    /// A synthetic **μ-opioid** substance (MOR agonist), for the recovery half-life calibration —
    /// the opioid adaptive layer carries the months-scale τ≈20 d (recovery t½ ≈ 14 d).
    static func opioid(referenceDoseMg: Double?, intrinsicEfficacy: Double = 1, halfMaxNanomolar: Double = 50) -> PharmacologyParameters {
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
                .init(target: "MOR", action: .agonist, halfMaxNanomolar: halfMaxNanomolar, kind: .ki, confidence: .high),
            ],
            intrinsicEfficacy: intrinsicEfficacy,
        )
    }

    /// A synthetic **psychedelic** substance (5-HT2A agonist) — an *endpoint-less* class, used to
    /// assert that classes without a differential safety endpoint report `nil` (Stage C).
    static func psychedelic(
        referenceDoseMg: Double?, tmaxMinutes: Double? = nil, tmaxConfidence: ConfidenceTier = .unverified,
    ) -> PharmacologyParameters {
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
            tmaxMinutes: tmaxMinutes,
            tmaxConfidence: tmaxConfidence,
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

    /// A synthetic **adrenergic** substance (Stage F) — a PK-complete stand-in with one adrenergic
    /// target, so the routing and rebound-axis assertions depend on the model alone. `target`/`action`
    /// pick the class: `"α2A adrenergic"`/`.agonist` → α₂-agonist, `"β1 / β2 adrenergic"`/`.antagonist`
    /// → β-blocker.
    static func adrenergic(
        name: String, target: String, action: BindingAction, referenceDoseMg: Double?,
    ) -> PharmacologyParameters {
        PharmacologyParameters(
            substanceName: name,
            molarMassGramsPerMole: 230,
            vdLPerKg: 2.5,
            bioavailabilityFraction: 1,
            bioavailabilityConfidence: .high,
            doseScale: 1,
            doseScaleConfidence: .high,
            halfLifeMinutes: 720,
            vdConfidence: .high,
            referenceDoseMg: referenceDoseMg,
            suppressesSerotoninSynthesis: false,
            targets: [
                .init(target: target, action: action, halfMaxNanomolar: 20, kind: .ki, confidence: .high),
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

    /// A PK-complete **Alprazolam** — a moderate-half-life GABA-A PAM (t½ 11.5 h, 80% protein-bound).
    /// The tighter Kᵢ relative to ``diazepam(referenceDoseMg:)`` reflects the higher per-mg potency;
    /// combined with the lower Vd and shorter half-life it produces a moderate occupancy that exercises
    /// the shift's dynamic range at therapeutic doses (1 mg) without saturating.
    static func alprazolam(referenceDoseMg: Double) -> PharmacologyParameters {
        PharmacologyParameters(
            substanceName: "Alprazolam",
            molarMassGramsPerMole: 309,
            vdLPerKg: 1.0,
            bioavailabilityFraction: 0.9,
            bioavailabilityConfidence: .high,
            doseScale: 1,
            doseScaleConfidence: .high,
            halfLifeMinutes: 690,
            vdConfidence: .high,
            referenceDoseMg: referenceDoseMg,
            suppressesSerotoninSynthesis: false,
            targets: [
                .init(target: "GABA-A", action: .positiveAllostericModulator, halfMaxNanomolar: 15, kind: .ki, confidence: .high),
            ],
        )
    }

    /// A PK-complete **Diazepam** representative (GABA-A PAM) — the class stand-in the GABA fallback
    /// resolves `ToleranceStore.classRepresentative[.gaba]` to.
    static func diazepam(
        referenceDoseMg: Double, metabolites: [PharmacologyParameters.MetaboliteContributor] = [],
    ) -> PharmacologyParameters {
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
            metabolites: metabolites,
        )
    }

    /// The nordazepam active metabolite for the K.5 goldens — t½ ≈ 100 h, equipotent (100% at GABA-A),
    /// fully formed. `mechanism`/`basis` are parameterized so the "divergent does not fold" and
    /// "non-clinical basis floors confidence" cases share one factory.
    static func nordazepamMetabolite(
        mechanism: String = "scaled", basis: String? = "clinical",
    ) -> PharmacologyParameters.MetaboliteContributor {
        .init(
            metaboliteName: "Nordazepam", metaboliteSubstanceName: "Nordazepam",
            halfLifeMinutes: 6_000, formationFractionPct: 100, potencyVsParentPct: 100,
            potencyBasis: basis, mechanismVsParent: mechanism,
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

    /// A **PK-less** psychedelic surrogate (5-HT2A agonist, dose ladder only) — e.g. 4-AcO-DMT. The
    /// Stage D fallback models it as the Psilocin representative.
    static func pkLessPsychedelic(name: String = "RC-Psychedelic", referenceDoseMg: Double?) -> PharmacologyParameters {
        PharmacologyParameters(
            substanceName: name,
            molarMassGramsPerMole: nil, vdLPerKg: nil, bioavailabilityFraction: nil,
            bioavailabilityConfidence: .unverified, doseScale: 1, doseScaleConfidence: .high,
            halfLifeMinutes: nil, vdConfidence: .unverified, referenceDoseMg: referenceDoseMg,
            suppressesSerotoninSynthesis: false,
            targets: [
                .init(target: "5-HT2A", action: .agonist, halfMaxNanomolar: 50, kind: .ki, confidence: .low),
            ],
        )
    }

    /// PK-complete **Psilocin** representative (5-HT2A agonist) — `classRepresentative[.psychedelic5HT2A]`.
    static func psilocin(referenceDoseMg: Double) -> PharmacologyParameters {
        PharmacologyParameters(
            substanceName: "Psilocin",
            molarMassGramsPerMole: 204, vdLPerKg: 4, bioavailabilityFraction: 0.5,
            bioavailabilityConfidence: .high, doseScale: 1, doseScaleConfidence: .high,
            halfLifeMinutes: 120, vdConfidence: .high, referenceDoseMg: referenceDoseMg,
            suppressesSerotoninSynthesis: false,
            targets: [
                .init(target: "5-HT2A", action: .agonist, halfMaxNanomolar: 50, kind: .ki, confidence: .high),
            ],
        )
    }

    /// A **PK-less** dissociative surrogate (NMDA channel blocker, dose ladder only). Fallback → Ketamine.
    static func pkLessDissociative(name: String = "RC-Dissociative", referenceDoseMg: Double?) -> PharmacologyParameters {
        PharmacologyParameters(
            substanceName: name,
            molarMassGramsPerMole: nil, vdLPerKg: nil, bioavailabilityFraction: nil,
            bioavailabilityConfidence: .unverified, doseScale: 1, doseScaleConfidence: .high,
            halfLifeMinutes: nil, vdConfidence: .unverified, referenceDoseMg: referenceDoseMg,
            suppressesSerotoninSynthesis: false,
            targets: [
                .init(target: "NMDA", action: .channelBlocker, halfMaxNanomolar: 50, kind: .ki, confidence: .low),
            ],
        )
    }

    /// PK-complete **Ketamine** representative (NMDA channel blocker) — `classRepresentative[.nmdaAntagonist]`.
    static func ketamine(referenceDoseMg: Double) -> PharmacologyParameters {
        PharmacologyParameters(
            substanceName: "Ketamine",
            molarMassGramsPerMole: 238, vdLPerKg: 2.5, bioavailabilityFraction: 0.2,
            bioavailabilityConfidence: .high, doseScale: 1, doseScaleConfidence: .high,
            halfLifeMinutes: 180, vdConfidence: .high, referenceDoseMg: referenceDoseMg,
            suppressesSerotoninSynthesis: false,
            targets: [
                .init(target: "NMDA", action: .channelBlocker, halfMaxNanomolar: 50, kind: .ki, confidence: .high),
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
        let respiratoryCessation = try Foundation.log(#require(cessation.safetyShiftFactor))
        let respiratoryAfter = try Foundation.log(#require(recovered.safetyShiftFactor))
        #expect(cessation.sAdaptive > 0)
        #expect(respiratoryCessation > 0)

        let respiratoryDecayRatio = respiratoryAfter / respiratoryCessation
        let analgesicDecayRatio = recovered.sAdaptive / cessation.sAdaptive
        // τ 10 d ⇒ exp(−12/10) ≈ 0.30 vs τ 20 d ⇒ exp(−12/20) ≈ 0.55 — respiratory has decayed to a
        // smaller fraction of its cessation value (the reset-after-break overdose raw material).
        #expect(respiratoryDecayRatio < analgesicDecayRatio)
    }

    // MARK: - 8. Stimulant CV = two mechanisms: chronic resting adapts, the acute pressor does not (§6)

    @Test
    func `Stimulant high tolerizes; the chronic cardiovascular endpoint adapts but the acute pressor does not`() throws {
        // A looser Kᵢ gives a moderate representative occupancy, so responseFraction is a sensitive
        // gauge of the right-shift (the tight-Kᵢ default saturates the gauge ≈1 regardless of S).
        let params = ["TestStimulant": Self.stimulant(referenceDoseMg: 60, halfMaxNanomolar: 2_500)]
        // Heavy escalated dosing (5× the heavy ceiling) daily 90 d → the high tolerizes (deep engages),
        // and the CHRONIC resting cardiovascular endpoint adapts over weeks — but less than the high.
        let states = ToleranceStore.simulate(
            doses: Self.dailyDoses("TestStimulant", mg: 300, days: 90),
            params: params, now: Self.now, weightKg: 70,
        )
        let stim = try #require(states[.catecholamineStimulant])

        #expect(stim.responseFraction < 0.9) // the subjective high is meaningfully toleranced
        let safetyShiftFactor = try #require(stim.safetyShiftFactor)
        #expect(stim.safetyEndpointKind == .cardiovascular)
        #expect(safetyShiftFactor > 1) // §6: the chronic resting response adapts over weeks
        #expect(stim.shiftFactor > safetyShiftFactor) // but the high pulls ahead — the redose-toxicity gap
        let safetyGap = try #require(stim.safetyGap)
        #expect(safetyGap > 1)

        // The ACUTE within-session pressor has no pool (acuteShiftMax 0): a single recent dose leaves the
        // endpoint ≈ 1 (no chronic buildup yet), so a user redosing in-session still hits a fresh spike.
        let acute = ToleranceStore.simulate(
            doses: Self.dailyDoses("TestStimulant", mg: 300, days: 1),
            params: params, now: Self.now, weightKg: 70,
        )
        let acuteStim = try #require(acute[.catecholamineStimulant])
        let acuteEndpoint = try #require(acuteStim.safetyShiftFactor)
        #expect(abs(acuteEndpoint - 1) < 0.02) // within-session pressor un-toleranced
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

    @Test
    func `A PK-less psychedelic still accrues 5-HT2A tolerance, modeled as the Psilocin representative`() throws {
        // 4-AcO-DMT-style: a 5-HT2A agonist with a dose ladder but no PK. Without a representative it
        // was stranded in "can't predict yet"; Psilocin now stands in for it.
        let params = [
            "RC-Psychedelic": Self.pkLessPsychedelic(referenceDoseMg: 30),
            "Psilocin": Self.psilocin(referenceDoseMg: 20),
        ]
        let doses = Self.dailyDoses("RC-Psychedelic", mg: 30, days: 5)
        let states = ToleranceStore.simulate(doses: doses, params: params, now: Self.now, weightKg: 70)
        let psychedelic = try #require(states[.psychedelic5HT2A])
        #expect(psychedelic.responseFraction < 1)
        #expect(psychedelic.shiftFactor > 1)
        #expect(psychedelic.confidence == .unverified)
        #expect(psychedelic.contributors == ["RC-Psychedelic"])
        #expect(!ToleranceStore.incompleteData(doses: doses, params: params, now: Self.now).contains("RC-Psychedelic"))
    }

    @Test
    func `A PK-less dissociative still accrues NMDA tolerance, modeled as the Ketamine representative`() throws {
        let params = [
            "RC-Dissociative": Self.pkLessDissociative(referenceDoseMg: 100),
            "Ketamine": Self.ketamine(referenceDoseMg: 150),
        ]
        let doses = Self.dailyDoses("RC-Dissociative", mg: 100, days: 5)
        let states = ToleranceStore.simulate(doses: doses, params: params, now: Self.now, weightKg: 70)
        let nmda = try #require(states[.nmdaAntagonist])
        #expect(nmda.responseFraction < 1)
        #expect(nmda.confidence == .unverified)
        #expect(nmda.contributors == ["RC-Dissociative"])
        #expect(!ToleranceStore.incompleteData(doses: doses, params: params, now: Self.now).contains("RC-Dissociative"))
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
    func `A PK-less substance whose class has no representative builds nothing and stays incomplete`() {
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

    // MARK: - 17. α₂-agonist routes to its class and hosts the rebound axis (Stage F)

    @Test
    func `An α2-adrenergic agonist routes to the alpha2Agonist class and hosts the rebound axis`() throws {
        // Routing is mechanism-gated: the α2 adrenergic target with an agonist action is the class.
        #expect(ReceptorClasses.classify(target: "α2A adrenergic", action: .agonist) == .alpha2Agonist)

        // Dosed → a faint .alpha2Agonist card appears (the adaptive shift exists only to host the warning).
        let params = ["TestClonidine": Self.adrenergic(
            name: "TestClonidine", target: "α2A adrenergic", action: .agonist, referenceDoseMg: 0.3,
        )]
        let states = ToleranceStore.simulate(
            doses: Self.dailyDoses("TestClonidine", mg: 0.2, days: 14),
            params: params, now: Self.now, weightKg: 70,
        )
        let alpha2 = try #require(states[.alpha2Agonist])
        #expect(alpha2.shiftFactor >= 1) // a (faint) right-shift, never a regression below naïve

        // The class hands tolerance off to the α₂ discontinuation-rebound safety axis.
        #expect(ReceptorClasses.parameters(for: .alpha2Agonist).safetyAxis == .alpha2Rebound)
    }

    // MARK: - 18. β-blocker routes to its class and hosts the rebound axis (Stage F)

    @Test
    func `A β-adrenergic antagonist routes to the betaBlocker class and hosts the rebound axis`() throws {
        #expect(ReceptorClasses.classify(target: "β1 / β2 adrenergic", action: .antagonist) == .betaBlocker)

        let params = ["TestPropranolol": Self.adrenergic(
            name: "TestPropranolol", target: "β1 / β2 adrenergic", action: .antagonist, referenceDoseMg: 40,
        )]
        let states = ToleranceStore.simulate(
            doses: Self.dailyDoses("TestPropranolol", mg: 40, days: 14),
            params: params, now: Self.now, weightKg: 70,
        )
        let beta = try #require(states[.betaBlocker])
        #expect(beta.shiftFactor >= 1)

        #expect(ReceptorClasses.parameters(for: .betaBlocker).safetyAxis == .betaRebound)
    }

    // MARK: - 19. α₁-adrenergic is out of scope (no tolerance class)

    @Test
    func `An α1-adrenergic target is not a tolerance class`() {
        // α₁ is a different receptor than the α₂ autoreceptor — deliberately routes to unknown (§3.5).
        #expect(ReceptorClasses.classify(target: "α1 adrenergic", action: .antagonist) == .unknown)
        #expect(ReceptorClasses.classify(target: "α1A adrenergic (human)", action: .agonist) == .unknown)
    }

    // MARK: - 20. GABA-A subunit strings still route to GABA, not the new α₂ branch (regression)

    @Test
    func `A GABA-A subunit string still routes to GABA despite containing α2`() {
        // "GABA-A α2β2γ2" contains both "α2" and "β"; the gaba branch must win (it precedes adrenergic,
        // and the string has no "adrenergic" keyword anyway). A regression here would misroute benzos.
        #expect(ReceptorClasses.classify(target: "GABA-A α2β2γ2", action: .positiveAllostericModulator) == .gaba)
        #expect(ReceptorClasses.classify(target: "GABA-A α1β2γ2", action: .positiveAllostericModulator) == .gaba)
    }

    // MARK: - 20b. A PK-less adrenergic is NOT surfaced as incomplete tolerance data (§3.5 intent)

    @Test
    func `A PK-less adrenergic builds no card and is not listed as incomplete tolerance data`() {
        // Mirrors the real bundled-DB state: clonidine/propranolol have adrenergic targets but no molar
        // mass, so canComputeOccupancy is false and there is no class representative. Unlike a PK-less
        // benzo/opioid (which the fallback models) or a PK-less cannabinoid (honestly "can't predict
        // yet"), the rebound-hosting adrenergics must produce *nothing* — no card, no incomplete flag.
        let params = ["TestClonidine": PharmacologyParameters(
            substanceName: "TestClonidine",
            molarMassGramsPerMole: nil, vdLPerKg: nil, bioavailabilityFraction: nil,
            bioavailabilityConfidence: .unverified, doseScale: 1, doseScaleConfidence: .high,
            halfLifeMinutes: nil, vdConfidence: .unverified, referenceDoseMg: 0.3,
            suppressesSerotoninSynthesis: false,
            targets: [.init(target: "α2A adrenergic", action: .agonist, halfMaxNanomolar: 20, kind: .ki, confidence: .low)],
        )]
        let doses = Self.dailyDoses("TestClonidine", mg: 0.2, days: 14)
        let states = ToleranceStore.simulate(doses: doses, params: params, now: Self.now, weightKg: 70)
        #expect(states[.alpha2Agonist] == nil) // no PK, no representative → no card
        #expect(states.isEmpty)

        let incomplete = ToleranceStore.incompleteData(doses: doses, params: params, now: Self.now)
        #expect(!incomplete.contains("TestClonidine")) // hosts a rebound warning, not a missing prediction
    }

    // MARK: - 21. Real-substance routing smoke (classify-only, no PK needed)

    @Test
    func `Clonidine and propranolol target strings route to their adrenergic classes`() {
        // The verified DB target strings (clonidine α2 agonist/partialAgonist, propranolol β antagonist).
        #expect(ReceptorClasses.classify(target: "α2A adrenergic (rat)", action: .partialAgonist) == .alpha2Agonist)
        #expect(ReceptorClasses.classify(target: "α2-adrenergic", action: .agonist) == .alpha2Agonist)
        #expect(ReceptorClasses.classify(target: "β1 / β2 adrenergic (human)", action: .antagonist) == .betaBlocker)
    }

    // MARK: - 21b. Category fallback: a benzo with NO bindings still drives GABA via its category

    @Test
    func `A categorised benzo with no binding rows still accrues GABA tolerance via its category`() throws {
        // Mirrors Bromazepam in the real DB: full dose ladder, but NO targets at all — so the target
        // path can't classify it. Its Benzodiazepine category alone routes it to GABA → Diazepam.
        let noTargetBenzo = PharmacologyParameters(
            substanceName: "RC-CategoryBenzo",
            molarMassGramsPerMole: 316, vdLPerKg: 1.2, bioavailabilityFraction: 0.84,
            bioavailabilityConfidence: .high, doseScale: 1, doseScaleConfidence: .high,
            halfLifeMinutes: 1_020, vdConfidence: .high, referenceDoseMg: 12,
            suppressesSerotoninSynthesis: false,
            targets: [], // ← the whole point: no receptor rows
            categoryClasses: [.gaba],
        )
        let params = ["RC-CategoryBenzo": noTargetBenzo, "Diazepam": Self.diazepam(referenceDoseMg: 30)]
        let doses = Self.dailyDoses("RC-CategoryBenzo", mg: 12, days: 14)
        let states = ToleranceStore.simulate(doses: doses, params: params, now: Self.now, weightKg: 70)
        let gaba = try #require(states[.gaba]) // previously silently dropped entirely
        #expect(gaba.shiftFactor > 1)
        #expect(gaba.contributors == ["RC-CategoryBenzo"]) // keeps the logged name
        #expect(gaba.confidence == .unverified) // dose-fraction surrogate floor
        // No longer stranded: not surfaced as incomplete, because the category fallback models it.
        #expect(!ToleranceStore.incompleteData(doses: doses, params: params, now: Self.now).contains("RC-CategoryBenzo"))
    }

    @Test
    func `A categorised substance whose class has no representative stays incomplete`() {
        // Category maps to a class (cannabinoid) that has NO representative → can't be modeled → honestly
        // surfaced as "can't predict yet" rather than silently dropped.
        let noTargetCannabinoid = PharmacologyParameters(
            substanceName: "RC-CategoryCannabinoid",
            molarMassGramsPerMole: nil, vdLPerKg: nil, bioavailabilityFraction: nil,
            bioavailabilityConfidence: .unverified, doseScale: 1, doseScaleConfidence: .high,
            halfLifeMinutes: nil, vdConfidence: .unverified, referenceDoseMg: 10,
            suppressesSerotoninSynthesis: false, targets: [], categoryClasses: [.cannabinoidCB1],
        )
        let params = ["RC-CategoryCannabinoid": noTargetCannabinoid]
        let doses = Self.dailyDoses("RC-CategoryCannabinoid", mg: 10, days: 14)
        let states = ToleranceStore.simulate(doses: doses, params: params, now: Self.now, weightKg: 70)
        #expect(states[.cannabinoidCB1] == nil)
        #expect(ToleranceStore.incompleteData(doses: doses, params: params, now: Self.now).contains("RC-CategoryCannabinoid"))
    }

    // MARK: - 22. Chronicity gate (§2): heavy but sustained engages deep; a heavy one-off binge does not

    @Test
    func `A heavy one-off binge stays out of the deep layer while sustained heavy use engages it`() throws {
        let params = ["TestStimulant": Self.stimulant(referenceDoseMg: 60)]
        // Both dose 5× the heavy ceiling, so magnitude is fully open for both — only chronicity differs.
        let sustained = ToleranceStore.simulate(
            doses: Self.dailyDoses("TestStimulant", mg: 300, days: 45),
            params: params, now: Self.now, weightKg: 70,
        )
        let binge = ToleranceStore.simulate(
            doses: Self.dailyDoses("TestStimulant", mg: 300, days: 1), // a single heavy dose
            params: params, now: Self.now, weightKg: 70,
        )
        let sustainedDeep = try #require(sustained[.catecholamineStimulant]).sDeep
        let bingeDeep = try #require(binge[.catecholamineStimulant]).sDeep
        #expect(sustainedDeep > 0) // sustained heavy use crosses the chronicity knee → deep entrenches
        #expect(bingeDeep < 1e-4) // one binge (chronicity ≈ 0) never lights deep, despite full magnitude
        #expect(sustainedDeep > bingeDeep * 100)
    }

    // MARK: - 23. Intrinsic efficacy (§5c): a partial agonist entrenches less per unit occupancy

    @Test
    func `A partial agonist builds a smaller adaptive shift than a full agonist at the same occupancy`() throws {
        // Identical opioids save for intrinsic efficacy — the partial (mitragynine-like) drives less.
        let params = [
            "TestOpioid": Self.opioid(referenceDoseMg: 30, intrinsicEfficacy: 1),
            "PartialOpioid": Self.opioid(referenceDoseMg: 30, intrinsicEfficacy: 0.4),
        ]
        // Rename the second so it routes as its own contributor set.
        var partialParams = params
        partialParams["PartialOpioid"] = PharmacologyParameters(
            substanceName: "PartialOpioid", molarMassGramsPerMole: 285, vdLPerKg: 3,
            bioavailabilityFraction: 1, bioavailabilityConfidence: .high, doseScale: 1,
            doseScaleConfidence: .high, halfLifeMinutes: 180, vdConfidence: .high, referenceDoseMg: 30,
            suppressesSerotoninSynthesis: false,
            targets: [.init(target: "MOR", action: .agonist, halfMaxNanomolar: 50, kind: .ki, confidence: .high)],
            intrinsicEfficacy: 0.4,
        )
        let full = ToleranceStore.simulate(
            doses: Self.dailyDoses("TestOpioid", mg: 60, days: 14), params: partialParams, now: Self.now, weightKg: 70,
        )
        let partial = ToleranceStore.simulate(
            doses: Self.dailyDoses("PartialOpioid", mg: 60, days: 14), params: partialParams, now: Self.now, weightKg: 70,
        )
        let fullAdaptive = try #require(full[.muOpioid]).sAdaptive
        let partialAdaptive = try #require(partial[.muOpioid]).sAdaptive
        #expect(fullAdaptive > 0)
        #expect(partialAdaptive < fullAdaptive) // partial agonist entrenches less per unit occupancy
        #expect(partialAdaptive > 0) // but still builds some tolerance
    }

    // MARK: - 24. Onset confidence (§3): a guessed Tmax badges the prediction down, an absent one doesn't

    @Test
    func `A low-confidence onset caps the class confidence; an absent onset does not`() throws {
        // Uses the psychedelic class (kinetics confidence .medium) so the onset input is the deciding
        // factor. A graded-low Tmax is a guessed input → it caps the class confidence at .low.
        let guessed = ToleranceStore.simulate(
            doses: Self.dailyDoses("TestPsychedelic", mg: 1, days: 3),
            params: ["TestPsychedelic": Self.psychedelic(referenceDoseMg: 0.2, tmaxMinutes: 30, tmaxConfidence: .low)],
            now: Self.now, weightKg: 70,
        )
        #expect(try #require(guessed[.psychedelic5HT2A]).confidence == .low)

        // With no Tmax at all we fall back to 4·ke (unchanged behaviour), so the onset adds no
        // uncertainty and the class keeps its otherwise-higher confidence (the .medium class kinetics).
        let absent = ToleranceStore.simulate(
            doses: Self.dailyDoses("TestPsychedelic", mg: 1, days: 3),
            params: ["TestPsychedelic": Self.psychedelic(referenceDoseMg: 0.2)],
            now: Self.now, weightKg: 70,
        )
        #expect(try #require(absent[.psychedelic5HT2A]).confidence > .low)
    }

    // MARK: - 25. Therapeutic alprazolam → gauge close to full (§H.1)

    @Test
    func `Therapeutic alprazolam builds substantial sedative GABA tolerance`() throws {
        // 1 mg daily for 30 d against a 6 mg heavy ceiling → dose ratio 0.17, far below the deep gate.
        // §B.cal: the primary gauge is now the SEDATIVE endpoint alone (VINK12: sedation tolerizes
        // near-complete), so even at a therapeutic anxiolytic dose the sedative response is roughly
        // halved — the drowsiness fades while the anxiolytic effect (not gauged here) and the
        // cognitive-impairment endpoint (shift ≡ 1) do not tolerize. Baseline ~0.48 response / ~3.9×
        // shift at fu=1 (§A's occupancy correction will temper both).
        let params = ["Alprazolam": Self.alprazolam(referenceDoseMg: 6)]
        let states = ToleranceStore.simulate(
            doses: Self.dailyDoses("Alprazolam", mg: 1, days: 30),
            params: params, now: Self.now, weightKg: 70,
        )
        let gaba = try #require(states[.gaba])
        #expect(gaba.responseFraction > 0.40 && gaba.responseFraction < 0.58)
        #expect(gaba.shiftFactor > 3 && gaba.shiftFactor < 5) // sedative-alone right-shift
        #expect(gaba.sDeep == 0) // GABA deepShiftMax is 0
    }

    // MARK: - 26. Diazepam 14-day course → measurable shift (§H.2 baseline)

    @Test
    func `Diazepam fourteen-day course produces measurable GABA tolerance`() throws {
        // 10 mg daily for 14 d (1/3 of the heavy ceiling). The adaptive layer (τ 14 d) has had one
        // full time-constant to build. §B will split the reading into near-complete sedative +
        // preserved anxiolytic; until then the blended scalar is the golden baseline.
        let params = ["Diazepam": Self.diazepam(referenceDoseMg: 30)]
        let states = ToleranceStore.simulate(
            doses: Self.dailyDoses("Diazepam", mg: 10, days: 14),
            params: params, now: Self.now, weightKg: 70,
        )
        let gaba = try #require(states[.gaba])
        #expect(gaba.shiftFactor > 1) // some tolerance has built
        #expect(gaba.sAdaptive > 0) // the adaptive layer has accrued
        #expect(gaba.sDeep == 0) // GABA deepShiftMax is 0
        #expect(gaba.responseFraction < 1) // not fully naïve
        // §B: the cognitive impairment endpoint does not tolerize (both shiftMax = 0) → its
        // shift factor is always 1 and safetyGap equals the primary shiftFactor.
        #expect(gaba.safetyEndpointKind == .cognitiveImpairment)
        let safetyShift = try #require(gaba.safetyShiftFactor)
        #expect(abs(safetyShift - 1) < 1e-6) // cognitive shift ≡ 1 (no tolerance)
        let gap = try #require(gaba.safetyGap)
        #expect(abs(gap - gaba.shiftFactor) < 1e-6) // gap = primary / 1
    }

    // MARK: - 27. Protein-binding 50× gap visible in occupancy (§H.3)

    @Test
    func `Protein binding produces a dramatic occupancy difference for diazepam`() throws {
        // Diazepam: 98% protein-bound (fu = 0.02). peakPrimaryOccupancy already accepts
        // unboundFraction (Stage 0; the stored field lands in §A). At fu=1 (current engine)
        // occupancy is overestimated — this pins the expected magnitude of the correction.
        let params = Self.diazepam(referenceDoseMg: 30)
        let atFuOne = try #require(
            params.peakPrimaryOccupancy(doseMg: 10, weightKg: 70, unboundFraction: 1),
        )
        let atFuReal = try #require(
            params.peakPrimaryOccupancy(doseMg: 10, weightKg: 70, unboundFraction: 0.02),
        )
        // fu=1 saturates occupancy; fu=0.02 sits well below the Hill half-maximum.
        #expect(atFuOne > 0.7)
        #expect(atFuReal < 0.25)
        // The sigmoidal compression narrows the 50× concentration gap, but the absolute
        // occupancy drop is still large.
        #expect(atFuOne - atFuReal > 0.4)
    }

    // MARK: - 28. Uncertainty bands scale with confidence (§E)

    @Test
    func `Uncertainty bands widen with lower confidence`() throws {
        let params = ["TestStimulant": Self.stimulant(referenceDoseMg: 60)]
        let states = ToleranceStore.simulate(
            doses: Self.dailyDoses("TestStimulant", mg: 40, days: 14),
            params: params, now: Self.now, weightKg: 70,
        )
        let stim = try #require(states[.catecholamineStimulant])
        #expect(stim.shiftFactorLow < stim.shiftFactor)
        #expect(stim.shiftFactorHigh > stim.shiftFactor)
        #expect(stim.responseFractionLow < stim.responseFraction)
        #expect(stim.responseFractionHigh > stim.responseFraction)
        let bandWidth = stim.shiftFactorHigh - stim.shiftFactorLow
        #expect(bandWidth > 0)
        #expect(stim.uncertaintyFraction == 0.40) // .low confidence class
    }

    // MARK: - 29. Diazepam-equivalence path: a named benzo uses its validated ratio (§K.4)

    @Test
    func `A named PK-less benzo uses its diazepam-equivalence at the low confidence floor`() throws {
        // Temazepam: diazepam factor 0.5 → 20 mg temazepam ≡ 10 mg diazepam. The equivalence path
        // carries .low (validated clinical ratio), not .unverified (dose-fraction guess).
        let params = [
            "temazepam": Self.pkLessBenzo(name: "temazepam", referenceDoseMg: 30),
            "Diazepam": Self.diazepam(referenceDoseMg: 30),
        ]
        let states = ToleranceStore.simulate(
            doses: Self.dailyDoses("temazepam", mg: 20, days: 14),
            params: params, now: Self.now, weightKg: 70,
        )
        let gaba = try #require(states[.gaba])
        #expect(gaba.shiftFactor > 1)
        #expect(gaba.confidence == .low)
        #expect(gaba.contributors == ["temazepam"])

        // Cross-check: 20 mg temazepam × 0.5 = 10 mg diazepam — same as logging Diazepam directly.
        let viaDiazepam = ToleranceStore.simulate(
            doses: Self.dailyDoses("Diazepam", mg: 10, days: 14),
            params: params, now: Self.now, weightKg: 70,
        )
        let directGaba = try #require(viaDiazepam[.gaba])
        #expect(abs(gaba.shiftFactor - directGaba.shiftFactor) < 1e-6)
    }

    // MARK: - K.5. Active metabolite simulation

    /// Test 30 — a single diazepam dose read days later: the nordazepam tail (t½ ≈ 100 h) keeps GABA
    /// engaged well after the parent (t½ 48 h) has largely cleared, so the metabolite-aware shift is
    /// strictly larger than the parent-only one.
    @Test
    func `Metabolite simulation extends a single dose's tolerance tail (K.5, test 30)`() throws {
        let dose = [ToleranceStore.SimDose(
            substance: "Diazepam", amountMg: 10,
            timestamp: Self.now.addingTimeInterval(-5 * 86_400),
        )]
        let without = ToleranceStore.simulate(
            doses: dose, params: ["Diazepam": Self.diazepam(referenceDoseMg: 30)],
            now: Self.now, weightKg: 70,
        )
        let with = ToleranceStore.simulate(
            doses: dose,
            params: ["Diazepam": Self.diazepam(referenceDoseMg: 30, metabolites: [Self.nordazepamMetabolite()])],
            now: Self.now, weightKg: 70,
        )
        let gabaWithout = try #require(without[.gaba])
        let gabaWith = try #require(with[.gaba])
        // Five days after one dose the parent-only shift has nearly relaxed; the nordazepam tail holds
        // it up. The metabolite adds occupancy, so it can only raise the integrated shift.
        #expect(gabaWith.shiftFactor > gabaWithout.shiftFactor)
        #expect(gabaWith.shiftFactor > 1)
    }

    /// Test 31 — a 14-day diazepam course: nordazepam accumulates across the fortnight, so the
    /// metabolite-aware shift is meaningfully higher at cessation, and still higher ten days into
    /// recovery (the tail extends the recovery timeline outward).
    @Test
    func `Metabolite simulation raises the shift and extends recovery over a course (K.5, test 31)`() throws {
        let doses = Self.dailyDoses("Diazepam", mg: 10, days: 14)
        let plainParams = ["Diazepam": Self.diazepam(referenceDoseMg: 30)]
        let metaParams = ["Diazepam": Self.diazepam(referenceDoseMg: 30, metabolites: [Self.nordazepamMetabolite()])]

        let without = try #require(ToleranceStore.simulate(doses: doses, params: plainParams, now: Self.now, weightKg: 70)[.gaba])
        let with = try #require(ToleranceStore.simulate(doses: doses, params: metaParams, now: Self.now, weightKg: 70)[.gaba])
        #expect(with.shiftFactor > without.shiftFactor)

        // Ten days after the last dose the parent-only shift has recovered further than the
        // metabolite-aware one — nordazepam's long tail is still holding GABA tolerance up.
        let later = Self.now.addingTimeInterval(10 * 86_400)
        let withoutLater = try #require(ToleranceStore.simulate(doses: doses, params: plainParams, now: later, weightKg: 70)[.gaba])
        let withLater = try #require(ToleranceStore.simulate(doses: doses, params: metaParams, now: later, weightKg: 70)[.gaba])
        #expect(withLater.shiftFactor > withoutLater.shiftFactor)
        // The recovery gap widens rather than closes: the metabolite-aware shift stays a larger multiple
        // of naïve at +10 d than the parent-only one does.
        #expect((withLater.shiftFactor - 1) > (withoutLater.shiftFactor - 1))
    }

    /// Test 32 — a **divergent** metabolite must never fold. Codeine→morphine is `scaled` in the
    /// catalog (morphine is codeine's active form), so the honest "must-not-fold" case is a
    /// genuinely divergent metabolite (tramadol→M1 in the real data); modeled here by flipping the
    /// nordazepam metabolite's mechanism to `divergent`, the shift is identical to the parent-only run.
    @Test
    func `A divergent metabolite is never folded into the parent's curve (K.5, test 32)`() throws {
        let doses = Self.dailyDoses("Diazepam", mg: 10, days: 14)
        let without = try #require(ToleranceStore.simulate(
            doses: doses, params: ["Diazepam": Self.diazepam(referenceDoseMg: 30)],
            now: Self.now, weightKg: 70,
        )[.gaba])
        let withDivergent = try #require(ToleranceStore.simulate(
            doses: doses,
            params: ["Diazepam": Self.diazepam(
                referenceDoseMg: 30,
                metabolites: [Self.nordazepamMetabolite(mechanism: "divergent", basis: "clinical")],
            )],
            now: Self.now, weightKg: 70,
        )[.gaba])
        #expect(abs(withDivergent.shiftFactor - without.shiftFactor) < 1e-9)
    }

    /// A `scaled` metabolite folds regardless of its potency **basis** — the mechanism gate (`scaled`),
    /// not the basis, decides folding; the basis only floors the folded contributor's confidence
    /// (§K.5.1, unobservable at the GABA class level, which its own class parameter already grades
    /// `.low`). So a `receptor_affinity`-basis nordazepam still extends the tail exactly like the
    /// clinical one.
    @Test
    func `A scaled metabolite folds regardless of potency basis (K.5)`() throws {
        let doses = Self.dailyDoses("Diazepam", mg: 10, days: 14)
        let plain = try #require(ToleranceStore.simulate(
            doses: doses, params: ["Diazepam": Self.diazepam(referenceDoseMg: 30)],
            now: Self.now, weightKg: 70,
        )[.gaba])
        let affinity = try #require(ToleranceStore.simulate(
            doses: doses,
            params: ["Diazepam": Self.diazepam(
                referenceDoseMg: 30,
                metabolites: [Self.nordazepamMetabolite(mechanism: "scaled", basis: "receptor_affinity")],
            )],
            now: Self.now, weightKg: 70,
        )[.gaba])
        #expect(affinity.shiftFactor > plain.shiftFactor) // still folds
    }
}
