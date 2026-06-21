import Foundation

/// The mechanism families that **additively** drive CNS / respiratory depression, each with a
/// relative danger weight. This is the contributor vocabulary for the combined-depression index
/// (`Specs/pharmacology-axis-meta-plan.md`, Stage 3b): instead of "two depressant tags co-exist,"
/// the engine sums a time-resolved load from per-substance engagement and reports the peak and when.
///
/// ## Why these weights
/// μ-opioid agonism suppresses the brainstem respiratory drive — it is *the* mechanism that stops
/// breathing, so it anchors the scale at `1.0`. GABAergic potentiation (benzodiazepines, alcohol,
/// GHB, z-drugs) is the next tier; the leading-cause-of-death pairs are opioid+benzo and
/// opioid+alcohol, which the weights are calibrated to land in the dangerous band (see
/// ``CombinedDepression``). Gabapentinoids and the sedating "other" classes (sedating antihistamines,
/// antipsychotics, α2 agonists) and dissociatives contribute real but lesser additive depression.
///
/// The weights are **ordinal / relative**, not a physiological percentage — house honesty rule
/// (Foundation C): the index is rendered "predicted (model, confidence)", never "measured".
nonisolated enum DepressantMechanism: String, CaseIterable {
    /// μ-opioid agonism — brainstem respiratory drive suppression. The killer; anchors the scale.
    case muOpioid
    /// GABA-A PAM / GABA-B (benzodiazepines, alcohol, z-drugs, GHB) — CNS depression.
    case gabaergic
    /// Gabapentinoids (pregabalin, gabapentin, phenibut) — potentiate opioid/CNS depression.
    case gabapentinoid
    /// Dissociatives (ketamine, DXM) — additive CNS depression, mask overdose signs.
    case dissociative
    /// Sedating antihistamines / antipsychotics / α2 agonists — additive sedation + respiratory load.
    case sedatingOther

    /// Relative respiratory/CNS-depression weight (dimensionless, ordinal). Calibrated so the encoded
    /// dangerous pairs (opioid+benzo, opioid+alcohol) reach ``CombinedDepression/dangerousThreshold``.
    var weight: Double {
        switch self {
        case .muOpioid: 1.0
        case .gabaergic: 0.8
        case .gabapentinoid: 0.5
        case .dissociative: 0.35
        case .sedatingOther: 0.3
        }
    }

    /// The depressant mechanism a **tolerance receptor class** drives, or `nil` if the class is not an
    /// additive CNS/respiratory depressant. Used on the occupancy path (real Hill occupancy at the
    /// class's target).
    static func from(receptorClass: ReceptorClasses.ReceptorClass) -> DepressantMechanism? {
        switch receptorClass {
        case .muOpioid: .muOpioid
        case .gaba: .gabaergic
        case .nmdaAntagonist: .dissociative
        default: nil
        }
    }

    /// The depressant mechanism an **interaction drug class** drives, or `nil` if it is not an additive
    /// CNS/respiratory depressant. Used on the surrogate path (effect-curve shape, no occupancy data).
    static func from(drugClass: DrugClass) -> DepressantMechanism? {
        switch drugClass {
        case .opioid: .muOpioid
        case .benzodiazepine, .alcohol, .ghb: .gabaergic
        case .gabapentinoid: .gabapentinoid
        case .dissociative: .dissociative
        // Alpha-2 agonists add sedation/hypotension but only modest intrinsic respiratory depression
        // (opioid-sparing for OIRD) — counted at the low `sedatingOther` weight (evidence run 2026-06-22).
        case .antihistamine, .antipsychotic, .alpha2Agonist: .sedatingOther
        default: nil
        }
    }
}

/// One depressant substance's resolved, time-sampled contribution to the combined index. Pure data,
/// produced by ``CombinedDepression/analyze(entries:now:weightKg:timestepMinutes:)`` and consumed by
/// the pure reducer ``CombinedDepression/reduce(curves:dtMinutes:gridStart:)``.
nonisolated struct DepressantContributor {
    let substance: String
    let mechanism: DepressantMechanism
    /// Dose-presence weight `[0, 1]`: `1` on the occupancy path (dose is already folded into the
    /// occupancy curve) and on an unknown-amount surrogate; `presence(magnitude)` for a known-amount
    /// surrogate dose so a clearly sub-threshold dose contributes little.
    let doseWeight: Double
    /// Weakest-link confidence of this contributor's inputs (the occupancy Vd+target tier, or `.low`
    /// for the class-based surrogate).
    let confidence: ConfidenceTier
    /// `true` when `engagement` is real Hill occupancy; `false` when it is the effect-shape surrogate.
    let isModeled: Bool
    /// Engagement `e(t)` ∈ [0, 1] sampled on the shared grid (index `i` → `gridStart + i·dt`). Zero
    /// before this substance's own dose time.
    let engagement: [Double]
}

