import SwiftUI

/// The two-line content of one "in your body" row — dot · name · intake count on
/// top with the uncolored session total, and a status line beneath. Shared by the
/// live ``SessionBodyLoadSection`` (inside its expandable curve) and the session
/// share image (static), so the two renderings can never drift apart.
struct BodyLoadRowLabel: View {
    let dotColor: Color
    let name: String
    let count: Int
    let total: Double
    let unit: String
    let status: BodyLoadStatus?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // At accessibility sizes the readout drops under the name; beside
            // it, the two truncated each other to "Methylpheni…" and "1…".
            if dynamicTypeSize.isAccessibilitySize {
                nameCluster
                trailingReadout
            } else {
                HStack(alignment: .center, spacing: Spacing.md) {
                    nameCluster
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    trailingReadout
                        .lineLimit(1)
                }
            }
            statusLine
        }
    }

    /// Dot · name · optional intake-count pill (`2×`). The count is a small neutral
    /// capsule rather than a tiny inline word so a redose count reads as a badge,
    /// not a stray glyph riding beside the name.
    private var nameCluster: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            Image(systemName: "circle.fill")
                .font(.chartAnnotation)
                .foregroundStyle(dotColor)
                .accessibilityHidden(true)
            Text(name)
                .font(.body.weight(.semibold))
            if count > 1 {
                Text(verbatim: "\(count)×")
                    .monospacedDigit()
                    .capsuleChip(text: Theme.secondaryLabel, fill: Theme.secondaryLabel)
            }
        }
    }

    /// The quantity, deliberately quieter than the entry rows' hero number — the
    /// totals section restates the same doses, so it shouldn't carry equal weight.
    /// An active substance shows "remaining / total unit" so the still-circulating
    /// amount leads; a cleared/static one shows the total alone.
    @ViewBuilder
    private var trailingReadout: some View {
        switch status {
        case let .eliminating(_, _, remaining):
            cumulativeReadout(remaining: remaining)
        case .cleared, .unmodeled, nil:
            MeasurementLabel(amount: total, unit: unit, numberStyle: .body, unitStyle: .caption)
        }
    }

    /// "33 / 110 mg" — remaining (primary, rounded) over the session total
    /// (secondary), unit trailing. Compact so seven glyphs don't take on the mass
    /// of the hero readout.
    private func cumulativeReadout(remaining: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xxs) {
            Text(remaining.doseFormatted)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(.primary)
            Text(verbatim: " / ")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.tertiary)
            Text(total.doseFormatted)
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundStyle(Theme.secondaryLabel)
            Text(unit)
                .captionSecondary()
        }
        .monospacedDigit()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(remaining.doseFormatted) of \(total.doseFormatted) \(unit) remaining"))
    }

    /// The secondary line, in the dose row's meta size (`.subheadline`, secondary):
    /// the eliminated share and the clear-by projection. The still-circulating
    /// amount leads the trailing readout on the line above ("33 / 110 mg").
    @ViewBuilder
    private var statusLine: some View {
        switch status {
        case let .eliminating(percent, clear, _):
            Group {
                if let clear {
                    Text("\(percent)% eliminated in model · threshold ~\(clear)")
                } else {
                    Text("\(percent)% eliminated in model")
                }
            }
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .font(.subheadline)
            .foregroundStyle(Theme.secondaryLabel)
        case let .cleared(hasActiveMetabolite):
            Text(hasActiveMetabolite
                ? "Below model threshold · active metabolite may persist"
                : "Below model threshold")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
        case .unmodeled:
            Text("No half-life data")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
        case nil:
            EmptyView()
        }
    }
}

