import Foundation
import os

/// A monoamine transporter at which a *releaser* (a transporter substrate) can be **blunted** by a
/// co-present *reuptake blocker* that competes for the same transporter.
///
/// A releaser (MDMA-type) works by being carried *into* the neuron through the transporter and then
/// reversing it to dump neurotransmitter. A reuptake blocker (an SSRI) occupies the transporter and
/// physically prevents the substrate from entering — so the releaser's transporter-mediated effect is
/// reduced. v1 seeds only **SERT** (the cleanest evidenced case); DAT/NET are structurally supported
/// by the same role detection but ship no graded reduction band until evidenced.
nonisolated enum CompetingTransporter: String {
    case sert

    /// Classify a binding `target` string to a competing transporter, or `nil`. Case-insensitive and
    /// substring-based to absorb the DB's qualifying suffixes (`"SERT (uptake, human)"`) — a loose
    /// substring relation like `ReceptorClasses.matchTarget`, not a `ReceptorTargetKey` fold.
    static func from(target: String) -> CompetingTransporter? {
        let t = target.lowercased()
        if t.contains("sert") || t.contains("serotonin transporter") { return .sert }
        return nil
    }

    /// Short transporter phrase for the readout copy.
    var displayName: LocalizedStringResource {
        switch self {
        case .sert: "serotonin transporter"
        }
    }

    /// A transporter's evidence-anchored fractional-reduction range.
    struct Band: Sendable {
        let low: Double
        let high: Double
    }

    /// The bands read from `attenuation_bands`, keyed by ``rawValue``. Held in a lock-guarded static
    /// rather than queried per call because the readers are `nonisolated` and run inside the
    /// interaction analysis, and installed once by ``SubstanceStore`` at index build. Before the load
    /// lands, ``reductionBand`` is `nil` and no attenuation result is produced.
    private static let bands = OSAllocatedUnfairLock<[String: Band]>(initialState: [:])

    /// Install the bands read from `attenuation_bands`. Called once per store init.
    static func load(_ loaded: [String: Band]) {
        bands.withLock { $0 = loaded }
    }

    /// Evidence-anchored fractional-reduction band for a releaser at this transporter when a blocker
    /// occupies it, or `nil` when the database ships none. It is a *range*, never a single fabricated
    /// %, because the relationship between transporter occupancy and subjective blunting is not 1:1.
    var reductionBand: Band? {
        Self.bands.withLock { $0[rawValue] }
    }
}

/// One predicted **effect-attenuation** ("it won't work as well") between a releaser and the
/// reuptake blocker(s) competing for its transporter — a *sign-flipped* interaction readout, distinct
/// from the danger stacking the rest of the interaction engine surfaces.
nonisolated struct EffectAttenuationResult: Identifiable {
    /// The releaser whose effect is predicted to be blunted (e.g. MDMA).
    let attenuated: String
    /// The co-present reuptake blocker(s) occupying the transporter (e.g. an SSRI), recency order.
    let blockers: [String]
    let transporter: CompetingTransporter
    /// Predicted fractional reduction band `[low, high]` ∈ [0, 1] (e.g. 0.30…0.80).
    let reductionLow: Double
    let reductionHigh: Double
    /// "predicted (model, confidence)" tier — HIGH for the directly-evidenced empathogen × SSRI
    /// archetype, lower for a structurally-detected but less-directly-evidenced pair.
    let confidence: ConfidenceTier

    var id: String {
        "\(attenuated)|\(transporter.rawValue)"
    }

    /// "30–80%" style percentage range for the headline.
    var reductionRangeText: String {
        let lo = Int((reductionLow * 100).rounded())
        let hi = Int((reductionHigh * 100).rounded())
        return "\(lo)\u{2013}\(hi)%"
    }
}

