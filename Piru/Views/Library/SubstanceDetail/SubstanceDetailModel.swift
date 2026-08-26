import SwiftData
import SwiftUI

/// Async-loaded detail data for ``SubstanceDetailView``, pulled off the SQLite
/// store in `.task` and swapped in reactively. Holding it in an `@Observable`
/// model (rather than a fistful of `@State` on the view) means each loaded field
/// invalidates only the section that reads it — the receptor list appearing
/// doesn't re-run the whole screen — and the loading logic lives next to the
/// data instead of in the view body.
@MainActor
@Observable
final class SubstanceDetailModel {
    private let store = SubstanceStore.shared

    /// Per-field source attribution (which database supplied category, half-life,
    /// mechanism, and per-route dose/duration). Fetched for every tier.
    var provenance: SubstanceStore.SubstanceProvenance?

    /// Measured receptor binding rows — feed both the pharma-nerd "Receptor
    /// Literature" list and the unified Pharmacology card's class hero.
    var literatureBindings: [BindingHit] = []

    /// The receptor rows worth showing, derived once per `literatureBindings`
    /// assignment (the filter/dedup/sort pipeline is too heavy to re-run per
    /// body pass). See ``visibleBindings(from:)`` for the relevance rules.
    var visibleLiteratureBindings: [BindingHit] = []

    /// Per-route pharmacokinetics (bioavailability / tmax / half-life), one row
    /// per route: the table holds a row per *study*, which rendered as the same
    /// card several times over. See ``SubstanceStore/displayRows(_:)``.
    var pkRoutes: [SubstanceStore.PKDisplayRow] = []

    /// CYP/enzyme clearance pathways and their metabolites.
    var metabolismRows: [SubstanceStore.MetabolismHit] = []

    /// Grapefruit / smoking / self-edge metabolic-modulation education.
    var metabolicEducation: [MetabolicModulation.Effect] = []

    /// Measured PK interactions from the literature: what a named drug or drug
    /// class does to this substance's exposure. Sourced facts, not warnings.
    var pkInteractions: [SubstanceStore.PKInteractionHit] = []

    /// Things the compound acts on that are not why anyone takes it — the hERG
    /// / bladder / taste-receptor rows. One per target, most-consequential first.
    var offTargets: [SubstanceStore.OffTargetHit] = []

    /// Genes whose variants change what this substance does — the enzymes that
    /// clear it, and the receptors and transporters it acts on. One row per
    /// gene.
    var pharmacogenetics: [SubstanceStore.PharmacogeneticHit] = []

    /// Pathway bias, receptor complexes and in-vivo imaging — the evidence about
    /// a target that is not an affinity number.
    var targetEvidence: [SubstanceStore.TargetEvidence] = []

    /// What happens after the receptor binds.
    var signallingCascade: SubstanceStore.SignallingCascade?

    /// The plasma concentrations at which named effects appear — what makes the
    /// PK curve readable rather than merely shaped.
    var concentrationThresholds: [SubstanceStore.ConcentrationThreshold] = []

    /// The pharmacological family this substance belongs to, and what its
    /// members share. Carries most of what is known about the long tail.
    var classContext: SubstanceStore.ClassContext?

    /// Which source supplied which field, for the Sources ledger. Loaded here
    /// rather than by the section itself: the ledger folds now, and a `.task`
    /// inside a collapsed disclosure doesn't run until the user opens it — so
    /// the layout's presence gate would be deciding whether to show the section
    /// from data that only arrives once the section is already on screen.
    var sourceContributions: SubstanceStore.SourceContributions = .empty

    /// Metabolites doing some of the work — the "Also Active" surface. Folded
    /// from ``metabolismRows`` by metabolite (the table groups by enzyme), and
    /// filtered to the ones that can actually say something, so the section is
    /// absent for the ~90% of the library with nothing to report.
    var activeMetabolites: [ActiveMetabolite] = []

    /// Set when this substance is a meaningful CYP3A4 inducer (modafinil,
    /// rifampicin…) — it can lower hormonal-contraception levels.
    var contraceptionCaution: MetabolicModulation.Modulator?

    /// CYP2D6 metabolism classification, derived from ``metabolismRows``. Non-nil when the
    /// substance has at least one metabolism row where CYP2D6 is a primary pathway.
    var cyp2d6Info: CYP2D6Info?

    /// DA↔5-HT character / releaser-blocker card, derived from the bindings.
    var monoamineProfile: MonoamineProfile?

    /// The class signature for the Pharmacology card — the gated comparison that says where this
    /// compound sits among the ones it is actually comparable to (efficacy axis / 5-HT balance /
    /// transporter ternary), or the stated absence when nothing passed the gate. `nil` for classes
    /// with no signature and for compounds with no rows of the kind at all.
    var classSignature: ClassSignature?

