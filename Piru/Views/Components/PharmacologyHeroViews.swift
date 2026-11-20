import SwiftUI

/// Shared species + citation trailing cluster used by the panel rows and the potency bars, so the
/// "Human" badge + ↗ link read identically on both.
struct SpeciesCite: View {
    let species: String?
    let citation: URL?

    var body: some View {
        if let species, species != "—", !species.isEmpty {
            let isHuman = species.lowercased() == "human"
            Text(species.prefix(1).uppercased() + species.dropFirst())
                .capsuleChip(
                    text: isHuman ? Color.successText : Theme.secondaryLabel,
                    fill: isHuman ? Color.successAccent : Theme.secondaryLabel,
                )
                .fixedSize(horizontal: true, vertical: false)
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
                HStack(spacing: Spacing.md) {
                    Text(row.label).font(.subheadline.weight(.bold))
                    if let action = row.action { actionChip(action) }
                    if let effect = row.effect {
                        Text(effect).captionSecondary()
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
            .background(color.opacity(Theme.Opacity.tint), in: skinChipShape())
    }
}

/// The dissociative enantiomer-potency bars (S / racemate / R).
struct PotencyBars: View {
    let bars: [PharmacologyHero.PotencyBar]
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            ForEach(bars) { bar in
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(spacing: Spacing.md) {
                        Text(bar.label).sectionLabel()
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
