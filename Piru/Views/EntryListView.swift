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

    // Filter state — category facets, plus an optional single day from the
    // calendar. (Substance and free date-range filtering were dropped:
    // substance duplicates Search, and a chronological day list makes time
    // windows pointless.)
    @State private var filterCategories: Set<SubstanceCategory> = []
    @State private var filterDay: Date? = nil

    private var hasActiveFilters: Bool {
        !filterCategories.isEmpty || filterDay != nil
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
        }
        return hasher.finalize()
    }

    /// Resolve derived data + regroup — entries or colours changed.
    private func rebuildAll() {
        model.refreshColorMap(substanceColors)
        model.rebuildDerived(entries: entries, colors: substanceColors, entriesSignature: entriesSignature)
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
            filterDay: filterDay,
            stackRedoses: stackRedoses,
        )
    }

    // MARK: - Body

    var body: some View {
        List {
            if !isSearchSurface, !model.tags.isEmpty {
                tagChipBar
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }

            // Main content
            switch grouping {
            case .recent: recentContent
            case .byDay: dayGroupedContent
            case .bySubstance: substanceGroupedContent
            case .byCategory: categoryGroupedContent
            }
        }
        .id(grouping)
        .listStyle(.plain)
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
            PerfLog.time("rebuildAll") { rebuildAll() }
        }
        .task(id: entriesSignature) {
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            PerfLog.time("rebuildAll") { rebuildAll() }
        }
        .onChange(of: searchText) { regroup() }
        .onChange(of: selectedTag) { regroup() }
        .onChange(of: grouping) { regroup() }
        .onChange(of: substanceColors.count) { rebuildAll() }
        .sheet(isPresented: $showingCalendar) {
            calendarSheet
                .presentationDetents([.medium])
                .presentationBackground(.regularMaterial)
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
        filterDay = nil
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
    @ViewBuilder
    private func entryRow(_ entry: DoseEntry) -> some View {
        Button {
            navigator.push(.entry(timestamp: entry.timestamp))
        } label: {
            SubstanceEntryRow(entry: entry, colorMap: model.colorMap)
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    // MARK: - Day Grouped Content

    private var dayGroupedContent: some View {
        ForEach(model.dayGroups) { day in
            // A plain Button (not NavigationLink) pushes programmatically so the
            // whole card is tappable with no system disclosure chevron over the
            // graph. Navigation still resolves through `.withAppDestinations()`.
            Button {
                navigator.push(.day(date: day.date))
            } label: {
                DayCardView(group: day, colorMap: model.colorMap)
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
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

    private var calendarSheet: some View {
        NavigationStack {
            JournalCalendarView(
                entries: entries,
                colorMap: model.colorMap,
                onSelectDate: { date in
                    filterDay = date
                    showingCalendar = false
                    regroup()
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

/// One day's worth of entries with its timeline precomputed (in
/// `JournalModel.rebuildGroups`) so the card's mini graph never re-derives PK
/// curves while scrolling.
///
/// The card's text — `dateTitle`/`weekday` (both `Date.FormatStyle`, which is
/// protocol-heavy and showed up as `swift_conformsToProtocol` self-time during
/// scroll/sizing), plus the substance summary and dose count — is formatted
/// **once here** rather than on every `DayCardView` body/`sizeThatFits` pass.
struct DayGroup: Identifiable {
    let date: Date
    let entries: [DoseEntry]
    let states: [ActiveSubstanceState]
    let markers: [DoseMarker]
    let dateTitle: String
    let weekday: String
    let uniqueSubstances: [String]
    let substanceSummary: String
    let doseCountText: String
    var id: Date { date }

    init(date: Date, entries: [DoseEntry], states: [ActiveSubstanceState], markers: [DoseMarker]) {
        self.date = date
        self.entries = entries
        self.states = states
        self.markers = markers

        // The current year is implicit — only show it for past/future years.
        let base = Date.FormatStyle.dateTime.day().month(.wide)
        let sameYear = Calendar.current.isDate(date, equalTo: .now, toGranularity: .year)
        dateTitle = date.formatted(sameYear ? base : base.year())
        weekday = date.formatted(.dateTime.weekday(.wide))

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

/// Withings/Health-style day card: date + metadata + substance dots on the
/// left, a compact PK timeline on the right. The card is content, so it sits on
/// `themeCard` (material/surface) — never glass.
struct DayCardView: View {
    let group: DayGroup
    let colorMap: [String: Color]

    @AppStorage("stackRedoses", store: UserDefaults(suiteName: "group.dev.yumeji.piru")) private var stackRedoses = true

    private var dotColors: [Color] {
        group.uniqueSubstances.prefix(4).map { SubstancePalette.color(for: $0, colorMap: colorMap) }
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(group.dateTitle)
                    .font(.headline)
                (Text(group.weekday) + Text("  ·  ") + Text(group.doseCountText))
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
                HStack(spacing: 6) {
                    substanceDots
                    Text(group.substanceSummary)
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
        .themeCard()
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var substanceDots: some View {
        HStack(spacing: 3) {
            ForEach(Array(dotColors.enumerated()), id: \.offset) { _, color in
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
            }
        }
    }

    @ViewBuilder
    private var graph: some View {
        if !group.states.isEmpty || !group.markers.isEmpty {
            // One unified renderer: curves rise from a shared baseline and any
            // duration-less doses rest on it as colour-coded dots. A pure-meds
            // day is simply the baseline with its dots — no special-case strip.
            // `showNowIndicator: false` — these are historical cards, so the
            // axis-less "now" dot would only add noise.
            TimelineGraphView(
                substances: group.states,
                currentTime: .now,
                compact: true,
                markers: group.markers,
                stackRedoses: stackRedoses,
                showNowIndicator: false,
                dayBounded: true,
            )
            .frame(width: 96, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Journal Calendar View

struct JournalCalendarView: View {
    let entries: [DoseEntry]
    let colorMap: [String: Color]
    let onSelectDate: (Date) -> Void

    @State private var selectedMonth: Date = .now

    private var calendar: Calendar {
        Calendar.current
    }

    private var datesWithEntries: Set<DateComponents> {
        var set = Set<DateComponents>()
        for entry in entries {
            let comps = calendar.dateComponents([.year, .month, .day], from: entry.timestamp)
            set.insert(comps)
        }
        return set
    }

    private func entriesFor(date: Date) -> Int {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        let start = calendar.date(from: comps)!
        let end = start.addingTimeInterval(86_400)
        return entries.count(where: { $0.timestamp >= start && $0.timestamp < end })
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
                        let count = entriesFor(date: date)
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