/// Computes predicted **effect attenuation** — the sign-flipped interaction readout
/// (`Specs/pharmacology-axis-meta-plan.md`, Stage 3c).
///
/// ## What it is, and what it is NOT
/// Some "warnings" in other apps are really *blunting*, not danger: a chronic SSRI competes for SERT
/// and reduces MDMA's effect by ~30–80% (controlled-human) — *"it won't work,"* not *"serotonin
/// syndrome."* SSRI + MDMA **alone lowers** serotonin-syndrome odds. This engine surfaces that as a
/// **negative-magnitude readout**, deliberately separate from the depression/danger surfaces. It does
/// **not** touch the genuine lethal serotonergic edge (MAOI + serotonergic), which remains a hard
/// danger rule in ``InteractionChecker``.
///
/// ## Faithfulness (Foundation C)
/// With the Stage-0 default unbound fraction (`fu = 1`) the Hill occupancy of a sub-nanomolar-Kᵢ SSRI
/// at SERT saturates to ~100%, which would *over-predict* blunting (real PET SERT occupancy ≈ 80%, the
/// behavioral blunting 30–80%). So this readout does **not** present a computed occupancy % as the
/// reduction — it surfaces the **evidence-anchored band** for the transporter, gated only on the two
/// roles being concurrently present. Every figure is "predicted (model, confidence)", never measured.
///
/// ## v1 scope ("start specific, structure for generality")
/// The transporter abstraction and role detection are general, but a result ships only when a
/// **releaser** (an empathogen, or a binding `releasingAgent` at a competing transporter) is co-present
/// with an **antidepressant** reuptake blocker (SSRI/SNRI/TCA — the trust anchor for the band).
/// MAOIs are excluded (they are the danger edge, not blunting). Adding DAT/NET bands or non-
/// antidepressant blockers later is a data change, not a structural one.
nonisolated enum EffectAttenuation {
    /// Fraction of a blocker's peak level (terminal half-life decay) below which it is treated as no
    /// longer meaningfully onboard. 0.25 ≈ two half-lives — for a chronically-dosed SSRI the most recent
    /// dose is hours old so presence is ~1, while a one-off dose weeks ago falls away. This is what
    /// replaces the short subjective-effect window: an antidepressant is *pharmacologically* present far
    /// longer than its acute effects, which the half-life captures and the effect curve does not.
    private static let onboardThreshold = 0.25

    /// Half-life used for a blocker with no resolvable half-life (a conservative day).
    private static let defaultBlockerHalfLifeMinutes = 1_440.0

    /// Resolve a set of doses into the effect-attenuation readouts among them. Returns one result per
    /// blunted releaser (with all of its onboard blockers folded in). Empty when no releaser ×
    /// reuptake-blocker competition is concurrently present. Ordered most-confident first.
    ///
    /// A blocker counts only while it is **pharmacologically onboard during the releaser's active
    /// window** — gated on its terminal half-life decay, not the short subjective-effect window. So a
    /// chronic SSRI taken days before tonight's MDMA still blunts it (a long half-life keeps it present),
    /// while a single SSRI dose long past does not. The entries' timestamps drive the gate (the
    /// prospective dose carries `now`).
    @MainActor
    static func analyze(entries: [DoseEntry]) -> [EffectAttenuationResult] {
        guard entries.count >= 2 else { return [] }

        // Resolve each entry's transporter roles once (carrying the entry for timing/half-life).
        struct Role {
            let entry: DoseEntry
            let releaserTransporters: Set<CompetingTransporter>
            let isEmpathogen: Bool
            let blockerTransporters: Set<CompetingTransporter>
            let isAntidepressantBlocker: Bool
            var substance: String {
                entry.substance
            }
        }
        var roles: [Role] = []
        roles.reserveCapacity(entries.count)
        for entry in entries {
            roles.append(Role(
                entry: entry,
                releaserTransporters: releaserTransporters(for: entry.substance),
                isEmpathogen: InteractionChecker.drugClasses(for: entry.substance).contains(.empathogen),
                blockerTransporters: blockerTransporters(for: entry.substance),
                isAntidepressantBlocker: isAntidepressantBlocker(entry.substance),
            ))
        }

        var results: [EffectAttenuationResult] = []
        for releaser in roles where !releaser.releaserTransporters.isEmpty {
            let releaserEnd = releaserEffectEnd(for: releaser.entry)
            for transporter in releaser.releaserTransporters {
                // Blockers: a different antidepressant that blocks this transporter and is still onboard
                // (half-life-gated) at some point during the releaser's active window.
                let blockers = roles.filter { candidate in
                    candidate.substance.lowercased() != releaser.substance.lowercased()
                        && candidate.isAntidepressantBlocker
                        && candidate.blockerTransporters.contains(transporter)
                        && blockerPresence(
                            blocker: candidate.entry,
                            releaserStart: releaser.entry.timestamp, releaserEnd: releaserEnd,
                        ) >= onboardThreshold
                }
                guard !blockers.isEmpty, let band = transporter.reductionBand else { continue }

                // De-dup blocker names, preserving order.
                var seen = Set<String>()
                let blockerNames = blockers.map(\.substance).filter { seen.insert($0.lowercased()).inserted }

                results.append(EffectAttenuationResult(
                    attenuated: releaser.substance,
                    blockers: blockerNames,
                    transporter: transporter,
                    reductionLow: band.low,
                    reductionHigh: band.high,
                    // HIGH for the directly-evidenced empathogen archetype; MEDIUM for a structurally-
                    // detected non-empathogen releaser (same mechanism, less direct human evidence).
                    confidence: releaser.isEmpathogen ? .high : .medium,
                ))
            }
        }
        return results.sorted { $0.confidence > $1.confidence }
    }

    // MARK: - Presence gating (half-life based)

    /// A blocker's fraction of peak level (terminal half-life decay) at the start of its overlap with the
    /// releaser's active window — `0` if it never overlaps that window. Models "is the blocker still
    /// onboard while the releaser is working," using its pharmacological half-life rather than the much
    /// shorter subjective-effect curve.
    @MainActor
    private static func blockerPresence(blocker: DoseEntry, releaserStart: Date, releaserEnd: Date) -> Double {
        let overlapStart = max(blocker.timestamp, releaserStart)
        guard overlapStart <= releaserEnd else { return 0 }
        let halfLife = halfLifeMinutes(for: blocker.substance) ?? defaultBlockerHalfLifeMinutes
        guard halfLife > 0 else { return 0 }
        let elapsedMinutes = overlapStart.timeIntervalSince(blocker.timestamp) / 60
        return pow(0.5, elapsedMinutes / halfLife)
    }

    /// The end of a releaser's active window — its subjective-effect duration (the interaction engine's
    /// active-substance model), falling back to ~5 half-lives, then a 6 h default.
    @MainActor
    private static func releaserEffectEnd(for entry: DoseEntry) -> Date {
        if let state = ActiveSubstanceState.from(entry: entry, colorHex: "") {
            let endMinutes = max(state.offsetEndMinutes, state.totalMinutes)
            return entry.timestamp.addingTimeInterval(endMinutes * 60)
        }
        let halfLife = halfLifeMinutes(for: entry.substance) ?? 360
        return entry.timestamp.addingTimeInterval(max(halfLife * 5, 360) * 60)
    }

    /// Resolved half-life (minutes) for a substance.
    @MainActor
    private static func halfLifeMinutes(for name: String) -> Double? {
        SubstanceLibrary.lookup(name)?.halfLifeMinutes
    }

    // MARK: - Role detection

    /// The transporters a substance *releases* at — from binding `releasingAgent` rows, plus the
    /// empathogen drug-class fallback (MDMA-type SERT releasers) so a substance without binding data is
    /// still caught.
    @MainActor
    private static func releaserTransporters(for name: String) -> Set<CompetingTransporter> {
        var transporters = Set<CompetingTransporter>()
        for t in SubstanceStore.shared.pharmacologyParameters(forSubstanceName: name).targets
            where t.action == .releasingAgent {
            if let transporter = CompetingTransporter.from(target: t.target) { transporters.insert(transporter) }
        }
        if InteractionChecker.drugClasses(for: name).contains(.empathogen) { transporters.insert(.sert) }
        return transporters
    }

    /// The transporters a substance *blocks reuptake* at — from binding `reuptakeInhibitor` rows, plus
    /// the antidepressant drug-class fallback (SSRI/SNRI/TCA → SERT) for substances without binding data.
    @MainActor
    private static func blockerTransporters(for name: String) -> Set<CompetingTransporter> {
        var transporters = Set<CompetingTransporter>()
        for t in SubstanceStore.shared.pharmacologyParameters(forSubstanceName: name).targets
            where t.action == .reuptakeInhibitor {
            if let transporter = CompetingTransporter.from(target: t.target) { transporters.insert(transporter) }
        }
        if isAntidepressantBlocker(name) { transporters.insert(.sert) }
        return transporters
    }

    /// Whether a substance is an antidepressant SERT blocker (SSRI/SNRI/TCA) — the evidence anchor for
    /// the reduction band and a persistent serotonergic state. **MAOIs are excluded**: they are the
    /// genuine additive-toxicity danger edge, not a blunting competitor.
    @MainActor
    private static func isAntidepressantBlocker(_ name: String) -> Bool {
        let classes = InteractionChecker.drugClasses(for: name)
        guard !classes.contains(.maoi) else { return false }
        return classes.contains(.ssri) || classes.contains(.snri) || classes.contains(.tca)
    }
}
