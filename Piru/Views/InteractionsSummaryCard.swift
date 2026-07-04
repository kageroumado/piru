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

    private func row(_ interaction: ActiveInteraction) -> some View {
        GlanceRow(dotColor: interaction.severity.color, title: Text("\(interaction.a) + \(interaction.b)")) {
            Text(interaction.severity.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(interaction.severity.labelColor)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(interaction.a) and \(interaction.b): \(String(localized: interaction.severity.label))"))
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
        let results = InteractionChecker.checkBatch(names, against: [])
        top = results.prefix(Self.maxShown).map {
            ActiveInteraction(id: "\($0.substanceA)|\($0.substanceB)", a: $0.substanceA, b: $0.substanceB, severity: $0.severity)
        }
        moreCount = max(0, results.count - Self.maxShown)
    }
}
