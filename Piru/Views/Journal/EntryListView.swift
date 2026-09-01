import SwiftData
import SwiftUI
import TipKit

// MARK: - Journal Grouping

enum JournalGrouping: String, CaseIterable {
    // Order drives the grouping menu; Days is the default so it leads.
    case byDay = "Days"
    case timeline = "Timeline"
    case recent = "Recent"
    case bySubstance = "Substance"
    case byCategory = "Category"

    var displayName: LocalizedStringResource {
        switch self {
        case .recent: "Recent"
        case .byDay: "Days"
        case .timeline: "Timeline"
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

    @AppStorage("journalGrouping", store: UserDefaults(suiteName: "group.dev.yumeji.piru")) private var grouping: JournalGrouping = .byDay
    @State private var showingCalendar = false

    /// The Timeline grouping's day layouts — built lazily, only while that
    /// grouping is selected. Shares the zoom preference with the pushed
    /// timeline screen.
    @State private var timelineModel = UnifiedTimelineModel()
    @AppStorage("timelineZoom", store: UserDefaults(suiteName: "group.dev.yumeji.piru")) private var timelineZoom = 1.0
    @AppStorage("timelineCompression", store: UserDefaults(suiteName: "group.dev.yumeji.piru")) private var timelineCompression = true
    @AppStorage("timelinePKCurves", store: UserDefaults(suiteName: "group.dev.yumeji.piru")) private var timelinePKCurves = false

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
    /// not part of the filtered history. The Timeline grouping already opens on
    /// the live strip, which carries the same doses and phases, so the card is
    /// omitted there rather than shown twice.
    private var showActiveHero: Bool {
        !isSearchSurface && grouping != .timeline && ActiveSessionManager.shared.hasActiveSession
    }

    /// The day-list card representing the currently-active session — the cluster
    /// the user is in right now, matched by the *most-recent* active dose. (Using
    /// the latest rather than the earliest keeps the badge on the real current
    /// session even when an older long-acting dose in a separate, overlapping
    /// session is still pharmacologically active.) The day list badges this
    /// card's row as "Active".
    private func activeSessionCard(states: [ActiveSubstanceState]) -> SessionCard? {
        guard showActiveHero, let anchor = states.map(\.doseTimestamp).max() else { return nil }
        for day in model.sessionDays {
            for card in day.sessions
                where card.entries.contains(where: { abs($0.timestamp.timeIntervalSince(anchor)) < 1 }) {
                return card
            }
        }
        return nil
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
    /// revision-driven re-runs animate the diff in.
    @State private var hasLoadedOnce = false

    /// Set once the first derive has actually completed (`hasLoadedOnce` flips
    /// at the *start* of that task). Until then, the search task's regroup
    /// would bucket against an empty `derived` and paint every day card
    /// graph-less — the cold-launch no-graphs flash.
    @State private var hasDerivedOnce = false

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
            revision: DoseLogService.shared.revision,
        )
    }

    // MARK: - Body

    var body: some View {
        ScrollViewReader { proxy in
            list(proxy: proxy)
        }
    }

    private func list(proxy: ScrollViewProxy) -> some View {
        // Resolve the active states and the active session's card id *once*
        // per body pass — building the states runs a substance resolve per
        // active dose, and the card lookup scans sessionDays × sessions ×
        // entries; the hero card and the day list's "Active" badge share them.
        let activeStates = isSearchSurface ? [] : ActiveSessionManager.shared.activeSubstanceStates
        let activeID = activeSessionCard(states: activeStates)?.id
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

            // The daily meds front door — today's checklist, tap to log
            // (Specs/meds-reminders-redesign.md). Renders nothing while the
            // user has no meds, so a recreational-only journal never sees it.
            if !isSearchSurface {
                MyMedsCard()
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 10, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }

            // The state card: what's active right now, as a compact live
            // status (dose · ROA · phase · countdown). Tapping opens *today's
            // session* — the app is organized around sessions, so this is the
            // door to the session detail, not a separate timeline surface. The
            // feed reads plan (My Meds) → state (Active Now) → log (History).
            if showActiveHero {
                ActiveNowCard(
                    states: activeStates,
                    entries: entries,
                    colors: substanceColors,
                    colorMap: model.colorMap,
                    onTap: {
                        navigator.push(.timeline)
                    },
                )
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 10, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            // No "History" label — the plan/state cards sit above, and the
            // dated day headers below (Today, Yesterday, July 20…) already
            // read as the record. The header was redundant chrome.

            // Main content
            switch grouping {
            case .recent: recentContent
            case .byDay: sessionGroupedContent(activeID: activeID)
            case .timeline: timelineContent
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
            // Gate the empty state on the first derive having finished: on a
            // cold launch the initial rebuild awaits the substance-store
            // warm-up, and flashing "No Entries" at a user who has entries
            // reads as a blink of data loss. Until then, a spinner.
            if model.filtered.isEmpty {
                if hasDerivedOnce {
                    emptyState
                } else {
                    ProgressView()
                }
            }
        }
        // Single derive driver: runs once on appear (paints fast, no animation)
        // and re-runs whenever the dose log commits a change (an edit / add /
        // delete — every mutation path bumps `DoseLogService.revision`),
        // debouncing briefly and animating the diff in. Keying off the one
        // observed Int — instead of hashing every entry's fields in `body` —
        // keeps this view from subscribing to every property of every dose.
        // The model's generation guard makes a newer run supersede an in-flight
        // one, so the overlap on first appear can't corrupt state.
        .task(id: DoseLogService.shared.revision) {
            let isFirst = !hasLoadedOnce
            hasLoadedOnce = true
            if !isFirst {
                // Animate the diff so a newly-logged session slides in and pushes
                // the others down instead of snapping.
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
            }
            await rebuildAll(animated: !isFirst)
            hasDerivedOnce = true
        }
        // Debounce the search filter: re-filtering the whole history runs on the
        // main actor, so doing it on every keystroke stalled typing. An empty
        // query (clearing search) regroups immediately. The `.task(id:)` cancels
        // the prior pending filter when the text changes again.
        .task(id: searchText) {
            // First appear: the derive task owns the initial regroup, and it
            // regroups with the live `searchText` when it lands — bucketing
            // now would run against an empty `derived`.
            guard hasDerivedOnce else { return }
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
        // The Timeline grouping's layouts. Waits a beat so the filter/search
        // regroup above lands first — the timeline renders `model.filtered`
        // whenever a filter or search is active, the raw log otherwise.
        .task(id: timelineRebuildKey) {
            guard grouping == .timeline else { return }
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            let source = (hasActiveFilters || !searchText.isEmpty) ? model.filtered : entries
            await timelineModel.rebuild(
                entries: source,
                colors: substanceColors,
                colorMap: substanceColors.colorMap,
                revision: timelineRebuildKey.hashValue,
                zoom: timelineZoom,
                compressGaps: timelineCompression,
                pkCurves: timelinePKCurves,
            )
        }
        .onChange(of: colorSignature) {
            Task { await rebuildAll(animated: true) }
        }
        .sheet(isPresented: $showingCalendar) {
            calendarSheet(proxy: proxy)
                .presentationDetents([.medium])
                .presentationBackground(.regularMaterial)
        }
    }

    private var timelineRebuildKey: String {
        "\(grouping.rawValue)|\(DoseLogService.shared.revision)|\(timelineZoom)|\(timelineCompression)|\(timelinePKCurves)|\(searchText)|\(filterTags.hashValue)|\(filterCategories.hashValue)|\(filterRoutes.hashValue)"
    }

    /// The Timeline grouping rendered as list rows — the same continuous
    /// strip the pushed timeline screen draws (day pills float over each
    /// slice), with the meds/Active Now cards above.
    private var timelineContent: some View {
        ForEach(timelineModel.days) { day in
            TimelineDayContent(
                day: day,
                onEntryTap: { entry in
                    navigator.push(.entry(timestamp: entry.timestamp, id: entry.id))
                },
                onSessionTap: { sessionID in
                    navigator.push(.session(id: sessionID))
                },
            )
            .id(day.date)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
    }

    /// Scroll the day list to the selected calendar date. Switches to the Days
    /// grouping if needed (the Timeline grouping scrolls in place), then
    /// targets the nearest rendered day at or before the tapped date (the
    /// list is newest-first), falling back to the oldest.
    private func jump(to date: Date, proxy: ScrollViewProxy) {
        if grouping == .timeline {
            let target = Calendar.current.startOfDay(for: date)
            Task {
                try? await Task.sleep(for: .milliseconds(350))
                guard let day = timelineModel.days.first(where: { $0.date <= target })
                    ?? timelineModel.days.last else { return }
                withAnimation {
                    proxy.scrollTo(day.date, anchor: .top)
                }
            }
            return
        }
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
        // Only days that actually put rows on screen are valid scroll targets —
        // a day holding just the (excluded) live session renders nothing.
        let activeID = activeSessionCard(states: ActiveSessionManager.shared.activeSubstanceStates)?.id
        let rendered = model.sessionDays.filter { day in day.sessions.contains { $0.id != activeID } }
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
                    .accessibilityHidden(true)
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
    @ViewBuilder
    private func sessionGroupedContent(activeID: UUID?) -> some View {
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

    private func sessionDayRows(activeID: UUID?) -> some View {
        ForEach(model.sessionDays) { day in
            // History is the *completed* record: the live session lives only in
            // the Active Now card until it ends, then enters the log. So drop
            // it here — otherwise a single-dose day showed the exact same dose
            // and curve twice (Active Now + a "Today" row). A day left empty by
            // that removal renders nothing (no orphan header); the session
            // reappears here once it wears off.
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
                                .foregroundStyle(group.category.labelColor)
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
enum JournalMenuAction {
    case jumpToDate
    case myMeds
    case settings
    case help
}

/// The groupings' screen sketches for ``MenuPhoneThumbnail`` — each mode's list
/// shape reduced to line art matching the real journal layouts: day-grouped
/// sessions in rounded cards, flat chronological rows, collapsible substance
/// sections with dots, collapsible category sections with icon tiles.
enum JournalGroupingArt {
    static func sketch(for grouping: JournalGrouping) -> (GraphicsContext, CGRect, Color) -> Void {
        switch grouping {
        case .byDay: drawDayGroups
        case .timeline: drawTimelineSpine
        case .recent: drawFlatRows
        case .bySubstance: drawDotGroups
        case .byCategory: drawTileGroups
        }
    }

    /// A vertical axis on the left with dose dots, connector lines reaching
    /// right into rounded card rows — the timeline's three-column shape.
    private static func drawTimelineSpine(_ context: GraphicsContext, in rect: CGRect, color: Color) {
        let unit = rect.height / 26
        let axisX = rect.minX + unit * 3
        // The time axis
        var axis = Path()
        axis.move(to: CGPoint(x: axisX, y: rect.minY))
        axis.addLine(to: CGPoint(x: axisX, y: rect.maxY))
        context.stroke(axis, with: .color(color.opacity(0.35)), lineWidth: 0.8)
        // Dose dots + connectors + card rows
        let cardX = rect.minX + unit * 7
        let cardW = rect.maxX - cardX
        for (index, dotY) in [rect.minY + unit * 3, rect.minY + unit * 11, rect.minY + unit * 20].enumerated() {
            let cardY = dotY + (index == 1 ? unit * 2.5 : 0)
            context.fill(
                Path(ellipseIn: CGRect(x: axisX - unit, y: dotY - unit, width: unit * 2, height: unit * 2)),
                with: .color(color),
            )
            var connector = Path()
            connector.move(to: CGPoint(x: axisX + unit, y: dotY))
            connector.addLine(to: CGPoint(x: cardX, y: cardY + unit * 2))
            context.stroke(connector, with: .color(color.opacity(0.4)), lineWidth: 0.6)
            let cardRect = CGRect(x: cardX, y: cardY, width: cardW, height: unit * 4)
            context.stroke(Path(roundedRect: cardRect, cornerRadius: unit), with: .color(color.opacity(0.5)), lineWidth: 0.6)
            line(context, x: cardX + unit, y: cardY + unit * 1.2, width: cardW * 0.5, height: unit * 0.9, color: color.opacity(0.7))
        }
    }

    /// A thin header line (date), then a rounded card containing session rows
    /// separated by hairlines — twice (two "days"). Mirrors the real layout
    /// where each day is a date header + a `.themeCard()`
    /// containing `SessionCardView` rows.
    private static func drawDayGroups(_ context: GraphicsContext, in rect: CGRect, color: Color) {
        let unit = rect.height / 26
        for groupTop in [rect.minY, rect.minY + unit * 14] {
            // Date header ("Aug 28 Wed")
            line(context, x: rect.minX + unit, y: groupTop, width: rect.width * 0.5, height: unit * 1.2, color: color)
            // Rounded card container
            let cardTop = groupTop + unit * 2.2
            let cardHeight = unit * 9
            let cardRadius = unit * 1.4
            let cardRect = CGRect(x: rect.minX, y: cardTop, width: rect.width, height: cardHeight)
            context.stroke(Path(roundedRect: cardRect, cornerRadius: cardRadius), with: .color(color.opacity(0.3)), lineWidth: 0.5)
            // Session rows inside the card
            let inset = unit * 1.2
            for row in 0 ..< 2 {
                let rowY = cardTop + inset + CGFloat(row) * (cardHeight - inset * 2) * 0.5
                line(context, x: rect.minX + inset, y: rowY, width: rect.width - inset * 2, height: unit * 1.2, color: color.opacity(0.7))
                line(context, x: rect.minX + inset, y: rowY + unit * 1.8, width: (rect.width - inset * 2) * 0.65, height: unit * 0.9, color: color.opacity(0.35))
            }
            // Hairline divider between rows
            let divY = cardTop + cardHeight * 0.5
            line(context, x: rect.minX + inset, y: divY, width: rect.width - inset * 2, height: 0.5, color: color.opacity(0.15))
        }
    }

    /// Individual entry rows with spacing — the flat chronological list. Each
    /// row has a title line and a shorter detail line (dose + time), matching
    /// the real entry rows.
    private static func drawFlatRows(_ context: GraphicsContext, in rect: CGRect, color: Color) {
        let unit = rect.height / 26
        for row in 0 ..< 4 {
            let y = rect.minY + unit * CGFloat(row) * 6.2
            // Substance name
            line(context, x: rect.minX, y: y, width: rect.width * 0.6, height: unit * 1.4, color: color)
            // Dose + route
            line(context, x: rect.minX, y: y + unit * 2, width: rect.width * 0.35, height: unit * 1, color: color.opacity(0.5))
            // Timestamp (right-aligned)
            line(context, x: rect.maxX - rect.width * 0.25, y: y + unit * 2, width: rect.width * 0.25, height: unit * 1, color: color.opacity(0.35))
        }
    }

    /// A leading dot + header line with a trailing chevron, then indented entry
    /// rows — twice (two substance sections). The dot represents the substance
    /// color, the chevron the expand/collapse toggle.
    private static func drawDotGroups(_ context: GraphicsContext, in rect: CGRect, color: Color) {
        let unit = rect.height / 26
        let dot = unit * 2
        for groupTop in [rect.minY, rect.minY + unit * 14] {
            // Substance dot
            context.fill(
                Path(ellipseIn: CGRect(x: rect.minX, y: groupTop, width: dot, height: dot)),
                with: .color(color),
            )
            // Substance name
            line(context, x: rect.minX + dot * 1.4, y: groupTop + (dot - unit * 1.4) / 2, width: rect.width * 0.5, height: unit * 1.4, color: color)
            // Chevron placeholder (right side)
            let chevSize = unit * 1.2
            line(context, x: rect.maxX - chevSize, y: groupTop + (dot - chevSize) / 2, width: chevSize, height: chevSize, color: color.opacity(0.3))
            // Indented entry rows
            let indent = dot * 1.4
            for row in 0 ..< 2 {
                let y = groupTop + unit * (4 + CGFloat(row) * 3.5)
                line(context, x: rect.minX + indent, y: y, width: rect.width - indent, height: unit * 1.2, color: color.opacity(0.5))
                line(context, x: rect.minX + indent, y: y + unit * 1.6, width: (rect.width - indent) * 0.4, height: unit * 0.8, color: color.opacity(0.25))
            }
        }
    }

    /// A leading rounded icon tile + header line with a trailing chevron, then
    /// indented entry rows — twice. The tile represents the category icon.
    private static func drawTileGroups(_ context: GraphicsContext, in rect: CGRect, color: Color) {
        let unit = rect.height / 26
        let tile = unit * 2
        for groupTop in [rect.minY, rect.minY + unit * 14] {
            // Category icon tile
            context.fill(
                Path(roundedRect: CGRect(x: rect.minX, y: groupTop, width: tile, height: tile), cornerRadius: tile * 0.25),
                with: .color(color),
            )
            // Category name
            line(context, x: rect.minX + tile * 1.4, y: groupTop + (tile - unit * 1.4) / 2, width: rect.width * 0.45, height: unit * 1.4, color: color)
            // Count bubble
            line(context, x: rect.maxX - unit * 3, y: groupTop + (tile - unit * 1.2) / 2, width: unit * 3, height: unit * 1.2, color: color.opacity(0.3))
            // Indented entry rows
            let indent = tile * 1.4
            for row in 0 ..< 2 {
                let y = groupTop + unit * (4 + CGFloat(row) * 3.5)
                line(context, x: rect.minX + indent, y: y, width: rect.width - indent, height: unit * 1.2, color: color.opacity(0.5))
                line(context, x: rect.minX + indent, y: y + unit * 1.6, width: (rect.width - indent) * 0.4, height: unit * 0.8, color: color.opacity(0.25))
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
                .accessibilityHidden(true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard()
        .contentShape(Theme.cardShape)
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
