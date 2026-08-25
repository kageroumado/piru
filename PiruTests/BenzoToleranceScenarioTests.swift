import Foundation
import Testing
@testable import Piru

/// Scenario gate for the benzodiazepine (GABA-class) tolerance + occupancy engine — the layer that
/// connects the receptor model to the withdrawal surface. These are **directional/ordinal** assertions
/// over the pure ``ToleranceStore/simulate(doses:params:now:weightKg:timestepMinutes:lookbackDays:)``
/// core (no bundled-DB numbers), pinning that typical dosing patterns produce *reasonable* results
/// rather than fitting exact percentages — the model's absolute calibration is still low-confidence, so
/// the tests lock the relationships, not the digits.
///
/// Reuses the synthetic pharmacology + dose-log builders from ``ToleranceCalibrationTests`` (same test
/// module): `alprazolam` (t½ 11.5 h, no metabolite), `diazepam` (+ optional nordazepam tail),
/// `dailyDoses`, and the fixed `now`.
@Suite("Benzo tolerance & occupancy scenarios")
@MainActor
struct BenzoToleranceScenarioTests {
    typealias Cal = ToleranceCalibrationTests
    static let now = Cal.now
    static let weightKg = 70.0

    /// Presence threshold shared with `WithdrawalReferenceView` — below this combined occupancy the drug
    /// is treated as essentially cleared. Kept in sync deliberately: these tests describe what the
    /// withdrawal surface reads.
    static let presenceFloor = 0.05

    private func gaba(_ doses: [ToleranceStore.SimDose], _ params: [String: PharmacologyParameters]) -> ClassTolerance? {
        ToleranceStore.simulate(doses: doses, params: params, now: Self.now, weightKg: Self.weightKg)[.gaba]
    }

    // MARK: - Contributor relevance (the noise fix)

    @Test
    func `A benzo taken once a year ago is not a contributor; a recent one is`() throws {
        // The export-shaped case: an intermediate benzo dosed until ~7.5 days ago (cleared, but recent
        // enough to carry residual tolerance) alongside a long benzo last taken ~318 days ago.
        let recent = Cal.dailyDoses("Alprazolam", mg: 1, days: 100, endingHoursBeforeNow: 7.5 * 24, relativeTo: Self.now)
        let yearOld = [ToleranceStore.SimDose(substance: "Diazepam", amountMg: 10, timestamp: Self.now.addingTimeInterval(-318 * 86_400))]
        let params = ["Alprazolam": Cal.alprazolam(referenceDoseMg: 1), "Diazepam": Cal.diazepam(referenceDoseMg: 30)]

        let state = try #require(gaba(recent + yearOld, params))
        #expect(state.contributors.contains("Alprazolam")) // last week → still restoring, still listed
        #expect(!state.contributors.contains("Diazepam")) // a year ago → can't affect anything, dropped
    }

    @Test
    func `A single dose long ago leaves the class rested with no contributors and nothing on board`() throws {
        let single = [ToleranceStore.SimDose(substance: "Alprazolam", amountMg: 1, timestamp: Self.now.addingTimeInterval(-200 * 86_400))]
        let state = try #require(gaba(single, ["Alprazolam": Cal.alprazolam(referenceDoseMg: 1)]))
        #expect(state.responseFraction > 0.98) // fully recovered
        #expect(state.contributors.isEmpty) // 200 d ago → below the relevance floor
        #expect(state.occupancyNow < 0.01) // long cleared
    }

    // MARK: - Presence vs residual tolerance (occupancyNow)

