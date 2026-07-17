import SwiftData
import SwiftUI
import TipKit

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
    /// Canonical common names for display (raw `uniqueSubstances` stays keyed for color lookups). A
    /// dose logged under an alias reads by its canonical name — "LSD", not "Lysergic Acid Diethylamide".
    let substanceDisplayList: [String]
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
            let shown = SubstanceLibrary.timelineLookup(name)?.displayTitle ?? name
            if seenDisplay.insert(shown.lowercased()).inserted { display.append(shown) }
        }
        uniqueSubstances = unique
        substanceDisplayList = display
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

// MARK: - Active Session Hero Card

/// The live session, promoted to a large card at the top of the Journal — the
/// "what's happening right now" focal point. It borrows the dose-detail screen's
/// language: a "Now" label, and then either the **single-dose** treatment (big
/// dose amount + route, a phase bar with the current phase & countdown, and the
/// phase-banded timeline) for the common one-substance case, or the
/// **multi-substance** treatment (substance dots + names, the full session
/// timeline — lane mode once it's busy — and an aggregate "elapsed · next phase"
/// line below). Tapping the body opens the session detail. This is content, so
/// it rides on `themeCard` — never glass.
struct ActiveSessionHeroCard: View {
    /// The matched day-list card, when the groups have been built. Supplies the
    /// custom session title, substance summary, and dose markers. `nil` only in
    /// the brief window right after logging, before the rebuild matches it — the
    /// header then falls back to values derived straight from the live states.
    let card: SessionCard?
    let states: [ActiveSubstanceState]
    let colorMap: [String: Color]
    var onTap: () -> Void

    @AppStorage("stackRedoses", store: UserDefaults(suiteName: "group.dev.yumeji.piru")) private var stackRedoses = true
    @AppStorage(LaneModeDefaults.enabledKey, store: UserDefaults(suiteName: LaneModeDefaults.suite)) private var laneModeEnabled = LaneModeDefaults.enabledDefault
    @AppStorage(LaneModeDefaults.thresholdKey, store: UserDefaults(suiteName: LaneModeDefaults.suite)) private var laneModeThreshold = LaneModeDefaults.thresholdDefault

    private var isSingleDose: Bool {
        states.count == 1
    }

