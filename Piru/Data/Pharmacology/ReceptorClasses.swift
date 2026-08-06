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
/// stays off for therapeutic users), not a false-precision percentage. These are the **Stage B
/// literature-anchored** values (`Specs/tolerance-faithful-model.md` §3): each class's `sourceNote`
/// records the controlled-evidence anchor (e.g. the opioid recovery t½ ≈ 14 d, PMC1666403; the
/// stimulant vesicular-reserve tachyphylaxis, de Wit 1996) and its grade. The deep layer is gated on a
/// **product of magnitude × chronicity** (§2): the dose-relative escalation factor (`dose ÷ the
/// substance's heavy ceiling`) *and* a leaky duty-cycle accumulator, so a heavy binge (not sustained)
/// and a therapeutic daily dose (not heavy) both stay dark — only sustained heavy use entrenches.
nonisolated enum ReceptorClasses {
    // MARK: - Time-constant vocabulary (minutes)

    private enum T {
        static let hour = 60.0
        static let day = 1_440.0
        static let week = 7 * day
        static let month = 30 * day
    }

    // MARK: - Deep-layer chronicity gate (class-shared, §2)

    /// The **deep** layer's drive is the product of two smoothsteps — how *heavy* dosing is
    /// (``deepMagnitudeThreshold``/``deepMagnitudeWidth`` on the escalation factor) × how *sustained* it
    /// is (``deepChronicityThreshold``/``deepChronicityWidth`` on the leaky duty-cycle
    /// ``chronicExposure``). Neither alone suffices: a one-off binge (heavy, not sustained) recovers; a
    /// therapeutic daily dose (sustained, not heavy) is stable. Deep needs **both**
    /// (`Specs/tolerance-faithful-model-improvements.md` §2). These are class-shared constants (the field
    /// evidence doesn't support per-class chronicity knobs).
    ///
    /// Magnitude: soft-on as dosing approaches the heavy ceiling (escalation ≈ 1), ~0 well below it,
    /// full by ~1.5× — no hard 2× cliff. Chronicity: below the knee for a once-daily therapeutic user
    /// (duty ~0.15), crossing it for a heavy multi-daily pattern, full by duty ≈ 0.6.
    static let deepMagnitudeThreshold = 0.5
    static let deepMagnitudeWidth = 1.0
    static let deepChronicityThreshold = 0.25
    static let deepChronicityWidth = 0.35
    /// Time-constant (minutes) of the ``chronicExposure`` leaky integrator — the duty-cycle proxy that
    /// tracks the time-averaged occupancy over ~3 weeks (§2). Many doses/day → high; once-daily
    /// therapeutic → ~0.1–0.2; occasional → ~0.
    static let tauChronicExposureMinutes = 21 * T.day

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
        /// α₂-adrenergic agonists (clonidine, guanfacine): little efficacy tolerance — a faint reading
        /// that *hosts* the discontinuation **rebound** warning (`Specs/tolerance-faithful-model.md` §3.5).
        case alpha2Agonist
        /// β-adrenergic antagonists (propranolol, metoprolol): little efficacy tolerance — a faint
        /// reading that *hosts* the discontinuation **rebound** warning (§3.5).
        case betaBlocker
        /// No curated class — generic class-default kinetics at the lowest confidence.
        case unknown

        /// Whether the class exists only to **host a discontinuation-rebound warning** rather than
        /// predict a meaningful tolerance curve — the adrenergics (`Specs/tolerance-faithful-model.md`
        /// §3.5). Such a class has no PK-less class representative *by design* (there is no clean dose
        /// equivalence), so a PK-less member must not be surfaced as "incomplete tolerance data": there
        /// is no tolerance to predict, complete PK or not. A PK-complete member still produces its faint
        /// card via the normal occupancy path.
        var hostsReboundWarningOnly: Bool {
            switch self {
            case .alpha2Agonist, .betaBlocker: true
            default: false
            }
        }

        /// Whether the gauge should evaluate the right-shift at a **capped** representative occupancy
        /// (the half-saturation / ED50 point) because for this class *occupancy is a poor proxy for felt
        /// effect* (`Specs/tolerance-faithful-model-improvements.md` §5). `true` only for the
        /// **release / reuptake** classes, whose transporters saturate at *recreational* doses — there
        /// felt effect tracks release/reuptake *flux*, not static occupancy, so an uncapped ratio would
        /// hide real tolerance (a releaser at DAT sits at occupancy ≈ 1, making any `S` read as "no
        /// tolerance"); evaluating at the sensitive part of the curve is the honest reading. For the
        /// **agonists / PAMs / antagonists** it is `false` (uncapped): there the usual-dose occupancy
        /// *is* the effect proxy, and capping it would pretend a heavy opioid/benzo user's escalated dose
        /// is a half-sat dose — throwing away their escalation and over-reading their tolerance (the
        /// opioid/GABA over-read). Uncapped, a heavy opioid user shows realistic *residual* response.
        /// The occupancy the gauge should cap at before forming the response ratio, or `nil` to use the
        /// true (uncapped) usual-dose occupancy — see ``PDModel/responseFraction(shiftFactor:representativeOccupancy:occupancyCap:)``.
        ///
        /// - **Release / reuptake** classes cap at the ED50 (`0.5`): occupancy saturates at recreational
        ///   doses and felt effect tracks flux, not static occupancy, so evaluating at the sensitive
        ///   half-sat point is honest (§5).
        /// - **Agonists / antagonists / PAMs** (opioid, psychedelic, GABA) are uncapped: usual-dose
        ///   occupancy *is* the effect proxy, and capping would over-read a heavy user's escalation.
        ///   GABA was previously capped at 0.9 as a stopgap for the `fu = 1` overestimate; the
        ///   protein-binding correction (`PharmacologyParameters.fractionUnbound`) resolved the root
        ///   cause, so the cap is gone.
        var gaugeOccupancyCap: Double? {
            switch self {
            case .catecholamineStimulant, .serotonergicReleaser: 0.5
            default: nil
            }
        }

        /// Short user-facing name for the tolerance class — the Stage-2 Tool card headline, shown to
        /// the **Curious** (harm-reduction) tier (the "(μ)"-style names with the mechanism in parens).
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
            case .alpha2Agonist: "α₂-agonists (clonidine)"
            case .betaBlocker: "Beta-blockers (propranolol)"
            case .unknown: "Other"
            }
        }

        /// Plain, jargon-free class name for the **Casual** tier — no receptor parentheticals.
        var casualName: LocalizedStringResource {
            switch self {
            case .psychedelic5HT2A: "Psychedelics"
            case .muOpioid: "Opioids"
            case .catecholamineStimulant: "Stimulants"
            case .serotonergicReleaser: "Serotonin releasers"
            case .gaba: "Sedatives"
            case .nmdaAntagonist: "Dissociatives"
            case .cannabinoidCB1: "Cannabis"
            case .adenosine: "Caffeine"
            case .nicotinic: "Nicotine"
            case .alpha2Agonist: "α₂-agonists"
            case .betaBlocker: "Beta-blockers"
            case .unknown: "Other"
            }
        }

        /// Precise receptor/transporter name for the **Pharma Nerd** tier.
        var scientificName: LocalizedStringResource {
            switch self {
            case .psychedelic5HT2A: "5-HT₂A receptor"
            case .muOpioid: "μ-opioid receptor (MOR)"
            case .catecholamineStimulant: "Dopamine/noradrenaline transporter (DAT/NET)"
            case .serotonergicReleaser: "Serotonin transporter (SERT)"
            case .gaba: "GABA-A receptor"
            case .nmdaAntagonist: "NMDA receptor"
            case .cannabinoidCB1: "CB1 receptor"
            case .adenosine: "Adenosine receptor"
            case .nicotinic: "nAChR"
            case .alpha2Agonist: "α₂-adrenoceptor"
            case .betaBlocker: "β-adrenoceptor"
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
        /// α₂-agonist discontinuation rebound — noradrenaline-surge rebound hypertension on abrupt or
        /// too-rapid taper (clonidine/guanfacine; §3.5). The class shows little efficacy tolerance, so
        /// this rebound axis — not a right-shift — is the reason it hosts a card.
        case alpha2Rebound
        /// β-blocker discontinuation rebound — receptor-upregulation rebound hypertension/tachycardia on
        /// abrupt stop (propranolol/metoprolol; §3.5). Likewise a rebound axis, not a tolerance curve.
        case betaRebound
    }

    // MARK: - Differential safety endpoint

    /// A **second** effect of a class that tolerizes *differently* from the desired effect — the
    /// differential-tolerance safety story (`Specs/tolerance-faithful-model.md` §3.1, §3.3). Two
    /// minimal log-space layers (acute + adaptive only — no deep, no escalation gate) run in parallel
    /// to the primary three, driven by the *same* occupancy, so the gap between the desired effect's
    /// right-shift and this endpoint's is observable:
    /// - **Opioids:** analgesia/euphoria tolerize fast; **respiratory depression tolerizes shallower
    ///   and recovers faster** → after a break the breathing is unprotected while the user still
    ///   expects their old dose (the reset-after-break overdose mechanism, §3.1).
    /// - **Stimulants:** the subjective high tolerizes; **cardiovascular/pressor effects do not**
    ///   (`adaptiveShiftMax == 0` ⇒ the endpoint shift stays ≡ 1) → a toleranced high pushes redoses
    ///   onto an un-toleranced pressor (redose toxicity, §3.3).
    ///
    /// The reset-overdose *warning* (peak/gap tracking and copy) is a later stage; Stage C only
    /// produces the endpoint's shift factor faithfully so the gap is visible.
    struct SafetyEndpoint {
        /// Which harm axis this endpoint measures.
        enum Kind: String {
            /// Opioid respiratory depression — the reset-after-break overdose axis.
            case respiratory
            /// Stimulant cardiovascular/pressor load — the redose-toxicity axis.
            case cardiovascular
        }

        /// The harm axis this endpoint tracks.
        let kind: Kind
        /// Acute-layer ln-shift ceiling (within-session). `0` ⇒ the endpoint has no acute pool.
        let acuteShiftMax: Double
        /// Acute-layer build/recover time-constant (minutes).
        let tauAcuteMinutes: Double
        /// Adaptive-layer ln-shift ceiling — the days–weeks endpoint shift. `0` ⇒ the endpoint does
        /// not tolerize at all (the stimulant cardiovascular case ⇒ its shift factor is always `1`).
        let adaptiveShiftMax: Double
        /// Adaptive-layer build/recover time-constant (minutes).
        let tauAdaptiveMinutes: Double
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
        /// Synthesis-layer ln-shift ceiling — the slow serotonin-synthesis pool that splits the SERT
        /// releaser class onto two recovery clocks (`Specs/tolerance-faithful-model.md` §3.4). `0` ⇒
        /// the class has no synthesis layer, so it never accrues regardless of the per-substance flag.
        /// Only the serotonergic releaser class is non-zero; it engages only for the substances flagged
        /// ``PharmacologyParameters/suppressesSerotoninSynthesis`` (MDMA-type entactogens).
        let synthesisShiftMax: Double
        /// Synthesis-layer build/recover time-constant (minutes) — weeks (the slow TPH-machinery
        /// recovery). Inert for the nine classes whose ``synthesisShiftMax`` is `0`.
        let tauSynthesisMinutes: Double
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
        /// A parallel **differential safety endpoint** (opioid respiratory, stimulant cardiovascular)
        /// that tolerizes on its own kinetics — `nil` for the eight classes without one (Stage C).
        let safetyEndpoint: SafetyEndpoint?

        /// Whether the class has a meaningful within-session acute (redose) pool.
        var hasAcutePool: Bool {
            acuteShiftMax > 0
        }
    }

    /// The curated right-shift parameters for a class — the **Stage B** literature-anchored table
    /// (`Specs/tolerance-faithful-model.md` §3); calibrated to the literature's *shape*, see the type
    /// doc for the honesty stance and confidence grading.
    static func parameters(for receptorClass: ReceptorClass) -> Parameters {
        switch receptorClass {
        case .psychedelic5HT2A:
            // 5-HT2A tolerance has two clocks. A **same-day tachyphylaxis** pool (fast 5-HT2A
            // internalisation/desensitisation — a same-day LSD re-dose is markedly weaker and largely
            // gone by the next morning), carried by the acute layer (τ ≈ ¾ d). And the **multi-day
            // adaptive shift** that builds over consecutive days toward near-total in-class
            // cross-tolerance and recovers in ~3–4 d (controlled-human; flagship correction 2026-06-21).
            // No deep layer (psychedelics don't entrench over months).
            Parameters(
                acuteShiftMax: 1.2, tauAcuteMinutes: 18 * T.hour,
                adaptiveShiftMax: 2.5, tauAdaptiveMinutes: 3.5 * T.day,
                deepShiftMax: 0, tauDeepMinutes: 3 * T.month,
                synthesisShiftMax: 0, tauSynthesisMinutes: 3 * T.month,
                safetyAxis: .hppd, confidence: .medium,
                classDefaultVdLPerKg: 4.0,
                sourceNote: "§3: acute same-day tachyphylaxis (fast 5-HT2A desensitisation, gone by next morning, τ≈18 h) + adaptive subjective tolerance ~3–4 d (controlled-human, flagship-corrected), near-total in-class cross-tolerance. No deep layer. Grade medium.",
                safetyEndpoint: nil,
            )
        case .muOpioid:
            // Days-to-weeks adaptive shift (recovery t½ ~14 d ⇒ τ≈20 d), a mild within-session acute
            // pool, and an escalation-gated deep layer: dosing sustained above the heavy ceiling
            // entrenches over months (the reset-after-break overdose axis is the safety hand-off, Stage C/F).
            Parameters(
                acuteShiftMax: 0.3, tauAcuteMinutes: 4 * T.hour,
                adaptiveShiftMax: 1.8, tauAdaptiveMinutes: 20 * T.day,
                deepShiftMax: 1.1, tauDeepMinutes: 6 * T.month,
                synthesisShiftMax: 0, tauSynthesisMinutes: 3 * T.month,
                safetyAxis: .resetOverdose, confidence: .low,
                classDefaultVdLPerKg: 3.0,
                sourceNote: "§3: ED50 right-shift 3–30× (controlled; the folkloric '100–300×' is palliative end-of-life dosing). Recovery t½ ~14 d → τ≈20 d (PMC1666403). Ceilings recalibrated to the controlled literature (acute 0.3 + adaptive 1.8 + deep 1.1 → ln ≤ 3.2 → ~25× worst-case, deep only on chronic escalation). Deep = chronicity+escalation-gated entrenched tolerance; reset-after-break overdose safety axis. Grade low.",
                // §3.1: respiratory depression tolerizes shallower than analgesia (ceiling 1.0 vs the
                // analgesic 2.0) and recovers faster (τ 10 d vs 20 d) — so after a break the breathing
                // is unprotected while the user still expects their old dose (the reset-OD mechanism).
                safetyEndpoint: SafetyEndpoint(
                    kind: .respiratory,
                    acuteShiftMax: 0.15, tauAcuteMinutes: 4 * T.hour,
                    adaptiveShiftMax: 1.0, tauAdaptiveMinutes: 10 * T.day,
                ),
            )
        case .catecholamineStimulant:
            // The flagship three-layer class. STRONG acute layer (vesicular reserve-pool depletion →
            // the redose loop), recovers overnight. A modest adaptive baseline shift (ADHD response is
            // stable for years). The deep layer is OFF for therapeutic users — the escalation gate
            // (dose ÷ heavy ceiling) only opens on heavy chronic escalation, then entrenches over
            // ~9 months (DAT density recovers slowly), asymptoting at its ceiling.
            Parameters(
                acuteShiftMax: 0.8, tauAcuteMinutes: 9 * T.hour,
                adaptiveShiftMax: 0.4, tauAdaptiveMinutes: 12 * T.day,
                deepShiftMax: 1.6, tauDeepMinutes: 9 * T.month,
                synthesisShiftMax: 0, tauSynthesisMinutes: 3 * T.month,
                safetyAxis: .stimulantLoad, confidence: .low,
                classDefaultVdLPerKg: 4.0,
                sourceNote: "§3: acute vesicular reserve-pool tachyphylaxis (subjective gone 3–4 h, τ 6–12 h; de Wit 1996). Adaptive modest (ADHD response stable, ~2.7%/10 y). Deep only on heavy chronic escalation (DAT recovers +20–26% over 12–17 mo; felt tolerance lags density). Cardiovascular = TWO mechanisms (§6): the acute within-session pressor does NOT tolerize (de Wit 1996), the chronic resting response adapts over weeks (CV meta PMC6121294). Grade low.",
                // §6: cardiovascular is two mechanisms on two timescales. The **acute** within-session
                // pressor (NET-mediated HR/BP spike) does NOT tolerize (`acuteShiftMax 0`) — so a chronic
                // user redosing in-session still lands on a fresh, un-toleranced spike (the redose-toxicity
                // hazard). The **chronic resting** cardiovascular response DOES adapt over weeks
                // (baroreflex resetting; `adaptiveShiftMax 0.6`, τ≈12 d, grade M). acute 0 / adaptive > 0
                // sharpens the safety story: the resting response settles, the per-redose spike does not.
                safetyEndpoint: SafetyEndpoint(
                    kind: .cardiovascular,
                    acuteShiftMax: 0, tauAcuteMinutes: 4 * T.hour,
                    adaptiveShiftMax: 0.6, tauAdaptiveMinutes: 12 * T.day,
                ),
            )
        case .serotonergicReleaser:
            // SERT releasers, split per-substance onto two recovery clocks (§3.4). A within-session
            // acute fade plus a *fast adaptive* pool (τ≈4 d — receptor/transporter resensitisation,
            // which is the whole story for the cathinone releasers like 4-MMC, days-scale). The slow
            // **synthesis** pool (τ≈2 wk) engages only for the substances that suppress serotonin
            // synthesis (MDMA-type entactogens; the per-substance ``suppressesSerotoninSynthesis``
            // flag) — so MDMA recovers over weeks while mephedrone resets in days, same class.
            Parameters(
                acuteShiftMax: 0.5, tauAcuteMinutes: 12 * T.hour,
                adaptiveShiftMax: 1.0, tauAdaptiveMinutes: 4 * T.day,
                deepShiftMax: 0, tauDeepMinutes: 3 * T.month,
                synthesisShiftMax: 1.0, tauSynthesisMinutes: 14 * T.day,
                safetyAxis: .serotonergicLoad, confidence: .low,
                classDefaultVdLPerKg: 5.0,
                sourceNote: "§3.4: two recovery clocks. Fast adaptive pool (receptor/transporter resensitisation, τ≈4 d) — the whole story for the cathinone releasers (4-MMC/mephedrone), which spare synthesis and reset in 2–4 d. Slow synthesis pool (τ≈14 d, single-dose inferred, range 3–14 d) driven only by the synthesis-suppressing entactogens: MDMA-type TPH suppression is *metabolite*-mediated, so recovery waits weeks. Rejected Shulgin's untested 3-month rule and both damage/harmless extremes. Grade low (human L).",
                safetyEndpoint: nil,
            )
        case .gaba:
            // Benzodiazepines / alcohol: a redose pool plus a days-scale adaptive shift (sedative
            // tolerance is fast but far less elastic than opioids); dependence + kindling is the safety
            // hand-off.
            Parameters(
                acuteShiftMax: 0.4, tauAcuteMinutes: 6 * T.hour,
                adaptiveShiftMax: 1.0, tauAdaptiveMinutes: 14 * T.day,
                deepShiftMax: 0, tauDeepMinutes: 3 * T.month,
                synthesisShiftMax: 0, tauSynthesisMinutes: 3 * T.month,
                safetyAxis: .dependenceKindling, confidence: .low,
                classDefaultVdLPerKg: 1.1,
                sourceNote: "§3: sedative tolerance 2–4× fast (~3–5 d); far less elastic than opioids (acute 0.4 + adaptive 1.0 → ~4× worst-case, matching the controlled sedative literature). Anxiolytic tolerance slow/absent (Stage C differential). Dependence/kindling safety axis. Grade low.",
                safetyEndpoint: nil,
            )
        case .nmdaAntagonist:
            // Ketamine / DXM / MXE: days-scale adaptive shift + a redose pool; cumulative toxicity.
            // Also a modulator of others' tolerance (ToleranceModulation).
            Parameters(
                acuteShiftMax: 0.4, tauAcuteMinutes: 4 * T.hour,
                adaptiveShiftMax: 1.0, tauAdaptiveMinutes: 3 * T.day,
                deepShiftMax: 0, tauDeepMinutes: 3 * T.month,
                synthesisShiftMax: 0, tauSynthesisMinutes: 3 * T.month,
                safetyAxis: .cumulativeToxicity, confidence: .low,
                classDefaultVdLPerKg: 3.0,
                sourceNote: "§3: days-scale adaptive shift; also a μ-opioid tolerance modulator (ToleranceModulation). Cumulative-toxicity axis (e.g. ketamine bladder). Grade low.",
                safetyEndpoint: nil,
            )
        case .cannabinoidCB1:
            // THC: fast, real, recoverable CB1 tolerance — a redose pool + a days-scale adaptive shift.
            Parameters(
                acuteShiftMax: 0.3, tauAcuteMinutes: 6 * T.hour,
                adaptiveShiftMax: 1.2, tauAdaptiveMinutes: 4 * T.day,
                deepShiftMax: 0, tauDeepMinutes: 3 * T.month,
                synthesisShiftMax: 0, tauSynthesisMinutes: 3 * T.month,
                safetyAxis: .none, confidence: .low,
                classDefaultVdLPerKg: 3.4,
                sourceNote: "§3: fast, real, recoverable CB1 tolerance — a redose pool + a days-scale adaptive shift. Grade low.",
                safetyEndpoint: nil,
            )
        case .adenosine:
            // Caffeine: clean, well-behaved up-regulation tolerance over days; no within-session pool.
            Parameters(
                acuteShiftMax: 0, tauAcuteMinutes: 4 * T.hour,
                adaptiveShiftMax: 1.0, tauAdaptiveMinutes: 5 * T.day,
                deepShiftMax: 0, tauDeepMinutes: 3 * T.month,
                synthesisShiftMax: 0, tauSynthesisMinutes: 3 * T.month,
                safetyAxis: .none, confidence: .low,
                classDefaultVdLPerKg: 0.6,
                sourceNote: "§3: clean adenosine-receptor up-regulation tolerance over days (caffeine); no within-session pool. Grade low.",
                safetyEndpoint: nil,
            )
        case .nicotinic:
            // Nicotine: desensitization-driven — a strong, fast acute layer plus a fast adaptive shift.
            Parameters(
                acuteShiftMax: 0.8, tauAcuteMinutes: 2 * T.hour,
                adaptiveShiftMax: 0.4, tauAdaptiveMinutes: 1 * T.day,
                deepShiftMax: 0, tauDeepMinutes: 3 * T.month,
                synthesisShiftMax: 0, tauSynthesisMinutes: 3 * T.month,
                safetyAxis: .none, confidence: .low,
                classDefaultVdLPerKg: 2.6,
                sourceNote: "§3: nAChR desensitization dominates — a fast, strong acute layer + a fast adaptive shift. Grade low.",
                safetyEndpoint: nil,
            )
        case .alpha2Agonist:
            // §3.5: α₂-agonists develop little efficacy tolerance — a faint adaptive shift only so a
            // card appears to carry the rebound warning. Everything else inert; the real hazard is the
            // discontinuation rebound safety axis, not a right-shift.
            Parameters(
                acuteShiftMax: 0, tauAcuteMinutes: 4 * T.hour,
                adaptiveShiftMax: 0.2, tauAdaptiveMinutes: 7 * T.day,
                deepShiftMax: 0, tauDeepMinutes: 3 * T.month,
                synthesisShiftMax: 0, tauSynthesisMinutes: 3 * T.month,
                safetyAxis: .alpha2Rebound, confidence: .low,
                classDefaultVdLPerKg: 2.0,
                sourceNote: "α2-agonists show little efficacy tolerance; the hazard is rebound hypertension on abrupt/too-fast discontinuation (Geyskes 1979; taper, β-blocker first if co-stopping). §3.5.",
                safetyEndpoint: nil,
            )
        case .betaBlocker:
            // §3.5: β-blockers develop little efficacy tolerance — a faint adaptive shift only so a card
            // appears to carry the rebound warning. The 'unopposed-α' stimulant scare is debunked (no
            // severe interaction); the genuine hazard is rebound on abrupt stop, the safety axis below.
            Parameters(
                acuteShiftMax: 0, tauAcuteMinutes: 4 * T.hour,
                adaptiveShiftMax: 0.15, tauAdaptiveMinutes: 7 * T.day,
                deepShiftMax: 0, tauDeepMinutes: 3 * T.month,
                synthesisShiftMax: 0, tauSynthesisMinutes: 3 * T.month,
                safetyAxis: .betaRebound, confidence: .low,
                classDefaultVdLPerKg: 3.0,
                sourceNote: "β-blockers show little efficacy tolerance; rebound hypertension/tachycardia (receptor upregulation) on abrupt stop — taper. 'Unopposed-α' with cocaine/stimulant is debunked, NOT a severe interaction (§3.5).",
                safetyEndpoint: nil,
            )
        case .unknown:
            // Generic, deliberately weak default at the lowest confidence.
            Parameters(
                acuteShiftMax: 0, tauAcuteMinutes: 4 * T.hour,
                adaptiveShiftMax: 0.7, tauAdaptiveMinutes: 7 * T.day,
                deepShiftMax: 0, tauDeepMinutes: 3 * T.month,
                synthesisShiftMax: 0, tauSynthesisMinutes: 3 * T.month,
                safetyAxis: .none, confidence: .unverified,
                classDefaultVdLPerKg: 1.0,
                sourceNote: "No curated tolerance class — generic class-default kinetics. Unverified.",
                safetyEndpoint: nil,
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
        case .alpha2Agonist: [.agonist, .partialAgonist]
        case .betaBlocker: [.antagonist]
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
        if t.contains("gaba-a") || t.contains("gabaa") || t.contains("α4β3δ gaba") { return .gaba }
        // Adrenergic / adrenoceptor targets, keyed *after* gaba so GABA-A subunit strings (e.g.
        // "GABA-A α2β2γ2", which contain "α2") route to gaba first. α1 / unspecified adrenergic
        // deliberately fall through to `.unknown` — a different receptor, out of scope (§3.5).
        if t.contains("adrenergic") || t.contains("adrenoceptor") {
            if t.contains("α2") || t.contains("alpha-2") || t.contains("alpha2") || t.contains("alpha 2") { return .alpha2Agonist }
            if t.contains("β") || t.contains("beta") { return .betaBlocker }
        }
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

    /// Infer a substance's tolerance class from its **pharmacological category**, independent of any
    /// binding data — so a benzodiazepine drives the GABA class and an opioid the μ class *even when the
    /// bundled DB lists no receptor rows for it* (`Specs/tolerance-faithful-model-improvements.md` §7
    /// follow-up). This is the class-level analogue of the target-based ``classify(target:action:)``:
    /// the engine's missing-PK fallback (`ToleranceStore.fallbackClasses`) uses it to model an
    /// untargeted-but-categorised substance as its class representative, rescuing the long RC tail
    /// (designer benzos, fluoro-amphetamines, RC opioids) that ships without curated bindings.
    ///
    /// Only categories with a well-defined mechanism class map; the rest (nootropic, supplement,
    /// gabapentinoid — whose target is α2δ, not a modeled tolerance class — etc.) return `nil`.
    static func toleranceClass(forCategory category: SubstanceCategory) -> ReceptorClass? {
        switch category {
        case .stimulant, .eugeroic: .catecholamineStimulant
        case .opioid: .muOpioid
        // Benzodiazepine only — NOT the broad `.depressant` category, which the DB also pins on
        // beta-blockers (propranolol), α₂-agonists (clonidine), antihistamines and anxiolytics that are
        // not GABA drugs. The true GABAergic depressants (alcohol, barbiturates, GHB, baclofen) carry
        // their own binding rows, so they route via the target path and don't need this fallback.
        case .benzodiazepine: .gaba
        case .psychedelic: .psychedelic5HT2A
        case .dissociative: .nmdaAntagonist
        case .empathogen: .serotonergicReleaser
        case .cannabinoid: .cannabinoidCB1
        default: nil
        }
    }

    /// A display-canonical receptor name for the card breakdown: strips parenthetical qualifiers
    /// (`"(recombinant human)"`, `"(MK-801 site, S-enantiomer)"`, `"(PCP site)"`), enantiomer prefixes
    /// (`"(+)-"`, `"(−)-"`), and a trailing `" receptor"`, so `"5-HT3 receptor"`, `"NMDA receptor (PCP
    /// site)"`, and `"MOR (+)-tramadol"` collapse to `"5-HT3"`, `"NMDA"`, `"MOR"`. Best-effort
    /// normalization for the sub-target list — the pipeline owns the authoritative cleanup (Phase 2).
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
