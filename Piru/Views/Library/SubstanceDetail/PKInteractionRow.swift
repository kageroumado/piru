import SwiftUI

/// One measured pharmacokinetic interaction: what a named counterpart does to this
/// substance's exposure, by which enzyme, from which study.
///
/// Styled as a measurement, not a warning — no severity color, no alert glyph. The
/// row deliberately reads at the same weight as the Metabolism rows beside it,
/// because that is what it is: a sourced PK fact about this drug. The severity
/// ladder belongs to ``InteractionChecker``'s class rules, which are shown
/// elsewhere and are a different kind of claim.
struct PKInteractionRow: View {
    let hit: SubstanceStore.PKInteractionHit
    var accent: Color = Theme.secondaryLabel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                // `verbatim`: a drug or class name copied from its source is not a
                // catalog key, and several are free-text sets ("ketoconazole /
                // itraconazole") that no translation should try to split.
                Text(verbatim: hit.withSubstance)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if let mechanism = hit.mechanism {
                    Text(verbatim: mechanism)
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryLabel)
                        .multilineTextAlignment(.trailing)
                }
            }
            if let effect = hit.clinicalEffect {
                Text(verbatim: effect)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let ki = hit.kiMicromolar {
                Text("Kᵢ \(ki.doseFormatted) µM")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.secondaryLabel)
            }
            // "AUC increased ~2.6×" is a number somebody measured; the row was
            // fetched with its DOI/PMID and printed without them, which reads as
            // the app's own claim.
            sourceLine(slug: hit.sourceSlug, detail: nil, doi: hit.doi, pmid: hit.pmid, accent: accent)
                .font(.caption2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
