import SwiftData
import SwiftUI

/// The Interactions entry on the Tools tab: when substances are currently
/// active together, it surfaces the two or three most important interactions
/// between them, ranked worst-first; otherwise it's a plain hub row. Tapping
/// opens the full ``InteractionCheckerView``.
struct InteractionsSummaryCard: View {
    @Query private var entries: [DoseEntry]

    /// Bound to the still-plausibly-active horizon (the quick-log window's
    /// 120 days clears even fluoxetine's ~5-half-life tail) and to the three
    /// fields the active filter reads — the unbounded query materialized the
    /// entire dose log on the main actor every time the Tools tab appeared.
    /// Captured once at init; a few hours of drift across 120 days is nothing.
    init() {
        let cutoff = Date.now.addingTimeInterval(-120 * 86_400)
        var descriptor = FetchDescriptor<DoseEntry>(
            predicate: #Predicate { $0.timestamp >= cutoff },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)],
        )
        descriptor.propertiesToFetch = [\.timestamp, \.substance, \.route]
        _entries = Query(descriptor)
    }

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
                VStack(spacing: Spacing.lg) {
                    ForEach(top) { interaction in
                        row(interaction)
                    }
                    if moreCount > 0 {
                        GlanceMoreRow(count: moreCount)
                    }
                }
            }
        }
        // Keyed on the dose-log revision — hashing `entries` here would both
        // pay an O(history) scan per body pass and subscribe this body to
        // every field of every dose.
        .task(id: DoseLogService.shared.revision) {
            await recompute()
        }
    }

    /// Dot + pair + what actually happens.
    ///
    /// The severity word used to sit where the mechanism now does — a coloured
    /// dot with the word "Dangerous" beside it says the same thing twice and
    /// leaves the reader no better informed than the colour already did. The
    /// dot keeps the severity; the line says why.
    private func row(_ interaction: ActiveInteraction) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.lg) {
            LegendDot(color: interaction.severity.color, size: .large)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            VStack(alignment: .leading, spacing: 1) {
                Text("\(interaction.a) + \(interaction.b)")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(interaction.lead)
                    .captionSecondary()
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(interaction.a) and \(interaction.b), \(String(localized: interaction.severity.label)): \(interaction.lead)"))
    }

    /// Currently-active substances → their worst pairwise interactions,
    /// ranked. Runs on the main actor (the drug-class lookups are MainActor),
    /// but only after the batch cache is warm — the active filter resolves a
    /// substance per entry, and a cold cache pays a synchronous batch build.
    private func recompute() async {
        await SubstanceStore.shared.ensureAllLoaded()
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
