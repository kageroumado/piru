import SwiftUI

/// The class-specific **hero** for the unified Pharmacology card (hybrid redesign step 3). Monoamine
/// drugs keep the dopamine↔serotonin slider; receptor-centric classes get a panel built from their own
/// binding rows:
/// - **opioid** → μ / κ / δ / NOP with an agonist / partial / antagonist chip
/// - **benzodiazepine** → GABA-A α-subunit with its effect (sedation / anxiolysis / …)
/// - **dissociative** → NMDA enantiomer-potency bars (S / racemate / R)
///
/// For these classes the hero *is* the primary receptor evidence, so the separate Receptor Literature
/// section is suppressed and any weaker targets fold into a one-line "minor / off-targets" footnote.
struct PharmacologyHero {
    enum Kind { case opioid, benzo, dissociative }

    let kind: Kind
    let character: LocalizedStringResource?
    let note: LocalizedStringResource?
    let rows: [PanelRow]
    let bars: [PotencyBar]
    let minor: String?

    /// Build the hero for a substance's category from its (deduped, relevance-capped) binding rows.
    /// Returns nil when the class has no usable receptor rows — the card then falls back to the grid.
    static func resolve(category: SubstanceCategory, bindings: [BindingHit]) -> PharmacologyHero? {
        switch category {
        case .opioid, .analgesic: opioid(bindings)
        case .benzodiazepine: benzo(bindings)
        case .dissociative: dissociative(bindings)
        default: nil
        }
    }

    // MARK: opioid

    private static func opioid(_ bindings: [BindingHit]) -> PharmacologyHero? {
        let receptors: [(key: String, label: String, match: (String) -> Bool)] = [
            ("mu", "μ", { $0.contains("mor") || $0.contains("μ-opioid") || $0.contains("mu-opioid") }),
            ("kappa", "κ", { $0.contains("kor") || $0.contains("κ-opioid") || $0.contains("kappa") }),
            ("delta", "δ", { $0.contains("dor") || $0.contains("δ-opioid") || $0.contains("delta-opioid") }),
            ("nop", "NOP", { $0.contains("nop") || $0.contains("orl") }),
        ]
        var rows: [PanelRow] = []
        var consumed = Set<Int64>()
        for r in receptors {
            let matching = bindings.filter { r.match($0.target.lowercased()) }
            guard let best = bestRow(matching) else { continue }
            consumed.formUnion(matching.map(\.id))
            let action = BindingAction(rawValue: best.action)
            rows.append(PanelRow(
                id: r.key, label: r.label,
                action: action.map { (label: $0.displayName, kind: ActionKind(from: $0)) },
                effect: nil,
                tier: ReceptorStrength.tier(kiNm: best.kiNm, ec50Nm: best.ec50Nm, ic50Nm: best.ic50Nm) ?? 1,
                value: concText(best), species: best.species,
                citation: citationURL(doi: best.doi, pmid: best.pmid),
            ))
        }
        guard let mu = rows.first(where: { $0.id == "mu" }) else { return nil }
        let character: LocalizedStringResource? = switch mu.action?.kind {
        case .agonist: "Full μ-opioid agonist"
        case .partial: "Partial μ-opioid agonist"
        case .antagonist: "μ-opioid antagonist"
        default: nil
        }
        return PharmacologyHero(
            kind: .opioid, character: character, note: nil,
            rows: rows, bars: [], minor: minorFootnote(bindings, consumed: consumed),
        )
    }

    // MARK: benzodiazepine (GABA-A α-subunit selectivity)

    private static func benzo(_ bindings: [BindingHit]) -> PharmacologyHero? {
        let subunits: [(token: String, label: String, effect: LocalizedStringResource)] = [
            ("α1", "α1", "Sedation"), ("α2", "α2", "Anxiolysis"),
            ("α3", "α3", "Muscle"), ("α5", "α5", "Memory"),
        ]
        var rows: [PanelRow] = []
        var consumed = Set<Int64>()
        for s in subunits {
            let matching = bindings.filter { $0.target.contains(s.token) }
            guard let best = bestRow(matching) else { continue }
            consumed.formUnion(matching.map(\.id))
            rows.append(PanelRow(
                id: s.token, label: s.label, action: nil, effect: s.effect,
                tier: ReceptorStrength.tier(kiNm: best.kiNm, ec50Nm: best.ec50Nm, ic50Nm: best.ic50Nm) ?? 1,
                value: concText(best), species: best.species,
                citation: citationURL(doi: best.doi, pmid: best.pmid),
            ))
        }
        guard !rows.isEmpty else { return nil }
        // Also consume the generic tier-only "GABA-A" row so it doesn't reappear in the footnote.
        consumed.formUnion(bindings.filter { $0.target.lowercased().hasPrefix("gaba") }.map(\.id))
        return PharmacologyHero(
            kind: .benzo, character: "GABA-A positive modulator",
            note: "Amplifies GABA — it doesn't open the channel on its own.",
            rows: rows, bars: [], minor: minorFootnote(bindings, consumed: consumed),
        )
    }

