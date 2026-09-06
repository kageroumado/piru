import SwiftData
import SwiftUI

// MARK: - Day Sections

/// Sessions grouped under day headers — the Journal's primary view. Each day is
/// a `Section`; its rows are the sessions that started that day, newest first.
struct JournalDaySections: View {
    @Environment(\.appNavigator) private var navigator

    let days: [SessionDay]
    let colorMap: [String: Color]
    /// The live session's card, dropped from the log — the Active Now card above
    /// already shows it, and a single-dose day otherwise printed the same dose
    /// and curve twice.
    let activeID: UUID?
    let actions: SessionCardActionModel

    var body: some View {
        ForEach(days) { day in
            // A day left empty by the live-session removal renders nothing (no
            // orphan header); the session reappears here once it wears off.
            let cards = day.sessions.filter { $0.id != activeID }
            if !cards.isEmpty {
                Section {
                    // The day's sessions share one rounded container, separated by
                    // inset hairlines — the day reads as a single unit rather than
                    // a stack of floating cards. Each row is still its own plain
                    // Button (programmatic push, no system disclosure chevron over
                    // the graph), so taps stay per-session.
                    VStack(spacing: 0) {
                        ForEach(cards.enumerated(), id: \.element.id) { index, card in
                            row(card)
                            if index < cards.count - 1 {
                                Divider()
                                    .padding(.horizontal, 14)
                            }
                        }
                    }
                    .themeCard()
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 12, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    // Scroll anchor for the calendar's "Jump to Date".
                    .id(day.id)
                } header: {
                    JournalDayHeader(title: day.dateTitle, weekday: day.weekday)
                }
            }
        }
    }

    private func row(_ card: SessionCard) -> some View {
        Button {
            if let session = card.session {
                navigator.push(.session(id: session.id))
            }
        } label: {
            SessionCardView(card: card, colorMap: colorMap, inGroup: true)
                .equatable()
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let session = card.session {
                SessionCardContextMenu(session: session, actions: actions)
            }
        } preview: {
            // The row draws no background inside the day's container, so the
            // preview is the standalone card.
            SessionCardView(card: card, colorMap: colorMap)
                .frame(width: 340)
        }
    }
}

private struct JournalDayHeader: View {
    let title: String
    let weekday: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(title)
                .cardTitle()
            Text(weekday)
                .font(.headline.weight(.regular))
                .foregroundStyle(Theme.secondaryLabel)
            Spacer()
        }
        .textCase(nil)
        // Indented to align with the cards' inner content (the card edge sits at
        // 16, its text at ~30), matching how the detail screens' section headers
        // sit in from the card edge. Plus a little more room beneath before the
        // day's container.
        .listRowInsets(EdgeInsets(top: 0, leading: 30, bottom: 8, trailing: 16))
    }
}

// MARK: - Substance Sections

/// The Grouped view keyed by substance: one collapsible section per substance,
/// most-logged first.
struct JournalSubstanceSections: View {
    let model: JournalModel

    var body: some View {
        ForEach(model.substanceGroups, id: \.name) { group in
            let isCollapsed = model.collapsedSubstances.contains(group.name)
            Section {
                if !isCollapsed {
                    ForEach(group.entries) { entry in
                        JournalEntryRow(entry: entry, colorMap: model.colorMap)
                    }
                }
            } header: {
                Button {
                    withAnimation(.snappy) { model.toggleCollapsed(substance: group.name) }
                } label: {
                    HStack(spacing: Spacing.md) {
                        SubstanceGroupHeader(
                            name: group.name,
                            count: group.entries.count,
                            colorMap: model.colorMap,
                        )
                        Spacer()
                        SectionDisclosureChevron(isCollapsed: isCollapsed)
                    }
                }
                .accessibilityValue(isCollapsed ? Text("Collapsed") : Text("Expanded"))
            }
        }
    }
}

// MARK: - Category Sections

/// The Grouped view keyed by category, in the category enum's own order.
struct JournalCategorySections: View {
    let model: JournalModel

    var body: some View {
        ForEach(model.categoryGroups, id: \.category) { group in
            let isCollapsed = model.collapsedCategories.contains(group.category)
            Section {
                if !isCollapsed {
                    ForEach(group.entries) { entry in
                        JournalEntryRow(entry: entry, colorMap: model.colorMap)
                    }
                }
            } header: {
                Button {
                    withAnimation(.snappy) { model.toggleCollapsed(category: group.category) }
                } label: {
                    HStack(spacing: Spacing.md) {
                        Label {
                            Text("\(String(localized: group.category.displayName)) (\(group.entries.count))")
                        } icon: {
                            Image(systemName: group.category.icon)
                                .foregroundStyle(group.category.labelColor)
                        }
                        .sectionLabel()
                        Spacer()
                        SectionDisclosureChevron(isCollapsed: isCollapsed)
                    }
                }
                .accessibilityValue(isCollapsed ? Text("Collapsed") : Text("Expanded"))
            }
        }
    }
}

private struct SectionDisclosureChevron: View {
    let isCollapsed: Bool

    var body: some View {
        Image(systemName: "chevron.right")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
            .rotationEffect(.degrees(isCollapsed ? 0 : 90))
            .accessibilityHidden(true)
    }
}

// MARK: - Grouped Entry Row

/// One dose entry as a tappable card row (chevron-free, pushes to detail).
/// Shared by the substance- and category-keyed Grouped lists.
private struct JournalEntryRow: View {
    @Environment(\.appNavigator) private var navigator

    let entry: DoseEntry
    let colorMap: [String: Color]

    var body: some View {
        Button {
            navigator.push(.entry(timestamp: entry.timestamp, id: entry.id))
        } label: {
            SubstanceEntryRow(entry: entry, colorMap: colorMap)
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}

private struct SubstanceEntryRow: View {
    let entry: DoseEntry
    let colorMap: [String: Color]

    private var color: Color {
        SubstancePalette.color(for: entry.substance, colorMap: colorMap)
    }

    var body: some View {
        HStack(spacing: Spacing.xl) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(DoseTitle.resolve(for: entry))
                    .sectionLabel()
                Text("\(entry.amount.doseFormatted) \(entry.unit) — \(String(localized: entry.route.localizedName))")
                    .captionSecondary()
            }
            Spacer(minLength: Spacing.md)
            VStack(alignment: .trailing, spacing: Spacing.xs) {
                Text(entry.timestamp.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.caption)
                Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
            }
            .foregroundStyle(Theme.secondaryLabel)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard()
        .contentShape(Theme.cardShape)
    }
}

private struct SubstanceGroupHeader: View {
    let name: String
    let count: Int
    let colorMap: [String: Color]

    var body: some View {
        HStack(spacing: Spacing.md) {
            LegendDot(color: SubstancePalette.color(for: name, colorMap: colorMap))
            Text("\(name) (\(count))")
                .sectionLabel()
        }
    }
}
