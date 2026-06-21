import Foundation

/// Routes a receptor/transporter `target` to its **tolerance class** and that class's rate constants
/// for the ``PDModel`` availability ODE. This is the curated, evidence-tiered table the engine reads
/// instead of applying one universal "tolerance %" — the load-bearing design claim is that tolerance
/// is *per-mechanism*, set by the target Piru already stores.
///
/// ## Honesty
/// Binding affinities (Kᵢ/EC₅₀/Vd) come from the citation-verified flagship evidence run; the
/// **tolerance kinetics (κ, τ) here do not** — that run graded exposure/affinity, not adaptation
/// rates, which are the field's softest numbers (over-claiming them is exactly the PsychonautWiki
/// failure the engine refuses). So every class ships its kinetics flagged ``ConfidenceTier`` —
/// `.medium` only where a controlled-human value anchors it (the psychedelic subjective-recovery
/// window, flagship-corrected to ~3–4 d), `.low` (class-default, order-of-magnitude) otherwise. The
/// constants are calibrated to reproduce the *shape* the literature agrees on (clustered dosing
/// suppresses, spacing recovers; the acute pool moves within a session while the slow axis does not),
/// not a false-precision percentage. A dedicated κ/τ evidence pass can upgrade any row later.
enum ReceptorClasses {
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

    /// Rate constants and policy for one tolerance class. `κ` is a per-minute depression rate; the
    /// closed-form ``PDModel/stepAvailability(availability:occupancy:dtMinutes:kappa:tauMinutes:modulation:)``
    /// makes the integration stable on any timestep, so these are calibrated by the per-episode
    /// availability drop a saturating dose produces, not by a fragile Euler grid.
    struct Parameters {
        /// Slow availability-axis depression rate (per minute).
        let kappaSlow: Double
        /// Slow availability-axis recovery time-constant (minutes).
        let tauSlowMinutes: Double
        /// Whether the class has a meaningful within-session acute (redose) pool.
        let hasAcutePool: Bool
        /// Acute-pool depression rate (per minute) — large; recovers overnight.
        let kappaAcute: Double
        /// Acute-pool recovery time-constant (minutes) — hours.
        let tauAcuteMinutes: Double
        /// Allostatic-load accrual gain (per minute) for the leaky integrator.
        let loadGain: Double
        /// Allostatic-load decay time-constant (minutes) — months.
        let tauLoadMinutes: Double
        /// Whether the *slow* availability is a valid multiplier on predicted effect. **False** for
        /// stimulants/releasers (the wrong-signed "tolerance %"); for those the slow axis is a
        /// recovery-state indicator only.
        let usesEffectMultiplier: Bool
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
    }

