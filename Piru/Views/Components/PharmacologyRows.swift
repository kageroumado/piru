import SwiftUI

// Pharmacology disclosure rows for the substance detail view — the Receptor
// Literature, Pharmacokinetics, and Metabolism rows, extracted from
// `SubstanceLibraryView` so the detail file stays under the length budget and
// these redesignable cards live in one obvious place.

/// The **grouped receptor-literature** table for monoamine drugs (the redesign's evidence block, step 4):
/// one cluster per receptor, laid out on a `Grid` so the `dots · value · species · ↗` columns line up
/// identically whether the receptor carries a single measurement (rendered inline next to its name) or
/// several (each its own sub-row, labeled only by what distinguishes it — an enantiomer/site qualifier,
/// or Release vs Reuptake). The Grid keeps the columns aligned even when a row has no species badge — a
/// trailing-cluster `HStack` would otherwise shove the dots right on those rows.
/// Receptor-panel classes (opioid/benzo/dissociative) never reach here — their class hero already carries this.
struct GroupedReceptorLiterature: View {
    let rows: [SubstanceStore.BindingHit]
    let accent: Color

    private struct Group: Identifiable {
        let id: String
        let rows: [SubstanceStore.BindingHit]
    }

    /// Group by base receptor name, preserving the parent's strength-sorted order (first appearance wins).
    private var groups: [Group] {
        var order: [String] = []
        var byName: [String: [SubstanceStore.BindingHit]] = [:]
        for hit in rows {
            let name = splitTarget(hit.target).name
            if byName[name] == nil { order.append(name) }
            byName[name, default: []].append(hit)
        }
        return order.map { Group(id: $0, rows: byName[$0] ?? []) }
    }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 9) {
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                if index > 0 {
                    Divider().gridCellUnsizedAxes(.horizontal).gridCellColumns(5)
                }
                if group.rows.count == 1, let only = group.rows.first {
                    GridRow {
                        inlineTitle(name: group.id, hit: only).lineLimit(1)
                        dotsCell(only)
                        valueCell(only)
                        speciesCell(only)
                        linkCell(only)
                    }
                } else {
                    GridRow {
                        Text(group.id).font(.subheadline.weight(.bold))
                    }
                    ForEach(group.rows) { hit in
                        GridRow {
                            label(hit)
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryLabel)
                                .lineLimit(1)
                            dotsCell(hit)
                            valueCell(hit)
                            speciesCell(hit)
                            linkCell(hit)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// Column 1 for a single-measurement receptor: name + its action concatenated into one `Text` so the
    /// dots/value/species/link columns start at the same place as the multi-row sub-rows.
    private func inlineTitle(name: String, hit: SubstanceStore.BindingHit) -> Text {
        // Build one styled `AttributedString` rather than interpolating `Text` segments: the
        // interpolation form extracts a bogus `"%@  %@"` key into the string catalog, and `Text + Text`
        // is deprecated in iOS 26 — the attributed run preserves each segment's font/color with neither.
        var title = AttributedString(name)
        title.font = .subheadline.weight(.bold)
        title.foregroundColor = .primary

        var action = AttributedString(labelString(hit))
        action.font = .caption
        action.foregroundColor = Theme.secondaryLabel

        return Text(title + AttributedString("  ") + action)
    }

    // MARK: column cells (shared by inline + sub-rows so every column lines up)

    private func dotsCell(_ hit: SubstanceStore.BindingHit) -> some View {
        let tier = ReceptorStrength.tier(kiNm: hit.kiNm, ec50Nm: hit.ec50Nm, ic50Nm: hit.ic50Nm) ?? 1
        return AffinityDots(filled: tier, tint: accent)
    }

    private func valueCell(_ hit: SubstanceStore.BindingHit) -> some View {
        Text(concLabel(kiNm: hit.kiNm, ec50Nm: hit.ec50Nm, ic50Nm: hit.ic50Nm))
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(accent)
            .gridColumnAlignment(.trailing)
    }

    /// The species badge (green for human, gray otherwise). An empty cell when the row carries no species —
    /// the Grid still reserves the column so the citation arrow stays aligned across rows.
    @ViewBuilder
    private func speciesCell(_ hit: SubstanceStore.BindingHit) -> some View {
        if let species = hit.species, !species.isEmpty, species != "—" {
            let isHuman = species.lowercased() == "human"
            Text(species.prefix(1).uppercased() + species.dropFirst())
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(isHuman ? Color(red: 0.11, green: 0.48, blue: 0.20) : Theme.secondaryLabel)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background((isHuman ? Color.green : Theme.secondaryLabel).opacity(0.16), in: Capsule())
        } else {
            Color.clear.frame(width: 0, height: 0)
        }
    }

    @ViewBuilder
    private func linkCell(_ hit: SubstanceStore.BindingHit) -> some View {
        if let url = citationURL(doi: hit.doi, pmid: hit.pmid) {
            Link(destination: url) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.secondaryLabel)
            }
        } else {
            Color.clear.frame(width: 0, height: 0)
        }
    }

    /// What sets this row apart from its siblings: the receptor's site/enantiomer qualifier if any,
    /// otherwise its action — shortened to **Release / Reuptake** for the two transporter mechanisms (the
    /// pair that actually co-occurs on one transporter), full display name otherwise. The binding-vs-
    /// functional distinction is dropped from the row (it lives in the help sheet) — the Kᵢ/EC₅₀/IC₅₀
    /// symbol in the value already carries it.
    private func label(_ hit: SubstanceStore.BindingHit) -> Text {
        Text(verbatim: labelString(hit))
    }

    /// The resolved row label as a plain `String` — shared by ``label(_:)`` and the attributed
    /// ``inlineTitle(name:hit:)`` so both render identically. "Release"/"Reuptake" and the action
    /// display name resolve through the catalog; qualifiers and raw actions pass through verbatim.
    private func labelString(_ hit: SubstanceStore.BindingHit) -> String {
        if let qualifier = splitTarget(hit.target).qualifier {
            return qualifier
        }
        switch BindingAction(rawValue: hit.action) {
        case .releasingAgent: return String(localized: "Release")
        case .reuptakeInhibitor: return String(localized: "Reuptake")
        case let .some(action): return String(localized: action.displayName)
        case .none: return hit.action
        }
    }
}