/// "In your body": the session's per-substance aggregates with their live
/// elimination state. Total dosed, what's still circulating, clearance
/// projections, and the elimination curve one tap away (a rotating chevron
/// marks every active row as expandable). Totals are the "dosed" side of the
/// body-load equation, so both sides read as one story. For a past session
/// (everything cleared) it shows re-dose totals alone; a session of single
/// doses that have all worn off shows nothing.
///
/// The model is built here, in a body that holds no state, so it is rebuilt
/// only when the entries or colors change. The fold state lives in
/// ``SessionBodyLoadRows``, so expanding a curve re-renders the rows without
/// rebuilding the model.
struct SessionBodyLoadSection: View {
    let entries: [DoseEntry]
    let colorMap: [String: Color]
    /// Section header — the session screen's per-substance aggregate reads
    /// "Total in Your Body"; the dose detail reuses the section for a single
    /// dose, where there is no "total" to speak of.
    var header: LocalizedStringKey = "Total in Your Body"
    /// When `true` the section renders only while something is still
    /// circulating — a fully cleared dose shows nothing at all rather than a
    /// "cleared" placeholder row (the dose detail's behavior).
    var activeOnly = false

    var body: some View {
        let model = SessionBodyLoadModel.make(entries: entries, colorMap: colorMap)
        SessionBodyLoadRows(
            model: model,
            header: header,
            isShown: !model.isEmpty && !(activeOnly && model.active.isEmpty),
        )
    }
}

/// The section's rows and their fold state. Always present (`isShown` hides
/// the section) so the fold state outlives a stretch where nothing is shown.
private struct SessionBodyLoadRows: View {
    let model: SessionBodyLoadModel
    let header: LocalizedStringKey
    let isShown: Bool

    /// Which substances have their elimination curve expanded in place.
    @State private var expanded: Set<String> = []
    /// Guards the one-time default expansion of the first substance.
    @State private var didSeedExpansion = false

    var body: some View {
        if isShown {
            Section {
                ForEach(model.active) { row in
                    activeRow(row)
                }
                ForEach(model.cleared) { row in
                    BodyLoadRowLabel(
                        dotColor: row.color,
                        name: row.displayName,
                        count: row.count,
                        total: row.total,
                        unit: row.unit,
                        status: model.status(of: row),
                    )
                    .padding(.vertical, Spacing.xxs)
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text(header)
            } footer: {
                if !model.active.isEmpty {
                    Text("How much is estimated to be in your body, using only data from this session.")
                }
            }
            // Open the first substance's curve by default, so the fold — and the
            // graph behind it — is discoverable without a tap.
            .onAppear {
                guard !didSeedExpansion else { return }
                didSeedExpansion = true
                if let first = model.active.first { expanded.insert(first.id) }
            }
        }
    }

    /// A fold: the shared ``BodyLoadRowLabel`` with a rotating chevron, the
    /// whole row one button, so the curve reads as expandable rather than as a
    /// navigation row. A `DisclosureGroup` draws the same look but exposes its
    /// chevron as a separate, unnamed 10 pt button that VoiceOver and Voice
    /// Control cannot name, so it stays out of here.
    @ViewBuilder
    private func activeRow(_ row: SessionBodyLoadModel.Active) -> some View {
        let isOpen = expanded.contains(row.id)
        Button {
            withAnimation(.snappy) {
                if isOpen { expanded.remove(row.id) } else { expanded.insert(row.id) }
            }
        } label: {
            HStack(spacing: Spacing.md) {
                BodyLoadRowLabel(
                    dotColor: row.active.color,
                    name: row.displayName,
                    count: row.count,
                    total: row.sessionTotal,
                    unit: row.unit,
                    status: .eliminating(
                        percent: Int((row.active.eliminatedFraction * 100).rounded()),
                        clear: row.clearText,
                        remaining: row.remaining,
                    ),
                )
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryLabel)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isOpen ? Text("Expanded") : Text("Collapsed"))
        .accessibilityHint(isOpen ? Text("Hides the elimination curve") : Text("Shows the elimination curve"))
        if isOpen {
            SubstanceEliminationCurve(active: row.active, displayName: row.displayName)
                .padding(.top, Spacing.xs)
        }
    }
}