    /// The substance's 2D skeleton, drawn faint behind the whole screen.
    var moleculeStructure: MoleculeStructure?

    /// drug.community intensity bands. Loaded here rather than in the Effects
    /// section because the **dose card** now owns the dial: dose and effect are
    /// one control, so they must read one copy of the data.
    var spectrumBands: [SpectrumBand] = []

    /// O(n) dose-history aggregates for the history card.
    var historyStats = HistoryStats()

    struct HistoryStats: Equatable {
        var minDose: Double = 0
        var maxDose: Double = 0
        var mostCommon: Double = 0
    }

    /// Resolve every store-backed field for the substance at the current
    /// disclosure tier. Each query is skipped for tiers that don't show its
    /// surface, matching the old per-tier `.task` gating.
    func load(substanceName: String, category: SubstanceCategory, policy: DisclosurePolicy) {
        // Always fetch provenance — per-field source attribution is shown to
        // every tier so users can see where each fact came from.
        provenance = store.provenance(forSubstanceName: substanceName)

        // The dial is the dose control, so its bands load for every tier that
        // sees a dose ladder — not just the ones that see the pharmacology.
        spectrumBands = store.spectrumBands(forSubstanceName: substanceName)
        moleculeStructure = store.moleculeStructure(forSubstanceName: substanceName)

        // Ungated by tier. A row here is a consequence ("ulcerative cystitis in
        // chronic high-dose users"), not an affinity table, and tiering in this
        // app governs density rather than access — the card ships folded at
        // every tier instead.
        offTargets = store.offTargets(forSubstanceName: substanceName)
        pharmacogenetics = store.pharmacogenetics(forSubstanceName: substanceName)
        targetEvidence = store.targetEvidence(forSubstanceName: substanceName)
        signallingCascade = store.signallingCascade(forSubstanceName: substanceName)
        concentrationThresholds = store.concentrationThresholds(forSubstanceName: substanceName)
        classContext = store.classContext(forSubstanceName: substanceName)
        sourceContributions = store.sourceContributions(forSubstanceName: substanceName)

        // Contraceptive-efficacy caution — a CYP3A4 inducer (modafinil,
        // rifampicin…) can lower hormonal-contraception levels. Ungated like a
        // boxed warning: a safety fact for every tier.
        contraceptionCaution = MetabolicModulation.contraceptiveEfficacyCaution(forSubstance: substanceName)

        // Binding rows feed two surfaces: the pharma-nerd "Receptor Literature"
        // list AND the broader "Monoamine Profile" card. The card loads for the
        // mechanism audience, so fetch once when either surface is shown.
        if policy.showsMechanism || policy.showsReceptorLiterature {
            let binds = store.bindings(forSubstanceName: substanceName)
            monoamineProfile = MonoamineProfile.from(
                bindings: binds,
                isSoldAsMDMA: store.hasFlag(PharmacologyParameters.Flag.missoldAsMDMA, forSubstanceName: substanceName),
            )
            literatureBindings = binds
            visibleLiteratureBindings = Self.visibleBindings(from: binds)
        } else {
            monoamineProfile = nil
            literatureBindings = []
            visibleLiteratureBindings = []
        }

        // The class signature is a *comparison*, so unlike everything else here it reads the whole
        // family's rows rather than this substance's. Only the mechanism audience sees it.
        //
        // Resolved through ``ActiveIngredient`` like the bindings above, and for a sharper reason:
        // the axis marks its focus by NAME. Left unresolved, cannabis would look for a "Cannabis"
        // leg among rows that are all filed under THC, find none, and drop the axis entirely on the
        // one page where "how far does this switch the receptor on" is the whole question.
        classSignature = policy.showsMechanism
            ? ClassSignature.family(for: category).flatMap { family in
                ClassSignature.resolve(
                    substanceName: ActiveIngredient.pharmacologyName(for: substanceName),
                    category: category,
                    legs: store.signatureLegs(family: family),
                )
            }
            : nil

        // Pharmacokinetics (per-route PK + CYP metabolism) is a pharma-nerd
        // surface — skip the two queries for other tiers.
        if policy.showsPharmacokinetics {
            pkRoutes = SubstanceStore.displayRows(store.pharmacokinetics(forSubstanceName: substanceName))
            metabolismRows = store.metabolism(forSubstanceName: substanceName)
            pkInteractions = store.pkInteractions(forSubstanceName: substanceName)
        } else {
            pkRoutes = []
            metabolismRows = []
            pkInteractions = []
        }

        // Grapefruit/smoking/self-edge education is harm-reduction-relevant, so
        // it loads for non-casual tiers from its own metabolism fetch (the full
        // PK table above stays pharma-nerd).
        // One fetch feeds both surfaces. "Also Active" is read on **every** tier,
        // including casual: whether something other than what you took is
        // producing the effect is a fact about your experience, not reference
        // data, and the reader least likely to already know it is the one who
        // never opens the pharmacology tier. The grapefruit/smoking education
        // below stays harm-reduction-and-up, since that is genuinely advisory.
        let rows = policy.showsPharmacokinetics ? metabolismRows : store.metabolism(forSubstanceName: substanceName)
        activeMetabolites = Self.foldActiveMetabolites(from: rows)
        cyp2d6Info = CYP2D6Info.from(metabolismRows: rows)
        metabolicEducation = policy.showsMechanism
            ? MetabolicModulation.educationalEffects(forSubstance: substanceName, metabolism: rows)
            : []
    }

