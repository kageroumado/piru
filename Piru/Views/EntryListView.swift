import SwiftData
import SwiftUI
import TipKit

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
    @Query(Self.entriesDescriptor, transaction: .init(animation: nil)) private var entries: [DoseEntry]

    /// Newest-first, **prefetching the `session` relationship**. Grouping and the
    /// entries signature both read `entry.session`; without prefetch that's a
    /// per-entry CoreData fault (N+1) on the main thread — hundreds of blocking
    /// round-trips at launch. Prefetch batches them into the initial fetch.
    private static var entriesDescriptor: FetchDescriptor<DoseEntry> {
        var descriptor = FetchDescriptor<DoseEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)],
        )
        descriptor.relationshipKeyPathsForPrefetching = [\.session]
        return descriptor
    }
    @Query private var substanceColors: [SubstanceColor]

    @Binding var searchText: String

    /// When embedded in the Search tab: drop the "Journal" header + filter bar,
    /// showing only the (recent / searched) entries.
    var isSearchSurface = false

    /// Search-surface only: invoked from the empty-results state to offer
    /// searching the Library instead when a query finds no journal entries.
    var onSwitchToLibrary: (() -> Void)?

    @State private var grouping: JournalGrouping = .byDay
    @State private var showingCalendar = false

    /// Mirrors the day cards' redose-stacking preference so the timeline prewarm
    /// computes geometry under the same key the cards will look up.
    @AppStorage("stackRedoses", store: UserDefaults(suiteName: "group.dev.yumeji.piru")) private var stackRedoses = true

    // Filter state — the funnel menu's three facets: tag, category, route.
    // Within a facet the values OR; across facets they AND. (Substance and date
    // filtering were dropped: substance duplicates Search, and a chronological
    // day list makes time windows pointless — the calendar *scrolls* to a day
    // instead.)
    @State private var filterTags: Set<String> = []
    @State private var filterCategories: Set<SubstanceCategory> = []
    @State private var filterRoutes: Set<RouteOfAdministration> = []

    private var hasActiveFilters: Bool {
        !filterTags.isEmpty || !filterCategories.isEmpty || !filterRoutes.isEmpty
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

    /// The id of the session owning the currently-active doses, read straight from
    /// SwiftData so a live-session tap always resolves — even in the window right
    /// after logging when the journal's day groups are still rebuilding and
    /// ``activeSessionCard`` hasn't matched. Anchored to the latest active dose.
    private func resolveActiveSessionID() -> UUID? {
        guard let anchor = ActiveSessionManager.shared.activeSubstanceStates.map(\.doseTimestamp).max() else { return nil }
        let lo = anchor.addingTimeInterval(-1)
        let hi = anchor.addingTimeInterval(1)
        var descriptor = FetchDescriptor<DoseEntry>(
            predicate: #Predicate { $0.timestamp >= lo && $0.timestamp <= hi },
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first?.session?.id
    }

    // MARK: - Derived State

    /// All derived journal state — the grouped buckets, color map, category
    /// facets, and tag list — lives in this observable model so recomputation
    /// happens off `body` and the view diffs a single source of truth. UI-only
    /// state (grouping, filters, collapse sets) stays on the view.
    @State private var model = JournalModel()

    @State private var collapsedSubstances: Set<String> = []
    @State private var collapsedCategories: Set<SubstanceCategory> = []

    /// First-appear gate: the initial derive paints without animation; later
    /// signature-driven re-runs animate the diff in.
    @State private var hasLoadedOnce = false

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

    /// Content fingerprint of the color assignments. Drives the recolor derive
    /// on *edits*, not just adds/removes: recoloring an existing substance
    /// mutates `hexColor` in place (`SettingsView` / `EntryDetailView` /
    /// `SessionDetailView`), so the count is unchanged and a `count`-only watch
    /// would leave the Day cards' baked-in tints stale. Hashing substance + hex
    /// closes that gap (mirrors `SessionDetailView`).
    private var colorSignature: Int {
        var hasher = Hasher()
        for color in substanceColors {
            hasher.combine(color.substance)
            hasher.combine(color.hexColor)
        }
        return hasher.finalize()
    }

    /// Resolve derived data + regroup — entries or colors changed. The derive
    /// awaits the off-main substance batch cache and resolves the visible window
    /// first (painting via `onPrefixReady`) before the tail, so a long history
    /// never blocks the first frame. `animated` slides a freshly-logged session
    /// in; the initial appear paints without animation.
    private func rebuildAll(animated: Bool) async {
        model.refreshColorMap(substanceColors)
        await model.rebuildDerived(entries: entries, colors: substanceColors) {
            applyRegroup(animated: animated)
        }
        applyRegroup(animated: animated)
    }

    private func applyRegroup(animated: Bool) {
        if animated {
            withAnimation(.smooth(duration: 0.35)) { regroup() }
        } else {
            regroup()
        }
    }

    /// A filter / search / grouping change: collapse the Day window back to the
    /// first page (a fresh result should start at the top) and re-bucket.
    private func resetWindowAndRegroup() {
        model.resetSessionWindow()
        regroup()
    }

    /// Sentinel-driven: pull in the next page of older sessions, then re-bucket
    /// with the wider window.
    private func loadMoreSessions() {
        model.growSessionWindow()
        regroup()
    }

    /// Re-bucket for the current filter/grouping selection — no re-resolve.
    private func regroup() {
        model.rebuildGroups(
            entries: entries,
            grouping: grouping,
            searchText: searchText,
            filterTags: filterTags,
            filterCategories: filterCategories,
            filterRoutes: filterRoutes,
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
        // Resolve the active-session card *once* per body pass — the lookup scans
        // sessionDays × sessions × entries, and it was previously re-run for the
        // hero card, the hero's id check, and the Day grouping separately.
        let activeCard = activeSessionCard
        let activeID = activeCard?.id
        return List {
            // Active-filter summary — the funnel's accent fill alone says *that*
            // something is filtered; this strip says *what*, chip-per-value, each
            // removable in place. It only exists while filtering, so the common
            // (unfiltered) case pays no standing row for it.
            if !isSearchSurface, hasActiveFilters {
                activeFilterBar
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }

            // The live session is promoted to a hero card above the history —
            // no "Today" header (its card is pulled from the day list below).
            if showActiveHero {
                ActiveSessionHeroCard(
                    card: activeCard,
                    states: ActiveSessionManager.shared.activeSubstanceStates,
                    colorMap: model.colorMap,
                    onTap: {
                        // Always push the session detail, like a day card does —
                        // the `.sessionDetail` sheet is reserved for notification
                        // deep links, never a tap here. Resolve the id from the
                        // matched card, falling back to a direct SwiftData lookup
                        // while the day groups are mid-rebuild (right after logging)
                        // so the tap still pushes instead of dead-ending.
                        if let id = activeID ?? resolveActiveSessionID() {
                            navigator.push(.session(id: id))
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
            case .byDay: sessionGroupedContent(activeID: activeID)
            case .bySubstance: substanceGroupedContent
            case .byCategory: categoryGroupedContent
            }
        }
        .id(grouping)
        .listStyle(.plain)
        .listSectionSpacing(.custom(2))
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .appNavigationBar("Journal", enabled: !isSearchSurface, showsOverflow: false)
        .toolbar {
            // Two controls, Files/Mail style: the funnel is the single home for
            // narrowing (tags + categories + routes), the ellipsis for everything
            // view-related (grouping thumbnails, Jump to Date, Settings, Help).
            if !isSearchSurface {
                ToolbarItem(placement: .topBarTrailing) {
                    JournalFilterMenu(
                        model: model,
                        filterTags: $filterTags,
                        filterCategories: $filterCategories,
                        filterRoutes: $filterRoutes,
                    )
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) {
                    JournalOptionsButton(grouping: $grouping) { showingCalendar = true }
                }
            }
        }
        .overlay {
            if model.filtered.isEmpty {
                emptyState
            }
        }
        // Single derive driver: runs once on appear (paints fast, no animation)
        // and re-runs whenever the entries fingerprint changes (an edit / add /
        // delete), debouncing briefly and animating the diff in. The model's
        // generation guard makes a newer run supersede an in-flight one, so the
        // overlap on first appear (when the signature also "changes" from its
        // initial value) can't corrupt state.
        .task(id: entriesSignature) {
            let isFirst = !hasLoadedOnce
            hasLoadedOnce = true
            if !isFirst {
                // Animate the diff so a newly-logged session slides in and pushes
                // the others down instead of snapping.
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
            }
            await rebuildAll(animated: !isFirst)
        }
        // Debounce the search filter: re-filtering the whole history runs on the
        // main actor, so doing it on every keystroke stalled typing. An empty
        // query (clearing search) regroups immediately. The `.task(id:)` cancels
        // the prior pending filter when the text changes again.
        .task(id: searchText) {
            if !searchText.isEmpty {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
            }
            resetWindowAndRegroup()
        }
        .onChange(of: filterTags) { resetWindowAndRegroup() }
        .onChange(of: grouping) { resetWindowAndRegroup() }
        .onChange(of: filterCategories) { resetWindowAndRegroup() }
        .onChange(of: filterRoutes) { resetWindowAndRegroup() }
        .onChange(of: colorSignature) {
            Task { await rebuildAll(animated: true) }
        }
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
        // The Day list is windowed, so an older target may not be built yet —
        // grow the window page by page until it reaches back past the target
        // (or the whole history is materialized). A deliberate calendar jump can
        // afford the rebuilds; everyday scrolling never hits this.
        while model.hasMoreSessions, (model.sessionDays.last?.date ?? .distantFuture) > target {
            model.growSessionWindow()
            regroup()
        }
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

    // MARK: - Active Filter Bar

    /// One removable chip per active filter value (tags, then categories, then
    /// routes) and a trailing Clear. Only rendered while a filter is active —
    /// the funnel menu is where filters are *applied*; this strip is where the
    /// current selection stays visible and individually dismissible.
    private var activeFilterBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(filterTags.sorted(), id: \.self) { tag in
                    filterChip(title: Text(verbatim: "#\(tag)")) {
                        filterTags.remove(tag)
                    }
                }
                ForEach(filterCategories.sorted { $0.rawValue < $1.rawValue }, id: \.self) { category in
                    filterChip(title: Text(category.displayName)) {
                        filterCategories.remove(category)
                    }
                }
                ForEach(filterRoutes.sorted { $0.rawValue < $1.rawValue }, id: \.self) { route in
                    filterChip(title: Text(route.localizedName)) {
                        filterRoutes.remove(route)
                    }
                }

                Button {
                    withAnimation(.snappy) { clearFilters() }
                } label: {
                    Text("Clear")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
    }

    private func filterChip(title: Text, remove: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy) { remove() }
        } label: {
            HStack(spacing: 5) {
                title
                Image(systemName: "xmark")
                    .font(.caption2.weight(.semibold))
                    .opacity(0.8)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.accent, in: Capsule())
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Removes this filter."))
    }

    private func clearFilters() {
        filterTags = []
        filterCategories = []
        filterRoutes = []
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
    private func sessionGroupedContent(activeID: UUID?) -> some View {
        Group {
            sessionDayRows(activeID: activeID)
            // Load-more sentinel: when the last built day scrolls into view, pull
            // in the next page of older sessions. Removed once the whole history
            // is materialized (`hasMoreSessions == false`).
            if model.hasMoreSessions {
                Color.clear
                    .frame(height: 1)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .onAppear { loadMoreSessions() }
            }
        }
    }

    private func sessionDayRows(activeID: UUID?) -> some View {
        ForEach(model.sessionDays) { day in
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
                                    .equatable()
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
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityValue(isCollapsed ? Text("Collapsed") : Text("Expanded"))
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
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityValue(isCollapsed ? Text("Collapsed") : Text("Expanded"))
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                searchText.isEmpty && !hasActiveFilters ? "No Entries" : "No Results",
                systemImage: searchText.isEmpty && !hasActiveFilters ? "pill" : "magnifyingglass",
            )
        } description: {
            Text(
                hasActiveFilters ? "Try adjusting your filters." :
                    searchText.isEmpty ? "Tap + to log your first entry." :
                    "Try a different search term.",
            )
        } actions: {
            if isSearchSurface, !searchText.isEmpty, let onSwitchToLibrary {
                Button("Search Library instead", action: onSwitchToLibrary)
                    .buttonStyle(.borderedProminent)
            }
        }
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
                        .accessibilityLabel(Text("Close"))
                }
            }
        }
    }
}

// MARK: - Toolbar Menus

/// The rows of the Journal options popover that act *after* it closes. A sheet
/// can't be presented while the popover is still up (the root is already
/// presenting), so the popover records the choice, dismisses, and the button
/// fires it once the dismissal settles.
private enum JournalMenuAction {
    case jumpToDate
    case settings
    case help
}

/// The Journal's `•••` toolbar button: a Mail-style options popover carrying the
/// grouping thumbnail picker plus Jump to Date and the app-level Settings/Help
/// (folded in from the removed ``AppOverflowMenu`` so the toolbar stays at two
/// controls). A popover rather than a `Menu` because a menu can't host the
/// custom thumbnail views — same pattern as the Tolerance screen's options menu.
private struct JournalOptionsButton: View {
    @Environment(\.appNavigator) private var navigator
    @Binding var grouping: JournalGrouping
    let onJumpToDate: () -> Void

    @State private var showsOptions = false
    @State private var pendingAction: JournalMenuAction?

    var body: some View {
        Button {
            showsOptions = true
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
        }
        .accessibilityLabel(Text("More"))
        .popover(isPresented: $showsOptions) {
            JournalOptionsMenu(grouping: $grouping) { action in
                pendingAction = action
                showsOptions = false
            }
            .presentationCompactAdaptation(.popover)
        }
        // The "your data lives here" tip points at Settings — it anchored to the
        // Journal's overflow menu before the toolbar consolidation, so it lives
        // on this button now (Journal is the landing tab; other tabs never
        // surfaced it).
        .popoverTip(SettingsDataTip(), arrowEdge: .top)
        .onChange(of: showsOptions) {
            guard !showsOptions, let action = pendingAction else { return }
            pendingAction = nil
            // Let the popover's dismissal settle before presenting a sheet — an
            // immediate present races the teardown (the root is still
            // "presenting" the popover) and gets dropped by UIKit.
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                switch action {
                case .jumpToDate: onJumpToDate()
                case .settings: present(.settings)
                case .help: present(.help)
                }
            }
        }
    }

    private func present(_ route: SheetRoute) {
        guard navigator.sheetStack.isEmpty else { return }
        navigator.present(route)
    }
}

/// The options popover content, modeled on Mail's view-options menu: the
/// grouping thumbnail picker across the top (four line-art phones with a radio
/// each), then Jump to Date, then the app-level Settings/Help. Picking a
/// grouping keeps the popover open (Mail's behavior — the list re-buckets
/// behind it); the action rows dismiss.
private struct JournalOptionsMenu: View {
    @Binding var grouping: JournalGrouping
    let onAction: (JournalMenuAction) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(JournalGrouping.allCases, id: \.self) { option in
                    groupingColumn(option)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            VStack(spacing: 0) {
                actionRow(.jumpToDate, title: Text("Jump to Date"), systemImage: "calendar")
            }
            .padding(.vertical, 4)

            Divider()

            VStack(spacing: 0) {
                actionRow(.settings, title: Text("Settings"), systemImage: "gearshape")
                actionRow(.help, title: Text("Help"), systemImage: "lifepreserver")
            }
            .padding(.vertical, 4)
        }
        .frame(width: 296)
    }

    private func groupingColumn(_ option: JournalGrouping) -> some View {
        let selected = grouping == option
        return Button {
            grouping = option
        } label: {
            VStack(spacing: 7) {
                MenuPhoneThumbnail(selected: selected, sketch: JournalGroupingArt.sketch(for: option))
                    .frame(width: 56, height: 115) // aspect 0.486 — the iPhone 17 bezel
                Text(option.displayName)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(.primary)
                radio(selected: selected)
                    .frame(width: 18, height: 18)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(option.displayName))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func radio(selected: Bool) -> some View {
        ZStack {
            if selected {
                Circle().fill(Theme.accent)
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Circle().strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1.5)
            }
        }
    }

    private func actionRow(_ action: JournalMenuAction, title: Text, systemImage: String) -> some View {
        Button {
            onAction(action)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 24)
                title
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The groupings' screen sketches for ``MenuPhoneThumbnail`` — each mode's list
/// shape reduced to line art: day-grouped, flat-chronological, grouped by a
/// substance dot, grouped by a category tile.
private enum JournalGroupingArt {
    static func sketch(for grouping: JournalGrouping) -> (GraphicsContext, CGRect, Color) -> Void {
        switch grouping {
        case .byDay: drawDayGroups
        case .recent: drawFlatRows
        case .bySubstance: drawDotGroups
        case .byCategory: drawTileGroups
        }
    }

    /// A solid header bar, then indented line rows — twice (two "days").
    private static func drawDayGroups(_ context: GraphicsContext, in rect: CGRect, color: Color) {
        let unit = rect.height / 24
        for groupTop in [rect.minY, rect.minY + unit * 13] {
            let header = CGRect(x: rect.minX, y: groupTop, width: rect.width * 0.55, height: unit * 2)
            context.fill(Path(roundedRect: header, cornerRadius: unit), with: .color(color))
            for row in 0 ..< 2 {
                let y = groupTop + unit * (4.5 + CGFloat(row) * 3.5)
                line(context, x: rect.minX, y: y, width: rect.width, height: unit * 1.6, color: color)
            }
        }
    }

    /// Five uniform rows — the flat chronological list.
    private static func drawFlatRows(_ context: GraphicsContext, in rect: CGRect, color: Color) {
        let unit = rect.height / 24
        for row in 0 ..< 5 {
            let y = rect.minY + unit * CGFloat(row) * 5
            line(context, x: rect.minX, y: y, width: rect.width, height: unit * 1.6, color: color)
            line(context, x: rect.minX, y: y + unit * 2.2, width: rect.width * 0.55, height: unit * 1.1, color: color.opacity(0.55))
        }
    }

    /// A leading dot + header line, then indented rows — twice (two substances).
    private static func drawDotGroups(_ context: GraphicsContext, in rect: CGRect, color: Color) {
        let unit = rect.height / 24
        let dot = unit * 2.4
        for groupTop in [rect.minY, rect.minY + unit * 13] {
            context.fill(
                Path(ellipseIn: CGRect(x: rect.minX, y: groupTop, width: dot, height: dot)),
                with: .color(color),
            )
            line(context, x: rect.minX + dot * 1.5, y: groupTop + (dot - unit * 1.6) / 2, width: rect.width - dot * 1.5, height: unit * 1.6, color: color)
            for row in 0 ..< 2 {
                let y = groupTop + unit * (4.5 + CGFloat(row) * 3.5)
                line(context, x: rect.minX + dot * 1.5, y: y, width: rect.width - dot * 1.5, height: unit * 1.4, color: color.opacity(0.55))
            }
        }
    }

    /// A leading rounded tile + header line, then indented rows — twice.
    private static func drawTileGroups(_ context: GraphicsContext, in rect: CGRect, color: Color) {
        let unit = rect.height / 24
        let tile = unit * 2.4
        for groupTop in [rect.minY, rect.minY + unit * 13] {
            context.fill(
                Path(roundedRect: CGRect(x: rect.minX, y: groupTop, width: tile, height: tile), cornerRadius: tile * 0.3),
                with: .color(color),
            )
            line(context, x: rect.minX + tile * 1.5, y: groupTop + (tile - unit * 1.6) / 2, width: rect.width - tile * 1.5, height: unit * 1.6, color: color)
            for row in 0 ..< 2 {
                let y = groupTop + unit * (4.5 + CGFloat(row) * 3.5)
                line(context, x: rect.minX + tile * 1.5, y: y, width: rect.width - tile * 1.5, height: unit * 1.4, color: color.opacity(0.55))
            }
        }
    }

    private static func line(_ context: GraphicsContext, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, color: Color) {
        context.fill(
            Path(roundedRect: CGRect(x: x, y: y, width: width, height: height), cornerRadius: height / 2),
            with: .color(color),
        )
    }
}

/// The Journal's filter toolbar menu — the single home for narrowing the list.
/// Reads the model's available facet values (only what's actually present in
/// the journal) and toggles the parent's filter sets through the bindings (the
/// parent's `onChange(of:)` drives the regroup + Day-window reset). Tags and
/// categories are multi-select checkmark sections; routes live one level down
/// so the top level stays short.
private struct JournalFilterMenu: View {
    let model: JournalModel
    @Binding var filterTags: Set<String>
    @Binding var filterCategories: Set<SubstanceCategory>
    @Binding var filterRoutes: Set<RouteOfAdministration>

    private var hasActiveFilters: Bool {
        !filterTags.isEmpty || !filterCategories.isEmpty || !filterRoutes.isEmpty
    }

    /// Spoken filter state — the active/inactive cue is otherwise tint-only.
    private var filterValue: Text {
        guard hasActiveFilters else { return Text("Off") }
        let parts = filterTags.sorted().map { "#\($0)" }
            + filterCategories.map { String(localized: $0.displayName) }.sorted()
            + filterRoutes.map { String(localized: $0.localizedName) }.sorted()
        return Text(verbatim: parts.joined(separator: ", "))
    }

    var body: some View {
        // Active state: an accent-filled circle nested inside the item's platter,
        // Phone-app style. A prominent `Menu` can't replace the platter the way a
        // prominent `Button` does (it renders via the generic bordered path), and
        // the platter's own tint API isn't public — so the filled circle is sized
        // *down* (regular control size + a small label frame) to sit within the
        // platter ring instead of fighting it.
        if hasActiveFilters {
            Menu {
                menuContent
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 20, height: 20)
            }
            .menuStyle(.button)
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .controlSize(.regular)
            .tint(Theme.accent)
            .accessibilityLabel(Text("Filter"))
            .accessibilityValue(filterValue)
        } else {
            Menu {
                menuContent
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 17, weight: .semibold))
            }
            .accessibilityLabel(Text("Filter"))
            .accessibilityValue(filterValue)
        }
    }

    /// Shared menu body for both filter button states. Each facet is its own
    /// drill-in submenu (substance type, tags, route of administration) whose
    /// rows are checkmark toggles — the top level stays a short list of facets,
    /// and the label carries a `(count)` badge so an applied filter is visible
    /// without opening the submenu. No time window — the list already shows
    /// every day in order, and the calendar *scrolls* to a day instead.
    @ViewBuilder
    private var menuContent: some View {
        Section {
            if !model.categories.isEmpty {
                Menu {
                    ForEach(model.categories, id: \.self) { category in
                        toggleRow(
                            isOn: filterCategories.contains(category),
                            title: Text(category.displayName),
                            icon: category.icon,
                        ) { toggle(category, in: $filterCategories) }
                    }
                } label: {
                    facetLabel("Category", systemImage: "square.grid.2x2", count: filterCategories.count)
                }
            }

            if !model.tags.isEmpty {
                Menu {
                    ForEach(model.tags, id: \.self) { tag in
                        toggleRow(
                            isOn: filterTags.contains(tag),
                            title: Text(verbatim: "#\(tag)"),
                        ) { toggle(tag, in: $filterTags) }
                    }
                } label: {
                    facetLabel("Tags", systemImage: "number", count: filterTags.count)
                }
            }

            if model.routes.count > 1 {
                Menu {
                    ForEach(model.routes, id: \.self) { route in
                        toggleRow(
                            isOn: filterRoutes.contains(route),
                            title: Text(route.localizedName),
                        ) { toggle(route, in: $filterRoutes) }
                    }
                } label: {
                    facetLabel("Route", systemImage: "point.topleft.down.to.point.bottomright.curvepath", count: filterRoutes.count)
                }
            }
        }

        if hasActiveFilters {
            Section {
                Button("Clear Filters", role: .destructive) {
                    filterTags = []
                    filterCategories = []
                    filterRoutes = []
                }
            }
        }
    }

    /// A submenu's title with a `(count)` suffix once that facet has selections,
    /// so the collapsed top level advertises what's applied. The facet name stays
    /// localized; the numeric suffix is universal.
    private func facetLabel(_ title: LocalizedStringResource, systemImage: String, count: Int) -> some View {
        Label {
            if count > 0 {
                Text(verbatim: "\(String(localized: title)) (\(count))")
            } else {
                Text(title)
            }
        } icon: {
            Image(systemName: systemImage)
        }
    }

    /// A checkmark toggle row inside a facet submenu. When `icon` is supplied it
    /// shows in place of the checkmark while unselected (matching the category
    /// rows' glyphs); otherwise the row is glyph-less until checked.
    private func toggleRow(isOn: Bool, title: Text, icon: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label {
                title
            } icon: {
                if isOn {
                    Image(systemName: "checkmark")
                } else if let icon {
                    Image(systemName: icon)
                }
            }
        }
    }

    private func toggle<Value: Hashable>(_ value: Value, in set: Binding<Set<Value>>) {
        if set.wrappedValue.contains(value) {
            set.wrappedValue.remove(value)
        } else {
            set.wrappedValue.insert(value)
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
                Text(CustomSubstanceStore.shared.displayName(for: entry.substance))
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
                .accessibilityLabel(Text("Previous month"))
                Spacer()
                Text(selectedMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.headline)
                Spacer()
                Button {
                    selectedMonth = calendar.date(byAdding: .month, value: 1, to: selectedMonth)!
                } label: {
                    Image(systemName: "chevron.right")
                }
                .accessibilityLabel(Text("Next month"))
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
                        .accessibilityLabel(dayAccessibilityLabel(for: date))
                        .accessibilityValue(count > 0 ? Text("^[\(count) dose](inflect: true)") : Text(verbatim: ""))
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

    /// "July 15" — plus "Today", the accent halo's only spoken equivalent.
    private func dayAccessibilityLabel(for date: Date) -> Text {
        let name = date.formatted(.dateTime.month(.wide).day())
        return calendar.isDateInToday(date) ? Text("\(name), Today") : Text(verbatim: name)
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