/// Split a receptor label into its base name and an optional parenthetical qualifier:
/// "NMDA (MK-801 site, S-enantiomer)" → ("NMDA", "MK-801 site, S-enantiomer").
func splitTarget(_ target: String) -> (name: String, qualifier: String?) {
    guard let open = target.range(of: " (") else { return (target, nil) }
    let name = String(target[..<open.lowerBound])
    var qualifier = String(target[open.upperBound...])
    if qualifier.hasSuffix(")") { qualifier.removeLast() }
    qualifier = qualifier.trimmingCharacters(in: .whitespaces)
    return (name, qualifier.isEmpty ? nil : qualifier)
}

/// Ki/EC50 display formatter shared with `AdvancedSearchView` — precision
/// scales with magnitude so small affinities keep their decimals.
func formatNm(_ value: Double) -> String {
    if value >= 100 { return String(format: "%.0f", value) }
    if value >= 10 { return String(format: "%.1f", value) }
    return String(format: "%.2f", value)
}

/// "Kᵢ 50 nM" / "EC₅₀ 1.7 µM" — the symbol from whichever field is populated, nM under 1000 else µM.
/// Shared by the grouped receptor-literature rows and the class-hero panels so values read identically.
/// The subscript symbols and SI units are universal, so the string is rendered verbatim (no localization).
func concLabel(kiNm: Double?, ec50Nm: Double?, ic50Nm: Double?) -> String {
    let (symbol, value): (String, Double?) =
        if let ki = kiNm {
            ("Kᵢ", ki)
        } else if let ec = ec50Nm {
            ("EC₅₀", ec)
        } else if let ic = ic50Nm {
            ("IC₅₀", ic)
        } else {
            ("", nil)
        }
    guard let value else { return "—" }
    if value < 1_000 { return "\(symbol) \(formatNm(value)) nM" }
    let micromolar = value / 1_000
    let umText = micromolar >= 100 ? String(format: "%.0f", micromolar)
        : (micromolar >= 10 ? String(format: "%.1f", micromolar) : String(format: "%.2f", micromolar))
    return "\(symbol) \(umText) µM"
}

/// Map a half-max concentration (nM) to a 1–3 strength tier for the dot scale. Absolute potency
/// bands so the Receptor card's dots rhyme with the Mechanism card: < 100 nM strong (3), 100–1000 nM
/// moderate (2), ≥ 1000 nM weak (1). Lower concentration = more potent = more filled dots.
func affinityTier(forNm value: Double) -> Int {
    if value < 100 { return 3 }
    if value < 1_000 { return 2 }
    return 1
}

/// The shared 3-dot strength glyph used by both the Mechanism and Receptor cards, so "stronger vs
/// weaker" reads identically across them.
struct AffinityDots: View {
    let filled: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0 ..< 3, id: \.self) { i in
                Circle()
                    .fill(i < filled ? tint : tint.opacity(0.15))
                    .frame(width: 6, height: 6)
            }
        }
    }
}