    /// Group the metabolism rows by metabolite and keep the ones with something
    /// to say. Excretion rows (no metabolite) and inactive byproducts drop out
    /// here — an "Also Active" card for an inactive metabolite is a
    /// contradiction, and one that only reads "Active" is noise.
    static func foldActiveMetabolites(from rows: [SubstanceStore.MetabolismHit]) -> [ActiveMetabolite] {
        var order: [String] = []
        var byName: [String: [SubstanceStore.MetabolismHit]] = [:]
        for row in rows {
            guard row.metaboliteActive == true, let name = row.metaboliteName, !name.isEmpty else { continue }
            // "unchanged <parent>" is an excretion row wearing a metabolite
            // field — it names no new molecule. Mirrors `MetabolismRow`'s own
            // elimination detection.
            guard !name.lowercased().hasPrefix("unchanged") else { continue }
            // Combination-only species (cocaethylene, ethylphenidate) form solely
            // while a second drug is onboard, so they must not read as an
            // unconditional metabolite of the parent — they surface through
            // `CombinationMetabolite.formed(among:)`, gated on co-occurrence.
            guard !CombinationMetabolite.isConditional(name) else { continue }
            let key = name.lowercased()
            if byName[key] == nil { order.append(key) }
            byName[key, default: []].append(row)
        }
        return order
            .compactMap { ActiveMetabolite.from(rows: byName[$0] ?? []) }
            .filter(\.isWorthShowing)
    }

    func rebuildHistoryStats(from entries: [DoseEntry]) {
        let amounts = entries.map(\.amount)
        var freq: [Double: Int] = [:]
        for a in amounts {
            freq[a, default: 0] += 1
        }
        historyStats = HistoryStats(
            minDose: amounts.min() ?? 0,
            maxDose: amounts.max() ?? 0,
            mostCommon: freq.max(by: { $0.value < $1.value })?.key ?? 0,
        )
    }

    // MARK: - Literature derivations

    /// The class-specific hero for the unified Pharmacology card (opioid / benzo
    /// / dissociative receptor panel). `nil` for monoamine and other classes,
    /// which fall back to the slider/target grid.
    func pharmacologyHero(category: SubstanceCategory) -> PharmacologyHero? {
        PharmacologyHero.resolve(category: category, bindings: visibleLiteratureBindings)
    }

    /// The receptor rows worth showing: the 10 µM relevance cap. Drops a **Kᵢ-based** off-target binding
    /// ≥ 10,000 nM (the standard "no meaningful affinity" cutoff) — ketamine's σ/µ/κ, meth's σ2, MDMA's
    /// 12–15 µM modulators — *unless* it sits within 10× of the substance's tightest binding, so a
    /// substance whose primary targets are all weak (caffeine's matched A1/A2A adenosine pair) keeps them.
    /// EC₅₀/IC₅₀ functional transporter rows are never capped: a releaser's DAT EC₅₀ is legitimately tens
    /// of µM yet is the primary mechanism.
    private static func visibleBindings(from literatureBindings: [BindingHit]) -> [BindingHit] {
        let floor = literatureBindings
            .compactMap { [$0.kiNm, $0.ec50Nm, $0.ic50Nm].compactMap(\.self).min() }
            .min()
        let capped = literatureBindings.filter { hit in
            // Drop curated tier-only rows (no measured value) — they drive the MOA dot table, not this
            // literature list, and would otherwise render as empty rows.
            guard hit.kiNm != nil || hit.ec50Nm != nil || hit.ic50Nm != nil else { return false }
            guard let ki = hit.kiNm, ki >= 10_000 else { return true }
            if let floor, ki <= floor * 10 { return true }
            return false
        }
        // Strongest receptors first: by strength tier desc, then more-potent-first within a tier.
        return Self.dedupedLiterature(capped).sorted { lhs, rhs in
            let lt = Self.strengthTier(for: lhs) ?? 0
            let rt = Self.strengthTier(for: rhs) ?? 0
            if lt != rt { return lt > rt }
            let lv = lhs.kiNm ?? lhs.ec50Nm ?? lhs.ic50Nm ?? .greatestFiniteMagnitude
            let rv = rhs.kiNm ?? rhs.ec50Nm ?? rhs.ic50Nm ?? .greatestFiniteMagnitude
            return lv < rv
        }
    }

