import SwiftData
import SwiftUI
import TipKit

// MARK: - Journal Grouping

/// The Journal's three views. `grouped` buckets entries under a secondary key
/// (``JournalGroupKey``) picked in the options popover.
enum JournalGrouping: String, CaseIterable {
    // Order drives the grouping menu; Days is the default so it leads.
    case byDay = "Days"
    case timeline = "Timeline"
    case grouped = "Grouped"

    var displayName: LocalizedStringResource {
        switch self {
        case .byDay: "Days"
        case .timeline: "Timeline"
        case .grouped: "Grouped"
        }
    }
}

/// What the Grouped view buckets by — the popover's segmented control under
/// the thumbnails. Remembered across launches.
enum JournalGroupKey: String, CaseIterable {
    case substance = "Substance"
    case category = "Category"

    var displayName: LocalizedStringResource {
        switch self {
        case .substance: "By Substance"
        case .category: "By Category"
        }
    }
}

/// Rewrites a persisted grouping from the five-thumbnail picker into the
/// three-view one, so nobody's saved choice snaps back to Days. Recent was the
/// Timeline's bubbles without the hour axis, so it becomes Timeline with the
/// axis off; Substance and Category become Grouped with the matching key.
enum JournalGroupingMigration {
    static let groupingKey = "journalGrouping"
    static let groupKeyKey = "journalGroupKey"
    static let timelineAxisKey = "timelineShowsAxis"

    enum Outcome: Equatable {
        case unchanged
        case recentToTimeline
        case substanceToGrouped
        case categoryToGrouped
    }

