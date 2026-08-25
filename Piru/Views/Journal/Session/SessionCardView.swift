import SwiftData
import SwiftUI

/// One session's card model, with its timeline inputs precomputed (in
/// `JournalModel.rebuildGroups`) so the card's mini graph never re-derives PK
/// curves while scrolling. Text — time label, substance summary, dose count — is
/// formatted **once here** rather than on every `SessionCardView` body pass.
/// Equatable so SwiftUI can skip a `SessionCardView` body re-eval when the parent
/// hands it a content-identical card — the progressive derive republishes the
/// card array (prefix paint, then tail), and without this every card re-rendered
/// on the second pass even when nothing about it changed (confirmed via
/// `_printChanges`). All stored fields are Equatable (value types, plus `@Model`
/// `Session`/`DoseEntry` which compare by identity, and `ActiveSubstanceState` /
/// `DoseMarker` which are `Hashable`).
struct SessionCard: Identifiable, Equatable {
    /// The session's stable id, used for navigation. For a (rare) session-less
    /// straggler this is a fresh UUID and the card is non-navigable.
    let id: UUID
    let session: Session?
    let entries: [DoseEntry]
    let states: [ActiveSubstanceState]
    let markers: [DoseMarker]
    let isMaintenance: Bool
    let startDate: Date
    /// User-given session title, if any.
    let title: String?
    /// Clock label — a single start time, or "start – end" for a span.
    let timeLabel: String
    let uniqueSubstances: [String]
    let substanceSummary: String
    let doseCountText: String

    /// Built once rather than per card — the clock format is constant.
    private static let clock = Date.FormatStyle.dateTime.hour().minute()

    init(session: Session?, entries: [DoseEntry], states: [ActiveSubstanceState], markers: [DoseMarker]) {
        self.session = session
        self.entries = entries
        self.states = states
        self.markers = markers
        id = session?.id ?? UUID()
        title = session?.title
        isMaintenance = session?.isMaintenance ?? (!entries.isEmpty && entries.allSatisfy(\.isBackgroundMed))

        let start = entries.first?.timestamp ?? session?.startDate ?? .now
        startDate = start
        if let end = entries.last?.timestamp, end.timeIntervalSince(start) >= 60 {
            timeLabel = "\(start.formatted(Self.clock)) – \(end.formatted(Self.clock))"
        } else {
            timeLabel = start.formatted(Self.clock)
        }

        // Order-preserving dedup without the NSOrderedSet/NSObject bridge — this
        // runs per windowed card inside the synchronous regroup, so the bridge
        // showed up in first-render profiles.
        var seen = Set<String>()
        var unique: [String] = []
        // Canonical display names, deduped independently so two aliases of the same drug collapse to one.
        var seenDisplay = Set<String>()
        var display: [String] = []
        for name in entries.map(\.substance) {
            if seen.insert(name).inserted { unique.append(name) }
            let shown = SubstanceLibrary.lookup(name)?.displayTitle ?? name
            if seenDisplay.insert(shown.lowercased()).inserted { display.append(shown) }
        }
        uniqueSubstances = unique
        if display.count <= 3 {
            substanceSummary = display.joined(separator: ", ")
        } else {
            let first = display.prefix(3).joined(separator: ", ")
            substanceSummary = String(localized: "\(first) +\(display.count - 3) more")
        }
        doseCountText = entries.count == 1
            ? String(localized: "1 dose")
            : String(localized: "\(entries.count) doses")
    }
}

/// A day header plus the sessions that started that day — the unit the Journal
/// list renders as a `Section`.
struct SessionDay: Identifiable, Equatable {
    let date: Date
    let dateTitle: String
    let weekday: String
    let sessions: [SessionCard]
    var id: Date {
        date
    }

    init(date: Date, sessions: [SessionCard]) {
        self.date = date
        self.sessions = sessions
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            dateTitle = String(localized: "Today")
        } else if cal.isDateInYesterday(date) {
            dateTitle = String(localized: "Yesterday")
        } else {
            // The current year is implicit — only show it for other years.
            let base = Date.FormatStyle.dateTime.day().month(.wide)
            let sameYear = cal.isDate(date, equalTo: .now, toGranularity: .year)
            dateTitle = date.formatted(sameYear ? base : base.year())
        }
        weekday = date.formatted(.dateTime.weekday(.wide))
    }
}

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
    /// every card re-rendered ~6× per open and re-subscribed its @AppStorage.
    static func == (lhs: SessionCardView, rhs: SessionCardView) -> Bool {
        lhs.card == rhs.card && lhs.inGroup == rhs.inGroup && lhs.colorMap == rhs.colorMap
    }

    @AppStorage("stackRedoses", store: UserDefaults(suiteName: "group.dev.yumeji.piru")) private var stackRedoses = true

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
        HStack(spacing: 12) {
            Image(systemName: "pills.fill")
                .font(.body)
                .foregroundStyle(Theme.secondaryLabel)
            VStack(alignment: .leading, spacing: 2) {
                Text(card.title ?? String(localized: "Medications"))
                    .font(.subheadline.weight(.semibold))
                Text(verbatim: "\(card.timeLabel)  ·  \(card.substanceSummary)")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard(enabled: !inGroup)
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }

    private var fullCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(card.title ?? card.timeLabel)
                    .font(.headline)
                Text(
                    verbatim: card.title == nil
                        ? card.doseCountText
                        : "\(card.timeLabel)  ·  \(card.doseCountText)",
                )
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
                HStack(spacing: 6) {
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
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard(enabled: !inGroup)
        .contentShape(RoundedRectangle(cornerRadius: 16))
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
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .allowsHitTesting(false)
        }
    }
}