/// The combined CNS/respiratory-depression readout over a shared timeline.
nonisolated struct CombinedDepressionResult {
    /// Combined load `L = Σ wClass·doseWeight·e(t)` at each grid step (index `i` → `gridStart + i·dt`).
    let sampleLoads: [Double]
    let dtMinutes: Double
    let gridStart: Date
    /// Peak combined load.
    let peakLoad: Double
    /// Minutes from `gridStart` to the peak.
    let peakMinute: Double
    /// Wall-clock time of the peak.
    let peakDate: Date
    /// Qualitative band of the peak, or `nil` when the load never reaches ``CombinedDepression/cautionThreshold``.
    let band: InteractionSeverity?
    /// Weakest-link confidence across the contributors — the "predicted (model, confidence)" tier.
    let confidence: ConfidenceTier
    /// How many contributors used real occupancy (vs the effect-shape surrogate).
    let modeledCount: Int
    /// Total depressant contributors.
    let totalCount: Int

    /// `true` when every contributor used real occupancy data (no surrogate fallback).
    var isFullyModeled: Bool {
        modeledCount == totalCount
    }

    /// `true` when the peak reaches at least the caution band — i.e. there is a meaningful combined
    /// depression to surface.
    var hasMeaningfulLoad: Bool {
        band != nil
    }

    /// `(minuteFromStart, load)` samples for charting.
    var points: [(minute: Double, load: Double)] {
        sampleLoads.enumerated().map { (Double($0.offset) * dtMinutes, $0.element) }
    }

    /// Depression-specific level label, kept distinct from the pair rule's own severity wording so the
    /// two readouts don't visually clash. Drawn from ``band``.
    var levelLabel: LocalizedStringResource? {
        switch band {
        case .dangerous: "Severe"
        case .unsafe: "High"
        case .caution: "Moderate"
        case nil: nil
        }
    }
}

