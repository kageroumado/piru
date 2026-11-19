import Foundation
import os

/// Builds the mechanistic effect engine's per-substance ``SubstanceModelParams`` from **hard data**
/// (the bundled pharmacology DB) plus a slim curated override layer.
///
/// The split:
///   - **PK + transporter binding come from the resolver** (`PharmacologyParameters`): the elimination
///     rate `ke` from the measured half-life, the absorption rate `ka` from the measured Tmax, the
///     DAT/NET/SERT weight *ratios* from the measured EC₅₀/Kᵢ, and `releaser` from whether the primary
///     transporter is engaged by release (EC₅₀) or reuptake block (Kᵢ/IC₅₀).
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
///
/// **The override layer is data, and it lives in the bundled DB** (`data/curated/model-overrides.json`
/// → `model_overrides` + `model_alias`), installed here once at index build by ``SubstanceStore``
/// through ``loadOverrides(_:)`` / ``loadModelAliases(_:)``. This type is the *engine* that reads it,
/// not the table: edit the curated JSON and rebuild, never add a literal here.
nonisolated enum SubstanceModelDatabase {
    static func normalize(_ name: String) -> String {
        PharmacologyNameKey.fold(name)
    }

    // MARK: - Curated override layer (the irreducible PD scalars + felt-effect PK patches)

    private static let ln2 = log(2.0)
    /// Cap on a transporter weight relative to DAT, so a drug that is far more potent at NET/SERT than
    /// at DAT gets a strong — but not runaway — off-DA weight. The engine's saturating nonlinearities
    /// bound the output regardless; this keeps the *numbers* interpretable.
    ///
    /// Verified **non-binding for the calibrated monoamine set** (amphetamine, methylphenidate, 2-/3-MMC,
    /// mephedrone): once the DAT:NET:SERT triple is taken from one coherent assay (`transporterProfile`),
    /// their off-DA ratios sit below the cap, so the felt mix is fully data-driven. The cap is a safety
    /// bound for the general library. It can bite on a near-pure serotonergic releaser whose DAT is
    /// ~1000× weaker than NET/SERT (MDMA), which is a *data* limitation (MDMA's SERT release EC₅₀ is
    /// understated in the DB); MDMA is outside the calibration set and in practice its curve is
    /// unaffected by this bound.
    private static let maxTransporterWeight = 4.0

    /// Per-substance overrides applied on top of the DB-derived base. Every field is optional: a `nil`
    /// PK field means "trust the DB"; a set PK field patches a DB value that is missing or wrong for the
    /// felt-effect curve. The PD scalars have no DB source and are authoritative here.
    struct Overrides {
        // Felt-effect PK patches (nil ⇒ use the DB-derived value): the plasma half-life / Tmax the DB
        // ships is wrong for the *felt* curve (prodrugs, enterohepatic drugs), or the DB has no PK at all.
        var ke: Double?
        var ka: Double?
        /// Dose-magnitude anchor — the reference dose the concentration is normalized to (`amt = dose/refDose`),
        /// not a PK constant. This is an **irreducible per-substance calibration scalar** for the
        /// DA-normalized engine: with one shared `Emax`/`Kd`, the mg dose that lands a substance at the
        /// engine's calibrated operating point (`amt ≈ 1`) is substance-specific and is *not* the DB dose
        /// ladder (e.g. 3-MMC calibrates at 80 mg though its heavy oral dose is ~350 mg). The DB
        /// `referenceDoseMg` is only the fallback for uncurated substances. It retires wholesale only under
        /// the full-molar concentration path, where dose→concentration is absolute via MW/Vd/F.
        var refDose: Measurement<UnitDoseMass>?
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

    /// The override layer and its PD-inheritance relation, loaded from the bundled DB at index build
    /// (``loadOverrides(_:)`` / ``loadModelAliases(_:)``). Held in locks because the builder and the
    /// elimination gate run from `nonisolated` code with no store reference; empty before the load,
    /// which simply leaves every substance on the classic timeline until the store is open.
    private static let overridesTable = OSAllocatedUnfairLock<[String: Overrides]>(initialState: [:])
    private static let aliasTable = OSAllocatedUnfairLock<[String: String]>(initialState: [:])

    /// Install the override rows read from `model_overrides`, converting each to an ``Overrides`` —
    /// the felt-effect `felt_half_life_minutes` (per minute) becomes the per-hour `ke` the engine
    /// works in, which is the one place that conversion happens. Called once per store init.
    static func loadOverrides(_ rows: [String: SubstanceReadModel.ModelOverrideRow]) {
        let table = rows.mapValues { row -> Overrides in
            let rec: ReceptorAffinities? = {
                guard row.recH1 != nil || row.recA2 != nil || row.rec2C != nil || row.rec2A != nil else { return nil }
                return ReceptorAffinities(h1: row.recH1, a2: row.recA2, c2C: row.rec2C, c2A: row.rec2A)
            }()
            return Overrides(
                ke: row.feltHalfLifeMinutes.map { ln2 / ($0 / 60) },
                ka: row.kaPerHour,
                refDose: row.referenceDoseMg.map { .mg($0) },
                deplete: row.deplete,
                koff: row.koff,
                mu: row.mu ?? 0,
                muEff: row.muEff ?? 1,
                gaba: row.gaba ?? 0,
                cae: row.cae ?? 0,
                resp: row.resp ?? 0,
                rec: rec,
            )
        }
        overridesTable.withLock { $0 = table }
    }

    /// Install the PD-inheritance relation read from `model_alias`. Called once per store init.
    static func loadModelAliases(_ aliases: [String: String]) {
        aliasTable.withLock { $0 = aliases }
    }

    private static func overrides(for name: String) -> Overrides? {
        let table = overridesTable.withLock { $0 }
        let aliases = aliasTable.withLock { $0 }
        return PharmacologyNameKey.resolve(name, in: table, aliases: aliases)
    }

    /// Names carrying a curated override, for the elimination-consistency gate.
    static var curatedOverrideNames: [String] {
        Array(overridesTable.withLock { $0 }.keys)
    }

    /// The felt-effect half-life a curated `ke` patch encodes, in **minutes**.
    /// `Overrides.ke` is per-HOUR while every sibling table is per-minute;
    /// putting the unit in this API name is what keeps that trap at the
    /// boundary — never expose the raw `ke`. `nil` when the override trusts
    /// the DB's PK.
    static func curatedHalfLifeMinutes(for name: String) -> Double? {
        overrides(for: name)?.ke.map { 60 * ln2 / $0 }
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
    /// per-transporter `.min()` across labs could straddle assays and distort the felt DA:NE:5-HT mix
    /// (e.g. methylphenidate's DAT IC₅₀ from one lab against a rat NET Kᵢ from another). Pick the assay
    /// with the best transporter coverage (then confidence, then potency) and read the triple from it,
    /// filling any transporter that assay lacks from the global tightest so a real target measured only
    /// elsewhere is never dropped.
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
        // The final assay-key tie-break keeps the pick deterministic: Dictionary iteration order is
        // hash-seeded per launch, so a full score+potency tie would otherwise flip the winning triple
        // (and the Effect Estimates curve) between app runs.
        let ranked = Dictionary(grouping: pool, by: \.assayKey)
            .map { key, group -> (key: String, group: [TransporterHit], score: Double, potency: Double) in
                (key, group, score(group), group.map(\.halfMax).min() ?? .infinity)
            }
        let best = ranked.max { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score < rhs.score }
            if lhs.potency != rhs.potency { return lhs.potency > rhs.potency }
            return lhs.key < rhs.key
        }?.group
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
        let refDoseMg = ov?.refDose?.value(in: .milligrams) ?? pharmacology?.referenceDoseMg ?? 50

        let hasMechanism = wDAT > 0 || wNET > 0 || wSERT > 0
            || (ov?.mu ?? 0) > 0 || (ov?.gaba ?? 0) > 0 || (ov?.cae ?? 0) > 0 || ov?.rec != nil
        guard hasMechanism else { return nil } // inert (e.g. a supplement) ⇒ not modelable

        return SubstanceModelParams(
            ke: ke, ka: ka, refDoseMg: refDoseMg,
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
    /// least one of these to surface the view.
    ///
    /// Lowercased canonical names carrying the bundled DB's `model-calibrated` flag; aliases (`4-mmc`,
    /// `ritalin`, `adderall`, …) resolve through ``aliases`` first, which is why the membership test is
    /// ``isCalibratedTrigger(_:)`` and not a bare `contains`. Held in a lock-guarded static because the
    /// gate runs from `nonisolated` code with no store reference; installed once by ``SubstanceStore``
    /// at index build, and empty before that, which surfaces the classic timeline rather than a
    /// mechanistic view built on a substance nobody calibrated.
    private static let calibrated = OSAllocatedUnfairLock<Set<String>>(initialState: [])

    /// Install the calibrated set read from `substance_flags`. Called once per store init.
    static func loadCalibrated(_ names: Set<String>) {
        calibrated.withLock { $0 = names }
    }

    /// The calibrated substances as canonical names — the anchor list the sandbox picker offers.
    static var calibratedTriggerSet: Set<String> {
        calibrated.withLock { $0 }
    }

    /// Whether `name` — after normalization and alias resolution — is one of the calibrated trigger
    /// substances (``calibratedTriggerSet``). e.g. "Ritalin" → `methylphenidate`, "4-MMC" → `mephedrone`.
    static func isCalibratedTrigger(_ name: String) -> Bool {
        calibratedTriggerSet.contains(PharmacologyNameKey.canonical(name, aliases: aliasTable.withLock { $0 }))
    }
}
