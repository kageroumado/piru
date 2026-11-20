import Foundation

// Formatters and source naming shared by the pharmacology rows, the class hero and the
// substance detail sections.

/// Compact numeric formatter for chemistry values: drops a trailing `.0`
/// (so `45.0` → `45`) but keeps real decimals (`2.34` → `2.34`).
func chemNumber(_ value: Double) -> String {
    value == value.rounded() ? String(format: "%.0f", value) : String(format: "%g", value)
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
    return concLabel(symbol: symbol, nanomolar: value)
}

/// `symbol` + the concentration in nM under 1000, else µM — the one formatter behind every
/// concentration readout, so a therapeutic threshold ("TDM 12.6 µM") prints like a Kᵢ.
func concLabel(symbol: String, nanomolar value: Double) -> String {
    if value < 1_000 { return "\(symbol) \(formatNm(value)) nM" }
    let micromolar = value / 1_000
    let umText = micromolar >= 100 ? String(format: "%.0f", micromolar)
        : (micromolar >= 10 ? String(format: "%.1f", micromolar) : String(format: "%.2f", micromolar))
    return "\(symbol) \(umText) µM"
}

/// Compact minutes→human formatter for PK timings: sub-hour stays in minutes,
/// hours with one decimal where it matters (90 min → "1.5 h"), and days past two
/// of them. `min`/`h` are universal SI-adjacent unit symbols — rendered verbatim;
/// "days" is localized because it is a word.
///
/// The days tier exists for metabolites: norfluoxetine's 12,384-minute half-life
/// read "206 h", a number nobody converts in their head, and the whole point of
/// showing it beside fluoxetine's own is that the comparison lands.
func pkMinutes(_ minutes: Double) -> String {
    if minutes < 60 { return "\(chemNumber(minutes)) min" }
    if minutes >= 48 * 60 {
        let days = (minutes / 144).rounded() / 10
        return String(localized: "\(chemNumber(days)) days")
    }
    // Round to one decimal so 155 min reads "2.6 h", not "2.58333 h"; chemNumber then drops a trailing
    // ".0" so a clean hour stays "3 h".
    let hours = (minutes / 6).rounded() / 10
    return "\(chemNumber(hours)) h"
}

/// Human-readable name for a source slug ("peer-review-primary" → "PubMed"), preferring the clean
/// ``AppSources`` names and falling back to the bundled `sources` table — so a wordy wire slug never
/// out-shouts the metabolite/receptor name it's attributing.
func pharmaSourceName(_ slug: String) -> String {
    AppSources.slugToName[slug] ?? SubstanceStore.shared.sourceDisplayName(forSlug: slug)
}

/// The name a row's source line shows, or `nil` for none.
///
/// A literature row (`peer-review-primary`) is named for the citation it carries — "PubMed" only
/// when the link opens PubMed — and an uncited one names nothing: its slug says the row was
/// researched, not where, and naming a literature database there would attribute the row to a
/// source it does not have. Every other slug is itself the attribution and keeps its name.
func rowSourceName(slug: String, citation: RowCitation?) -> String? {
    if slug == AppSources.literatureSlug { return citation?.linkName }
    return pharmaSourceName(slug)
}
