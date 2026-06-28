import SwiftUI

// Pharmacology disclosure rows for the substance detail view — the Receptor
// Literature, Pharmacokinetics, and Metabolism rows, extracted from
// `SubstanceLibraryView` so the detail file stays under the length budget and
// these redesignable cards live in one obvious place.

struct ReceptorLiteratureRow: View {
    let hit: SubstanceStore.BindingHit
    let accent: Color
    /// Strength tier (1–3) for the dots, supplied by the parent so it can be reconciled with the
    /// Mechanism card (a target's MOA tier wins over an absolute-band guess — see `strengthTier(for:)`).
    let strengthTier: Int?

    var body: some View {
        let target = splitTarget(hit.target)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                // Left: the receptor, its site/enantiomer qualifier (a chip on its own line so a long
                // "(MK-801 site, S-enantiomer)" can't shove the name around), and the action.
                VStack(alignment: .leading, spacing: 4) {
                    Text(target.name)
                        .font(.subheadline.weight(.semibold))
                    if let qualifier = target.qualifier {
                        qualifierChip(qualifier)
                    }
                    actionLabel
                }
                Spacer(minLength: 8)
                // Right: dots with the value directly beneath them — strength + the number it came from
                // are the primary, semantically-paired fact, so they stack together.
                if let m = measurement {
                    VStack(alignment: .trailing, spacing: 2) {
                        if let strengthTier {
                            AffinityDots(filled: strengthTier, tint: accent)
                        }
                        Text(m.value)
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(accent)
                        Text(m.kind)
                            .font(.caption2)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.caption2)
                sourceNameLink(pharmaSourceName(hit.sourceSlug), doi: hit.doi, pmid: hit.pmid, accent: accent)
                ProvenanceBadge(confidence: hit.confidence, species: hit.species, sourceSlug: hit.sourceSlug)
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(Theme.secondaryLabel)
        }
    }

    /// The action with its kind-glyph (releaser vs agonist vs blocker) so the mechanism splits visually.
    /// Humanised + localised via BindingAction — "Releasing Agent", not "releasingAgent".
    @ViewBuilder
    private var actionLabel: some View {
        if let action = BindingAction(rawValue: hit.action) {
            HStack(spacing: 4) {
                Image(systemName: action.symbolName)
                    .font(.caption2)
                Text(action.displayName)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
            Text(hit.action)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func qualifierChip(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(Theme.secondaryLabel)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Theme.secondaryLabel.opacity(0.1), in: Capsule())
    }

    /// The one measurement this row carries, resolved to a (plain-language kind, value label) pair.
    /// Kᵢ is binding affinity; EC₅₀/IC₅₀ are functional potency.
    private var measurement: (kind: LocalizedStringResource, value: String)? {
        if let ki = hit.kiNm { return ("binding", "Ki \(formatNm(ki)) nM") }
        if let ec = hit.ec50Nm { return ("functional", "EC50 \(formatNm(ec)) nM") }
        if let ic = hit.ic50Nm { return ("functional", "IC50 \(formatNm(ic)) nM") }
        return nil
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

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(hit.enzyme)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let frac = hit.fractionOfClearancePct {
                    // A faint stat pill, not an accent-coloured number — the percentage used to read
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
