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
    /// Verified **non-binding for the calibrated monoamine set** (amphetamine, methylphenidate, 2-/3-MMC,
    /// mephedrone): once the DAT:NET:SERT triple is taken from one coherent assay (`transporterProfile`),
    /// their off-DA ratios sit below the cap, so the felt mix is fully data-driven. The cap is retained
    /// only as a safety bound for the general library. The sole case where it still bites — a near-pure
    /// serotonergic releaser whose DAT is ~1000× weaker than NET/SERT (MDMA) — is a *data* limitation
    /// (MDMA's SERT release EC₅₀ is understated in the DB), not an engine one; MDMA is outside the
    /// calibration set and its curve is unaffected by this bound in practice.
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
        /// not a PK constant. This is an **irreducible per-substance calibration scalar** for the
        /// DA-normalized engine: with one shared `Emax`/`Kd`, the mg dose that lands a substance at the
        /// engine's calibrated operating point (`amt ≈ 1`) is substance-specific and is *not* the DB dose
        /// ladder (e.g. 3-MMC calibrates at 80 mg though its heavy oral dose is ~350 mg). The DB
        /// `referenceDoseMg` is only the fallback for uncurated substances. It retires wholesale only under
        /// the full-molar concentration path, where dose→concentration is absolute via MW/Vd/F.
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

    private static let transporterSymbols = ["DAT", "NET", "SERT"]

    /// One transporter engagement reduced to what the weight math needs, tagged with the physical
    /// **assay** it was measured in (one paper, one species) so a DAT:NET:SERT triple can be taken from a
    /// single coherent source rather than mixed across labs.
    private struct TransporterHit {
        let symbol: String // "DAT" | "NET" | "SERT"
        let halfMax: Double // nM
        let kind: PharmacologyParameters.HalfMaxKind
        let confidence: ConfidenceTier
        let assayKey: String
    }

    private static func transporterHits(_ p: PharmacologyParameters) -> [TransporterHit] {
        p.targets.compactMap { t in
            let up = t.target.uppercased()
            guard let symbol = transporterSymbols.first(where: { up.contains($0) }), t.halfMaxNanomolar > 0 else { return nil }
            // Prefer the specific paper (doi/pmid) as the assay identity; fall back to source+species,
            // which still separates, e.g., a human HEK IC₅₀ set from a rat-synaptosome Kᵢ set.
            let assayKey = t.citationKey ?? "\(t.sourceSlug)|\(t.species ?? "")"
            return TransporterHit(symbol: symbol, halfMax: t.halfMaxNanomolar, kind: t.kind, confidence: t.confidence, assayKey: assayKey)
        }
    }

    /// The DA-normalized DAT/NET/SERT weight backbone plus releaser/blocker classification, resolved from
    /// a **single coherent assay** wherever one covers the transporters. A transporter ratio is only
    /// physically meaningful within one experiment (same lab, species, tissue, radioligand), so taking a
    /// per-transporter `.min()` across labs — the old behavior — could straddle assays and distort the
    /// felt DA:NE:5-HT mix (e.g. methylphenidate's DAT IC₅₀ from one lab against a rat NET Kᵢ from
    /// another). We instead pick the assay with the best transporter coverage (then confidence, then
    /// potency) and read the triple from it, filling any transporter that assay lacks from the global
    /// tightest so a real target measured only elsewhere is never dropped.
    private static func transporterProfile(_ p: PharmacologyParameters)
        -> (wDAT: Double, wNET: Double, wSERT: Double, releaser: Bool)? {
        let hits = transporterHits(p)
        guard let mostPotent = hits.min(by: { $0.halfMax < $1.halfMax }) else { return nil }

        // Releaser vs reuptake blocker from the *most potent* transporter engagement overall: the felt
        // mechanism follows the tightest site, so a stray release EC₅₀ on an otherwise-blocker (or the
        // reverse) can't flip the classification. Releaser ⇒ release EC₅₀; blocker ⇒ uptake Kᵢ/IC₅₀.
        let releaser = mostPotent.kind == .ec50
        let mechHits = hits.filter { releaser ? $0.kind == .ec50 : $0.kind != .ec50 }
        let pool = mechHits.isEmpty ? hits : mechHits

        func tightest(_ group: [TransporterHit], _ symbol: String) -> Double? {
            group.filter { $0.symbol == symbol }.map(\.halfMax).min()
        }
        /// Confidence-weighted coverage: a graded transporter is worth more than an ungraded one, so a
        /// two-transporter HIGH assay outranks a three-transporter unverified one. This matters because the
        /// resolver pre-collapses each (target, action, kind) to its tightest row, which can strand a
        /// transporter's provenance in a low-confidence assay and inflate a raw coverage count.
        func confidenceWeight(_ tier: ConfidenceTier) -> Double {
            switch tier {
            case .high: 3
            case .medium: 2
            case .low: 1
            case .unverified: 0.5
            }
        }
        func score(_ group: [TransporterHit]) -> Double {
            transporterSymbols.reduce(0) { total, symbol in
                let best = group.filter { $0.symbol == symbol }.map(\.confidence).max()
                return total + (best.map(confidenceWeight) ?? 0)
            }
        }
        // Pick the assay with the best coverage score, breaking ties toward the more potent (smaller
        // half-max) tightest site; scoring each assay once. Then read its DAT/NET/SERT triple.
        let ranked = Dictionary(grouping: pool, by: \.assayKey).values.map {
            group -> (group: [TransporterHit], score: Double, potency: Double) in
            (group, score(group), group.map(\.halfMax).min() ?? .infinity)
        }
        let best = ranked.max { $0.score != $1.score ? $0.score < $1.score : $0.potency > $1.potency }?.group
        func kd(_ symbol: String) -> Double? {
            best.flatMap { tightest($0, symbol) } ?? tightest(pool, symbol)
        }
        let datKd = kd("DAT"), netKd = kd("NET"), sertKd = kd("SERT")
        guard let referenceKd = datKd ?? [netKd, sertKd].compactMap(\.self).min() else { return nil }
        func weight(_ value: Double?) -> Double {
            guard let value, value > 0 else { return 0 }
            return Swift.min(referenceKd / value, maxTransporterWeight)
        }
        return (weight(datKd), weight(netKd), weight(sertKd), releaser)
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

        // Transporter mix + releaser/blocker classification from a single coherent assay (see
        // `transporterProfile`): DA-normalized so DAT = 1 (the scale the engine's dopamine/reward stage is
        // tuned to) and NET/SERT scale by their potency ratio to DAT, capped. So the felt mix (DA vs NE vs
        // 5-HT) follows the data — a serotonin-dominant releaser (MDMA) reads warmth-led, a DA-selective
        // blocker (MDPV) reward-led — while amphetamine keeps its wDAT ≈ 1 (and thus its store-depletion
        // crash). A substance with no DAT normalizes to its most potent transporter instead.
        let profile = pharmacology.flatMap { transporterProfile($0) }
        let releaser = profile?.releaser ?? false
        let wDAT = profile?.wDAT ?? 0, wNET = profile?.wNET ?? 0, wSERT = profile?.wSERT ?? 0

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

    /// Whether a built parameter set carries a modelable stimulant (transporter) or opioid (µ)
    /// mechanism — i.e. the engine can *simulate* it as an agent. Pure sedatives/enhancers/antagonists
    /// (benzos, CAEs, mirtazapine) are adjuncts: modelable alongside a stimulant/opioid, never alone.
    /// This is a *modelability* check, not a *trigger* — see ``isCalibratedTrigger(_:)``.
    static func triggersMechanisticView(_ params: SubstanceModelParams) -> Bool {
        params.wDAT > 0 || params.wNET > 0 || params.mu > 0 || params.releaser
    }

    /// The substances the effect model was actually **calibrated** on — the only ones allowed to
    /// *trigger* Effect Estimates. The engine can still read every other modelable substance
    /// (methamphetamine, cocaine, kratom, MDMA, …) as an interacting agent that shapes the aggregate
    /// curves, but their solo precision is too low to anchor the model, so a session must contain at
    /// least one of these to surface the view. Normalized canonical names; aliases (`4-mmc`, `ritalin`,
    /// `adderall`, …) resolve through ``aliases`` first. The cathinones rest on a human 3-MMC study.
    static let calibratedTriggerSet: Set<String> = [
        "amphetamine", "methylphenidate", "2-mmc", "3-mmc", "mephedrone",
    ]

    /// Whether `name` — after normalization and alias resolution — is one of the calibrated trigger
    /// substances (``calibratedTriggerSet``). e.g. "Ritalin" → `methylphenidate`, "4-MMC" → `mephedrone`.
    static func isCalibratedTrigger(_ name: String) -> Bool {
        let key = normalize(name)
        return calibratedTriggerSet.contains(aliases[key] ?? key)
    }
}