    var body: some View {
        // Re-evaluate every minute so the now-line, the phase bar's countdown,
        // and the "next phase in …" readout stay live without a per-frame tick.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = context.date
            // One Button over the whole card (opens the session detail) — a
            // single, properly-traited accessibility element. The active card is
            // pulled from the day list, so this is VoiceOver's only path to it.
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 10) {
                    if isSingleDose, let state = states.first {
                        singleDoseContent(state: state, now: now)
                    } else {
                        multiSubstanceContent(now: now)
                    }
                }
                // 12pt horizontal keeps the title and the graph canvas on one
                // shared inset. Bottom padding is near-zero — the graph already
                // carries its own axis-label band, so anything more beneath it
                // reads as a gap.
                .padding(.top, 12)
                .padding(.horizontal, 12)
                .padding(.bottom, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .themeCard()
        }
    }

    // MARK: Header — the "Current Session" (or custom) label + disclosure chevron.

    private var titleLabel: some View {
        Text(titleText)
            .font(.title3.weight(.semibold))
            .lineLimit(1)
    }

    /// Overlaid (not laid out in a row) so the substance names beneath it can run
    /// the card's full width rather than stopping short of a reserved column.
    private var disclosureChevron: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tertiary)
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
        // Fill the width so the overlaid chevron parks at the card's edge, not at
        // the end of the (intrinsically narrower) text.
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

        // Phase bar carries the current phase + "{elapsed} in · {remaining} left"
        // — unambiguous for a single substance.
        DosePhaseProgressBar(state: state, now: now)

        // Phase-banded timeline with the clock/hour axis (compact: false).
        TimelineGraphView(
            substances: [state],
            currentTime: now,
            compact: false,
            // The hero is the focal, on-screen graph: compute its geometry
            // synchronously so it draws at the right span on the first frame
            // instead of flashing the placeholder, then popping + jumping a few
            // px right when the off-main model lands. One small graph, cached
            // after — cheap enough for the main thread.
            synchronous: true,
        )
        .equatable()
        .frame(height: 160)
        .allowsHitTesting(false)
        // The phase bar above already speaks the graph's story; inside the
        // card button the timeline summary would only double-read.
        .accessibilityHidden(true)
    }

    // MARK: Multi-substance — dots + names, the full session timeline, aggregate timing.

    @ViewBuilder
    private func multiSubstanceContent(now: Date) -> some View {
        // Title + substance dots & names, kept tight as a title/subtitle pair,
        // with the chevron overlaid so the names can run the full width.
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
        // Fill the width so the overlaid chevron parks at the card's edge, not at
        // the end of the (intrinsically narrower) text.
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .trailing) { disclosureChevron }

        // The same renderer as the session screen: overlapping curves, or
        // stacked per-substance lanes once it's busy (≥ 4), with the hour/clock
        // axis and the now-line. `dayBounded` is what unlocks lane mode.
        TimelineGraphView(
            substances: graphStates,
            currentTime: now,
            compact: false,
            markers: card?.markers ?? [],
            stackRedoses: stackRedoses,
            dayBounded: true,
            // Focal on-screen graph — compute inline so it lands at the right
            // span immediately (no placeholder pop / span jump). See the
            // single-dose hero for the rationale.
            synchronous: true,
        )
        .equatable()
        .frame(height: multiGraphHeight)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        // No aggregate "elapsed / next phase" line here: across several
        // substances "10h in" answers "in what?" and only adds weight beneath an
        // already busy graph. The now-line carries the temporal cue.
    }

    // MARK: - Derived values

    private var titleText: String {
        if let title = card?.title, !title.isEmpty { return title }
        return String(localized: "Current Session")
    }

    /// Every active substance, comma-joined — no "+N more" truncation. The row is
    /// `lineLimit(1)`, so the system truncates only if the names genuinely don't
    /// fit, rather than pre-empting a name (e.g. "Memantine") that would.
    private var displayNames: String {
        // Canonical common names (the no-card fallback reads `states`, whose names are already
        // canonical); `uniqueSubstances` stays raw because it also keys the color dots.
        if let card { return card.substanceDisplayList.joined(separator: ", ") }
        return uniqueSubstances.joined(separator: ", ")
    }

    private var uniqueSubstances: [String] {
        if let card { return card.uniqueSubstances }
        var seen = Set<String>()
        return states.compactMap { state in
            let key = state.substanceName.lowercased()
            guard !seen.contains(key) else { return nil }
            seen.insert(key)
            return state.substanceName
        }
    }

    private var dotColors: [Color] {
        uniqueSubstances.prefix(4).map { SubstancePalette.color(for: $0, colorMap: colorMap) }
    }

    /// The full session's curves for the multi-substance graph, so it matches the
    /// session-detail timeline exactly. Active-only states would start the axis at
    /// the earliest *still-active* dose, shifting the origin and dropping the
    /// leftmost clock label. Falls back to the live states before the card matches.
    private var graphStates: [ActiveSubstanceState] {
        card?.states ?? states
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

    /// Distinct substances on the graph — the lane count once it switches to
    /// small multiples. Mirrors `SessionDetailView.graphHeight` so the embedded
    /// hero timeline grows with the lane count instead of crushing each strip.
    private var distinctCount: Int {
        Set(graphStates.map { $0.substanceName.lowercased() }).count
    }

    private var multiGraphHeight: CGFloat {
        let base = GraphMetrics.embedded
        guard laneModeEnabled, distinctCount >= laneModeThreshold else { return base }
        let ideal = CGFloat(distinctCount) * 32 + 40
        return max(base, min(ideal, 380))
    }
}

// MARK: - Journal Calendar View