    /// Collapse the literature list: when a (target, action) has any **human** row, drop its non-human
    /// (in-vitro / animal) rows — "who cares about in vitro when we have human data" — then remove exact
    /// duplicate measurements (same target+action+value across sources), so MDMA's 5-HT2A 7800 ×2 and
    /// DAT 22000 ×2 collapse to one. Order is preserved (the store already sorts Kᵢ-tightest first, then
    /// functional EC₅₀/IC₅₀), so binding affinities still lead the functional transporter rows.
    static func dedupedLiterature(_ rows: [BindingHit]) -> [BindingHit] {
        func isHuman(_ s: String?) -> Bool {
            (s ?? "").lowercased().contains("human")
        }
        let humanTAs = Set(rows.filter { isHuman($0.species) }.map { "\($0.target)|\($0.action)" })
        let preferred = rows.filter { hit in
            humanTAs.contains("\(hit.target)|\(hit.action)") ? isHuman(hit.species) : true
        }
        var seen = Set<String>()
        return preferred.filter { hit in
            let value = if let ki = hit.kiNm {
                "ki\(ki)"
            } else if let ec = hit.ec50Nm {
                "ec\(ec)"
            } else if let ic = hit.ic50Nm {
                "ic\(ic)"
            } else {
                "na"
            }
            return seen.insert("\(hit.target)|\(hit.action)|\(value)").inserted
        }
    }

    /// Strength tier (1–3) for a literature row's dots — the single, systematic `ReceptorStrength`
    /// model (measurement-aware bands). The Mechanism card computes the *same* bands from the *same*
    /// measured values in SQL, so the two cards agree by construction (no per-target inheritance hack).
    static func strengthTier(for hit: BindingHit) -> Int? {
        ReceptorStrength.tier(kiNm: hit.kiNm, ec50Nm: hit.ec50Nm, ic50Nm: hit.ic50Nm)
    }
}

// MARK: - CYP2D6 substrate classification

/// Whether a substance is primarily metabolized by CYP2D6, and whether that metabolism creates
/// a qualitatively different drug (prodrug pattern) or just clears the parent. `nonisolated` (pure
/// value logic over ``SubstanceStore/MetabolismHit``) so the off-main tolerance resolve can reuse it
/// for the §F.3 CYP2D6 half-life multiplier.
nonisolated struct CYP2D6Info {
    /// CYP2D6 is the primary (first-listed or sole) metabolic pathway.
    let isMajorPathway: Bool
    /// The CYP2D6 step produces a divergent metabolite — the parent is a prodrug and the
    /// metabolite is the active species (codeine→morphine, tramadol→M1). When true, a
    /// poor-metabolizer note emphasizes reduced activation; when false, it emphasizes
    /// slower clearance / longer duration.
    let hasProdrugPattern: Bool

    static func from(metabolismRows rows: [SubstanceStore.MetabolismHit]) -> CYP2D6Info? {
        let cyp2d6Rows = rows.filter { isCYP2D6Primary($0.enzyme) }
        guard !cyp2d6Rows.isEmpty else { return nil }
        // A CYP2D6 step is a prodrug pattern when the metabolite is active AND
        // either divergent-mechanism OR ≥5× more potent than the parent. The
        // potency gate catches codeine→morphine (scaled, 200×) and
        // oxycodone→oxymorphone (scaled, 10–40×), where the parent is a weak
        // opioid and the metabolite is the real drug.
        let hasProdrugPattern = cyp2d6Rows.contains { row in
            row.metaboliteActive == true
                && (row.metaboliteMechanismVsParent == .divergent
                    || (row.metabolitePotencyVsParentPct ?? 100) >= 500)
        }
        return CYP2D6Info(isMajorPathway: true, hasProdrugPattern: hasProdrugPattern)
    }

    /// CYP2D6 is a primary pathway when it appears at the leading position of the
    /// freeform enzyme string — "CYP2D6", "CYP2D6 (major)", "CYP2D6 / CYP3A4".
    /// A string like "CYP3A4 / CYP2D6" lists it as a minor contributor.
    private static func isCYP2D6Primary(_ enzyme: String) -> Bool {
        let trimmed = enzyme.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("CYP2D6")
    }
}
