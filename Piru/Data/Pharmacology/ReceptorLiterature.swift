import Foundation

/// Which measured receptor bindings the Receptor Literature list shows, and in
/// what order. Pure functions of the binding rows.
enum ReceptorLiterature {
    /// The receptor rows worth showing: the 10 µM relevance cap. Drops a **Kᵢ-based** off-target binding
    /// ≥ 10,000 nM (the standard "no meaningful affinity" cutoff) — ketamine's σ/µ/κ, meth's σ2, MDMA's
    /// 12–15 µM modulators — *unless* it sits within 10× of the substance's tightest binding, so a
    /// substance whose primary targets are all weak (caffeine's matched A1/A2A adenosine pair) keeps them.
    /// EC₅₀/IC₅₀ functional transporter rows are never capped: a releaser's DAT EC₅₀ is legitimately tens
    /// of µM yet is the primary mechanism.
    static func visibleBindings(from literatureBindings: [BindingHit]) -> [BindingHit] {
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
        return deduped(capped).sorted { lhs, rhs in
            let lt = strengthTier(for: lhs) ?? 0
            let rt = strengthTier(for: rhs) ?? 0
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
    static func deduped(_ rows: [BindingHit]) -> [BindingHit] {
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
