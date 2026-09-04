import SwiftUI

/// **Off-Target Effects** — the things a drug acts on that are not the reason
/// anyone takes it: citalopram's hERG block, ketamine's bladder, zopiclone's
/// metallic aftertaste.
///
/// The card is deliberately not filtered down to the alarming rows. A `low`
/// concern row states that a measured off-target action *doesn't* matter at real
/// doses — mephedrone blocking hERG by 9% at 30 µM, 3-MeO-PCP's negligible DAT
/// binding — and that is a claim readers otherwise make for themselves, wrongly,
/// from a headline about the same binding. Showing the measurement together with
/// its consequence is the whole content.
struct OffTargetSection: View {
    let substance: Substance
    let model: SubstanceDetailModel

    /// Folded at every tier, like its Pharmacokinetics and Metabolism neighbours
    /// — hence a plain `Bool` rather than the tier-defaulted optional those
    /// sections carry: there is no per-tier default here to fall back to.
    @State private var isExpanded = false

    var body: some View {
        if !model.offTargets.isEmpty {
            CollapsibleSection(
                "Off-Target Effects",
                count: model.offTargets.count,
                isExpanded: $isExpanded,
            ) {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    ForEach(model.offTargets) { hit in
                        OffTargetRow(hit: hit, accent: substance.category.color)
                        if hit.id != model.offTargets.last?.id { Divider() }
                    }
                }
                .padding(.vertical, Spacing.xs)
            }
        }
    }
}

/// One off-target row: the target with its concern mark, the measured
/// concentration where one exists, and the plain-language consequence — then the
/// source.
struct OffTargetRow: View {
    let hit: SubstanceStore.OffTargetHit
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: Spacing.sm) {
                // `verbatim`: targets are proper nouns and lab shorthand ("hERG",
                // "nAChR α3β4"), authored in the DB and not catalog keys.
                Text(verbatim: hit.target)
                    .sectionLabel()
                    .fixedSize(horizontal: false, vertical: true)
                if let value = hit.valueNm {
                    // No Kᵢ/IC₅₀ symbol — `ki_or_ic50_nm` does not record which
                    // one it holds, and the two are different quantities.
                    Text(verbatim: concentrationText(value))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.secondaryLabel)
                }
                Spacer(minLength: 6)
                ConcernMark(concern: hit.concern)
            }
            if let consequence = hit.clinicalConsequence, !consequence.isEmpty {
                // Authored per row in the curated data, so it ships in English
                // regardless of locale — `verbatim` keeps it out of the catalog
                // rather than minting ~200 untranslatable keys.
                Text(verbatim: consequence)
                    .captionSecondary()
                    .fixedSize(horizontal: false, vertical: true)
            }
            sourceLine(slug: hit.sourceSlug, detail: nil, doi: hit.doi, pmid: hit.pmid, accent: accent)
        }
        .accessibilityElement(children: .combine)
    }

    /// nM under 1 µM, µM above — the same threshold ``concLabel(kiNm:ec50Nm:ic50Nm:)``
    /// uses, minus the symbol this column can't supply.
    private func concentrationText(_ value: Double) -> String {
        if value < 1_000 { return "\(formatNm(value)) nM" }
        let micromolar = value / 1_000
        return micromolar >= 10
            ? "\(String(format: "%.0f", micromolar)) µM"
            : "\(String(format: "%.1f", micromolar)) µM"
    }
}

/// The concern level as a tinted capsule. Color alone would carry the whole
/// meaning, so the word rides along with it.
private struct ConcernMark: View {
    let concern: SubstanceStore.OffTargetConcern

    var body: some View {
        Text(label)
            .capsuleChip(text: textColor, fill: accentColor)
            .accessibilityLabel(Text(accessibilityLabel))
    }

    /// What the level says about *consequence*, not about binding strength — a
    /// bare "Low" beside a receptor name reads as low affinity, which is the one
    /// thing this column never means.
    private var label: LocalizedStringResource {
        switch concern {
        case .high: "Significant"
        case .moderate: "Limited"
        case .low: "Minor"
        }
    }

    private var accessibilityLabel: LocalizedStringResource {
        switch concern {
        case .high: "Clinically significant"
        case .moderate: "Real but bounded"
        case .low: "Not clinically dominant"
        }
    }

    private var textColor: Color {
        switch concern {
        case .high: .dangerText
        case .moderate: .cautionText
        case .low: .infoText
        }
    }

    private var accentColor: Color {
        switch concern {
        case .high: .dangerAccent
        case .moderate: .cautionAccent
        case .low: .infoAccent
        }
    }
}
