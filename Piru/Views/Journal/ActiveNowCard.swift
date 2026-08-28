import SwiftData
import SwiftUI

/// The Journal's **state** surface: everything pharmacologically active right
/// now, in one card. The feed reads plan → state → log — `MyMedsCard` is the
/// plan, the labeled day list below is the log, and this card is the single
/// answer to "what's in effect?". A lone active dose gets the quick-glance
/// treatment (big amount + route badge, phase bar with countdown — the bar
/// alone tells the story, no graph). Several *substances* get dots + names
/// with a window of the *continuous* timeline (``ActiveNowWindowGraph``)
/// beneath — overlapping curves need a picture where one phase bar doesn't.
/// The session itself lives in the log under Today like any other; this card
/// never says "session". Content, so it rides on `themeCard` — never glass.
struct ActiveNowCard: View {
    let states: [ActiveSubstanceState]
    let entries: [DoseEntry]
    let colors: [SubstanceColor]
    let colorMap: [String: Color]
    var onTap: () -> Void

    private var isSingleDose: Bool {
        states.count == 1
    }

    /// The graph earns its height only when curves can overlap — two or more
    /// distinct substances. A lone substance (even redosed) reads fine from
    /// the phase bar.
    private var showsGraph: Bool {
        uniqueSubstances.count >= 2
    }

    var body: some View {
        // Re-evaluate every minute so the phase bar's countdown stays live
        // without a per-frame tick.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = context.date
            // One Button over the whole card — a single, properly-traited
            // accessibility element — opening today's session detail.
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 10) {
                    if isSingleDose, let state = states.first {
                        singleDoseContent(state: state, now: now)
                    } else {
                        multiSubstanceContent
                    }
                    if showsGraph {
                        ActiveNowWindowGraph(
                            entries: entries,
                            colors: colors,
                            states: states,
                            now: now,
                        )
                    }
                }
                .padding(.top, 12)
                .padding(.horizontal, 12)
                .padding(.bottom, showsGraph ? 6 : 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .themeCard()
            .accessibilityHint(Text("Opens this session."))
        }
    }

    // MARK: Header — the "Active Now" label + disclosure chevron.

    private var titleLabel: some View {
        Text("Active Now")
            .font(.title3.weight(.semibold))
            .lineLimit(1)
    }

    /// Overlaid (not laid out in a row) so the substance names beneath it can
    /// run the card's full width rather than stopping short of a reserved column.
    private var disclosureChevron: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }

    // MARK: Single-dose — the common, quick-glance case.

    @ViewBuilder
    private func singleDoseContent(state: ActiveSubstanceState, now: Date) -> some View {
        let color = SubstancePalette.color(for: state.substanceName, colorMap: colorMap)

        // Title + substance identity, kept tight as a title/subtitle pair, with
        // the chevron overlaid at the trailing edge.
        VStack(alignment: .leading, spacing: 2) {
            titleLabel
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                Text(verbatim: CustomSubstanceStore.shared.displayName(for: state.substanceName))
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
                    .lineLimit(1)
            }
        }
        // Fill the width so the overlaid chevron parks at the card's edge, not
        // at the end of the (intrinsically narrower) text.
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .trailing) { disclosureChevron }

        // Big dose amount + route badge, mirroring the dose-detail hero.
        HStack(alignment: .center, spacing: 8) {
            Text(verbatim: "\(state.amount.doseFormatted) \(state.unit)")
                .font(.system(.title, design: .rounded).weight(.bold))
                .lineLimit(1)
            Spacer(minLength: 8)
            ROAPill(route: RouteOfAdministration.from(string: state.route), size: .regular)
        }

        // Phase bar carries the current phase + "{elapsed} in · {remaining}
        // left" — unambiguous for a single substance.
        DosePhaseProgressBar(state: state, now: now)
    }

    // MARK: Multi-substance — dots + names.

    private var multiSubstanceContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            titleLabel
            HStack(spacing: 6) {
                substanceDots
                Text(displayNames)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .trailing) { disclosureChevron }
    }

    // MARK: - Derived values

    /// Every active substance, comma-joined — no "+N more" truncation. The row
    /// is `lineLimit(1)`, so the system truncates only if the names genuinely
    /// don't fit. State names are already resolved display titles.
    private var displayNames: String {
        uniqueSubstances.joined(separator: ", ")
    }

    private var uniqueSubstances: [String] {
        var seen = Set<String>()
        return states.compactMap { state in
            let key = state.substanceName.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return state.substanceName
        }
    }

    private var substanceDots: some View {
        HStack(spacing: 3) {
            ForEach(uniqueSubstances.prefix(4).enumerated(), id: \.offset) { _, name in
                Circle()
                    .fill(SubstancePalette.color(for: name, colorMap: colorMap))
                    .frame(width: 7, height: 7)
            }
        }
    }
}
