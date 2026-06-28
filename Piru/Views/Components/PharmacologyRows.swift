import SwiftUI

// Pharmacology disclosure rows for the substance detail view — the Receptor
// Literature, Pharmacokinetics, and Metabolism rows, extracted from
// `SubstanceLibraryView` so the detail file stays under the length budget and
// these redesignable cards live in one obvious place.

struct ReceptorLiteratureRow: View {
    let hit: SubstanceStore.BindingHit
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(hit.target)
                    .font(.subheadline.weight(.semibold))
                Text(hit.action)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                affinityLabel
            }
            HStack(spacing: 6) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.caption2)
                Text(hit.sourceSlug)
                    .font(.caption2.monospaced())
                ProvenanceBadge(confidence: hit.confidence, species: hit.species, sourceSlug: hit.sourceSlug)
                Spacer()
                if let pmid = hit.pmid, let url = URL(string: "https://pubmed.ncbi.nlm.nih.gov/\(pmid)/") {
                    Link(destination: url) {
                        Text("PMID \(pmid)")
                            .font(.caption2)
                            .foregroundStyle(accent)
                    }
                } else if let doi = hit.doi, !doi.isEmpty, let url = URL(string: "https://doi.org/\(doi)") {
                    Link(destination: url) {
                        Text("DOI")
                            .font(.caption2)
                            .foregroundStyle(accent)
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(Theme.secondaryLabel)
        }
    }

    @ViewBuilder
    private var affinityLabel: some View {
        if let ki = hit.kiNm {
            Text("Ki \(formatNm(ki)) nM")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(accent)
        } else if let ec = hit.ec50Nm {
            Text("EC50 \(formatNm(ec)) nM")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(accent)
        }
    }
}

/// Ki/EC50 display formatter shared with `AdvancedSearchView` — precision
/// scales with magnitude so small affinities keep their decimals.
func formatNm(_ value: Double) -> String {
    if value >= 100 { return String(format: "%.0f", value) }
    if value >= 10 { return String(format: "%.1f", value) }
    return String(format: "%.2f", value)
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
                        PKMetricChip(label: metric.label, symbol: metric.symbol, value: metric.value)
                    }
                }
            }
            sourceLine(slug: hit.sourceSlug, detail: hit.demographics, doi: hit.doi, pmid: hit.pmid, accent: accent)
        }
    }

    /// One populated PK metric: a plain-language label (so "what does this mean?" is answered without a
    /// glossary), the standard scientific symbol kept as a subtitle, and the value with its verbatim unit.
    private struct PKMetric: Identifiable {
        let id: String
        let label: LocalizedStringResource
        let symbol: String
        let value: String
    }

    private var metrics: [PKMetric] {
        let n = SubstanceDetailView.chemNumber
        var out: [PKMetric] = []
        if let v = hit.bioavailabilityPct { out.append(.init(id: "F", label: "Bioavailability", symbol: "F", value: "\(n(v))%")) }
        if let v = hit.tmaxMin { out.append(.init(id: "Tmax", label: "Time to peak", symbol: "Tmax", value: pkMinutes(v))) }
        if let v = hit.halfLifeMin { out.append(.init(id: "t12", label: "Half-life", symbol: "t½", value: pkMinutes(v))) }
        if let v = hit.proteinBindingPct { out.append(.init(id: "PPB", label: "Protein binding", symbol: "PPB", value: "\(n(v))%")) }
        if let v = hit.vdLPerKg { out.append(.init(id: "Vd", label: "Distribution", symbol: "Vd", value: "\(n(v)) L/kg")) }
        if let v = hit.clearanceMlPerMinPerKg { out.append(.init(id: "CL", label: "Clearance", symbol: "CL", value: "\(n(v)) mL/min/kg")) }
        if let v = hit.cmaxNgPerMl { out.append(.init(id: "Cmax", label: "Peak level", symbol: "Cmax", value: "\(n(v)) ng/mL")) }
        return out
    }
}

/// A labeled mini-stat chip for one pharmacokinetic value: plain-language term on top, the value with its
/// unit below, and the scientific symbol as a faint trailing tag. Replaces the dense " · "-joined run-on
/// line so each number is scannable and self-explaining.
private struct PKMetricChip: View {
    let label: LocalizedStringResource
    let symbol: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryLabel)
                Text(symbol)
                    .font(.caption2.monospaced())
                    .foregroundStyle(Theme.secondaryLabel.opacity(0.6))
            }
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
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(hit.enzyme)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let frac = hit.fractionOfClearancePct {
                    Text("\(SubstanceDetailView.chemNumber(frac))%")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(accent)
                }
            }
            if let metabolite = hit.metaboliteName, !metabolite.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.turn.down.right").font(.caption2)
                    Text(metabolite).font(.caption)
                    if let active = hit.metaboliteActive {
                        Text(active ? "active" : "inactive")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(active ? accent : .secondary)
                    }
                }
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            sourceLine(slug: hit.sourceSlug, detail: hit.notes, doi: hit.doi, pmid: hit.pmid, accent: accent)
        }
    }
}

/// Shared source/citation footer for the PK + metabolism rows — a source slug,
/// an optional italic detail (demographics / notes), and a PMID/DOI link.
private func sourceLine(slug: String, detail: String?, doi: String?, pmid: Int?, accent: Color) -> some View {
    HStack(spacing: 6) {
        Image(systemName: "doc.text.magnifyingglass").font(.caption2)
        Text(slug).font(.caption2.monospaced())
        if let detail, !detail.isEmpty {
            Text("·")
            Text(detail).italic().lineLimit(1)
        }
        Spacer()
        if let pmid, let url = URL(string: "https://pubmed.ncbi.nlm.nih.gov/\(pmid)/") {
            Link(destination: url) {
                Text("PMID \(pmid)").font(.caption2).foregroundStyle(accent)
            }
        } else if let doi, !doi.isEmpty, let url = URL(string: "https://doi.org/\(doi)") {
            Link(destination: url) {
                Text("DOI").font(.caption2).foregroundStyle(accent)
            }
        }
    }
    .font(.caption)
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
