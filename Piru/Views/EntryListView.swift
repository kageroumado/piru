import SwiftData
import SwiftUI

// MARK: - Journal Grouping

enum JournalGrouping: String, CaseIterable {
    // Order drives the grouping menu; Days is the default so it leads.
    case byDay = "Days"
    case recent = "Recent"
    case bySubstance = "Substance"
    case byCategory = "Category"

    var icon: String {
        switch self {
        case .recent: "clock"
        case .byDay: "calendar.day.timeline.left"
        case .bySubstance: "pill"
        case .byCategory: "square.grid.2x2"
        }
    }

    var displayName: LocalizedStringResource {
        switch self {
        case .recent: "Recent"
        case .byDay: "Days"
        case .bySubstance: "Substance"
        case .byCategory: "Category"
        }
    }
}

// MARK: - Entry List View

struct EntryListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appNavigator) private var navigator
    @Query(sort: \DoseEntry.timestamp, order: .reverse, transaction: .init(animation: nil)) private var entries: [DoseEntry]
    @Query private var substanceColors: [SubstanceColor]

    @Binding var searchText: String

    /// When embedded in the Search tab: drop the "Journal" header + filter bar,
    /// showing only the (recent / searched) entries.
    var isSearchSurface = false

    @State private var selectedTag: String? = nil
    @State private var grouping: JournalGrouping = .byDay
    @State private var showingCalendar = false

    /// Mirrors the day cards' redose-stacking preference so the timeline prewarm
    /// computes geometry under the same key the cards will look up.
    @AppStorage("stackRedoses", store: UserDefaults(suiteName: "group.dev.yumeji.piru")) private var stackRedoses = true

    // Filter state — category facets only. (Substance and date filtering were
    // dropped: substance duplicates Search, and a chronological day list makes
    // time windows pointless — the calendar *scrolls* to a day instead.)
    @State private var filterCategories: Set<SubstanceCategory> = []

    private var hasActiveFilters: Bool {
        !filterCategories.isEmpty
    }

    /// Surface the live session as a hero card atop the Journal. Independent of
    /// the tag/category filters — "what's active right now" is a status banner,
    /// not part of the filtered history.
    private var showActiveHero: Bool {
        !isSearchSurface && ActiveSessionManager.shared.hasActiveSession
    }

    /// The day-list card representing the currently-active session — the cluster
    /// the user is in right now, matched by the *most-recent* active dose. (Using
    /// the latest rather than the earliest keeps the tap on the real current
    /// session even when an older long-acting dose in a separate, overlapping
    /// session is still pharmacologically active.) It's excluded from the day
    /// list (and its header suppressed when it was the day's only session)
    /// because the hero already represents it.
    private var activeSessionCard: SessionCard? {
        guard showActiveHero,
              let anchor = ActiveSessionManager.shared.activeSubstanceStates.map(\.doseTimestamp).max()
        else { return nil }
        for day in model.sessionDays {
            for card in day.sessions
                where card.entries.contains(where: { abs($0.timestamp.timeIntervalSince(anchor)) < 1 }) {
                return card
            }
        }
        return nil
    }

    private var activeSessionCardID: UUID? {
        activeSessionCard?.id
    }

    // MARK: - Derived State

    /// All derived journal state — the grouped buckets, colour map, category
    /// facets, and tag list — lives in this observable model so recomputation
    /// happens off `body` and the view diffs a single source of truth. UI-only
    /// state (grouping, filters, collapse sets) stays on the view.
    @State private var model = JournalModel()

    @State private var collapsedSubstances: Set<String> = []
    @State private var collapsedCategories: Set<SubstanceCategory> = []

    /// Cheap content fingerprint of the fetched entries. Used as the rebuild
    /// task's identity so the derived data refreshes on *edits*, not just
    /// adds/removes. `entries.count` alone misses an in-place edit (moving a dose
    /// to another day, changing its amount): the count is unchanged, so the cache
    /// would go stale. Hashing the fields `derived` depends on closes that gap.
    private var entriesSignature: Int {
        var hasher = Hasher()
        for entry in entries {
            hasher.combine(entry.persistentModelID)
            hasher.combine(entry.timestamp)
            hasher.combine(entry.amount)
            hasher.combine(entry.substance)
            hasher.combine(entry.route)
            // Session membership feeds the grouping; a split / merge / reassign
            // changes only this, so it must invalidate the cached buckets.
            hasher.combine(entry.session?.id)
        }
        return hasher.finalize()
    }

    /// Resolve derived data + regroup — entries or colours changed.
    private func rebuildAll() {
        model.refreshColorMap(substanceColors)
        model.rebuildDerived(entries: entries, colors: substanceColors)
        regroup()
    }

    /// Re-bucket for the current filter/grouping selection — no re-resolve.
    private func regroup() {
        model.rebuildGroups(
            entries: entries,
            grouping: grouping,
            searchText: searchText,
            selectedTag: selectedTag,
            filterCategories: filterCategories,
            stackRedoses: stackRedoses,
            entriesSignature: entriesSignature,
        )
    }

    // MARK: - Body

    var body: some View {
        ScrollViewReader { proxy in
            list(proxy: proxy)
        }
    }

    private func list(proxy: ScrollViewProxy) -> some View {
        List {
            if !isSearchSurface, !model.tags.isEmpty {
                tagChipBar
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }

            // The live session is promoted to a hero card above the history —
            // no "Today" header (its card is pulled from the day list below).
            if showActiveHero {
                ActiveSessionHeroCard(
                    card: activeSessionCard,
                    states: ActiveSessionManager.shared.activeSubstanceStates,
                    colorMap: model.colorMap,
                    onTap: {
                        // Push the session detail like a day card does (not the
                        // accessory's sheet). Fall back to the live-session sheet
                        // only if the card hasn't been matched yet (e.g. the day
                        // groups are mid-rebuild right after logging).
                        if let id = activeSessionCardID {
                            navigator.push(.session(id: id))
                        } else {
                            guard navigator.sheetStack.isEmpty else { return }
                            navigator.present(.sessionDetail)
                        }
                    },
                )
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 10, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            // Main content
            switch grouping {
            case .recent: recentContent
            case .byDay: sessionGroupedContent
            case .bySubstance: substanceGroupedContent
            case .byCategory: categoryGroupedContent
            }
        }
        .id(grouping)
        .listStyle(.plain)
        .listSectionSpacing(.custom(2))
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .appHeader(
            "Journal",
            enabled: !isSearchSurface,
            leadingControls: { journalHeaderControls },
            menuExtras: {
                Button {
                    showingCalendar = true
                } label: {
                    Label("Jump to Date", systemImage: "calendar")
                }
            },
        )
        .overlay {
            if model.filtered.isEmpty {
                emptyState
            }
        }
        .task {
            rebuildAll()
        }
        .task(id: entriesSignature) {
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            // Animate the diff so a newly-logged session slides in and pushes the
            // others down instead of snapping. Safe to wrap unconditionally: the
            // model's incremental derive bails when nothing actually changed (the
            // initial appear / a re-appear), so `withAnimation` wraps a no-op and
            // nothing animates on first load.
            withAnimation(.smooth(duration: 0.35)) { rebuildAll() }
        }
        .onChange(of: searchText) { regroup() }
        .onChange(of: selectedTag) { regroup() }
        .onChange(of: grouping) { regroup() }
        .onChange(of: substanceColors.count) { rebuildAll() }
        .sheet(isPresented: $showingCalendar) {
            calendarSheet(proxy: proxy)
                .presentationDetents([.medium])
                .presentationBackground(.regularMaterial)
        }
    }

    /// Scroll the day list to the selected calendar date. Switches to the Days
    /// grouping if needed, then targets the nearest rendered day at or before
    /// the tapped date (the list is newest-first), falling back to the oldest.
    private func jump(to date: Date, proxy: ScrollViewProxy) {
        if grouping != .byDay {
            grouping = .byDay
            regroup()
        }
        let target = Calendar.current.startOfDay(for: date)
        // A day whose only session is the live one renders no section (the hero
        // card represents it), so only days that actually put rows on screen
        // are valid scroll targets.
        let rendered = model.sessionDays.filter { day in
            day.sessions.contains { $0.id != activeSessionCardID }
        }
        guard let day = rendered.first(where: { $0.date <= target }) ?? rendered.last else { return }
        // Let the sheet dismissal (and a possible grouping switch, which
        // recreates the List via `.id(grouping)`) settle before scrolling.
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation {
                proxy.scrollTo(day.id, anchor: .top)
            }
        }
    }

    // MARK: - Header Controls

    /// Journal-specific controls injected into the app header: the grouping
    /// picker (primary, accent) and a filter pull-down. Each is its own glass
    /// capsule inside the header's shared `GlassEffectContainer`.
    @ViewBuilder
    private var journalHeaderControls: some View {
        Menu {
            Picker("Group by", selection: $grouping) {
                ForEach(JournalGrouping.allCases, id: \.self) { mode in
                    Label(mode.displayName, systemImage: mode.icon).tag(mode)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(grouping.displayName)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .fixedSize(horizontal: true, vertical: false)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .frame(height: 44)
            .padding(.horizontal, 14)
            .contentShape(Capsule())
        }
        .glassEffect(.regular, in: .capsule)

        filterMenu
    }

    /// Filter as a pull-down menu (Mail's idiom) rather than a modal sheet:
    /// category checkmark toggles plus a one-tap Clear. The funnel tints pink
    /// while any filter is active.
    private var filterMenu: some View {
        Menu {
            // Category is the only meaningful filter here — the list already
            // shows every day in order, so a time window adds nothing. Each
            // category is a checkmark toggle (activate/deactivate in place).
            if !model.categories.isEmpty {
                Section("Category") {
                    ForEach(model.categories, id: \.self) { category in
                        Button {
                            toggleCategory(category)
                        } label: {
                            Label {
                                Text(category.displayName)
                            } icon: {
                                Image(systemName: filterCategories.contains(category) ? "checkmark" : category.icon)
                            }
                        }
                    }
                }
            }

            if hasActiveFilters {
                Section {
                    Button("Clear Filters", role: .destructive) {
                        clearFilters()
                    }
                }
            }
        } label: {
            // Constant glass effect — the active state is a filled accent disc
            // behind the glyph (animated opacity), NOT a change of glass *type*.
            // Swapping the Glass value (tinted vs regular) changed the element's
            // identity inside the shared GlassEffectContainer, so the button
            // morphed out and briefly vanished whenever a filter toggled.
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(hasActiveFilters ? .white : Theme.accent)
                .frame(width: 44, height: 44)
                .background {
                    Circle()
                        .fill(Theme.accent)
                        .opacity(hasActiveFilters ? 1 : 0)
                }
                .contentShape(Circle())
        }
        .glassEffect(.regular, in: .circle)
        .animation(.snappy, value: hasActiveFilters)
    }

    private func toggleCategory(_ category: SubstanceCategory) {
        if filterCategories.contains(category) {
            filterCategories.remove(category)
        } else {
            filterCategories.insert(category)
        }
        regroup()
    }

    private func clearFilters() {
        filterCategories = []
        regroup()
    }

    // MARK: - Tag Chip Bar

    private var tagChipBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                // Grouping and category filtering live in the navbar menus
                // (Mail's idiom); this row is purely the tag facet. The leading
                // "All" reset plus the single-select accent fill carry the
                // filter affordance, so no separate funnel glyph is needed —
                // having one here duplicated the navbar's filter button.
                tagPill(
                    title: Text("All"),
                    isSelected: selectedTag == nil,
                ) {
                    selectedTag = nil
                }

                ForEach(model.tags, id: \.self) { tag in
                    tagPill(
                        title: Text(verbatim: "#\(tag)"),
                        isSelected: selectedTag == tag,
                    ) {
                        selectedTag = selectedTag == tag ? nil : tag
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
    }

    private func tagPill(title: Text, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy) {
                action()
                regroup()
            }
        } label: {
            title
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    isSelected
                        ? AnyShapeStyle(Theme.accent)
                        : AnyShapeStyle(Color(.secondarySystemFill)),
                    in: Capsule(),
                )
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Recent (Flat) Content

    private var recentContent: some View {
        ForEach(model.filtered) { entry in
            entryRow(entry)
        }
    }

    /// One dose entry as a tappable card row (chevron-free, pushes to detail).
    /// Shared by the flat, substance-grouped, and category-grouped lists.
    private func entryRow(_ entry: DoseEntry) -> some View {
        Button {
            navigator.push(.entry(timestamp: entry.timestamp, id: entry.id))
        } label: {
            SubstanceEntryRow(entry: entry, colorMap: model.colorMap)
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    // MARK: - Session Grouped Content

    /// Sessions grouped under day headers — the Journal's primary view. Each day
    /// is a `Section`; its rows are the sessions that started that day, newest
    /// first. A maintenance session (only background meds) renders as a compact
    /// row; everything else is a full card with a mini per-session timeline.
    private var sessionGroupedContent: some View {
        let activeID = activeSessionCardID
        return ForEach(model.sessionDays) { day in
            // The active session lives in the hero card, so drop it here. A day
            // left empty by that removal (e.g. Today held only the live session)
            // renders nothing — no orphan header.
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
                            Button {
                                if let session = card.session {
                                    navigator.push(.session(id: session.id))
                                }
                            } label: {
                                SessionCardView(card: card, colorMap: model.colorMap, inGroup: true)
                            }
                            .buttonStyle(.plain)

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
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(day.dateTitle)
                            .font(.headline)
                        Text(day.weekday)
                            .font(.headline.weight(.regular))
                            .foregroundStyle(Theme.secondaryLabel)
                        Spacer()
                    }
                    .textCase(nil)
                    // Indented to align with the cards' inner content (the card
                    // edge sits at 16, its text at ~30), matching how the detail
                    // screens' section headers sit in from the card edge. Plus a
                    // little more room beneath before the day's container.
                    .listRowInsets(EdgeInsets(top: 0, leading: 30, bottom: 8, trailing: 16))
                }
            }
        }
    }

    // MARK: - Substance Grouped Content

    private var substanceGroupedContent: some View {
        ForEach(model.substanceGroups, id: \.name) { group in
            let isCollapsed = collapsedSubstances.contains(group.name)
            Section {
                if !isCollapsed {
                    ForEach(group.entries) { entry in
                        entryRow(entry)
                    }
                }
            } header: {
                Button {
                    withAnimation(.snappy) {
                        if isCollapsed {
                            collapsedSubstances.remove(group.name)
                        } else {
                            collapsedSubstances.insert(group.name)
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        SubstanceGroupHeader(name: group.name, count: group.entries.count, colorMap: model.colorMap)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    }
                }
            }
        }
    }

    // MARK: - Category Grouped Content

    private var categoryGroupedContent: some View {
        ForEach(model.categoryGroups, id: \.category) { group in
            let isCollapsed = collapsedCategories.contains(group.category)
            Section {
                if !isCollapsed {
                    ForEach(group.entries) { entry in
                        entryRow(entry)
                    }
                }
            } header: {
                Button {
                    withAnimation(.snappy) {
                        if isCollapsed {
                            collapsedCategories.remove(group.category)
                        } else {
                            collapsedCategories.insert(group.category)
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Label {
                            Text("\(String(localized: group.category.displayName)) (\(group.entries.count))")
                        } icon: {
                            Image(systemName: group.category.icon)
                                .foregroundStyle(group.category.color)
                        }
                        .font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView(
            searchText.isEmpty && !hasActiveFilters ? "No Entries" : "No Results",
            systemImage: searchText.isEmpty && !hasActiveFilters ? "pill" : "magnifyingglass",
            description: Text(
                hasActiveFilters ? "Try adjusting your filters." :
                    searchText.isEmpty ? "Tap + to log your first entry." :
                    "Try a different search term.",
            ),
        )
    }

    // MARK: - Calendar Sheet

    private func calendarSheet(proxy: ScrollViewProxy) -> some View {
        NavigationStack {
            JournalCalendarView(
                entries: entries,
                colorMap: model.colorMap,
                onSelectDate: { date in
                    showingCalendar = false
                    jump(to: date, proxy: proxy)
                },
            )
            .navigationTitle("Jump to Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { showingCalendar = false } label: { Image(systemName: "xmark") }
                }
            }
        }
    }
}

// MARK: - Substance Entry Row (for substance/category grouping)

private struct SubstanceEntryRow: View {
    let entry: DoseEntry
    let colorMap: [String: Color]

    private var color: Color {
        SubstancePalette.color(for: entry.substance, colorMap: colorMap)
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.substance)
                    .font(.subheadline.weight(.semibold))
                Text("\(entry.amount.doseFormatted) \(entry.unit) — \(String(localized: entry.route.localizedName))")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(entry.timestamp.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.caption)
                Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
            }
            .foregroundStyle(Theme.secondaryLabel)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard()
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Substance Group Header

private struct SubstanceGroupHeader: View {
    let name: String
    let count: Int
    let colorMap: [String: Color]

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(SubstancePalette.color(for: name, colorMap: colorMap))
                .frame(width: 8, height: 8)
            Text("\(name) (\(count))")
                .font(.subheadline.weight(.semibold))
        }
    }
}

// MARK: - Day Card

/// One session's card model, with its timeline inputs precomputed (in
/// `JournalModel.rebuildGroups`) so the card's mini graph never re-derives PK
/// curves while scrolling. Text — time label, substance summary, dose count — is
/// formatted **once here** rather than on every `SessionCardView` body pass.
struct SessionCard: Identifiable {
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
        let clock = Date.FormatStyle.dateTime.hour().minute()
        if let end = entries.last?.timestamp, end.timeIntervalSince(start) >= 60 {
            timeLabel = "\(start.formatted(clock)) – \(end.formatted(clock))"
        } else {
            timeLabel = start.formatted(clock)
        }

        let names = entries.map(\.substance)
        let unique = (NSOrderedSet(array: names).array as? [String]) ?? names
        uniqueSubstances = unique
        if unique.count <= 3 {
            substanceSummary = unique.joined(separator: ", ")
        } else {
            let first = unique.prefix(3).joined(separator: ", ")
            substanceSummary = String(localized: "\(first) +\(unique.count - 3) more")
        }
        doseCountText = entries.count == 1
            ? String(localized: "1 dose")
            : String(localized: "\(entries.count) doses")
    }
}

/// A day header plus the sessions that started that day — the unit the Journal
/// list renders as a `Section`.
struct SessionDay: Identifiable {
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
struct SessionCardView: View {
    let card: SessionCard
    let colorMap: [String: Color]
    /// When the card is a row inside a day's shared grouped container, it drops
    /// its own background (the container draws it) and relies on hairline
    /// dividers for separation.
    var inGroup: Bool = false

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
            // duration-less doses rest on it as colour-coded dots.
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
private struct ActiveSessionHeroCard: View {
    /// The matched day-list card, when the groups have been built. Supplies the
    /// custom session title, substance summary, and dose markers. `nil` only in
    /// the brief window right after logging, before the rebuild matches it — the
    /// header then falls back to values derived straight from the live states.
    let card: SessionCard?
    let states: [ActiveSubstanceState]
    let colorMap: [String: Color]
    var onTap: () -> Void

    @AppStorage("stackRedoses", store: UserDefaults(suiteName: "group.dev.yumeji.piru")) private var stackRedoses = true

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
                // Horizontal padding matches the regular cards (14) so the title
                // aligns with the session titles below. Bottom padding is tighter
                // than the top — the graph already carries its own axis-label band,
                // so anything more beneath it reads as a gap.
                .padding(.top, 16)
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
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
                Text(verbatim: state.substanceName)
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
            Text(verbatim: state.route)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(color.opacity(0.16), in: Capsule())
                .foregroundStyle(color)
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
        uniqueSubstances.joined(separator: ", ")
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
        guard distinctCount >= TimelineGraphView.laneModeThreshold else { return base }
        let ideal = CGFloat(distinctCount) * 32 + 40
        return max(base, min(ideal, 380))
    }
}

// MARK: - Journal Calendar View

struct JournalCalendarView: View {
    let entries: [DoseEntry]
    let colorMap: [String: Color]
    let onSelectDate: (Date) -> Void

    @State private var selectedMonth: Date = .now

    /// Per-day entry counts keyed by day start, bucketed once per change to
    /// `entries` so each of the ~31 day cells does an O(1) lookup instead of
    /// scanning every entry.
    @State private var dayCounts: [Date: Int] = [:]

    private var calendar: Calendar {
        Calendar.current
    }

    /// Content fingerprint of the fields the day buckets depend on — the
    /// rebuild task's identity, mirroring `EntryListView.entriesSignature`.
    private var entriesSignature: Int {
        var hasher = Hasher()
        for entry in entries {
            hasher.combine(entry.timestamp)
        }
        return hasher.finalize()
    }

    private func rebuildDayCounts() {
        dayCounts = entries.reduce(into: [:]) { counts, entry in
            counts[calendar.startOfDay(for: entry.timestamp), default: 0] += 1
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            // Month navigation
            HStack {
                Button {
                    selectedMonth = calendar.date(byAdding: .month, value: -1, to: selectedMonth)!
                } label: {
                    Image(systemName: "chevron.left")
                }
                Spacer()
                Text(selectedMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.headline)
                Spacer()
                Button {
                    selectedMonth = calendar.date(byAdding: .month, value: 1, to: selectedMonth)!
                } label: {
                    Image(systemName: "chevron.right")
                }
            }
            .padding(.horizontal)

            // Day-of-week header
            let weekdays = calendar.shortWeekdaySymbols
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                ForEach(weekdays, id: \.self) { day in
                    Text(day)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Theme.secondaryLabel)
                }

                // Calendar days
                ForEach(daysInMonth()) { item in
                    if item.day == 0 {
                        Color.clear.frame(height: 40)
                    } else {
                        let date = calendar.date(from: DateComponents(year: item.year, month: item.month, day: item.day))!
                        let count = dayCounts[date, default: 0]
                        Button {
                            onSelectDate(date)
                        } label: {
                            VStack(spacing: 2) {
                                Text("\(item.day)")
                                    .font(.subheadline)
                                    .foregroundStyle(count > 0 ? .primary : Theme.secondaryLabel)
                                    .fontWeight(count > 0 ? .semibold : .regular)
                                if count > 0 {
                                    Circle()
                                        .fill(Theme.accent)
                                        .frame(width: 5, height: 5)
                                } else {
                                    Color.clear.frame(width: 5, height: 5)
                                }
                            }
                            .frame(width: 40, height: 40)
                            .background {
                                if calendar.isDateInToday(date) {
                                    Circle().fill(Theme.accent.opacity(0.15))
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding(.top)
        .task(id: entriesSignature) {
            rebuildDayCounts()
        }
    }

    private struct CalendarDay: Identifiable, Hashable {
        let id: Int // unique within the grid (slot index); negative for leading placeholders
        let year: Int
        let month: Int
        let day: Int // 0 = placeholder
    }

    private func daysInMonth() -> [CalendarDay] {
        let comps = calendar.dateComponents([.year, .month], from: selectedMonth)
        guard let monthStart = calendar.date(from: comps),
              let range = calendar.range(of: .day, in: .month, for: monthStart) else { return [] }

        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let leadingBlanks = (firstWeekday - calendar.firstWeekday + 7) % 7

        var days: [CalendarDay] = []
        for blank in 0 ..< leadingBlanks {
            days.append(CalendarDay(id: -(blank + 1), year: comps.year!, month: comps.month!, day: 0))
        }
        for day in range {
            days.append(CalendarDay(id: day, year: comps.year!, month: comps.month!, day: day))
        }
        return days
    }
}
