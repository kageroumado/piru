import SwiftData
import SwiftUI

/// A session row in the Journal: a full card (time + substance dots + mini
/// per-session timeline) for a normal session, or a compact "Medications" row
/// for a maintenance session (only background meds). The card is content, so it
/// sits on `themeCard` — never glass.
struct SessionCardView: View, Equatable {
    let card: SessionCard
    let colorMap: [String: Color]
    /// When the card is a row inside a day's shared grouped container, it drops
    /// its own background (the container draws it) and relies on hairline
    /// dividers for separation.
    var inGroup: Bool = false

    /// Compare only the real inputs (not the `@AppStorage`/`@State` wrappers) so
    /// `.equatable()` at the call site lets SwiftUI keep the existing instance
    /// when the card's content is unchanged. The Journal's progressive derive
    /// re-runs `EntryListView.body` several times on open (the @Query results +
    /// the model's prefix/tail publishes each land separately); without this skip
    /// every card re-renders on each pass and re-subscribes its @AppStorage.
    static func == (lhs: SessionCardView, rhs: SessionCardView) -> Bool {
        lhs.card == rhs.card && lhs.inGroup == rhs.inGroup && lhs.colorMap == rhs.colorMap
    }

    @AppStorage("stackRedoses", store: UserDefaults(suiteName: AppIdentity.appGroup)) private var stackRedoses = true

    private var dotColors: [Color] {
        card.uniqueSubstances.prefix(4).map { SubstancePalette.color(for: $0, colorMap: colorMap) }
    }

    var body: some View {
        if card.isMaintenance {
            maintenanceRow
        } else {
            fullCard
        }
    }

    private var maintenanceRow: some View {
        HStack(spacing: Spacing.xl) {
            Image(systemName: "pills.fill")
                .font(.body)
                .foregroundStyle(Theme.secondaryLabel)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(card.title ?? String(localized: "Medications"))
                    .sectionLabel()
                Text(verbatim: "\(card.timeLabel)  ·  \(card.substanceSummary)")
                    .captionSecondary()
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.tertiaryLabel)
                .accessibilityHidden(true)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard(enabled: !inGroup)
        .contentShape(Theme.cardShape)
    }

    private var fullCard: some View {
        HStack(spacing: Spacing.xl) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(card.title ?? card.timeLabel)
                    .cardTitle()
                HStack(spacing: Spacing.md) {
                    Text(
                        verbatim: card.title == nil
                            ? card.doseCountText
                            : "\(card.timeLabel)  ·  \(card.doseCountText)",
                    )
                    .captionSecondary()
                    if let sessionID = card.sessionID {
                        SharedSessionMark(sessionID: sessionID, diameter: 16)
                    }
                }
                HStack(spacing: Spacing.sm) {
                    substanceDots
                    Text(card.substanceSummary)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryLabel)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            graph

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.tertiaryLabel)
                .accessibilityHidden(true)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard(enabled: !inGroup)
        .contentShape(Theme.cardShape)
    }

    private var substanceDots: some View {
        HStack(spacing: 3) {
            ForEach(dotColors.enumerated(), id: \.offset) { _, color in
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
            }
        }
    }

    @ViewBuilder
    private var graph: some View {
        if !card.states.isEmpty || !card.markers.isEmpty {
            // One unified renderer: curves rise from a shared baseline and any
            // duration-less doses rest on it as color-coded dots.
            // `showNowIndicator: false` — historical cards, so the axis-less
            // "now" dot would only add noise.
            TimelineGraphView(
                substances: card.states,
                currentTime: .now,
                compact: true,
                markers: card.markers,
                stackRedoses: stackRedoses,
                showNowIndicator: false,
                dayBounded: true,
            )
            .equatable()
            .frame(width: 96, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.input))
            .allowsHitTesting(false)
        }
    }
}