    // MARK: dissociative (NMDA enantiomer potency)

    private static func dissociative(_ bindings: [BindingHit]) -> PharmacologyHero? {
        let nmda = bindings.filter { $0.target.uppercased().contains("NMDA") }
        guard !nmda.isEmpty else { return nil }
        func enantiomer(_ target: String) -> (label: String, order: Int) {
            let t = target.lowercased()
            if t.contains("s-enantiomer") || t.contains("s-ket") || t.contains("esket") { return ("S-enantiomer", 0) }
            if t.contains("r-enantiomer") || t.contains("r-ket") || t.contains("arket") { return ("R-enantiomer", 2) }
            return ("racemate", 1)
        }
        var byEnantiomer: [String: BindingHit] = [:]
        var order: [String: Int] = [:]
        for hit in nmda {
            let e = enantiomer(hit.target)
            order[e.label] = e.order
            if let existing = byEnantiomer[e.label], rank(existing) <= rank(hit) { continue }
            byEnantiomer[e.label] = hit
        }
        let entries = byEnantiomer.sorted { (order[$0.key] ?? 1) < (order[$1.key] ?? 1) }
        let maxConc = entries.compactMap { conc($0.value) }.max() ?? 1
        var consumed = Set<Int64>()
        let bars: [PotencyBar] = entries.map { label, hit in
            consumed.insert(hit.id)
            return PotencyBar(
                id: label, label: label, value: concText(hit), species: hit.species,
                fraction: max(0.14, (conc(hit) ?? maxConc) / maxConc),
                citation: citationURL(doi: hit.doi, pmid: hit.pmid),
            )
        }
        // consume any other NMDA rows we didn't surface so they don't show up in the footnote
        consumed.formUnion(nmda.map(\.id))
        return PharmacologyHero(
            kind: .dissociative, character: "NMDA channel blocker",
            note: "Lower IC₅₀ / Kᵢ = more potent block.",
            rows: [], bars: bars, minor: minorFootnote(bindings, consumed: consumed),
        )
    }

    // MARK: helpers

    /// Best row for a receptor: prefer a measured value, then human data, then highest potency.
    private static func bestRow(_ rows: [BindingHit]) -> BindingHit? {
        rows.min { a, b in
            let am = hasMeasure(a), bm = hasMeasure(b)
            if am != bm { return am }
            let ah = a.species?.lowercased() == "human", bh = b.species?.lowercased() == "human"
            if ah != bh { return ah }
            return (conc(a) ?? .greatestFiniteMagnitude) < (conc(b) ?? .greatestFiniteMagnitude)
        }
    }

    private static func hasMeasure(_ h: BindingHit) -> Bool {
        h.kiNm != nil || h.ec50Nm != nil || h.ic50Nm != nil
    }

    private static func conc(_ h: BindingHit) -> Double? {
        h.kiNm ?? h.ec50Nm ?? h.ic50Nm
    }

    /// Sort rank for picking the best of duplicate enantiomer rows (lower is better).
    private static func rank(_ h: BindingHit) -> Int {
        (hasMeasure(h) ? 0 : 2) + (h.species?.lowercased() == "human" ? 0 : 1)
    }

    /// "Kᵢ 0.21 nM" / "EC₅₀ 1.7 µM" — symbol from which field is populated; nM under 1000, else µM.
    /// Shares one formatter (`concLabel`) with the grouped receptor-literature rows so values read identically.
    private static func concText(_ h: BindingHit) -> String {
        concLabel(kiNm: h.kiNm, ec50Nm: h.ec50Nm, ic50Nm: h.ic50Nm)
    }

