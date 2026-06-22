import Foundation
import SwiftData

/// A snapshot of tolerance state at one receptor target, derived by replaying the dose log. The
/// value type the UI reads (Stage 2); the SwiftData ``ToleranceState`` row is its cached persistence.
struct TargetTolerance: Hashable, Identifiable {
    let target: String
    let receptorClass: ReceptorClasses.ReceptorClass
    /// Slow availability `A_R` ∈ [0, 1] — 1 = naïve/rested.
    let availability: Double
    /// Within-session acute (redose) pool ∈ [0, 1].
    let acute: Double
    /// Allostatic load (ordinal recovery-state indicator; never an effect multiplier).
    let load: Double
    /// Weakest-link confidence across the contributing substances' occupancy inputs and the class
    /// kinetics — the house "predicted (model, confidence)" tier.
    let confidence: ConfidenceTier

    var id: String {
        target
    }
}

/// A predicted **cross-tolerance** readout for a substance about to be logged: the shared receptor
/// availability `A_R` at one engaged class, already lowered by recent use of substances that hit the
/// same target. Surfaced at dose entry (Stage 4a) — "≈X% of rested response."
struct CrossToleranceReadout: Identifiable {
    let receptorClass: ReceptorClasses.ReceptorClass
    /// Predicted availability `A_R` ∈ [0, 1] — 1 = rested. The "% of rested response."
    let availability: Double
    /// Substances driving this class's tolerance, recency order (may include the same substance's own
    /// recent doses — same-drug tolerance is as real as cross-drug).
    let contributors: [String]
    let confidence: ConfidenceTier

    var id: String {
        receptorClass.rawValue
    }

    /// Predicted response as a percentage of rested.
    var responsePercent: Int {
        Int((min(1, max(0, availability)) * 100).rounded())
    }
}

/// A predicted **reset-after-break overdose** risk for a μ-opioid about to be logged (Stage 5 opioid
/// safety axis). Fires *only* in the genuine relapse window: the user built real μ-opioid tolerance,
/// then a break let availability recover toward naïve — so a dose that was tolerated before the break
/// can now stop their breathing. Deliberately narrow (false positives spend trust); a naïve first-timer
/// and a still-actively-using person both fail the gate.
struct OpioidResetRisk: Identifiable {
    /// Lowest μ-opioid availability reached before the break — how tolerant they had become (≤ 1).
    let peakAvailability: Double
    /// Current μ-opioid availability, recovered toward naïve over the break.
    let currentAvailability: Double
    /// Whole days since the last opioid dose (the break length).
    let breakDays: Int
    /// The opioids that drove the prior tolerance, most-recent first.
    let contributors: [String]
    let confidence: ConfidenceTier

    var id: String {
        "opioid-reset"
    }

    /// Current response as a percentage of a rested/naïve system — how hard the old dose now hits.
    var currentResponsePercent: Int {
        Int((min(1, max(0, currentAvailability)) * 100).rounded())
    }
}

/// Owns the user's **per-target tolerance state**, recomputed by replaying the dose log through
/// ``PDModel`` — the lead thread of `Specs/pharmacology-axis-meta-plan.md` (Stage 1).
///
/// ## Why replay, not increment
/// Tolerance is computed by *integrating the whole dose log* on demand (like
/// ``ActiveSubstanceCalculator``), not by mutating a running value per dose. That makes it
/// deterministic and trivially testable (the gate is literally a replay of a synthetic log), immune
/// to out-of-order edits/back-dated doses, and free of drift. The persisted ``ToleranceState`` rows
/// are a *cache* of the latest replay so the UI/widget can read a current number without re-walking
/// history.
///
/// ## SwiftData isolation gotchas (carried over from `UserProfileStore`)
/// The `ModelContainer`/`ModelContext` are held ``ObservationIgnored`` — storing a SwiftData type as
/// an observation-tracked property of an `@Observable` drags in `_SwiftData_SwiftUI` and traps on
/// mutate. Views observe the plain ``states`` dictionary instead. The store also **retains its
/// container** (a `ModelContext` does not), or inserts trap on an orphaned container.
@Observable
@MainActor
final class ToleranceStore {
    static let shared = ToleranceStore()