    @Test
    func `A recent dose reads as on board; the same run cleared a week later does not`() throws {
        let onBoard = try #require(gaba(
            Cal.dailyDoses("Alprazolam", mg: 1, days: 30, endingHoursBeforeNow: 1, relativeTo: Self.now),
            ["Alprazolam": Cal.alprazolam(referenceDoseMg: 1)],
        ))
        #expect(onBoard.occupancyNow > Self.presenceFloor) // dosed an hour ago → present

        let cleared = try #require(gaba(
            Cal.dailyDoses("Alprazolam", mg: 1, days: 30, endingHoursBeforeNow: 10 * 24, relativeTo: Self.now),
            ["Alprazolam": Cal.alprazolam(referenceDoseMg: 1)],
        ))
        #expect(cleared.occupancyNow < Self.presenceFloor) // t½ 11.5 h → gone after 10 days…
        #expect(cleared.contributors.contains("Alprazolam")) // …but still a tolerance contributor
    }

    // MARK: - Metabolite tail extends the clearance (the withdrawal-onset driver)

    @Test
    func `The nordazepam tail keeps GABA loaded days after an equivalent no-metabolite benzo has cleared`() throws {
        // Both stopped 5 days ago. Diazepam's equipotent ~100 h metabolite should still occupy the
        // receptor where alprazolam (t½ 11.5 h, no tail) has essentially cleared — this is exactly what
        // moves the withdrawal-onset window later for long-acting agents.
        let endHours = 5.0 * 24
        let alp = try #require(gaba(
            Cal.dailyDoses("Alprazolam", mg: 1, days: 14, endingHoursBeforeNow: endHours, relativeTo: Self.now),
            ["Alprazolam": Cal.alprazolam(referenceDoseMg: 1)],
        ))
        let dz = try #require(gaba(
            Cal.dailyDoses("Diazepam", mg: 10, days: 14, endingHoursBeforeNow: endHours, relativeTo: Self.now),
            ["Diazepam": Cal.diazepam(referenceDoseMg: 30, metabolites: [Cal.nordazepamMetabolite()])],
        ))
        #expect(dz.occupancyNow > alp.occupancyNow)
    }

    @Test
    func `The forward load trail peaks once then decays below the presence floor`() throws {
        let doses = Cal.dailyDoses("Alprazolam", mg: 1, days: 14, endingHoursBeforeNow: 1, relativeTo: Self.now)
        let trail = ToleranceStore.loadTrail(
            doses: doses, params: ["Alprazolam": Cal.alprazolam(referenceDoseMg: 1)],
            now: Self.now, weightKg: Self.weightKg, receptorClass: .gaba,
            horizonMinutes: 21 * 24 * 60, stepMinutes: 6 * 60,
        )
        #expect(!trail.isEmpty)
        #expect(abs(trail[0].date.timeIntervalSince(Self.now)) < 60) // first sample is "now"
        #expect(trail[0].load > Self.presenceFloor) // dosed an hour ago → loaded
        #expect(trail.allSatisfy { $0.load <= 1.0 + 1e-9 }) // relative to recent peak → ∈ [0,1]
        // The last dose is still absorbing at `now`, so load rises to Tmax and then, with no future
        // doses, decays monotonically — one hump, not a monotonic fall from the first sample.
        let peak = try #require(trail.enumerated().max { $0.element.load < $1.element.load }?.offset)
        for i in (peak + 1) ..< trail.count {
            #expect(trail[i].load <= trail[i - 1].load + 1e-9)
        }
        #expect(try #require(trail.last?.load) < Self.presenceFloor) // clears within the horizon
    }

    // MARK: - Saturation: why absolute occupancy is a poor clearance signal

    /// A **tight-Kᵢ** (saturating) benzo — like the real DB benzos, unlike the moderate synthetic
    /// `alprazolam`. Cᵢ/Kᵢ ≫ 1 at ordinary doses, so occupancy pins near 1 across a wide concentration
    /// range. Documents the pitfall behind the withdrawal-clock redesign: absolute `occupancyNow` stays
    /// ~100% for many half-lives after the last dose, so it can't say "the drug has cleared".
    private func saturatingBenzo() -> PharmacologyParameters {
        PharmacologyParameters(
            molarMassGramsPerMole: 309, vdLPerKg: 1.0,
            bioavailabilityFraction: 0.9, bioavailabilityConfidence: .high, doseScale: 1,
            doseScaleConfidence: .high, halfLifeMinutes: 690, vdConfidence: .high,
            referenceDoseMg: 1, suppressesSerotoninSynthesis: false,
            targets: [.init(target: "GABA-A", action: .positiveAllostericModulator, halfMaxNanomolar: 0.3, kind: .ki, confidence: .high)],
        )
    }

    @Test
    func `Relative load clears a week after the last dose even for a saturating benzo`() throws {
        // Daily for 30 d, last dose 7 days ago. Absolute occupancy of a tight-Kᵢ benzo can stay high
        // (the saturation trap the withdrawal card must not fall into); relative load — the fraction of
        // the user's recent peak drive — decays cleanly and reads as cleared.
        let doses = Cal.dailyDoses("TightBenzo", mg: 1, days: 30, endingHoursBeforeNow: 7 * 24, relativeTo: Self.now)
        let params = ["TightBenzo": saturatingBenzo()]
        let trail = ToleranceStore.loadTrail(
            doses: doses, params: params, now: Self.now, weightKg: Self.weightKg,
            receptorClass: .gaba, horizonMinutes: 60, stepMinutes: 60, pastHorizonMinutes: 0,
        )
        let loadNow = try #require(trail.first?.load)
        #expect(loadNow < 0.10) // relative load has cleared, whatever the absolute occupancy reads
    }

    // MARK: - Effect ladder (differential tolerance)

    @Test
    func `The effect ladder fades sedation but not anxiolysis or the impairments`() throws {
        // Heavy daily use for 60 days → sedation (the primary layer) tolerizes; anxiolysis, memory and
        // coordination are modeled flat (do not tolerize); anticonvulsant fades slowly and partially.
        // This is the escalation trap made legible: the sedation you notice fades, the impairments don't.
        let state = try #require(gaba(
            Cal.dailyDoses("Alprazolam", mg: 2, days: 60, relativeTo: Self.now),
            ["Alprazolam": Cal.alprazolam(referenceDoseMg: 1)],
        ))
        let sedation = try #require(state.responseFraction(forEffect: .sedation))
        let anxiolysis = try #require(state.responseFraction(forEffect: .anxiolysis))
        let memory = try #require(state.responseFraction(forEffect: .memory))
        let coordination = try #require(state.responseFraction(forEffect: .coordination))
        let anticonvulsant = try #require(state.responseFraction(forEffect: .anticonvulsant))

        #expect(sedation < 0.8) // sedation has faded past the "unchanged" line
        #expect(anxiolysis > 0.95) // no anxiolytic tolerance
        #expect(abs(memory - anxiolysis) < 1e-9) // impairments modeled identically flat…
        #expect(abs(coordination - anxiolysis) < 1e-9) // …and unchanged
        #expect(sedation < anticonvulsant) // anticonvulsant fades less than sedation…
        #expect(anticonvulsant < anxiolysis) // …but more than the flat anxiolysis (partial)
        #expect(state.responseFraction(forEffect: .hypnotic) == nil) // sleep is not a GABA ladder effect
    }

    @Test
    func `Non-ladder classes expose no per-effect breakdown`() throws {
        // A stimulant has one undifferentiated gauge — effectShifts is empty and per-effect queries nil.
        let states = ToleranceStore.simulate(
            doses: Cal.dailyDoses("TestStimulant", mg: 20, days: 14, relativeTo: Self.now),
            params: ["TestStimulant": Cal.stimulant(referenceDoseMg: 60)], now: Self.now, weightKg: Self.weightKg,
        )
        let stim = try #require(states[.catecholamineStimulant])
        #expect(stim.effectShifts.isEmpty)
        #expect(stim.responseFraction(forEffect: .sedation) == nil)
    }

    // MARK: - Gabapentinoids: single gauge, not a ladder (evidence-bounded)

    /// Pregabalin: α2δ-1 Kᵢ 32 nM, t½ 6 h — occupancy saturates at ordinary doses, which is why the
    /// gauge needs the half-sat cap to show tolerance.
    private func pregabalin() -> PharmacologyParameters {
        PharmacologyParameters(
            molarMassGramsPerMole: 159, vdLPerKg: 0.5,
            bioavailabilityFraction: 0.9, bioavailabilityConfidence: .high, doseScale: 1,
            doseScaleConfidence: .high, halfLifeMinutes: 360, vdConfidence: .high,
            referenceDoseMg: 600, suppressesSerotoninSynthesis: false,
            targets: [.init(target: "α2δ-1", action: .modulator, halfMaxNanomolar: 32, kind: .ki, confidence: .high)],
        )
    }

    @Test
    func `Gabapentinoids show a single gauge, and heavy use reads as toleranced despite saturation`() throws {
        // Owen 2007: somnolence habituates in ~weeks; Feltner 2008: anxiolytic maintained. No evidence
        // for a graded ladder, so α2δ carries no effect endpoints. The gauge must still SHOW the real
        // sedative tolerance — occupancy saturates (rep occ ≈ 1), so without the half-sat cap a 3× shift
        // read as ~100% (the "Sleep 100%" bug).
        let a2d = try #require(ToleranceStore.simulate(
            doses: Cal.dailyDoses("Pregabalin", mg: 300, days: 90, relativeTo: Self.now),
            params: ["Pregabalin": pregabalin()], now: Self.now, weightKg: Self.weightKg,
        )[.alpha2Delta])
        #expect(a2d.effectShifts.isEmpty) // no per-effect ladder for gabapentinoids
        #expect(a2d.responseFraction(forEffect: .sedation) == nil) // …and no per-effect gauge
        #expect(a2d.shiftFactor > 1.5) // heavy daily use builds real tolerance
        #expect(a2d.responseFraction < 0.85) // and the capped gauge shows it, not ~100%
    }

    // MARK: - Reasonableness of typical patterns

    @Test
    func `Longer daily use builds more tolerance and more chronic exposure than a short run`() throws {
        let params = ["Alprazolam": Cal.alprazolam(referenceDoseMg: 1)]
        let week = try #require(gaba(Cal.dailyDoses("Alprazolam", mg: 1, days: 7, relativeTo: Self.now), params))
        let year = try #require(gaba(Cal.dailyDoses("Alprazolam", mg: 1, days: 365, relativeTo: Self.now), params))

        #expect(year.shiftFactor >= week.shiftFactor) // more history → at least as much shift
        #expect(year.chronicExposure > week.chronicExposure) // the duty-cycle accumulator has ramped
        #expect(year.responseFraction < 1) // a year of daily use is not "rested"
    }

    @Test
    func `A high-dose week builds real tolerance but less chronic exposure than a year of daily use`() throws {
        let params = ["Alprazolam": Cal.alprazolam(referenceDoseMg: 1)]
        let highWeek = try #require(gaba(Cal.dailyDoses("Alprazolam", mg: 4, days: 7, relativeTo: Self.now), params))
        let year = try #require(gaba(Cal.dailyDoses("Alprazolam", mg: 1, days: 365, relativeTo: Self.now), params))

        #expect(highWeek.shiftFactor > 1) // a week of heavy dosing does shift the curve
        #expect(highWeek.chronicExposure < year.chronicExposure) // …but chronicity is about duration, not dose
    }
}