    @discardableResult
    static func migrate(in defaults: UserDefaults) -> Outcome {
        switch defaults.string(forKey: groupingKey) {
        case "Recent":
            defaults.set(JournalGrouping.timeline.rawValue, forKey: groupingKey)
            defaults.set(false, forKey: timelineAxisKey)
            return .recentToTimeline
        case "Substance":
            defaults.set(JournalGrouping.grouped.rawValue, forKey: groupingKey)
            defaults.set(JournalGroupKey.substance.rawValue, forKey: groupKeyKey)
            return .substanceToGrouped
        case "Category":
            defaults.set(JournalGrouping.grouped.rawValue, forKey: groupingKey)
            defaults.set(JournalGroupKey.category.rawValue, forKey: groupKeyKey)
            return .categoryToGrouped
        default:
            return .unchanged
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
    @AppStorage("journalGroupKey", store: UserDefaults(suiteName: "group.dev.yumeji.piru")) private var groupKey: JournalGroupKey = .substance
    @State private var showingCalendar = false

    /// Rename / Move Doses / Share targets set from a session card's context
    /// menu; the matching alert and sheets hang off the list.
    @State private var cardActions = SessionCardActionModel()

    /// Runs once per process, ahead of the first `@AppStorage` read above — a
    /// raw value the enum no longer has would otherwise silently read as Days.
    private static let persistedGroupingMigrated: Void = {
        if let defaults = UserDefaults(suiteName: "group.dev.yumeji.piru") {
            JournalGroupingMigration.migrate(in: defaults)
        }
    }()

    init(searchText: Binding<String>, isSearchSurface: Bool = false, onSwitchToLibrary: (() -> Void)? = nil) {
        _ = Self.persistedGroupingMigrated
        _searchText = searchText
        self.isSearchSurface = isSearchSurface
        self.onSwitchToLibrary = onSwitchToLibrary
    }

    /// The Timeline grouping's day layouts — built lazily, only while that
    /// grouping is selected. Shares the zoom preference with the pushed
    /// timeline screen.
    @State private var timelineModel = UnifiedTimelineModel()

    /// The strip's display options plus the day cards' redose stacking, read
    /// live from the app-group defaults the rest of the app writes.
    private var prefs = TimelinePreferences()

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

    /// All journal state that isn't a persisted preference — the grouped
    /// buckets, color map, category facets, tag list, the funnel's facet
    /// selection, and which Grouped sections are folded shut — lives in this
    /// observable model so recomputation happens off `body` and the view diffs a
    /// single source of truth.
    @State private var model = JournalModel()

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
        model.regroup(
            entries: entries,
            grouping: grouping,
            groupKey: groupKey,
            searchText: searchText,
            stackRedoses: prefs.stackRedoses,
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
        @Bindable var model = self.model
        return List {
            // Active-filter summary — the funnel's accent fill alone says *that*
            // something is filtered; this strip says *what*, chip-per-value, each
            // removable in place. It only exists while filtering, so the common
            // (unfiltered) case pays no standing row for it.
            if !isSearchSurface, model.hasActiveFilters {
                JournalActiveFilterBar(
                    tags: $model.filterTags,
                    categories: $model.filterCategories,
                    routes: $model.filterRoutes,
                    onClear: { model.clearFilters() },
                )
                .listRowInsets(.rowFlush)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            // The daily meds front door — today's checklist, tap to log
            // (Specs/meds-reminders-redesign.md). Renders nothing while the
            // user has no meds, so a recreational-only journal never sees it.
            if !isSearchSurface {
                MyMedsCard()
                    .listRowInsets(.rowStandard)
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
                .listRowInsets(.rowStandard)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            // No "History" label — the plan/state cards sit above, and the
            // dated day headers below (Today, Yesterday, July 20…) already
            // read as the record. The header was redundant chrome.

            // Main content
            switch grouping {
            case .byDay: sessionGroupedContent(activeID: activeID)
            case .timeline: timelineContent
            case .grouped:
                switch groupKey {
                case .substance: JournalSubstanceSections(model: model)
                case .category: JournalCategorySections(model: model)
                }
            }
        }
        .id(listIdentity)
        .listStyle(.plain)
        .listSectionSpacing(.custom(2))
        .themedPage()
        .appNavigationBar("Journal", enabled: !isSearchSurface, showsOverflow: false)
        .toolbar {
            // Two controls, Files/Mail style: the funnel is the single home for
            // narrowing (tags + categories + routes), the ellipsis for everything
            // view-related (grouping thumbnails, Jump to Date, Settings, Help).
            // The Timeline grouping adds a third, leading them: the strip's
            // display options.
            if !isSearchSurface {
                if grouping == .timeline {
                    ToolbarItem(placement: .topBarTrailing) {
                        JournalTimelineOptionsButton(
                            zoom: prefs.$zoom,
                            compressGaps: prefs.$compressGaps,
                            pkCurves: prefs.$pkCurves,
                            showsAxis: prefs.$showsAxis,
                            bubbleStyle: prefs.$bubbleStyle,
                        )
                    }
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    JournalFilterMenu(
                        model: model,
                        filterTags: $model.filterTags,
                        filterCategories: $model.filterCategories,
                        filterRoutes: $model.filterRoutes,
                    )
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) {
                    JournalOptionsButton(grouping: $grouping, groupKey: $groupKey) { showingCalendar = true }
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
        .onChange(of: grouping) { resetWindowAndRegroup() }
        .onChange(of: groupKey) { resetWindowAndRegroup() }
        .onChange(of: model.filterSignature) { resetWindowAndRegroup() }
        // The Timeline grouping's layouts. Waits a beat so the filter/search
        // regroup above lands first — the timeline renders `model.filtered`
        // whenever a filter or search is active, the raw log otherwise.
        .task(id: timelineRebuildKey) {
            guard grouping == .timeline else { return }
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            let source = (model.hasActiveFilters || !searchText.isEmpty) ? model.filtered : entries
            await timelineModel.rebuild(
                entries: source,
                colors: substanceColors,
                colorMap: substanceColors.colorMap,
                revision: timelineRebuildKey.hashValue,
                zoom: prefs.zoom,
                compressGaps: prefs.compressGaps,
                pkCurves: prefs.pkCurves,
                showsAxis: prefs.showsAxis,
                bubbleStyle: prefs.bubbleStyle,
                showsVitals: prefs.showsVitals,
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
        .sessionCardActions(cardActions, colors: substanceColors)
    }

    /// The List is recreated (scroll reset, fresh rows) when the view changes;
    /// the Grouped key is part of that identity, the other views ignore it.
    private var listIdentity: String {
        grouping == .grouped ? "\(grouping.rawValue)|\(groupKey.rawValue)" : grouping.rawValue
    }

    private var timelineRebuildKey: String {
        "\(grouping.rawValue)|\(DoseLogService.shared.revision)|\(prefs.layoutSignature)|\(searchText)|\(model.filterSignature)"
    }

    /// The Timeline grouping rendered as list rows — the same continuous
    /// strip the pushed timeline screen draws (day pills float over each
    /// slice), with the meds/Active Now cards above; the strip's display
    /// options live in the toolbar (``JournalTimelineOptionsButton``).
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
            .listRowInsets(.rowFlush)
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

    // MARK: - Session Grouped Content

    /// Sessions grouped under day headers — the Journal's primary view. Each day
    /// is a `Section`; its rows are the sessions that started that day, newest
    /// first. A maintenance session (only background meds) renders as a compact
    /// row; everything else is a full card with a mini per-session timeline.
    @ViewBuilder
    private func sessionGroupedContent(activeID: UUID?) -> some View {
        JournalDaySections(
            days: model.sessionDays,
            colorMap: model.colorMap,
            activeID: activeID,
            actions: cardActions,
        )
        // Load-more sentinel: when the last built day scrolls into view, pull
        // in the next page of older sessions. Removed once the whole history
        // is materialized (`hasMoreSessions == false`).
        if model.hasMoreSessions {
            Color.clear
                .frame(height: 1)
                .listRowInsets(.rowFlush)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .onAppear { loadMoreSessions() }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                searchText.isEmpty && !model.hasActiveFilters ? "No Entries" : "No Results",
                systemImage: searchText.isEmpty && !model.hasActiveFilters ? "pill" : "magnifyingglass",
            )
        } description: {
            Text(
                model.hasActiveFilters ? "Try adjusting your filters." :
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
