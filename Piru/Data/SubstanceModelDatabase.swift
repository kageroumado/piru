import Foundation

/// Curated pharmacology parameters for the mechanistic effect engine, plus the resolver.
///
/// Separation of concerns: `EffectEngine` (Shared/) is substance-agnostic — it only consumes
/// `SubstanceModelParams`. This file is the DATA + CLASSIFICATION layer that maps a real substance to
/// those params:
///   1. a **curated** entry (hand-authored against the JS reference / `SPEC.md`), keyed by canonical
///      name or a known alias;
///   2. else `nil` — the caller falls back to the classic duration timeline (Tier 0). Honest, not faked.
///
/// **No analogue fallback (for now).** A previous version filled uncurated substances with a single
/// per-class template (amphetamine for *every* stimulant, morphine for *every* opioid). That produced
/// confident-looking mechanistic curves for substances with completely different kinetics — a prodrug,
/// a long-acting reuptake blocker, and a short-acting releaser all rendered identically — with no
/// "estimate" caveat surfaced to the user. Until a real nearest-analogue system exists (matching by
/// actual pharmacology, not just category — e.g. a prodrug like lisdexamfetamine *can* borrow
/// amphetamine, but a benzo can't borrow another benzo's kinetics blindly), an uncurated substance
/// gets the classic duration curve rather than a fabricated one. The curated table already covers the
/// common stimulants/opioids/empathogens.
///
/// Mirrors the `HalfLifeDatabase` house style: a `nonisolated enum` with a lowercased-name dictionary,
/// an alias map, and a lookup. Ports the JS `DRUG` table (`piru-effect-model/model-hc.mjs`).
nonisolated enum SubstanceModelDatabase {
    /// Where a resolved parameter set came from. Currently only ``curated`` is ever produced; the
    /// ``analogue`` case is reserved for the future nearest-analogue rework (see the type doc) and the
    /// downstream "estimated" plumbing (`MechanisticSessionModel.Result.usesAnalogue`) is kept wired
    /// for it.
    enum Source: Equatable {
        case curated // hand-authored params for this substance (or its alias)
        case analogue(SubstanceCategory) // reserved — not produced until the analogue rework lands
    }

    struct Resolution: Equatable {
        let params: SubstanceModelParams
        let source: Source
    }

    /// Resolve params for a substance. `nil` ⇒ not curated ⇒ fall back to the classic duration curve.
    /// `category` is currently unused (the analogue fallback that consumed it is disabled) but retained
    /// in the signature for the coming nearest-analogue rework.
    static func resolve(name: String, category _: SubstanceCategory) -> Resolution? {
        let key = normalize(name)
        if let p = curated[key] { return Resolution(params: p, source: .curated) }
        if let canonical = aliases[key], let p = curated[canonical] { return Resolution(params: p, source: .curated) }
        return nil
    }

    static func normalize(_ name: String) -> String {
        name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Classification (which views a session supports)

    /// True iff the mechanistic lenses (Feeling/Energy/Compulsion/Strain) should be surfaced for a session — i.e. it
    /// contains at least one stimulant or opioid the engine models. Pure sedatives/enhancers/modifiers (benzos,
    /// CAEs, mirtazapine) don't trigger it on their own; nor do unmodelable classes. Everything else stays on the
    /// classic duration timeline (Tier 0). Matches Kiri's rule: "only surface it when we have stimulants or opioids."
    static func supportsMechanisticView(_ substances: [(name: String, category: SubstanceCategory)]) -> Bool {
        substances.contains { s in
            guard let p = resolve(name: s.name, category: s.category)?.params else { return false }
            return p.wDAT > 0 || p.wNET > 0 || p.mu > 0 || p.releaser
        }
    }

    // MARK: - Curated table (ports the JS DRUG table, keyed by canonical substance name)

    private static let LN2 = log(2.0)

    private static let curated: [String: SubstanceModelParams] = [
        "amphetamine": SubstanceModelParams(ke: LN2 / 10.0, ka: 2.0, refUnit: 50, wDAT: 1.0, wNET: 1.8, wSERT: 0.0, deplete: 1.0, releaser: true),
        "methylphenidate": SubstanceModelParams(ke: LN2 / 3.0, ka: 1.2, refUnit: 60, wDAT: 1.0, wNET: 0.9, wSERT: 0.0, deplete: 0.0, releaser: false, koff: 8.0),
        "2-mmc": SubstanceModelParams(ke: LN2 / 2.0, ka: 5.0, refUnit: 250, wDAT: 1.0, wNET: 1.5, wSERT: 0.16, deplete: 0.12, releaser: true),
        "3-mmc": SubstanceModelParams(ke: LN2 / 2.0, ka: 5.0, refUnit: 80, wDAT: 1.0, wNET: 1.7, wSERT: 0.32, deplete: 0.12, releaser: true),
        "mdma": SubstanceModelParams(ke: LN2 / 7.0, ka: 2.0, refUnit: 90, wDAT: 0.6, wNET: 1.2, wSERT: 2.8, deplete: 0.10, releaser: true),
        "4-fea": SubstanceModelParams(ke: LN2 / 5.0, ka: 2.0, refUnit: 120, wDAT: 0.15, wNET: 0.2, wSERT: 2.6, deplete: 0.05, releaser: true),
        "mdpv": SubstanceModelParams(ke: LN2 / 2.0, ka: 2.0, refUnit: 15, wDAT: 1.0, wNET: 0.9, wSERT: 0.02, deplete: 0.0, releaser: false, koff: 3.0),
        "5-apb": SubstanceModelParams(ke: LN2 / 6.0, ka: 2.0, refUnit: 70, wDAT: 0.3, wNET: 0.6, wSERT: 3.2, deplete: 0.08, releaser: true),
        "kratom": SubstanceModelParams(ke: LN2 / 4.0, ka: 1.5, refUnit: 3, wDAT: 0.0, wNET: 0.25, wSERT: 0.15, deplete: 0.0, releaser: false, mu: 0.55, muEff: 0.5),
        "bromazepam": SubstanceModelParams(ke: LN2 / 16.0, ka: 1.0, refUnit: 6, releaser: false, gaba: 1.0),
        "ppap": SubstanceModelParams(ke: LN2 / 4.0, ka: 1.5, refUnit: 20, releaser: false, cae: 0.45),
        "bpap": SubstanceModelParams(ke: LN2 / 5.0, ka: 1.5, refUnit: 1, releaser: false, cae: 1.1),
        "mirtazapine": SubstanceModelParams(ke: LN2 / 24.0, ka: 1.2, refUnit: 30, releaser: false, rec: ReceptorAffinities(h1: 0.03, a2: 0.6, c2C: 0.6, c2A: 0.9)),
        "heroin": SubstanceModelParams(ke: LN2 / 2.5, ka: 6.0, refUnit: 10, releaser: false, mu: 1.0, muEff: 0.97, resp: 1.4),
        "morphine": SubstanceModelParams(ke: LN2 / 3.0, ka: 1.2, refUnit: 30, releaser: false, mu: 1.0, muEff: 0.95, resp: 1.0),
        "oxycodone": SubstanceModelParams(ke: LN2 / 4.0, ka: 1.5, refUnit: 20, releaser: false, mu: 1.0, muEff: 0.92, resp: 0.9),
    ]

    private static let aliases: [String: String] = [
        "adderall": "amphetamine", "dextroamphetamine": "amphetamine", "lisdexamfetamine": "amphetamine",
        "speed": "amphetamine", "ritalin": "methylphenidate", "concerta": "methylphenidate",
        "mephedrone": "3-mmc", "3mmc": "3-mmc", "2mmc": "2-mmc",
        "molly": "mdma", "ecstasy": "mdma", "mitragynine": "kratom",
        "diamorphine": "heroin", "diacetylmorphine": "heroin", "oxycontin": "oxycodone",
        "remeron": "mirtazapine",
    ]
}