/// Computes the combined CNS/respiratory-depression index — the deepest layer of the interaction
/// de-noising work (`Specs/pharmacology-axis-meta-plan.md`, Stage 3b).
///
/// ## What it is
/// For the additive depressant mechanisms it computes a **single weighted load over time**
/// ```
/// L(t) = Σᵢ  wClassᵢ · doseWeightᵢ · eᵢ(t)
/// ```
/// from each depressant substance's engagement `eᵢ(t)`, and surfaces the **peak value and when** —
/// "your combined respiratory depression peaks at ~02:30," not "two depressant tags co-exist." This
/// is where interactions and the PD engine share math: `eᵢ(t)` is the same absolute-exposure → Hill
/// occupancy the tolerance engine uses (``ToleranceStore``).
///
/// ## Graceful degradation (mixed per-contributor)
/// Real receptor occupancy needs a graded Vd + Kᵢ + molar mass — present only for flagship substances.
/// Most depressants degrade (diazepam ships without a molar mass; ethanol has no meaningful Kᵢ), so
/// each contributor independently uses occupancy where it can and the 3a effect-curve surrogate where
/// it can't, combined into one curve. The surrogate is deliberately *conservative* — a known-dose
/// substance is treated as fully engaged at its effect peak (effect shape peaks at 1), erring toward
/// warning, which is the safe bias for a depression readout. The result carries the weakest-link
/// confidence and an "N of M modeled" count so the UI badges exactly how much to trust it.
///
/// ## Calibration
/// `wClass` and the band thresholds are calibrated against the already-encoded dangerous pairs:
/// opioid+benzo and opioid+alcohol at realistic concurrent doses must reach ``dangerousThreshold``,
/// while a single moderate opioid stays below it. The numbers are ordinal/relative, never a
/// physiological percentage.
nonisolated enum CombinedDepression {
    // MARK: - Calibration constants

    /// Combined-load thresholds for the qualitative band. Calibrated so opioid+benzo and opioid+alcohol
    /// at realistic concurrent doses land at/above ``dangerousThreshold`` while a single moderate
    /// opioid stays below it (`ToleranceStore`-style end-to-end gate in `CombinedDepressionTests`).
    static let cautionThreshold = 0.45
    static let unsafeThreshold = 0.85
    static let dangerousThreshold = 1.15

    /// Integration timestep (minutes). 15 min resolves the peak time finely without much cost over the
    /// bounded window.
    static let defaultTimestepMinutes = 15.0

    /// Hard cap on the simulated span so an outlier long-acting dose can't make the grid unbounded.
    private static let maxSpanMinutes = 72.0 * 60

    /// Dose-presence smoothstep window, mirroring ``InteractionChecker``'s gate so a clearly
    /// sub-threshold surrogate dose barely contributes.
    private static let presenceLow = 0.04
    private static let presenceFull = 0.25

    // MARK: - Band

    /// The qualitative band a combined-load peak falls in, or `nil` below ``cautionThreshold``.
    static func band(forLoad load: Double) -> InteractionSeverity? {
        if load >= dangerousThreshold { return .dangerous }
        if load >= unsafeThreshold { return .unsafe }
        if load >= cautionThreshold { return .caution }
        return nil
    }

    // MARK: - Pure reducer (the testable core)

    /// Sum the contributors' weighted engagement into a combined-load timeline and locate the peak.
    /// Pure — no I/O, no resolution — so the math is unit-testable with synthetic curves. Returns
    /// `nil` when there are no contributors or no samples.
    static func reduce(
        curves: [DepressantContributor],
        dtMinutes: Double,
        gridStart: Date,
    ) -> CombinedDepressionResult? {
        guard !curves.isEmpty, dtMinutes > 0 else { return nil }
        let count = curves.map(\.engagement.count).max() ?? 0
        guard count > 0 else { return nil }

        var loads = [Double](repeating: 0, count: count)
        for c in curves {
            let w = c.mechanism.weight * c.doseWeight
            guard w > 0 else { continue }
            for i in 0 ..< c.engagement.count {
                loads[i] += w * max(0, c.engagement[i])
            }
        }

        var peakIndex = 0
        var peak = 0.0
        for (i, v) in loads.enumerated() where v > peak {
            peak = v
            peakIndex = i
        }

        let peakMinute = Double(peakIndex) * dtMinutes
        return CombinedDepressionResult(
            sampleLoads: loads,
            dtMinutes: dtMinutes,
            gridStart: gridStart,
            peakLoad: peak,
            peakMinute: peakMinute,
            peakDate: gridStart.addingTimeInterval(peakMinute * 60),
            band: band(forLoad: peak),
            confidence: curves.map(\.confidence).min() ?? .unverified,
            modeledCount: curves.filter(\.isModeled).count,
            totalCount: curves.count,
        )
    }

    // MARK: - Resolution + analysis (MainActor: reads the substance store)

    /// Resolve a dose log into the combined-depression readout. Non-depressant entries are ignored;
    /// returns `nil` when no entry is an additive CNS/respiratory depressant. `weightKg` defaults to
    /// the user's effective body weight.
    @MainActor
    static func analyze(
        entries: [DoseEntry],
        weightKg: Double? = nil,
        timestepMinutes: Double = defaultTimestepMinutes,
    ) -> CombinedDepressionResult? {
        let weight = weightKg ?? UserProfileStore.shared.effectiveWeightKg
        guard weight > 0, !entries.isEmpty else { return nil }

        let resolved = entries.compactMap { resolveContributor(for: $0, weightKg: weight) }
        guard !resolved.isEmpty else { return nil }

        let gridStart = resolved.map(\.start).min()!
        let rawEnd = resolved.map(\.end).max()!
        let span = min(rawEnd.timeIntervalSince(gridStart) / 60, maxSpanMinutes)
        guard span > 0 else { return nil }

        let steps = max(1, Int(ceil(span / timestepMinutes)))
        let sampleCount = steps + 1

        let curves: [DepressantContributor] = resolved.map { r in
            let offsetMinutes = r.start.timeIntervalSince(gridStart) / 60
            var engagement = [Double](repeating: 0, count: sampleCount)
            for i in 0 ..< sampleCount {
                let minute = Double(i) * timestepMinutes
                let sinceDose = minute - offsetMinutes
                engagement[i] = sinceDose >= 0 ? r.engagement(sinceDose) : 0
            }
            return DepressantContributor(
                substance: r.substance, mechanism: r.mechanism, doseWeight: r.doseWeight,
                confidence: r.confidence, isModeled: r.isModeled, engagement: engagement,
            )
        }

        return reduce(curves: curves, dtMinutes: timestepMinutes, gridStart: gridStart)
    }

    // MARK: - Per-entry contributor resolution

    /// An entry resolved to its depressant mechanism plus a closure giving engagement `e` at minutes
    /// since its own dose — occupancy where the data allows, the effect-shape surrogate otherwise.
    private struct ResolvedContributor {
        let substance: String
        let mechanism: DepressantMechanism
        let doseWeight: Double
        let confidence: ConfidenceTier
        let isModeled: Bool
        let start: Date
        let end: Date
        let engagement: (Double) -> Double
    }

    @MainActor
    private static func resolveContributor(for entry: DoseEntry, weightKg: Double) -> ResolvedContributor? {
        let doseMg = DoseUnit.convert(entry.amount, from: entry.unit, to: "mg")
        let params = SubstanceStore.shared.pharmacologyParameters(forSubstanceName: entry.substance)

        // Occupancy path: the most-potent engaged target that is itself a depressant mechanism, when
        // the absolute-exposure inputs (Vd, molar mass, half-life, F) and a dose are all present.
        if let doseMg, doseMg > 0, params.canComputeOccupancy,
           let vdPerKg = params.vdLPerKg, let mw = params.molarMassGramsPerMole,
           let f = params.bioavailabilityFraction, let halfLife = params.halfLifeMinutes,
           let depressantTarget = params.targets.first(where: {
               DepressantMechanism.from(receptorClass: ReceptorClasses.classify(target: $0.target, action: $0.action)) != nil
           }) {
            let vd = vdPerKg * weightKg
            if vd > 0, mw > 0, halfLife > 0 {
                let mechanism = DepressantMechanism.from(
                    receptorClass: ReceptorClasses.classify(target: depressantTarget.target, action: depressantTarget.action),
                )!
                let ke = PKModel.ke(fromHalfLifeMinutes: halfLife)
                let ka = PKModel.defaultKa(ke: ke)
                let prefactorNanomolar = (f * doseMg / vd) / 1_000 / mw * 1e9
                let halfMax = depressantTarget.halfMaxNanomolar
                let tail = PKModel.timeToFraction(0.03, ke: ke, ka: ka, maxMinutes: halfLife * 8)
                return ResolvedContributor(
                    substance: entry.substance, mechanism: mechanism, doseWeight: 1,
                    confidence: Swift.min(params.vdConfidence, depressantTarget.confidence),
                    isModeled: true,
                    start: entry.timestamp,
                    end: entry.timestamp.addingTimeInterval(tail * 60),
                    engagement: { sinceDose in
                        let free = prefactorNanomolar * PKModel.concentration(at: sinceDose, ke: ke, ka: ka)
                        return PKModel.occupancy(concentration: free, halfMax: halfMax)
                    },
                )
            }
        }

        // Surrogate path: classify by drug class, ride the effect-curve shape (3a's signal). Used for
        // every depressant the occupancy path can't model (most of them).
        guard let mechanism = InteractionChecker.drugClasses(for: entry.substance)
            .lazy.compactMap({ DepressantMechanism.from(drugClass: $0) }).first
        else { return nil }

        guard let state = ActiveSubstanceState.from(entry: entry, colorHex: "") else { return nil }
        let amountKnown = doseMg != nil && entry.amount > 0
        let doseWeight = amountKnown ? presence(state.doseMagnitude) : 1
        let endMinutes = max(state.offsetEndMinutes, state.totalMinutes)
        return ResolvedContributor(
            substance: entry.substance, mechanism: mechanism, doseWeight: doseWeight,
            confidence: .low, isModeled: false,
            start: entry.timestamp,
            end: entry.timestamp.addingTimeInterval(endMinutes * 60),
            engagement: { sinceDose in TimelineCurveModel.effectShape(at: sinceDose, for: state) },
        )
    }

    /// Dose-presence weight in `[0, 1]` — smoothstep over `[presenceLow, presenceFull]`, matching the
    /// 3a gate so a clearly sub-threshold surrogate dose barely registers.
    private static func presence(_ magnitude: Double) -> Double {
        let t = min(1, max(0, (magnitude - presenceLow) / (presenceFull - presenceLow)))
        return t * t * (3 - 2 * t)
    }
}