    /// Default integration timestep (minutes). The closed-form ``PDModel/stepAvailability`` is exact
    /// for piecewise-constant occupancy, so a coarse grid stays accurate; 30 min balances fidelity
    /// against the cost of replaying a long history.
    static let defaultTimestepMinutes = 30.0

    /// How far back the replay reaches. Beyond the longest recovery/decay τ (a few months) a dose's
    /// contribution has decayed to nothing, so older history is dropped to bound the work.
    static let defaultLookbackDays = 547.0 // ~18 months

    /// Lookback for the cross-tolerance readout (Stage 4a). Cross-tolerance reads only the *availability*
    /// axis, whose slowest recovery τ among multiplier classes is ~10 days (opioid/GABA), so a dose more
    /// than ~6 τ back has recovered to <1% and contributes nothing. 90 days is a generous margin and a
    /// far smaller fetch/replay than the 18-month load window (the LOAD axis, which needs the long
    /// window, is not used here).
    static let crossToleranceLookbackDays = 90.0

    /// Current per-target tolerance snapshot, keyed by target. Observation-tracked; views read this.
    private(set) var states: [String: TargetTolerance] = [:]

    @ObservationIgnored private var container: ModelContainer?
    @ObservationIgnored private var context: ModelContext?

    /// Public for the test seam; production uses ``shared``.
    init() {}

    // MARK: - Lifecycle

    /// Bind to the app's shared container and load the last cached snapshot. Call once at launch.
    func configure(container: ModelContainer) {
        self.container = container
        context = ModelContext(container)
        loadCachedSnapshot()
    }

    /// Recompute every target's tolerance from the dose log and refresh the cache. Call after the
    /// dose log changes (and at launch). `now` is injectable for deterministic tests.
    func recompute(from entries: [DoseEntry], now: Date = .now) {
        let weightKg = UserProfileStore.shared.effectiveWeightKg
        let computed = Self.simulate(entries: entries, now: now, weightKg: weightKg) {
            SubstanceStore.shared.pharmacologyParameters(forSubstanceName: $0)
        }
        states = computed
        persist(computed, now: now)
    }

    /// Current availability at a target, or `nil` if untracked (treated as naïve `1` by callers).
    func tolerance(forTarget target: String) -> TargetTolerance? {
        states[target]
    }

    // MARK: - Cross-tolerance readout (Stage 4a)