    /// Leftover (non-hero) bindings as a compact footnote — the weak σ / opioid off-targets, etc.
    private static func minorFootnote(_ bindings: [BindingHit], consumed: Set<Int64>) -> String? {
        let leftover = bindings.filter { !consumed.contains($0.id) && hasMeasure($0) }
        // collapse to one row per target, weakest-relevant first, cap to keep it a footnote
        var seen = Set<String>()
        let items = leftover
            .sorted { (conc($0) ?? 0) < (conc($1) ?? 0) }
            .compactMap { hit -> String? in
                let name = splitTarget(hit.target).name
                guard seen.insert(name).inserted else { return nil }
                return "\(name) (\(concText(hit)))"
            }
            .prefix(5)
        return items.isEmpty ? nil : items.joined(separator: ", ")
    }

    struct PanelRow: Identifiable {
        let id: String
        let label: String
        let action: (label: LocalizedStringResource, kind: ActionKind)?
        let effect: LocalizedStringResource?
        let tier: Int
        let value: String
        let species: String?
        let citation: URL?
    }

    struct PotencyBar: Identifiable {
        let id: String
        let label: String
        let value: String
        let species: String?
        let fraction: Double
        let citation: URL?
    }

    enum ActionKind {
        case agonist
        case partial
        case antagonist
        case other
        init(from action: BindingAction) {
            switch action {
            case .agonist, .releasingAgent: self = .agonist
            case .partialAgonist: self = .partial
            case .antagonist, .inverseAgonist, .channelBlocker, .enzymeInhibitor, .reuptakeInhibitor: self = .antagonist
            default: self = .other
            }
        }
    }
}

// MARK: - Views

/// Shared species + citation trailing cluster used by the panel rows, the potency bars, and the grouped
/// receptor-literature table — so the "Human" badge + ↗ link read identically across every pharmacology surface.
struct SpeciesCite: View {
    let species: String?
    let citation: URL?

    var body: some View {
        if let species, species != "—", !species.isEmpty {
            Text(species.prefix(1).uppercased() + species.dropFirst())
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(species.lowercased() == "human" ? Color(red: 0.11, green: 0.48, blue: 0.20) : Theme.secondaryLabel)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background((species.lowercased() == "human" ? Color.green : Theme.secondaryLabel).opacity(0.16), in: Capsule())
        }
        if let citation {
            CitationLink(url: citation, size: 9)
        }
    }
}

/// The opioid / benzo receptor panel: `label + action/effect` on the left, `dots · value · species · ↗`
/// right-aligned into shared columns.
struct ReceptorPanel: View {
    let rows: [PharmacologyHero.PanelRow]
    let accent: Color

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider() }
                HStack(spacing: 8) {
                    Text(row.label).font(.subheadline.weight(.bold))
                    if let action = row.action { actionChip(action) }
                    if let effect = row.effect {
                        Text(effect).font(.caption).foregroundStyle(Theme.secondaryLabel)
                    }
                    Spacer(minLength: 6)
                    AffinityDots(filled: row.tier, tint: accent)
                    Text(row.value)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(accent)
                        .frame(width: 92, alignment: .trailing)
                    SpeciesCite(species: row.species, citation: row.citation)
                }
                .accessibilityElement(children: .combine)
                .padding(.vertical, 7)
            }
        }
    }

    private func actionChip(_ action: (label: LocalizedStringResource, kind: PharmacologyHero.ActionKind)) -> some View {
        let color: Color = switch action.kind {
        case .agonist: Color(red: 0.11, green: 0.48, blue: 0.20)
        case .antagonist: Color(red: 0.75, green: 0.22, blue: 0.17)
        case .partial: Color(red: 0.58, green: 0.38, blue: 0.0)
        case .other: Theme.secondaryLabel
        }
        return Text(action.label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 1)
            .background(color.opacity(0.10), in: Capsule())
    }
}

/// The dissociative enantiomer-potency bars (S / racemate / R).
struct PotencyBars: View {
    let bars: [PharmacologyHero.PotencyBar]
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            ForEach(bars) { bar in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(bar.label).font(.subheadline.weight(.semibold))
                        SpeciesCite(species: bar.species, citation: bar.citation)
                        Spacer(minLength: 6)
                        Text(bar.value).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(accent)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(accent.opacity(0.14)).frame(height: 7)
                            Capsule().fill(accent).frame(width: max(8, geo.size.width * bar.fraction), height: 7)
                        }
                    }
                    .frame(height: 7)
                }
            }
        }
        .chartSummaryAccessibility(
            label: Text("Enantiomer potency"),
            value: Text(bars.map { "\($0.label) \($0.value)" }.joined(separator: ", ")),
        )
    }
}
