import SwiftUI

/// **Genetics** — the genes whose variants change what this substance does, and
/// what carrying one means.
///
/// Sits beside ``CYP2D6NoteSection`` and does not repeat it: that note is about
/// *the reader* (the metabolizer status they set in Settings, applied to this
/// drug), while these rows are about *the drug* and carry the study behind each
/// one. Merging them would trade a sourced fact for a personalized sentence, or
/// print both halves as one paragraph.
struct PharmacogeneticsSection: View {
    let substance: Substance
    let model: SubstanceDetailModel

    /// Folded at every tier, like its Metabolism and Off-Target neighbours.
    @State private var isExpanded = false

    var body: some View {
        if !model.pharmacogenetics.isEmpty {
            CollapsibleSection(
                "Genetics",
                count: model.pharmacogenetics.count,
                isExpanded: $isExpanded,
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.pharmacogenetics) { hit in
                        PharmacogeneticRow(hit: hit, accent: substance.category.color)
                        if hit.id != model.pharmacogenetics.last?.id { Divider() }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

/// One gene: its name, what a variant does, and the study.
struct PharmacogeneticRow: View {
    let hit: SubstanceStore.PharmacogeneticHit
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // `verbatim`: gene symbols and rsIDs are nomenclature, not copy.
            Text(verbatim: hit.gene)
                .font(.subheadline.weight(.semibold).monospaced())
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: hit.phenotypeEffects)
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            sourceLine(slug: hit.sourceSlug, detail: nil, doi: hit.doi, pmid: hit.pmid, accent: accent)
        }
        .accessibilityElement(children: .combine)
    }
}

/// **Target evidence** — what the binding actually does, where the row is not a
/// Kᵢ: which signalling pathway an agonist favours, what complex the receptor
/// sits in, and what a scan of a living brain measured.
///
/// One section rather than three, because all three answer the same follow-up
/// question to an affinity table, and because 83 rows spread over three
/// self-hiding sections would cost more screen than the rows are worth. The
/// chip says which kind each row is.
struct TargetEvidenceSection: View {
    let substance: Substance
    let model: SubstanceDetailModel

    @State private var isExpanded = false

    var body: some View {
        if !model.targetEvidence.isEmpty {
            CollapsibleSection(
                "Target Evidence",
                count: model.targetEvidence.count,
                isExpanded: $isExpanded,
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.targetEvidence) { item in
                        TargetEvidenceRow(item: item, accent: substance.category.color)
                        if item.id != model.targetEvidence.last?.id { Divider() }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

struct TargetEvidenceRow: View {
    let item: SubstanceStore.TargetEvidence
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                // `verbatim`: a target, a complex or a scan modality — lab
                // nomenclature authored in the DB, not catalog keys.
                Text(verbatim: item.subject)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                Text(item.kind.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.secondaryLabel)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(accent.opacity(0.10), in: Capsule())
            }
            Text(verbatim: item.finding)
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            sourceLine(slug: item.sourceSlug, detail: nil, doi: item.doi, pmid: item.pmid, accent: accent)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The cascade a substance sets off after it binds, rendered inside the
/// Pharmacology card rather than as a section of its own: it is the second half
/// of the sentence the card's first half started.
struct SignallingCascadeRow: View {
    let cascade: SubstanceStore.SignallingCascade
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Authored as an arrow chain ("NMDA block -> glutamate surge -> AMPA
            // -> BDNF/TrkB -> mTORC1"), which is the notation the field uses and
            // reads far denser than the same claim as prose.
            Text(verbatim: cascade.summary)
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            sourceLine(slug: cascade.sourceSlug, detail: nil, doi: cascade.doi, pmid: cascade.pmid, accent: accent)
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }
}

/// One concentration threshold: the effect, where it starts, and where it is
/// full.
///
/// The range is written `70 – 200 ng/mL` when both ends are concentrations, and
/// as a bare threshold otherwise. `peak_effect` is not always a concentration —
/// citalopram's QTc row keeps 18.5 milliseconds of prolongation in that column —
/// so the second number is only given the unit when it is larger than the
/// first, which is the one thing every real concentration pair has in common.
struct ConcentrationThresholdRow: View {
    let hit: SubstanceStore.ConcentrationThreshold
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: hit.effect)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(verbatim: rangeText)
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(Theme.secondaryLabel)
                    .layoutPriority(1)
            }
            sourceLine(slug: hit.sourceSlug, detail: nil, doi: hit.doi, pmid: hit.pmid, accent: accent)
                .font(.caption2)
        }
        .accessibilityElement(children: .combine)
    }

    private var rangeText: String {
        guard let threshold = hit.threshold else {
            return hit.peak.map { "\(SubstanceDetailView.chemNumber($0)) \(hit.unit)" } ?? ""
        }
        guard let peak = hit.peak, peak > threshold else {
            return "\(SubstanceDetailView.chemNumber(threshold)) \(hit.unit)"
        }
        return "\(SubstanceDetailView.chemNumber(threshold))–\(SubstanceDetailView.chemNumber(peak)) \(hit.unit)"
    }
}