    /// Predicted **cross-tolerance** for a substance about to be logged: the already-computed shared
    /// availability `A_R` at the receptor classes it engages, lowered by *other* recent substances that
    /// hit the same target ("≈X% of rested response — shared 5-HT2A tolerance from LSD 3 days ago").
    ///
    /// Fetches the long tolerance window from the store's own context (the form's `@Query` is only the
    /// 48 h interaction window) and replays it through ``simulate(entries:now:weightKg:resolve:)``. The
    /// prospective dose itself is **not** included — tolerance is a property of *past* exposure, so the
    /// readout is independent of this dose's amount. Returns `[]` before launch configuration.
    func crossToleranceReadouts(forSubstance name: String, now: Date = .now) -> [CrossToleranceReadout] {
        guard let context else { return [] }
        let cutoff = now.addingTimeInterval(-Self.crossToleranceLookbackDays * 86_400)
        let descriptor = FetchDescriptor<DoseEntry>(predicate: #Predicate<DoseEntry> { $0.timestamp >= cutoff })
        guard let entries = try? context.fetch(descriptor) else { return [] }
        let weightKg = UserProfileStore.shared.effectiveWeightKg
        return Self.crossTolerance(forSubstance: name, entries: entries, now: now, weightKg: weightKg) {
            SubstanceStore.shared.pharmacologyParameters(forSubstanceName: $0)
        }
    }

    /// Pure cross-tolerance computation (the testable core). Replays `entries`, then for each receptor
    /// **class** the prospective substance engages that is a valid effect *multiplier*
    /// (``ReceptorClasses/Parameters/usesEffectMultiplier`` — psychedelic / opioid / GABA / NMDA / CB1 /
    /// adenosine; stimulants/releasers are excluded because their slow axis is LOAD, not a multiplier),
    /// it surfaces the worst (lowest-availability) shared state of that class and the substances driving
    /// it. Only classes reduced by at least `minReduction` are returned, worst first.
    @MainActor
    static func crossTolerance(
        forSubstance name: String,
        entries: [DoseEntry],
        now: Date,
        weightKg: Double,
        minReduction: Double = 0.1,
        resolve: (String) -> PharmacologyParameters?,
    ) -> [CrossToleranceReadout] {
        guard let prospective = resolve(name) else { return [] }

        // Receptor classes the prospective substance engages whose *availability* axis is a valid
        // multiplier (the only classes for which "≈X% of rested response" is meaningful). `.unknown`
        // is excluded: a "% of rested" readout for an uncurated receptor with class-default kinetics is
        // noise, even though that fallback class nominally allows the multiplier.
        var engagedClasses = Set<ReceptorClasses.ReceptorClass>()
        for t in prospective.targets {
            let cls = ReceptorClasses.classify(target: t.target, action: t.action)
            guard cls != .unknown, ReceptorClasses.parameters(for: cls).usesEffectMultiplier else { continue }
            engagedClasses.insert(cls)
        }
        guard !engagedClasses.isEmpty else { return [] }

        let states = simulate(entries: entries, now: now, weightKg: weightKg, resolve: resolve)
        guard !states.isEmpty else { return [] }

        // Substances driving each engaged class, recency order, deduped — mirrors `simulate`'s gating
        // (only occupancy-computable substances contribute) so the names match the computed state.
        let sortedDesc = entries.filter { $0.timestamp <= now }.sorted { $0.timestamp > $1.timestamp }
        var contributorsByClass: [ReceptorClasses.ReceptorClass: [String]] = [:]
        var seenByClass: [ReceptorClasses.ReceptorClass: Set<String>] = [:]
        var paramCache: [String: PharmacologyParameters?] = [:]
        for e in sortedDesc {
            let p: PharmacologyParameters?
            if let cached = paramCache[e.substance] { p = cached } else { p = resolve(e.substance); paramCache[e.substance] = p }
            guard let p, p.canComputeOccupancy else { continue }
            for t in p.targets {
                let cls = ReceptorClasses.classify(target: t.target, action: t.action)
                guard engagedClasses.contains(cls) else { continue }
                if seenByClass[cls, default: []].insert(e.substance).inserted {
                    contributorsByClass[cls, default: []].append(e.substance)
                }
            }
        }

        var readouts: [CrossToleranceReadout] = []
        for cls in engagedClasses {
            let classStates = states.values.filter { $0.receptorClass == cls }
            guard let worst = classStates.min(by: { $0.availability < $1.availability }),
                  (1 - worst.availability) >= minReduction else { continue }
            readouts.append(CrossToleranceReadout(
                receptorClass: cls,
                availability: worst.availability,
                contributors: contributorsByClass[cls] ?? [],
                confidence: classStates.map(\.confidence).min() ?? worst.confidence,
            ))
        }
        return readouts.sorted { $0.availability < $1.availability }
    }

    // MARK: - Opioid reset-after-break overdose (Stage 5 safety axis)

    /// Peak μ-opioid availability ≤ this counts as having built genuine tolerance (≥ ~40% depressed).
    static let opioidTolerantThreshold = 0.6
    /// Current μ-opioid availability ≥ this counts as having recovered toward naïve over the break.
    static let opioidRecoveredThreshold = 0.78
    /// Minimum availability regained (current − peak) for the reset to be meaningful, not noise.
    static let opioidMinRecovery = 0.18
    /// Minimum gap since the last opioid dose to count as a break (days). Below this they're still
    /// actively using and the dose matches their tolerance — not a reset.
    static let opioidMinBreakDays = 5.0

    /// Predicted reset-after-break overdose risk for a μ-opioid about to be logged. Fetches the opioid
    /// window from the store's own context and replays it; returns `nil` (no warning) unless the full
    /// relapse pattern holds. See ``opioidResetRisk(forSubstance:entries:now:weightKg:resolve:)``.
    func opioidResetRisk(forSubstance name: String, now: Date = .now) -> OpioidResetRisk? {
        guard let context else { return nil }
        // Reach back far enough to see a long break after a using period (the classic post-detox window).
        let cutoff = now.addingTimeInterval(-Self.defaultLookbackDays * 86_400)
        let descriptor = FetchDescriptor<DoseEntry>(predicate: #Predicate<DoseEntry> { $0.timestamp >= cutoff })
        guard let entries = try? context.fetch(descriptor) else { return nil }
        let weightKg = UserProfileStore.shared.effectiveWeightKg
        return Self.opioidResetRisk(forSubstance: name, entries: entries, now: now, weightKg: weightKg) {
            SubstanceStore.shared.pharmacologyParameters(forSubstanceName: $0)
        }
    }

    /// Pure reset-after-break computation (the testable core). Fires only when **all** hold:
    /// 1. the prospective substance is a μ-opioid agonist (a respiratory depressant — the reset axis);
    /// 2. the user has prior μ-opioid doses (a naïve first-timer is *not* a reset, even at full availability);
    /// 3. a genuine break since the last opioid dose (``opioidMinBreakDays``);
    /// 4. real prior tolerance — peak (lowest) μ-opioid availability before the break ≤ ``opioidTolerantThreshold``;
    /// 5. that availability has since recovered toward naïve (≥ ``opioidRecoveredThreshold`` *and* by
    ///    ≥ ``opioidMinRecovery``), so the old dose now lands on a far less tolerant system.
    @MainActor
    static func opioidResetRisk(
        forSubstance name: String,
        entries: [DoseEntry],
        now: Date,
        weightKg: Double,
        resolve: (String) -> PharmacologyParameters?,
    ) -> OpioidResetRisk? {
        var paramCache: [String: PharmacologyParameters?] = [:]
        func params(_ s: String) -> PharmacologyParameters? {
            if let cached = paramCache[s] { return cached }
            let p = resolve(s)
            paramCache[s] = p
            return p
        }
        func engagesMuOpioid(_ p: PharmacologyParameters) -> Bool {
            p.targets.contains { ReceptorClasses.classify(target: $0.target, action: $0.action) == .muOpioid }
        }

        // 1. The prospective substance must be a μ-opioid agonist.
        guard let prospective = params(name), engagesMuOpioid(prospective) else { return nil }

        // 2. Prior μ-opioid doses (occupancy-computable, so they actually drove tolerance), recency-first.
        let past = entries.filter { $0.timestamp <= now }.sorted { $0.timestamp > $1.timestamp }
        let opioidPast = past.filter { e in
            guard let p = params(e.substance), p.canComputeOccupancy else { return false }
            return engagesMuOpioid(p)
        }
        guard let lastDose = opioidPast.first else { return nil }

        // 3. A genuine break since the last opioid dose.
        let breakInterval = now.timeIntervalSince(lastDose.timestamp)
        guard breakInterval >= opioidMinBreakDays * 86_400 else { return nil }

        /// 4. Real prior tolerance: the lowest μ-opioid availability reached by the end of the using period.
        func muAvailability(at instant: Date) -> Double? {
            let states = simulate(entries: opioidPast, now: instant, weightKg: weightKg, resolve: resolve)
            return states.values.filter { $0.receptorClass == .muOpioid }.map(\.availability).min()
        }
        guard let peakAvail = muAvailability(at: lastDose.timestamp), peakAvail <= opioidTolerantThreshold else { return nil }

        // 5. …that has since recovered toward naïve over the break.
        guard let currentAvail = muAvailability(at: now),
              currentAvail >= opioidRecoveredThreshold,
              currentAvail - peakAvail >= opioidMinRecovery else { return nil }

        var seen = Set<String>()
        let contributors = opioidPast.map(\.substance).filter { seen.insert($0).inserted }
        let confidence = simulate(entries: opioidPast, now: lastDose.timestamp, weightKg: weightKg, resolve: resolve)
            .values.filter { $0.receptorClass == .muOpioid }.map(\.confidence).min() ?? .low

        return OpioidResetRisk(
            peakAvailability: peakAvail,
            currentAvailability: currentAvail,
            breakDays: Int((breakInterval / 86_400).rounded(.down)),
            contributors: contributors,
            confidence: confidence,
        )
    }

    // MARK: - Pure replay (the testable core)

    /// Replay a dose log into per-target tolerance state. Pure aside from the injected `resolve`
    /// closure (production passes `SubstanceStore`), so the gate runs without a container or singleton.
    ///
    /// Each substance contributes a time-resolved occupancy curve at every target it engages
    /// (absolute molar concentration → Hill occupancy, Foundation A); contributions at a *shared*
    /// target combine via ``PDModel/combinedOccupancy(_:)``, and that combined occupancy drives the
    /// per-target availability/acute/load ODEs with the class's ``ReceptorClasses/Parameters``.
    static func simulate(
        entries: [DoseEntry],
        now: Date,
        weightKg: Double,
        timestepMinutes: Double = defaultTimestepMinutes,
        lookbackDays: Double = defaultLookbackDays,
        resolve: (String) -> PharmacologyParameters?,
    ) -> [String: TargetTolerance] {
        let relevant = entries
            .filter { $0.timestamp <= now && $0.timestamp >= now.addingTimeInterval(-lookbackDays * 86_400) }
            .sorted { $0.timestamp < $1.timestamp }
        guard let start = relevant.first?.timestamp, weightKg > 0 else { return [:] }

        var contributorsByTarget: [String: [Contributor]] = [:]
        var classByTarget: [String: ReceptorClasses.ReceptorClass] = [:]
        // Tolerance-modulation contributors keyed by the *affected* class (Stage 4b): an NMDA
        // antagonist onboard lowers μ-opioid tolerance development, etc.
        var modulatorsByClass: [ReceptorClasses.ReceptorClass: [ModulatorContributor]] = [:]

        for entry in relevant {
            guard let p = resolve(entry.substance), p.canComputeOccupancy,
                  let vdPerKg = p.vdLPerKg, let mw = p.molarMassGramsPerMole,
                  let f = p.bioavailabilityFraction, let halfLife = p.halfLifeMinutes,
                  let doseMg = DoseUnit.convert(entry.amount, from: entry.unit, to: "mg")
            else { continue }
            let vd = vdPerKg * weightKg
            guard vd > 0, mw > 0, halfLife > 0 else { continue }
            let ke = PKModel.ke(fromHalfLifeMinutes: halfLife)
            let ka = PKModel.defaultKa(ke: ke)
            // molar = (F·dose/Vd)·shape /1000 /MW ; ×1e9 → nM (fu = 1, Stage 1). One concentration()
            // call per contributor per step then multiplies this prefactor.
            let prefactorNanomolar = (f * doseMg / vd) / 1_000 / mw * 1e9
            let offsetMinutes = entry.timestamp.timeIntervalSince(start) / 60

            // Most-potent target per class (p.targets is tightest-first, so the first per class wins) —
            // used both to route the contributor and to drive any modulation edge's presence curve.
            var bestTargetByClass: [ReceptorClasses.ReceptorClass: PharmacologyParameters.TargetEngagement] = [:]
            for engagement in p.targets {
                let cls = ReceptorClasses.classify(target: engagement.target, action: engagement.action)
                if bestTargetByClass[cls] == nil { bestTargetByClass[cls] = engagement }
                contributorsByTarget[engagement.target, default: []].append(
                    Contributor(
                        offsetMinutes: offsetMinutes, ke: ke, ka: ka,
                        prefactorNanomolar: prefactorNanomolar,
                        halfMaxNanomolar: engagement.halfMaxNanomolar,
                        confidence: Swift.min(p.vdConfidence, engagement.confidence),
                    ),
                )
                classByTarget[engagement.target] = cls
            }

            // Register this dose as a tolerance modulator for any class it modulates. Presence is the
            // occupancy of its most-potent target *of the modulating class*, so the edge fires only
            // while the modulator is actually onboard (concentration/overlap-gated).
            for (modClass, best) in bestTargetByClass {
                for edge in ToleranceModulation.edges(forModulatorClass: modClass) {
                    modulatorsByClass[edge.affectedClass, default: []].append(
                        ModulatorContributor(
                            offsetMinutes: offsetMinutes, ke: ke, ka: ka,
                            prefactorNanomolar: prefactorNanomolar,
                            halfMaxNanomolar: best.halfMaxNanomolar,
                            muFactor: edge.muFactor,
                        ),
                    )
                }
            }
        }
        guard !contributorsByTarget.isEmpty else { return [:] }

        let totalMinutes = now.timeIntervalSince(start) / 60
        var result: [String: TargetTolerance] = [:]

        for (target, contributors) in contributorsByTarget {
            let receptorClass = classByTarget[target] ?? .unknown
            let params = ReceptorClasses.parameters(for: receptorClass)

            let modulators = modulatorsByClass[receptorClass] ?? []

            var availability = 1.0
            var acute = 1.0
            var load = 0.0
            var elapsed = 0.0
            while elapsed < totalMinutes {
                let step = Swift.min(timestepMinutes, totalMinutes - elapsed)
                let mid = elapsed + step / 2
                let occ = combinedOccupancy(atMinute: mid, contributors: contributors)
                // μ_R(t): tolerance-modulation factor for the slow availability axis only (Stage 4b).
                let modulation = modulators.isEmpty ? 1.0 : modulationFactor(atMinute: mid, modulators: modulators)
                availability = PDModel.stepAvailability(
                    availability: availability, occupancy: occ, dtMinutes: step,
                    kappa: params.kappaSlow, tauMinutes: params.tauSlowMinutes,
                    modulation: modulation,
                )
                if params.hasAcutePool {
                    acute = PDModel.stepAvailability(
                        availability: acute, occupancy: occ, dtMinutes: step,
                        kappa: params.kappaAcute, tauMinutes: params.tauAcuteMinutes,
                    )
                }
                if params.loadGain > 0 {
                    load = PDModel.stepLoad(
                        load: load, occupancy: occ, dtMinutes: step,
                        tauMinutes: params.tauLoadMinutes, gain: params.loadGain,
                    )
                }
                elapsed += step
            }

            let inputConfidence = contributors.map(\.confidence).min() ?? .unverified
            result[target] = TargetTolerance(
                target: target, receptorClass: receptorClass,
                availability: availability, acute: acute, load: load,
                confidence: Swift.min(inputConfidence, params.confidence),
            )
        }
        return result
    }

    // MARK: - Private

    /// One substance-dose's contribution to one target: PK shape + the nM prefactor + that target's
    /// half-saturation constant.
    private struct Contributor {
        let offsetMinutes: Double
        let ke: Double
        let ka: Double
        let prefactorNanomolar: Double
        let halfMaxNanomolar: Double
        let confidence: ConfidenceTier
    }

    /// One co-active substance's tolerance-modulation contribution at one affected class: its PK shape +
    /// nM prefactor + the half-saturation of the target driving its presence + the μ factor at full
    /// engagement.
    private struct ModulatorContributor {
        let offsetMinutes: Double
        let ke: Double
        let ka: Double
        let prefactorNanomolar: Double
        let halfMaxNanomolar: Double
        let muFactor: Double
    }

    /// Combined tolerance-modulation factor `μ` at one grid minute. Each modulator blends its
    /// `muFactor` toward 1 by its current engagement (presence), and modulators compound
    /// multiplicatively — `μ = Π (1 − (1 − muFactorᵢ)·presenceᵢ)`, bounded in `[0, 1]` and reducing to 1
    /// when no modulator is onboard.
    private static func modulationFactor(atMinute minute: Double, modulators: [ModulatorContributor]) -> Double {
        var mu = 1.0
        for m in modulators {
            let dt = minute - m.offsetMinutes
            guard dt >= 0 else { continue }
            let free = m.prefactorNanomolar * PKModel.concentration(at: dt, ke: m.ke, ka: m.ka)
            let presence = PKModel.occupancy(concentration: free, halfMax: m.halfMaxNanomolar)
            mu *= (1 - (1 - m.muFactor) * presence)
        }
        return mu
    }

    /// Combined fractional occupancy at one grid minute from all contributors active by then.
    private static func combinedOccupancy(atMinute minute: Double, contributors: [Contributor]) -> Double {
        var occupancies: [Double] = []
        occupancies.reserveCapacity(contributors.count)
        for c in contributors {
            let dtSinceDose = minute - c.offsetMinutes
            guard dtSinceDose >= 0 else { continue }
            let freeNanomolar = c.prefactorNanomolar * PKModel.concentration(at: dtSinceDose, ke: c.ke, ka: c.ka)
            let o = PKModel.occupancy(concentration: freeNanomolar, halfMax: c.halfMaxNanomolar)
            if o > 0 { occupancies.append(o) }
        }
        return PDModel.combinedOccupancy(occupancies)
    }

    // MARK: - Persistence (cache)

    private func loadCachedSnapshot() {
        guard let context else { return }
        guard let rows = try? context.fetch(FetchDescriptor<ToleranceState>()) else { return }
        var loaded: [String: TargetTolerance] = [:]
        for row in rows {
            loaded[row.target] = TargetTolerance(
                target: row.target,
                receptorClass: ReceptorClasses.classify(target: row.target),
                availability: row.availability, acute: row.acute, load: row.load,
                confidence: ReceptorClasses.parameters(forTarget: row.target).confidence,
            )
        }
        states = loaded
    }

    private func persist(_ computed: [String: TargetTolerance], now: Date) {
        guard let context else { return }
        let existing = (try? context.fetch(FetchDescriptor<ToleranceState>())) ?? []
        var byTarget = Dictionary(existing.map { ($0.target, $0) }, uniquingKeysWith: { a, _ in a })

        for (target, t) in computed {
            if let row = byTarget[target] {
                row.availability = t.availability
                row.acute = t.acute
                row.load = t.load
                row.lastUpdated = now
            } else {
                context.insert(ToleranceState(
                    target: target, availability: t.availability, acute: t.acute,
                    load: t.load, lastUpdated: now,
                ))
            }
            byTarget[target] = nil
        }
        // Targets no longer driven by any in-window dose: reset their cached row to naïve rather than
        // deleting (keeps a stable row set; a target that recovers fully reads as availability 1).
        for (_, stale) in byTarget {
            stale.availability = 1
            stale.acute = 1
            stale.load = 0
            stale.lastUpdated = now
        }

        try? context.save()
    }
}
