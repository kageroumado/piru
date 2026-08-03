import SwiftUI

/// **How Long It Stays** — the benzodiazepine duration ladder, this compound
/// marked among the ones a reader already has a feel for.
///
/// See ``BenzoDurationLadder`` for why this card exists in place of a diazepam
/// equivalence table: equivalence is potency, and potency is not strength.
struct BenzoDurationSection: View {
    let substance: Substance
    let model: SubstanceDetailModel

    @State private var isExpanded = false

    private var rungs: [BenzoDurationLadder.Rung] {
        guard substance.category == .benzodiazepine else { return [] }
        return BenzoDurationLadder.rungs(for: substance, metabolites: model.activeMetabolites) {
            SubstanceLibrary.lookup($0)
        }
    }

    var body: some View {
        let rungs = rungs
        if rungs.count > 1 {
            let longest = rungs.map(\.halfLifeMinutes).max() ?? 1
            CollapsibleSection(
                "How Long It Stays",
                systemImage: "hourglass",
                isExpanded: $isExpanded,
            ) {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(rungs) { rung in
                        BenzoRungRow(rung: rung, longestMinutes: longest, accent: substance.category.color)
                    }
                    // Earns its negation: every reader arrives believing
                    // half-life is how long the drug is felt.
                    Text("Elimination half-life — not how long you feel it.", comment: "Ladder caption")
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }
        }
    }
}

/// One rung: the compound, a bar proportional to its half-life, and the value.
///
/// The bar is **linear**, not log. Triazolam's bar next to diazepam's really is
/// a twentieth of the length, and flattening that onto a log axis would soften
/// the one comparison the card is for.
private struct BenzoRungRow: View {
    let rung: BenzoDurationLadder.Rung
    let longestMinutes: Double
    let accent: Color

    private var isOwn: Bool {
        rung.role != .reference
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                if rung.role == .metabolite {
                    // The glyph is the sentence: this rung is *made from* the one
                    // above, so its longer bar is the parent's real reach.
                    Image(systemName: "arrow.turn.down.right")
                        .font(.caption2)
                        .foregroundStyle(accent)
                        .accessibilityLabel(Text("Metabolite of the above", comment: "Ladder rung role"))
                }
                // `verbatim`: a substance name is a proper noun, not a catalog key.
                Text(verbatim: rung.name)
                    .font(.caption.weight(rung.role == .subject ? .bold : .regular))
                    .foregroundStyle(isOwn ? accent : Color.primary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(verbatim: hoursLabel(rung.halfLifeMinutes))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isOwn ? accent : Theme.secondaryLabel)
            }
            GeometryReader { geometry in
                let fraction = longestMinutes > 0 ? rung.halfLifeMinutes / longestMinutes : 0
                Capsule()
                    .fill(barStyle)
                    .frame(width: max(2, geometry.size.width * fraction))
            }
            .frame(height: 5)
        }
        .padding(.leading, rung.role == .metabolite ? 14 : 0)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(rung.role == .subject ? [.isSelected] : [])
    }

    /// Hours for every rung, where ``pkMinutes(_:)`` would roll past 48 h into
    /// days. On a ladder whose only job is comparison, "2.9 days" beside "46 h"
    /// makes the reader do the conversion the bars already did for them.
    private func hoursLabel(_ minutes: Double) -> String {
        "\(SubstanceDetailView.chemNumber((minutes / 6).rounded() / 10)) h"
    }

    private var barStyle: AnyShapeStyle {
        switch rung.role {
        case .subject: AnyShapeStyle(accent)
        case .metabolite: AnyShapeStyle(accent.opacity(0.45))
        case .reference: AnyShapeStyle(Theme.secondaryLabel.opacity(0.25))
        }
    }
}