/// Human-readable name for a source slug ("peer-review-primary" → "PubMed"), preferring the clean
/// ``AppSources`` names and falling back to the bundled `sources` table — so a wordy wire slug never
/// out-shouts the metabolite/receptor name it's attributing.
func pharmaSourceName(_ slug: String) -> String {
    AppSources.slugToName[slug] ?? SubstanceStore.shared.sourceDisplayName(forSlug: slug)
}

/// The deep link for a row's citation, preferring PMID over DOI.
func citationURL(doi: String?, pmid: Int?) -> URL? {
    if let pmid { return URL(string: "https://pubmed.ncbi.nlm.nih.gov/\(pmid)/") }
    if let doi, !doi.isEmpty { return URL(string: "https://doi.org/\(doi)") }
    return nil
}

/// The source name rendered as its own citation link (name + trailing ↗) when a DOI/PMID exists, else
/// plain text. Folds the old "PubMed … (spacer) … DOI↗" split into one tappable element so the name and
/// its link stop sitting at opposite ends of the row.
@ViewBuilder
func sourceNameLink(_ name: String, doi: String?, pmid: Int?, accent: Color) -> some View {
    if let url = citationURL(doi: doi, pmid: pmid) {
        Link(destination: url) {
            HStack(spacing: 2) {
                Text(name).font(.caption2)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(accent)
        }
    } else {
        Text(name).font(.caption2)
    }
}

/// One per-route pharmacokinetic row: the route, a chip line of populated
/// metrics (bioavailability/tmax/half-life/…), and the source + citation.
struct PKRouteRow: View {
    let hit: SubstanceStore.PKRouteHit
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(RouteOfAdministration.from(string: hit.route).localizedName)
                .font(.subheadline.weight(.semibold))
            if !metrics.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(metrics) { metric in
                        PKMetricChip(label: metric.label, value: metric.value)
                    }
                }
            }
            sourceLine(slug: hit.sourceSlug, detail: hit.demographics, doi: hit.doi, pmid: hit.pmid, accent: accent)
        }
    }

    /// One populated PK metric: a plain-language label (so "what does this mean?" is answered at a glance,
    /// with the scientific symbol explained one tap away in the help sheet) and the value with its unit.
    private struct PKMetric: Identifiable {
        let id: String
        let label: LocalizedStringResource
        let value: String
    }

    private var metrics: [PKMetric] {
        let n = SubstanceDetailView.chemNumber
        var out: [PKMetric] = []
        if let v = hit.bioavailabilityPct { out.append(.init(id: "F", label: "Bioavailability", value: "\(n(v))%")) }
        if let v = hit.tmaxMin { out.append(.init(id: "Tmax", label: "Time to peak", value: pkMinutes(v))) }
        if let v = hit.halfLifeMin { out.append(.init(id: "t12", label: "Half-life", value: pkMinutes(v))) }
        if let v = hit.proteinBindingPct { out.append(.init(id: "PPB", label: "Protein binding", value: "\(n(v))%")) }
        if let v = hit.vdLPerKg { out.append(.init(id: "Vd", label: "Distribution", value: "\(n(v)) L/kg")) }
        if let v = hit.clearanceMlPerMinPerKg { out.append(.init(id: "CL", label: "Clearance", value: "\(n(v)) mL/min/kg")) }
        if let v = hit.cmaxNgPerMl { out.append(.init(id: "Cmax", label: "Peak level", value: "\(n(v)) ng/mL")) }
        return out
    }
}

/// A labeled mini-stat chip for one pharmacokinetic value: plain-language term on top, the value with its
/// unit below. The scientific symbol (Tmax, t½, …) is intentionally off the chip face — it lives in the
/// card's help sheet so the chip stays scannable and self-explaining.
private struct PKMetricChip: View {
    let label: LocalizedStringResource
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.secondaryLabel.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// One metabolism row: the enzyme/pathway, an optional metabolite (flagged
/// active/inactive), and the source + citation.
struct MetabolismRow: View {
    let hit: SubstanceStore.MetabolismHit
    let accent: Color

