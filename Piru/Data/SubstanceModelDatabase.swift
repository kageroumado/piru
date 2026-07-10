import Foundation

/// Builds the mechanistic effect engine's per-substance ``SubstanceModelParams`` from **hard data**
/// (the bundled pharmacology DB) plus a slim curated override layer.
///
/// The split (see `Specs/effect-model-molar-calibration.md`):
///   - **PK + transporter binding come from the resolver** (`PharmacologyParameters`): the elimination
///     rate `ke` from the measured half-life, the absorption rate `ka` from the measured Tmax, the
///     DAT/NET/SERT weight *ratios* from the measured EC₅₀/Kᵢ, and `releaser` from whether the primary
///     transporter is engaged by release (EC₅₀) or reuptake block (Kᵢ/IC₅₀). These were formerly a
///     hardcoded table of eyeballed numbers; they are now data.
///   - **The irreducible PD scalars stay curated** (`Overrides`): vesicular store-depletion
///     susceptibility, DAT dissociation `koff`, µ-opioid drive/efficacy, GABA/CAE drive, respiratory
///     drive, and multi-receptor antagonism. No pharmacology DB carries these — they are model
///     constants (Tier C). The override layer *also* patches the handful of cases where the DB value is
///     absent or wrong for a *felt-effect* curve: prodrugs and enterohepatic drugs whose plasma
///     half-life ≠ the duration of effect (heroin, kratom), and RC/CAEs the DB has no PK for
///     (5-APB, PPAP, BPAP).
///
/// A substance with neither DB data nor an override is not modelable — the caller falls back to the
/// classic duration timeline (Tier 0). No fabricated curves.
nonisolated enum SubstanceModelDatabase {
    static func normalize(_ name: String) -> String {
        name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Curated override layer (the irreducible PD scalars + felt-effect PK patches)

    private static let ln2 = log(2.0)
    /// Cap on a transporter weight relative to DAT, so a drug that is far more potent at NET/SERT than
    /// at DAT gets a strong — but not runaway — off-DA weight. The engine's saturating nonlinearities
    /// bound the output regardless; this keeps the *numbers* interpretable.
    ///
    /// Known tradeoff: when DAT is orders of magnitude weaker than NET/SERT (a near-pure serotonergic
    /// releaser like MDMA), *both* the NET and SERT ratios exceed the cap and collapse to it, flattening
    /// their ordering. The full-molar concentration path (where absolute potency emerges from EC₅₀ +
    /// concentration and `refUnit`/DA-normalization retire) is what ultimately cures this.
    private static let maxTransporterWeight = 4.0

    /// Per-substance overrides applied on top of the DB-derived base. Every field is optional: a `nil`
    /// PK field means "trust the DB"; a set PK field patches a DB value that is missing or wrong for the
    /// felt-effect curve. The PD scalars have no DB source and are authoritative here.
    struct Overrides {
        // Felt-effect PK patches (nil ⇒ use the DB-derived value): the plasma half-life / Tmax the DB
        // ships is wrong for the *felt* curve (prodrugs, enterohepatic drugs), or the DB has no PK at all.
        var ke: Double?
        var ka: Double?
        /// Dose-magnitude anchor — the reference dose the concentration is normalized to (`amt = dose/refUnit`),
        /// not a PK constant. Curated to preserve the engine's calibrated magnitudes; falls back to the DB's
        /// dose-ladder `referenceDoseMg` when absent. Retired once the full-molar concentration path lands.
        var refUnit: Double?
        // Irreducible pharmacodynamics (no DB source).
        var deplete: Double?
        var koff: Double?
        var mu: Double = 0
        var muEff: Double = 1
        var gaba: Double = 0
        var cae: Double = 0
        var resp: Double = 0
        var rec: ReceptorAffinities?
    }

    /// Keyed by normalized canonical name. Aliases resolve through ``aliases`` first.
    private static let overrides: [String: Overrides] = [
        // Releaser stimulants — PK + weights from DB; only the depletion (crash) scalar is curated.
        "amphetamine": Overrides(refUnit: 50, deplete: 1.0),
        "mdma": Overrides(refUnit: 90, deplete: 0.10),
        "3-mmc": Overrides(refUnit: 80, deplete: 0.12),
        "2-mmc": Overrides(refUnit: 250, deplete: 0.12),
        "mephedrone": Overrides(refUnit: 150, deplete: 0.12),
        "4-fa": Overrides(refUnit: 120, deplete: 0.05),
        // Reuptake-blocker stimulants — no depletion; curated DAT dissociation controls the plateau.
        "methylphenidate": Overrides(refUnit: 60, deplete: 0, koff: 8.0),
        "mdpv": Overrides(refUnit: 15, deplete: 0, koff: 3.0),
        // No DB PK — full PK from the override, weights still from DB.
        "5-apb": Overrides(ke: ln2 / 6.0, ka: 2.0, refUnit: 70, deplete: 0.08),
        // Opioids — µ drive/efficacy/respiratory are curated; heroin's 3-min *plasma* half-life is the
        // prodrug, not the felt duration (6-MAM/morphine), so its ke is patched.
        "heroin": Overrides(ke: ln2 / 2.5, ka: 6.0, refUnit: 10, mu: 1.0, muEff: 0.97, resp: 1.4),
        "morphine": Overrides(refUnit: 30, mu: 1.0, muEff: 0.95, resp: 1.0),
        "oxycodone": Overrides(refUnit: 20, mu: 1.0, muEff: 0.92, resp: 0.9),
        // Kratom's terminal half-life (~23 h, enterohepatic) far outlasts the felt effect (~4 h).
        "kratom": Overrides(ke: ln2 / 4.0, ka: 1.5, refUnit: 3, mu: 0.55, muEff: 0.5),
        // Sedatives / enhancers / antagonists — adjuncts (never trigger the view alone).
        "bromazepam": Overrides(refUnit: 6, gaba: 1.0),
        "ppap": Overrides(ke: ln2 / 4.0, ka: 1.5, refUnit: 20, cae: 0.45),
        "bpap": Overrides(ke: ln2 / 5.0, ka: 1.5, refUnit: 1, cae: 1.1),
        "mirtazapine": Overrides(refUnit: 30, rec: ReceptorAffinities(h1: 0.03, a2: 0.6, c2C: 0.6, c2A: 0.9)),
    ]

    private static let aliases: [String: String] = [
        "adderall": "amphetamine", "dextroamphetamine": "amphetamine", "lisdexamfetamine": "amphetamine",
        "speed": "amphetamine", "ritalin": "methylphenidate", "concerta": "methylphenidate",
        "3mmc": "3-mmc", "2mmc": "2-mmc", "4-mmc": "mephedrone", "4mmc": "mephedrone",
        "molly": "mdma", "ecstasy": "mdma", "mitragynine": "kratom", "4-fea": "4-fa",
        "diamorphine": "heroin", "diacetylmorphine": "heroin", "oxycontin": "oxycodone",
        "remeron": "mirtazapine",
    ]

    private static func overrides(for name: String) -> Overrides? {
        let key = normalize(name)
        return overrides[key] ?? aliases[key].flatMap { overrides[$0] }
    }

    // MARK: - DB → params

    /// The mechanism-appropriate functional half-max (nM) for a transporter: the release EC₅₀ for a
    /// releaser, the uptake Kᵢ/IC₅₀ for a blocker — the tightest such value, else the tightest of any
    /// kind. This is the *functional* potency the felt effect follows, not necessarily the raw binding
    /// affinity the resolver lists first.
    private static func transporterKd(_ p: PharmacologyParameters, _ symbol: String, releaser: Bool) -> Double? {
        let matches = p.targets.filter { $0.target.uppercased().contains(symbol) && $0.halfMaxNanomolar > 0 }
        guard !matches.isEmpty else { return nil }
        let preferred = matches.filter { releaser ? $0.kind == .ec50 : $0.kind != .ec50 }
        return (preferred.isEmpty ? matches : preferred).map(\.halfMaxNanomolar).min()
    }

    /// Build the engine's per-substance parameters from resolved pharmacology + the curated overlay.
    /// `nil` when the substance has neither modelable DB data nor an override — the caller then leaves
    /// it on the classic duration timeline.
    static func params(name: String, pharmacology: PharmacologyParameters?) -> SubstanceModelParams? {
        let ov = overrides(for: name)

        // Elimination: patched felt-effect ke wins; else the measured half-life; else nothing.
        let ke: Double
        if let keOverride = ov?.ke {
            ke = keOverride
        } else if let hlMinutes = pharmacology?.halfLifeMinutes, hlMinutes > 0 {
            ke = ln2 / (hlMinutes / 60) // per hour
        } else {
            return nil // no elimination anchor ⇒ not modelable
        }

        // Absorption: patched ka wins; else Tmax-derived; else the elimination-derived default.
        let ka: Double = if let kaOverride = ov?.ka {
            kaOverride
        } else if let tmaxMinutes = pharmacology?.tmaxMinutes, tmaxMinutes > 0 {
            PKModel.estimateKa(timeToPeak: tmaxMinutes / 60, ke: ke)
        } else {
            PKModel.defaultKa(ke: ke)
        }

        // Substrate releaser (evokes efflux) if ANY engaged transporter carries a functional release
        // EC₅₀; otherwise a reuptake blocker. Scans all targets so a releaser whose tightest single row
        // is an uptake constant still classifies correctly. Amp/cathinones/MDMA release; MPH/MDPV/cocaine block.
        let releaser = pharmacology?.targets.contains { t in
            let symbol = t.target.uppercased()
            return (symbol.contains("DAT") || symbol.contains("NET") || symbol.contains("SERT")) && t.kind == .ec50
        } ?? false

        // Transporter weights from the measured functional potencies, DA-normalized: DAT = 1 (the scale
        // the engine's dopamine/reward stage is tuned to) and NET/SERT scale by their potency ratio to
        // DAT, capped. So the felt mix (DA vs NE vs 5-HT) follows the data — a serotonin-dominant releaser
        // (MDMA) reads warmth-led, a DA-selective blocker (MDPV) reward-led — while amphetamine keeps its
        // wDAT ≈ 1 (and thus its store-depletion crash). A substance with no DAT normalizes to its most
        // potent transporter instead.
        let datKd = pharmacology.flatMap { transporterKd($0, "DAT", releaser: releaser) }
        let netKd = pharmacology.flatMap { transporterKd($0, "NET", releaser: releaser) }
        let sertKd = pharmacology.flatMap { transporterKd($0, "SERT", releaser: releaser) }
        let referenceKd = datKd ?? [netKd, sertKd].compactMap(\.self).min()
        func weight(_ kd: Double?) -> Double {
            guard let kd, let referenceKd, kd > 0 else { return 0 }
            return Swift.min(referenceKd / kd, maxTransporterWeight)
        }
        let wDAT = weight(datKd), wNET = weight(netKd), wSERT = weight(sertKd)

        // Reference dose: curated anchor wins (preserves the calibrated magnitudes), else the DB's
        // heavy-dose ladder, else a neutral default.
        let refUnit = ov?.refUnit ?? pharmacology?.referenceDoseMg ?? 50

        let hasMechanism = wDAT > 0 || wNET > 0 || wSERT > 0
            || (ov?.mu ?? 0) > 0 || (ov?.gaba ?? 0) > 0 || (ov?.cae ?? 0) > 0 || ov?.rec != nil
        guard hasMechanism else { return nil } // inert (e.g. a supplement) ⇒ not modelable

        return SubstanceModelParams(
            ke: ke, ka: ka, refUnit: refUnit,
            wDAT: wDAT, wNET: wNET, wSERT: wSERT,
            deplete: ov?.deplete ?? (releaser ? 0.1 : 0),
            releaser: releaser,
            koff: ov?.koff,
            mu: ov?.mu ?? 0, muEff: ov?.muEff ?? 1,
            gaba: ov?.gaba ?? 0, cae: ov?.cae ?? 0, resp: ov?.resp ?? 0,
            rec: ov?.rec,
        )
    }

    /// Whether a built parameter set should **surface the mechanistic lenses** — i.e. it carries a
    /// stimulant (transporter) or opioid (µ) mechanism. Pure sedatives/enhancers/antagonists
    /// (benzos, CAEs, mirtazapine) are adjuncts: modelable when they accompany a stimulant/opioid, but
    /// they never trigger the view on their own.
    static func triggersMechanisticView(_ params: SubstanceModelParams) -> Bool {
        params.wDAT > 0 || params.wNET > 0 || params.mu > 0 || params.releaser
    }
}
