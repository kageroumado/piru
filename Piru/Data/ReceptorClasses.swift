import Foundation

/// Routes a receptor/transporter `target` to its **tolerance class** and that class's right-shift
/// parameters for the ``PDModel`` layered `S(t)`. This is the curated, evidence-tiered table the
/// engine reads instead of applying one universal "tolerance %" — the load-bearing design claim is
/// that tolerance is *per-mechanism*, set by the target Piru already stores.
///
/// ## Honesty
/// Binding affinities (Kᵢ/EC₅₀/Vd) come from the citation-verified flagship evidence run; the
/// **tolerance kinetics (the layer ln-shift ceilings and τ) here do not** — that run graded
/// exposure/affinity, not adaptation rates, which are the field's softest numbers (over-claiming them
/// is exactly the PsychonautWiki failure the engine refuses). So every class ships its kinetics
/// flagged ``ConfidenceTier`` — `.medium` only where a controlled-human value anchors it (the
/// psychedelic subjective-recovery window, flagship-corrected to ~3–4 d), `.low` (class-default,
/// order-of-magnitude) otherwise. The constants are calibrated to reproduce the *shape* the
/// literature agrees on (clustered dosing right-shifts the curve, spacing relaxes it; the acute layer
/// moves within a session while the adaptive layer is the days–weeks baseline shift; the deep layer
/// stays off for therapeutic users), not a false-precision percentage. These are the **Stage A
/// initial** values; the Stage B literature pass (`Specs/tolerance-faithful-model.md` §3) refines
/// them.
nonisolated enum ReceptorClasses {
    // MARK: - Time-constant vocabulary (minutes)

    private enum T {
        static let hour = 60.0
        static let day = 1_440.0
        static let week = 7 * day
        static let month = 30 * day
    }

    // MARK: - Tolerance class

    /// The mechanism family a target belongs to — what kind of tolerance it shows.
    enum ReceptorClass: String, CaseIterable {
        /// Classic serotonergic psychedelics (5-HT2A agonists): fast, near-total, valid multiplier.
        case psychedelic5HT2A
        /// μ-opioid agonists: the reset-after-break overdose axis.
        case muOpioid
        /// Catecholamine transporters (DAT/NET) — stimulants: strong acute tachyphylaxis, a *months*
        /// allostatic axis that is **not** a dose multiplier.
        case catecholamineStimulant
        /// Serotonin transporter (SERT) releasers/blockers — MDMA-type: reversible-leaning, partial.
        case serotonergicReleaser
        /// GABA-A/B (benzodiazepines, alcohol): dependence + kindling axis.
        case gaba
        /// NMDA antagonists (ketamine, DXM, MXE): cumulative-toxicity axis; also a tolerance modulator.
        case nmdaAntagonist
        /// CB1 cannabinoids (THC): fast, real, recoverable tolerance.
        case cannabinoidCB1
        /// Adenosine receptors (caffeine): clean, well-behaved tolerance.
        case adenosine
        /// Nicotinic ACh receptors (nicotine): desensitization-driven, fast.
        case nicotinic
        /// No curated class — generic class-default kinetics at the lowest confidence.
        case unknown

        /// Short user-facing name for the tolerance class — the Stage-2 Tool card headline.
        var displayName: LocalizedStringResource {
            switch self {
            case .psychedelic5HT2A: "Psychedelics (5-HT2A)"
            case .muOpioid: "Opioids (μ)"
            case .catecholamineStimulant: "Stimulants (DAT/NET)"
            case .serotonergicReleaser: "Serotonin releasers (SERT)"
            case .gaba: "GABA (benzos / alcohol)"
            case .nmdaAntagonist: "Dissociatives (NMDA)"
            case .cannabinoidCB1: "Cannabinoids (CB1)"
            case .adenosine: "Adenosine (caffeine)"
            case .nicotinic: "Nicotinic (nAChR)"
            case .unknown: "Other"
            }
        }
    }

    /// The harm-reduction axis a class hands tolerance off to (drives Stage-2/5 copy; not yet shown).
    enum SafetyAxis: String {
        case none
        case resetOverdose
        case stimulantLoad
        case serotonergicLoad
        case dependenceKindling
        case cumulativeToxicity
        case hppd
    }

    // MARK: - Per-class parameters

    /// Right-shift parameters for one tolerance class: the three log-space layers that sum into
    /// `ln S(t)` (see ``PDModel``), each a leaky integrator toward `shiftMax · occupancy · drive`.
    /// Everything is now one unified shift — the old availability-multiplier-vs-load split is gone;
    /// the gauge is the saturating ``PDModel/responseFraction(shiftFactor:representativeOccupancy:)``
    /// at the user's usual dose. The closed-form
    /// ``PDModel/stepShift(current:shiftMax:occupancy:drive:dtMinutes:tauMinutes:)`` keeps integration
    /// stable on any timestep, so these are calibrated by the steady-state ln-shift a saturating dose
    /// pattern produces, not by a fragile Euler grid.
    struct Parameters {
        /// Acute-layer ln-shift ceiling (within-session tachyphylaxis). `0` ⇒ the class has no acute
        /// pool, so the layer never contributes.
        let acuteShiftMax: Double
        /// Acute-layer build/recover time-constant (minutes) — hours; recovers overnight.
        let tauAcuteMinutes: Double
        /// Adaptive-layer ln-shift ceiling — the days–weeks baseline shift people mean by "tolerance".
        let adaptiveShiftMax: Double
        /// Adaptive-layer build/recover time-constant (minutes) — days to ~2 weeks.
        let tauAdaptiveMinutes: Double
        /// Deep-layer ln-shift ceiling (entrenched neuroadaptation). `0` ⇒ no deep layer.
        let deepShiftMax: Double
        /// Deep-layer build/recover time-constant (minutes) — months.
        let tauDeepMinutes: Double
        /// Adaptive ln-shift value at which the deep layer begins to engage (the escalation
        /// threshold). A large value (e.g. 99) with `deepShiftMax == 0` keeps the gate at 0 always.
        let deepGateThreshold: Double
        /// Width of the deep-layer smoothstep gate above ``deepGateThreshold``.
        let deepGateWidth: Double
        /// The harm-reduction axis this class maps to.
        let safetyAxis: SafetyAxis
        /// Confidence in *these kinetics* (not the affinity data) — see the type doc.
        let confidence: ConfidenceTier
        /// CNS-distribution volume-of-distribution fallback (L/kg), used (flagged ``ConfidenceTier/unverified``)
        /// when a substance in this class has no graded Vd of its own — e.g. LSD, which the evidence
        /// run left without a Vd.
        let classDefaultVdLPerKg: Double
        /// Human-readable provenance/calibration note.
        let sourceNote: String

        /// Whether the class has a meaningful within-session acute (redose) pool.
        var hasAcutePool: Bool { acuteShiftMax > 0 }
    }

    /// The curated right-shift parameters for a class. These are the **Stage A initial** values
    /// (Stage B refines them from the literature pass); calibrated to the literature's *shape*, see the
    /// type doc for the honesty stance and confidence grading.
    static func parameters(for receptorClass: ReceptorClass) -> Parameters {
        switch receptorClass {
        case .psychedelic5HT2A:
            // Subjective 5-HT2A tachyphylaxis recovers in ~3–4 d (controlled-human; flagship
            // correction 2026-06-21). Near-total over consecutive days → a large adaptive ceiling;
            // psychedelics aren't redosed within a session, so no acute layer; no deep layer.
            Parameters(
                acuteShiftMax: 0, tauAcuteMinutes: 4 * T.hour,
                adaptiveShiftMax: 2.5, tauAdaptiveMinutes: 3.5 * T.day,
                deepShiftMax: 0, tauDeepMinutes: 3 * T.month, deepGateThreshold: 99, deepGateWidth: 1,
                safetyAxis: .hppd, confidence: .medium,
                classDefaultVdLPerKg: 4.0,
                sourceNote: "Subjective recovery ~3–4 d (controlled-human; flagship-corrected). Adaptive ln-shift calibrated to near-total consecutive-day tachyphylaxis; no acute or deep layer.",
            )
        case .muOpioid:
            // Days-to-weeks adaptive shift, a mild within-session acute pool, and a gated deep layer:
            // chronic escalation entrenches over months (the reset-after-break overdose axis is the
            // safety hand-off, Stage C/F).
            Parameters(
                acuteShiftMax: 0.3, tauAcuteMinutes: 4 * T.hour,
                adaptiveShiftMax: 2.0, tauAdaptiveMinutes: 10 * T.day,
                deepShiftMax: 1.5, tauDeepMinutes: 6 * T.month, deepGateThreshold: 1.4, deepGateWidth: 0.6,
                safetyAxis: .resetOverdose, confidence: .low,
                classDefaultVdLPerKg: 3.0,
                sourceNote: "Days–weeks adaptive shift + months-scale gated deep layer (class-default order-of-magnitude). Safety axis: tolerance-reset overdose after a break.",
            )
        case .catecholamineStimulant:
            // The flagship three-layer class. STRONG acute layer (vesicular depletion → the redose
            // loop), recovers overnight. A modest adaptive baseline shift. The deep layer is OFF for
            // therapeutic users (low adaptive shift keeps the gate closed) and only entrenches after
            // heavy chronic escalation — months to recover, asymptoting at its ceiling.
            Parameters(
                acuteShiftMax: 0.8, tauAcuteMinutes: 9 * T.hour,
                adaptiveShiftMax: 0.4, tauAdaptiveMinutes: 10 * T.day,
                deepShiftMax: 1.6, tauDeepMinutes: 2 * T.month, deepGateThreshold: 0.30, deepGateWidth: 0.15,
                safetyAxis: .stimulantLoad, confidence: .low,
                classDefaultVdLPerKg: 4.0,
                sourceNote: "Acute vesicular-depletion tachyphylaxis (overnight) + modest adaptive shift + a deep layer gated OFF below escalation (months, asymptoting). Class-default kinetics.",
            )
        case .serotonergicReleaser:
            // MDMA-type SERT releasers: a within-session acute fade plus a weeks-scale adaptive shift
            // (reversible-leaning). No deep layer in Stage A (the per-substance synthesis-suppression
            // split is Stage E).
            Parameters(
                acuteShiftMax: 0.5, tauAcuteMinutes: 12 * T.hour,
                adaptiveShiftMax: 1.5, tauAdaptiveMinutes: 3 * T.week,
                deepShiftMax: 0, tauDeepMinutes: 3 * T.month, deepGateThreshold: 99, deepGateWidth: 1,
                safetyAxis: .serotonergicLoad, confidence: .low,
                classDefaultVdLPerKg: 5.0,
                sourceNote: "Within-session acute fade + weeks-scale reversible-leaning adaptive shift (no fitted human kinetics — pilot). Per-substance MDMA-vs-cathinone clock is Stage E.",
            )
        case .gaba:
            // Benzodiazepines / alcohol: a redose pool plus a days–weeks adaptive shift; dependence +
            // kindling is the safety hand-off.
            Parameters(
                acuteShiftMax: 0.4, tauAcuteMinutes: 6 * T.hour,
                adaptiveShiftMax: 1.2, tauAdaptiveMinutes: 10 * T.day,
                deepShiftMax: 0, tauDeepMinutes: 3 * T.month, deepGateThreshold: 99, deepGateWidth: 1,
                safetyAxis: .dependenceKindling, confidence: .low,
                classDefaultVdLPerKg: 1.1,
                sourceNote: "Days–weeks adaptive shift + a redose pool (class-default). Safety axis: dependence + kindling on repeated withdrawal.",
            )
        case .nmdaAntagonist:
            // Ketamine / DXM / MXE: days-scale adaptive shift + a redose pool; cumulative toxicity.
            // Also a modulator of others' tolerance (ToleranceModulation).
            Parameters(
                acuteShiftMax: 0.4, tauAcuteMinutes: 4 * T.hour,
                adaptiveShiftMax: 1.0, tauAdaptiveMinutes: 3 * T.day,
                deepShiftMax: 0, tauDeepMinutes: 3 * T.month, deepGateThreshold: 99, deepGateWidth: 1,
                safetyAxis: .cumulativeToxicity, confidence: .low,
                classDefaultVdLPerKg: 3.0,
                sourceNote: "Days-scale adaptive shift + a redose pool (class-default). Cumulative-toxicity axis (e.g. ketamine bladder).",
            )
        case .cannabinoidCB1:
            // THC: fast, real, recoverable CB1 tolerance — a redose pool + a days-scale adaptive shift.
            Parameters(
                acuteShiftMax: 0.3, tauAcuteMinutes: 6 * T.hour,
                adaptiveShiftMax: 1.2, tauAdaptiveMinutes: 4 * T.day,
                deepShiftMax: 0, tauDeepMinutes: 3 * T.month, deepGateThreshold: 99, deepGateWidth: 1,
                safetyAxis: .none, confidence: .low,
                classDefaultVdLPerKg: 3.4,
                sourceNote: "Fast, real, recoverable CB1 tolerance — a redose pool + a days-scale adaptive shift (class-default).",
            )
        case .adenosine:
            // Caffeine: clean, well-behaved up-regulation tolerance over days; no within-session pool.
            Parameters(
                acuteShiftMax: 0, tauAcuteMinutes: 4 * T.hour,
                adaptiveShiftMax: 1.0, tauAdaptiveMinutes: 5 * T.day,
                deepShiftMax: 0, tauDeepMinutes: 3 * T.month, deepGateThreshold: 99, deepGateWidth: 1,
                safetyAxis: .none, confidence: .low,
                classDefaultVdLPerKg: 0.6,
                sourceNote: "Clean adenosine-receptor up-regulation tolerance over days (class-default); no within-session pool.",
            )
        case .nicotinic:
            // Nicotine: desensitization-driven — a strong, fast acute layer plus a fast adaptive shift.
            Parameters(
                acuteShiftMax: 0.8, tauAcuteMinutes: 2 * T.hour,
                adaptiveShiftMax: 0.4, tauAdaptiveMinutes: 1 * T.day,
                deepShiftMax: 0, tauDeepMinutes: 3 * T.month, deepGateThreshold: 99, deepGateWidth: 1,
                safetyAxis: .none, confidence: .low,
                classDefaultVdLPerKg: 2.6,
                sourceNote: "nAChR desensitization dominates — a fast, strong acute layer + a fast adaptive shift (class-default).",
            )
        case .unknown:
            // Generic, deliberately weak default at the lowest confidence.
            Parameters(
                acuteShiftMax: 0, tauAcuteMinutes: 4 * T.hour,
                adaptiveShiftMax: 0.7, tauAdaptiveMinutes: 7 * T.day,
                deepShiftMax: 0, tauDeepMinutes: 3 * T.month, deepGateThreshold: 99, deepGateWidth: 1,
                safetyAxis: .none, confidence: .unverified,
                classDefaultVdLPerKg: 1.0,
                sourceNote: "No curated tolerance class — generic class-default kinetics.",
            )
        }
    }

    // MARK: - Routing

    /// The **mechanism-defining** binding actions for each tolerance class. An engagement is assigned
    /// to a class only when its target *and* its action match — direction matters, and it is
    /// per-class, not a global "agonists only" rule:
    /// - A 5-HT2A **antagonist** (mirtazapine) is not a psychedelic; an α7 nAChR **antagonist**
    ///   (memantine) is not nicotine — both are off-mechanism and drop out.
    /// - But caffeine (an adenosine **antagonist**) and ketamine (an NMDA **channel blocker**) are
    ///   correct, because antagonism *is* the tolerance mechanism of those classes.
    /// Used by the tolerance engine; `classify(target:)` with no action stays target-only (legacy) for
    /// CNS-distribution Vd fallback and cache reload, where direction is irrelevant.
    static func mechanismActions(for receptorClass: ReceptorClass) -> Set<BindingAction> {
        switch receptorClass {
        case .psychedelic5HT2A: [.agonist, .partialAgonist]
        case .muOpioid: [.agonist, .partialAgonist]
        case .catecholamineStimulant: [.releasingAgent, .reuptakeInhibitor]
        // SERT *releasers* (MDMA-type) only — plain reuptake inhibition is the SSRI / cocaine story,
        // a different tolerance, so cocaine/DXM SERT blockade does not become a "serotonin releaser".
        case .serotonergicReleaser: [.releasingAgent]
        case .gaba: [.positiveAllostericModulator, .agonist]
        case .nmdaAntagonist: [.antagonist, .channelBlocker, .negativeAllostericModulator]
        case .cannabinoidCB1: [.agonist, .partialAgonist]
        case .adenosine: [.antagonist]
        case .nicotinic: [.agonist, .partialAgonist]
        case .unknown: []
        }
    }

    /// Classify a target string into a tolerance class by name only — case-insensitive prefix/substring
    /// matching to absorb the DB's qualifying suffixes (`"GABA-A α1β2γ2"`, `"nAChR α4β2"`,
    /// `"Adenosine A2A"`). Falls back to ``ReceptorClass/unknown``.
    private static func matchTarget(_ target: String) -> ReceptorClass {
        let t = target.lowercased()

        if t.contains("5-ht2a") || t.contains("5ht2a") { return .psychedelic5HT2A }
        if t.contains("mor") || t.contains("μ-opioid") || t.contains("mu-opioid") || t.contains("μ opioid") { return .muOpioid }
        if t.contains("sert") || t.contains("serotonin transporter") { return .serotonergicReleaser }
        if t.contains("dat") || t.contains("net") || t.contains("dopamine transporter")
            || t.contains("norepinephrine transporter") || t.contains("noradrenaline transporter") { return .catecholamineStimulant }
        if t.contains("gaba") { return .gaba }
        if t.contains("nmda") { return .nmdaAntagonist }
        if t.contains("cb1") || t.contains("cannabinoid") { return .cannabinoidCB1 }
        if t.contains("adenosine") { return .adenosine }
        if t.contains("nachr") || t.contains("nicotinic") || t.contains("acetylcholine") { return .nicotinic }

        return .unknown
    }

    /// Classify a target into its tolerance class. With no `action`, this is name-only (legacy — used
    /// for the Vd fallback and cache reload). With an `action`, the **mechanism-direction gate**
    /// applies: a target whose action isn't in ``mechanismActions(for:)`` is off-mechanism and returns
    /// ``ReceptorClass/unknown`` (so it drives no tolerance card).
    static func classify(target: String, action: BindingAction? = nil) -> ReceptorClass {
        let cls = matchTarget(target)
        guard cls != .unknown, let action else { return cls }
        return mechanismActions(for: cls).contains(action) ? cls : .unknown
    }

    /// The tolerance parameters for a target string — `classify` then `parameters(for:)`.
    static func parameters(forTarget target: String, action: BindingAction? = nil) -> Parameters {
        parameters(for: classify(target: target, action: action))
    }

    /// A display-canonical receptor name for the card breakdown: strips parenthetical qualifiers
    /// (`"(recombinant human)"`, `"(MK-801 site, S-enantiomer)"`, `"(PCP site)"`), enantiomer prefixes
    /// (`"(+)-"`, `"(−)-"`), and a trailing `" receptor"`, so `"5-HT3 receptor"`, `"NMDA receptor (PCP
    /// site)"`, and `"MOR (+)-tramadol"` collapse to `"5-HT3"`, `"NMDA"`, `"MOR"`. Best-effort
    /// normalisation for the sub-target list — the pipeline owns the authoritative cleanup (Phase 2).
    static func canonicalTarget(_ raw: String) -> String {
        var s = raw
        // Drop a parenthetical qualifier *and everything after it* first — this also removes the
        // " (−)-tramadol" / " (MK-801 site, …)" enantiomer/site suffixes, so `"NET (−)-tramadol"` and
        // `"NMDA (MK-801 site, S-enantiomer)"` collapse to `"NET"` / `"NMDA"`.
        if let open = s.range(of: " (") { s = String(s[..<open.lowerBound]) }
        for prefix in ["(+)-", "(−)-", "(-)-", "(±)-"] {
            s = s.replacingOccurrences(of: prefix, with: "")
        }
        if s.hasSuffix(" receptor") { s = String(s.dropLast(" receptor".count)) }
        return s.trimmingCharacters(in: .whitespaces)
    }
}