    /// An *elimination* row (renal/biliary excretion of the unchanged parent) is not metabolism — there's
    /// no enzyme turning the drug into something else, so a "→ unchanged parent [active]" arrow is wrong on
    /// two counts (it isn't a metabolite, and an unchanged drug isn't an "active metabolite"). Detect those
    /// rows and render a plain excretion line instead. Robust across the curated encodings: the metabolite
    /// is literally the unchanged parent, OR there's no metabolite and the enzyme field describes excretion.
    /// (Phenibut, whose enzyme note mentions excretion but which *does* list real hydroxylation metabolites,
    /// deliberately stays a metabolism row.)
    private var isElimination: Bool {
        if let metabolite = hit.metaboliteName?.lowercased(), metabolite.hasPrefix("unchanged") {
            return true
        }
        let hasMetabolite = !(hit.metaboliteName ?? "").isEmpty
        if hasMetabolite { return false }
        let enzyme = hit.enzyme.lowercased()
        return enzyme.contains("renal") || enzyme.contains("urinary")
            || enzyme.contains("biliary") || enzyme.contains("excret")
    }

    /// Plain-language headline for an elimination line, localised — almost everything here is renal.
    private var eliminationLabel: LocalizedStringResource {
        let enzyme = hit.enzyme.lowercased()
        if enzyme.contains("biliary") || enzyme.contains("fecal") || enzyme.contains("faecal") {
            return "Biliary excretion"
        }
        return "Renal excretion"
    }

    var body: some View {
        if isElimination { eliminationBody } else { metabolismBody }
    }

    /// Elimination line: a kidney/drop glyph, "Renal excretion", and the cleared fraction — no metabolite
    /// arrow and no active/inactive chip, because an unchanged-drug excretion fraction is neither.
    private var eliminationBody: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "drop")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(eliminationLabel)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let frac = hit.fractionOfClearancePct {
                    Text("\(SubstanceDetailView.chemNumber(frac))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Theme.secondaryLabel)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Theme.secondaryLabel.opacity(0.1), in: Capsule())
                }
            }
            sourceLine(slug: hit.sourceSlug, detail: nil, doi: hit.doi, pmid: hit.pmid, accent: accent)
        }
    }

    private var metabolismBody: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(hit.enzyme)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let frac = hit.fractionOfClearancePct {
                    // A faint stat pill, not an accent-colored number — the percentage used to read
                    // like a tappable source attribution sitting next to the DOI/PMID links.
                    Text("\(SubstanceDetailView.chemNumber(frac))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Theme.secondaryLabel)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Theme.secondaryLabel.opacity(0.1), in: Capsule())
                }
            }
            if let metabolite = hit.metaboliteName, !metabolite.isEmpty {
                // The metabolite is the row's headline fact — give it body weight, not the caption it
                // used to share with the source slug below. Baseline-align so the active/inactive chip
                // sits on the metabolite's line instead of floating below it.
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(metabolite).font(.subheadline)
                    if let active = hit.metaboliteActive {
                        Text(active ? "active" : "inactive")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(active ? accent : .secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background((active ? accent : Theme.secondaryLabel).opacity(0.12), in: Capsule())
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            // No `detail`: the per-row prose notes belonged in the cited source, not crammed under the
            // metabolite. The card's job is just "which enzymes, which metabolites" — tap the source to read on.
            sourceLine(slug: hit.sourceSlug, detail: nil, doi: hit.doi, pmid: hit.pmid, accent: accent)
        }
    }
}

/// Shared source/citation footer for the PK + metabolism rows — the friendly source name *is* the
/// citation link (name + ↗), followed by an optional italic detail (PK demographics). Left-aligned so
/// the source and its link read as one element instead of sitting at opposite ends of the row.
private func sourceLine(slug: String, detail: String?, doi: String?, pmid: Int?, accent: Color) -> some View {
    HStack(spacing: 6) {
        Image(systemName: "doc.text.magnifyingglass").font(.caption2)
        sourceNameLink(pharmaSourceName(slug), doi: doi, pmid: pmid, accent: accent)
        if let detail, !detail.isEmpty {
            Text(verbatim: "·").font(.caption2)
            Text(detail).font(.caption2).italic().lineLimit(1)
        }
        Spacer()
    }
    .foregroundStyle(Theme.secondaryLabel)
}

/// Compact minutes→human formatter for PK timings: sub-hour stays in minutes,
/// otherwise hours with one decimal where it matters (90 min → "1.5 h").
/// `min`/`h` are universal SI-adjacent unit symbols — rendered verbatim.
private func pkMinutes(_ minutes: Double) -> String {
    if minutes < 60 { return "\(SubstanceDetailView.chemNumber(minutes)) min" }
    // Round to one decimal so 155 min reads "2.6 h", not "2.58333 h"; chemNumber then drops a trailing
    // ".0" so a clean hour stays "3 h".
    let hours = (minutes / 6).rounded() / 10
    return "\(SubstanceDetailView.chemNumber(hours)) h"
}
