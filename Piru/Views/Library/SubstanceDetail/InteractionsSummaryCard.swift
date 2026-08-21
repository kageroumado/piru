import SwiftData
import SwiftUI

/// The Interactions entry on the Tools tab: when substances are currently
/// active together, it surfaces the two or three most important interactions
/// between them, ranked worst-first; otherwise it's a plain hub row. Tapping
/// opens the full ``InteractionCheckerView``.
struct InteractionsSummaryCard: View {
    @Query(sort: \DoseEntry.timestamp, order: .reverse) private var entries: [DoseEntry]

    @State private var top: [ActiveInteraction] = []
    /// How many ranked interactions beyond the shown ones exist.
    @State private var moreCount = 0

    /// A ranked interaction between two currently-active substances.
    private struct ActiveInteraction: Identifiable {
        let id: String
        let a: String
        let b: String
        let severity: InteractionSeverity
        /// The mechanism, in the fewest words that still say what happens.
        let lead: String
    }

    private static let maxShown = 3

    var body: some View {
        GlanceCard(
            icon: Tool.interactions.icon,
            title: Text(Tool.interactions.name),
            route: .tool(.interactions),
        ) {
            if top.isEmpty {
                Text(Tool.interactions.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
            } else {
                VStack(spacing: 10) {
                    ForEach(top) { interaction in
                        row(interaction)
                    }
                    if moreCount > 0 {
                        GlanceMoreRow(count: moreCount)
                    }
                }
            }
        }
        .task(id: EntriesFingerprint.make(entries)) {
            recompute()
        }
    }

    /// Dot + pair + what actually happens.
    ///
    /// The severity word used to sit where the mechanism now does — a coloured
    /// dot with the word "Dangerous" beside it says the same thing twice and
    /// leaves the reader no better informed than the colour already did. The
    /// dot keeps the severity; the line says why.
    private func row(_ interaction: ActiveInteraction) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(interaction.severity.color)
                .frame(width: 9, height: 9)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            VStack(alignment: .leading, spacing: 1) {
                Text("\(interaction.a) + \(interaction.b)")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(interaction.lead)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(interaction.a) and \(interaction.b), \(String(localized: interaction.severity.label)): \(interaction.lead)"))
    }

    /// Currently-active substances → their worst pairwise interactions,
    /// ranked. Runs on the main actor (the drug-class lookups are MainActor).
    private func recompute() {
        let active = InteractionChecker.activeEntries(from: entries)
        let names = Array(Set(active.map(\.substance)))
        guard names.count >= 2 else {
            top = []
            moreCount = 0
            return
        }
        // `.background` findings are true but do not belong on a glance card
        // beside opioid + benzodiazepine; they stay in the count and open the
        // explorer.
        let results = InteractionChecker.checkBatch(names, against: [])
        let admitted = results.admitted(.notable)
        top = admitted.prefix(Self.maxShown).map {
            ActiveInteraction(
                id: "\($0.substanceA)|\($0.substanceB)",
                a: $0.substanceA,
                b: $0.substanceB,
                severity: $0.severity,
                lead: $0.leadClause,
            )
        }
        moreCount = max(0, results.count - top.count)
    }
}