    /// The curated kinetics for a class. Values are calibrated to the literature's *shape*; see the
    /// type doc for the honesty stance and confidence grading.
    static func parameters(for receptorClass: ReceptorClass) -> Parameters {
        switch receptorClass {
        case .psychedelic5HT2A:
            // Subjective 5-HT2A tachyphylaxis recovers in ~3–4 d (controlled-human; flagship
            // correction 2026-06-21 — the "10–14 d / 2-week reset" is a harm-reduction rule, not the
            // measured τ). Near-total over consecutive days; psychedelics aren't redosed within a
            // session, so no acute pool. Valid multiplier (near-complete in-class cross-tolerance).
            Parameters(
                kappaSlow: 0.003, tauSlowMinutes: 3.5 * T.day,
                hasAcutePool: false, kappaAcute: 0, tauAcuteMinutes: 4 * T.hour,
                loadGain: 0, tauLoadMinutes: 3 * T.month,
                usesEffectMultiplier: true, safetyAxis: .hppd, confidence: .medium,
                classDefaultVdLPerKg: 4.0,
                sourceNote: "Subjective recovery ~3–4 d (controlled-human; flagship-corrected). κ class-default, calibrated to near-total consecutive-day tachyphylaxis.",
            )
        case .muOpioid:
            // Days-to-weeks recovery; mild within-session pool. Valid multiplier. The reset-after-
            // break overdose axis is the safety hand-off (Stage 5).
            Parameters(
                kappaSlow: 0.0015, tauSlowMinutes: 10 * T.day,
                hasAcutePool: true, kappaAcute: 0.004, tauAcuteMinutes: 4 * T.hour,
                loadGain: 0, tauLoadMinutes: 3 * T.month,
                usesEffectMultiplier: true, safetyAxis: .resetOverdose, confidence: .low,
                classDefaultVdLPerKg: 3.0,
                sourceNote: "Days–weeks recovery (class-default order-of-magnitude). Safety axis: tolerance-reset overdose after a break.",
            )
        case .catecholamineStimulant:
            // The class the whole engine is built to get right. STRONG acute pool (vesicular
            // depletion → the redose loop), recovers overnight. The slow axis is a *months*
            // allostatic / recovery-state indicator with a deliberately small κ — and it is NOT an
            // effect multiplier. A low therapeutic dose therefore shows acute tachyphylaxis but
            // negligible allostatic change; chronic high exposure accrues real load.
            // The slow *availability* axis is deliberately near-inert (κ≈0): transporter occupancy
            // saturates at therapeutic doses, so availability can't distinguish dose, and a slow
            // "tolerance %" there is the wrong-signed error this engine refuses. The slow signal is
            // carried entirely by the bounded allostatic LOAD integrator (gain 1 → recovery-state in
            // [0,1]), which is dose/frequency-dependent via the exposure integral.
            Parameters(
                kappaSlow: 0.00001, tauSlowMinutes: 2 * T.month,
                hasAcutePool: true, kappaAcute: 0.02, tauAcuteMinutes: 12 * T.hour,
                loadGain: 1.0, tauLoadMinutes: 3 * T.month,
                usesEffectMultiplier: false, safetyAxis: .stimulantLoad, confidence: .low,
                classDefaultVdLPerKg: 4.0,
                sourceNote: "Acute vesicular-depletion tachyphylaxis (overnight) + slow allostatic LOAD (months, NOT a multiplier; availability axis inert by design). κ/τ class-default; the 'stimulant tolerance %' is refused.",
            )
        case .serotonergicReleaser:
            // MDMA-type SERT releasers: weeks-scale, reversible-leaning. Partial — not a clean
            // multiplier (the "magic loss" is self-report, the SERT change a confounded surrogate).
            Parameters(
                kappaSlow: 0.0001, tauSlowMinutes: 3 * T.week,
                hasAcutePool: true, kappaAcute: 0.01, tauAcuteMinutes: 12 * T.hour,
                loadGain: 1.0, tauLoadMinutes: 3 * T.month,
                usesEffectMultiplier: false, safetyAxis: .serotonergicLoad, confidence: .low,
                classDefaultVdLPerKg: 5.0,
                sourceNote: "Weeks-scale, reversible-leaning (no fitted human κ/τ — pilot). Slow signal is the bounded LOAD axis, a SERT-binding association surrogate — never 'neurotoxicity'.",
            )
        case .gaba:
            // Benzodiazepines / alcohol: days–weeks; dependence + kindling axis. Some redose pool.
            Parameters(
                kappaSlow: 0.002, tauSlowMinutes: 10 * T.day,
                hasAcutePool: true, kappaAcute: 0.008, tauAcuteMinutes: 6 * T.hour,
                loadGain: 0, tauLoadMinutes: 3 * T.month,
                usesEffectMultiplier: true, safetyAxis: .dependenceKindling, confidence: .low,
                classDefaultVdLPerKg: 1.1,
                sourceNote: "Days–weeks recovery (class-default). Safety axis: dependence + kindling on repeated withdrawal.",
            )
        case .nmdaAntagonist:
            // Ketamine / DXM / MXE: days; cumulative toxicity. Also a modulator of others' tolerance.
            Parameters(
                kappaSlow: 0.0015, tauSlowMinutes: 3 * T.day,
                hasAcutePool: true, kappaAcute: 0.01, tauAcuteMinutes: 4 * T.hour,
                loadGain: 1.0, tauLoadMinutes: 3 * T.month,
                usesEffectMultiplier: true, safetyAxis: .cumulativeToxicity, confidence: .low,
                classDefaultVdLPerKg: 3.0,
                sourceNote: "Days-scale recovery (class-default). Cumulative-toxicity axis (e.g. ketamine bladder).",
            )
        case .cannabinoidCB1:
            // THC: fast, real, recoverable CB1 tolerance.
            Parameters(
                kappaSlow: 0.0025, tauSlowMinutes: 4 * T.day,
                hasAcutePool: true, kappaAcute: 0.004, tauAcuteMinutes: 6 * T.hour,
                loadGain: 0, tauLoadMinutes: 3 * T.month,
                usesEffectMultiplier: true, safetyAxis: .none, confidence: .low,
                classDefaultVdLPerKg: 3.4,
                sourceNote: "Fast, real, recoverable CB1 tolerance (class-default κ/τ).",
            )
        case .adenosine:
            // Caffeine: clean, well-behaved tolerance over days.
            Parameters(
                kappaSlow: 0.0015, tauSlowMinutes: 5 * T.day,
                hasAcutePool: false, kappaAcute: 0, tauAcuteMinutes: 4 * T.hour,
                loadGain: 0, tauLoadMinutes: 3 * T.month,
                usesEffectMultiplier: true, safetyAxis: .none, confidence: .low,
                classDefaultVdLPerKg: 0.6,
                sourceNote: "Clean adenosine-receptor up-regulation tolerance over days (class-default κ/τ).",
            )
        case .nicotinic:
            // Nicotine: desensitization-driven, fast acute + fast slow.
            Parameters(
                kappaSlow: 0.004, tauSlowMinutes: 1 * T.day,
                hasAcutePool: true, kappaAcute: 0.03, tauAcuteMinutes: 2 * T.hour,
                loadGain: 0, tauLoadMinutes: 3 * T.month,
                usesEffectMultiplier: false, safetyAxis: .none, confidence: .low,
                classDefaultVdLPerKg: 2.6,
                sourceNote: "nAChR desensitization dominates (fast acute + fast slow); class-default κ/τ.",
            )
        case .unknown:
            // Generic, deliberately weak default at the lowest confidence.
            Parameters(
                kappaSlow: 0.001, tauSlowMinutes: 7 * T.day,
                hasAcutePool: false, kappaAcute: 0, tauAcuteMinutes: 4 * T.hour,
                loadGain: 0, tauLoadMinutes: 3 * T.month,
                usesEffectMultiplier: true, safetyAxis: .none, confidence: .unverified,
                classDefaultVdLPerKg: 1.0,
                sourceNote: "No curated tolerance class — generic class-default kinetics.",
            )
        }
    }

    // MARK: - Routing

    /// Classify a target string (optionally informed by its `action`) into a tolerance class. Matching
    /// is case-insensitive and prefix/substring-based to absorb the DB's qualifying suffixes
    /// (`"GABA-A α1β2γ2"`, `"nAChR α4β2"`, `"Adenosine A2A"`). Falls back to ``ReceptorClass/unknown``.
    static func classify(target: String, action _: BindingAction? = nil) -> ReceptorClass {
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

    /// The tolerance parameters for a target string — `classify` then `parameters(for:)`.
    static func parameters(forTarget target: String, action: BindingAction? = nil) -> Parameters {
        parameters(for: classify(target: target, action: action))
    }
}
