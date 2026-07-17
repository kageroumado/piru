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
    var literatureBindings: [SubstanceStore.BindingHit] = []

    /// Per-route pharmacokinetics (bioavailability / tmax / half-life).
    var pkRoutes: [SubstanceStore.PKRouteHit] = []

    /// CYP/enzyme clearance pathways and their metabolites.
    var metabolismRows: [SubstanceStore.MetabolismHit] = []

    /// Grapefruit / smoking / self-edge metabolic-modulation education.
    var metabolicEducation: [MetabolicModulation.Effect] = []

    /// Set when this substance is a meaningful CYP3A4 inducer (modafinil,
    /// rifampicin…) — it can lower hormonal-contraception levels.
    var contraceptionCaution: MetabolicModulation.Modulator?

    /// DA↔5-HT character / releaser-blocker card, derived from the bindings.
    var monoamineProfile: MonoamineProfile?

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
    func load(substanceName: String, policy: DisclosurePolicy) {
        // Always fetch provenance — per-field source attribution is shown to
        // every tier so users can see where each fact came from.
        provenance = store.provenance(forSubstanceName: substanceName)

        // Contraceptive-efficacy caution — a CYP3A4 inducer (modafinil,
        // rifampicin…) can lower hormonal-contraception levels. Ungated like a
        // boxed warning: a safety fact for every tier.
        contraceptionCaution = MetabolicModulation.contraceptiveEfficacyCaution(forSubstance: substanceName)

        // Binding rows feed two surfaces: the pharma-nerd "Receptor Literature"
        // list AND the broader "Monoamine Profile" card. The card loads for the
        // mechanism audience, so fetch once when either surface is shown.
        if policy.showsMechanism || policy.showsReceptorLiterature {
            let binds = store.bindings(forSubstanceName: substanceName)
            monoamineProfile = MonoamineProfile.from(bindings: binds, substanceName: substanceName)
            literatureBindings = binds
        } else {
            monoamineProfile = nil
            literatureBindings = []
        }

        // Pharmacokinetics (per-route PK + CYP metabolism) is a pharma-nerd
        // surface — skip the two queries for other tiers.
        if policy.showsPharmacokinetics {
            pkRoutes = store.pharmacokinetics(forSubstanceName: substanceName)
            metabolismRows = store.metabolism(forSubstanceName: substanceName)
        } else {
            pkRoutes = []
            metabolismRows = []
        }

        // Grapefruit/smoking/self-edge education is harm-reduction-relevant, so
        // it loads for non-casual tiers from its own metabolism fetch (the full
        // PK table above stays pharma-nerd).
        if policy.showsMechanism {
            let rows = policy.showsPharmacokinetics ? metabolismRows : store.metabolism(forSubstanceName: substanceName)
            metabolicEducation = MetabolicModulation.educationalEffects(forSubstance: substanceName, metabolism: rows)
        } else {
            metabolicEducation = []
        }
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
        PharmacologyHero.resolve(category: category, bindings: Self.dedupedLiterature(visibleLiteratureBindings))
    }

    /// The receptor rows worth showing: the 10 µM relevance cap. Drops a **Kᵢ-based** off-target binding
    /// ≥ 10,000 nM (the standard "no meaningful affinity" cutoff) — ketamine's σ/µ/κ, meth's σ2, MDMA's
    /// 12–15 µM modulators — *unless* it sits within 10× of the substance's tightest binding, so a
    /// substance whose primary targets are all weak (caffeine's matched A1/A2A adenosine pair) keeps them.
    /// EC₅₀/IC₅₀ functional transporter rows are never capped: a releaser's DAT EC₅₀ is legitimately tens
    /// of µM yet is the primary mechanism.
    var visibleLiteratureBindings: [SubstanceStore.BindingHit] {
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
    static func dedupedLiterature(_ rows: [SubstanceStore.BindingHit]) -> [SubstanceStore.BindingHit] {
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
    static func strengthTier(for hit: SubstanceStore.BindingHit) -> Int? {
        ReceptorStrength.tier(kiNm: hit.kiNm, ec50Nm: hit.ec50Nm, ic50Nm: hit.ic50Nm)
    }
}
