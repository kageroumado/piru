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

    // Filter state — category facets, plus an optional single day from the
    // calendar. (Substance and free date-range filtering were dropped:
    // substance duplicates Search, and a chronological day list makes time
    // windows pointless.)
    @State private var filterCategories: Set<SubstanceCategory> = []
    @State private var filterDay: Date? = nil

    private var hasActiveFilters: Bool {
        !filterCategories.isEmpty || filterDay != nil
    }

    // MARK: - Filtering

    private var filteredEntries: [DoseEntry] {
        var result = entries

        // Tag filter
        if let selectedTag {
            result = result.filter { $0.tags.contains(selectedTag) }
        }

        // Search filter
        if !searchText.isEmpty {
            let query = searchText
            if query.hasPrefix("#") {
                let tagQuery = String(query.dropFirst()).lowercased()
                if !tagQuery.isEmpty {
                    result = result.filter { entry in
                        entry.tags.contains { $0.localizedCaseInsensitiveContains(tagQuery) }
                    }
                }
            } else {
                result = result.filter {
                    $0.substance.localizedCaseInsensitiveContains(query) ||
                        ($0.notes?.localizedCaseInsensitiveContains(query) ?? false) ||
                        $0.tags.contains { $0.localizedCaseInsensitiveContains(query) }
                }
            }
        }

        // Single-day filter (set via Jump to Date).
        if let day = filterDay {
            let start = Calendar.current.sessionDayStart(for: day)
            let end = start.addingTimeInterval(86_400)
            result = result.filter { $0.timestamp >= start && $0.timestamp < end }
        }

        // Category filter — reads the precomputed category, no store lookup.
        if !filterCategories.isEmpty {
            result = result.filter { entry in
                guard let category = derived[entry.persistentModelID]?.category else { return false }
                return filterCategories.contains(category)
            }
        }

        return result
    }

    // MARK: - Cached Groups

    @State private var cachedDayGroups: [DayGroup] = []
    @State private var cachedSubstanceGroups: [(name: String, entries: [DoseEntry])] = []
    @State private var cachedCategoryGroups: [(category: SubstanceCategory, entries: [DoseEntry])] = []
    @State private var cachedColorMap: [String: Color] = [:]
    @State private var collapsedSubstances: Set<String> = []
    @State private var collapsedCategories: Set<SubstanceCategory> = []

    /// The current filter result, cached so neither the empty-state overlay nor
    /// the Recent list recompute the whole filter pass on every body evaluation.
    @State private var cachedFiltered: [DoseEntry] = []
    /// Categories present in the data, cached for the filter menu.
    @State private var cachedCategories: [SubstanceCategory] = []
    /// Per-entry category + timeline, resolved once (SubstanceLibrary lookups and
    /// PK curves are the expensive part). Filtering and regrouping then run as
    /// plain dictionary lookups instead of re-hitting the store on every tap —
    /// which is what made filtering jank the main thread.
    @State private var derived: [PersistentIdentifier: EntryDerived] = [:]

    struct EntryDerived {
        let category: SubstanceCategory
        let state: ActiveSubstanceState?
        let marker: DoseMarker?
    }

    private var allUsedTags: [String] {
        var counts: [String: Int] = [:]
        for entry in entries {
            for tag in entry.tags {
                counts[tag, default: 0] += 1
            }
        }
        return counts.sorted { $0.value > $1.value }.map(\.key)
    }

    /// Resolve each entry's category and timeline inputs once. This is the only
    /// place that hits SubstanceLibrary / computes PK curves; filter and regroup
    /// then read from `derived`. Run when entries or colours change — never on a
    /// filter tap.
    private func rebuildDerived() {
        let hexMap = Array(substanceColors).hexColorMap
        var map: [PersistentIdentifier: EntryDerived] = [:]
        map.reserveCapacity(entries.count)
        var seen = Set<SubstanceCategory>()
        var categories: [SubstanceCategory] = []
        for entry in entries {
            let category = SubstanceLibrary.lookupByNameOrAlias(entry.substance)?.category ?? .other
            if seen.insert(category).inserted { categories.append(category) }
            let hex = SubstancePalette.hex(for: entry.substance, hexMap: hexMap)
            let state = ActiveSubstanceState.from(entry: entry, colorHex: hex)
            let marker = state == nil
                ? DoseMarker(
                    substanceName: entry.substance,
                    timestamp: entry.timestamp,
                    colorHex: hex,
                    amount: entry.amount,
                    unit: entry.unit,
                )
                : nil
            map[entry.persistentModelID] = EntryDerived(category: category, state: state, marker: marker)
        }
        derived = map
        cachedCategories = categories.sorted { $0.rawValue < $1.rawValue }
    }

    /// Cheap content fingerprint of the fetched entries. Used as the rebuild
    /// task's identity so the derived cache + day-grouping refresh on *edits*,
    /// not just adds/removes. `entries.count` alone misses an in-place edit
    /// (e.g. moving a dose to another day, or changing its amount): the count is
    /// unchanged, so the cache went stale and the dose got stuck in its old day
    /// bucket. Hashing the fields the derived cache depends on closes that gap.
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

    private func rebuildGroups() {
        let calendar = Calendar.current
        let filtered = filteredEntries
        cachedFiltered = filtered

        switch grouping {
        case .recent:
            break // Uses cachedFiltered directly, no grouping needed

        case .byDay:
            // Group by session day (configurable cutoff hour) so a 02:00
            // dose joins the previous evening's session instead of starting
            // a new day at midnight. Timelines come from the `derived` cache,
            // so this is pure grouping work — no PK recompute.
            let grouped = Dictionary(grouping: filtered) { entry in
                calendar.sessionDayStart(for: entry.timestamp)
            }
            cachedDayGroups = grouped.sorted { $0.key > $1.key }.map { date, dayEntries in
                var states: [ActiveSubstanceState] = []
                var markers: [DoseMarker] = []
                for entry in dayEntries {
                    guard let d = derived[entry.persistentModelID] else { continue }
                    if let state = d.state { states.append(state) }
                    if let marker = d.marker { markers.append(marker) }
                }
                return DayGroup(date: date, entries: dayEntries, states: states, markers: markers)
            }

        case .bySubstance:
            let grouped = Dictionary(grouping: filtered, by: \.substance)
            cachedSubstanceGroups = grouped.sorted { $0.value.count > $1.value.count }
                .map { (name: $0.key, entries: $0.value) }

        case .byCategory:
            let grouped = Dictionary(grouping: filtered) { entry in
                derived[entry.persistentModelID]?.category ?? .other
            }
            cachedCategoryGroups = SubstanceCategory.allCases.compactMap { cat in
                guard let entries = grouped[cat], !entries.isEmpty else { return nil }
                return (category: cat, entries: entries)
            }
        }
    }

    private func rebuildColorMap() {
        cachedColorMap = Array(substanceColors).colorMap
    }

    // MARK: - Body

    var body: some View {
        List {
            if !isSearchSurface, !allUsedTags.isEmpty {
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
            if cachedFiltered.isEmpty {
                emptyState
            }
        }
        .task {
            rebuildColorMap()
            rebuildDerived()
            rebuildGroups()
        }
        .task(id: entriesSignature) {
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            rebuildDerived()
            rebuildGroups()
        }
        .onChange(of: searchText) { rebuildGroups() }
        .onChange(of: selectedTag) { rebuildGroups() }
        .onChange(of: grouping) { rebuildGroups() }
        .onChange(of: substanceColors.count) {
            rebuildColorMap()
            rebuildDerived()
            rebuildGroups()
        }
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
            if !cachedCategories.isEmpty {
                Section("Category") {
                    ForEach(cachedCategories, id: \.self) { category in
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
        rebuildGroups()
    }

    private func clearFilters() {
        filterCategories = []
        filterDay = nil
        rebuildGroups()
    }

    // MARK: - Tag Chip Bar

    private var tagChipBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(allUsedTags, id: \.self) { tag in
                    let isSelected = selectedTag == tag
                    Button {
                        withAnimation(.snappy) {
                            selectedTag = isSelected ? nil : tag
                            rebuildGroups()
                        }
                    } label: {
                        Text("#\(tag)")
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
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Recent (Flat) Content

    private var recentContent: some View {
        ForEach(cachedFiltered) { entry in
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
            SubstanceEntryRow(entry: entry, colorMap: cachedColorMap)
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    // MARK: - Day Grouped Content

    private var dayGroupedContent: some View {
        ForEach(cachedDayGroups) { day in
            // A plain Button (not NavigationLink) pushes programmatically so the
            // whole card is tappable with no system disclosure chevron over the
            // graph. Navigation still resolves through `.withAppDestinations()`.
            Button {
                navigator.push(.day(date: day.date))
            } label: {
                DayCardView(
                    date: day.date,
                    entries: day.entries,
                    states: day.states,
                    markers: day.markers,
                    colorMap: cachedColorMap,
                )
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Substance Grouped Content

    private var substanceGroupedContent: some View {
        ForEach(cachedSubstanceGroups, id: \.name) { group in
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
                        SubstanceGroupHeader(name: group.name, count: group.entries.count, colorMap: cachedColorMap)
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
        ForEach(cachedCategoryGroups, id: \.category) { group in
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
                colorMap: cachedColorMap,
                onSelectDate: { date in
                    filterDay = date
                    showingCalendar = false
                    rebuildGroups()
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

/// One day's worth of entries with its timeline precomputed (in `rebuildGroups`)
/// so the card's mini graph never re-derives PK curves while scrolling.
struct DayGroup: Identifiable {
    let date: Date
    let entries: [DoseEntry]
    let states: [ActiveSubstanceState]
    let markers: [DoseMarker]
    var id: Date { date }
}

/// Withings/Health-style day card: date + metadata + substance dots on the
/// left, a compact PK timeline on the right. The card is content, so it sits on
/// `themeCard` (material/surface) — never glass.
struct DayCardView: View {
    let date: Date
    let entries: [DoseEntry]
    let states: [ActiveSubstanceState]
    let markers: [DoseMarker]
    let colorMap: [String: Color]

    @AppStorage("stackRedoses", store: UserDefaults(suiteName: "group.dev.yumeji.piru")) private var stackRedoses = false

    private var dateTitle: String {
        date.formatted(.dateTime.day().month(.wide).year())
    }

    private var weekday: String {
        date.formatted(.dateTime.weekday(.wide))
    }

    private var uniqueSubstances: [String] {
        let names = entries.map(\.substance)
        return (NSOrderedSet(array: names).array as? [String]) ?? names
    }

    private var substanceSummary: String {
        let unique = uniqueSubstances
        if unique.count <= 3 {
            return unique.joined(separator: ", ")
        }
        let first = unique.prefix(3).joined(separator: ", ")
        return String(localized: "\(first) +\(unique.count - 3) more")
    }

    private var doseCountText: String {
        entries.count == 1
            ? String(localized: "1 dose")
            : String(localized: "\(entries.count) doses")
    }

    private var dotColors: [Color] {
        uniqueSubstances.prefix(4).map { SubstancePalette.color(for: $0, colorMap: colorMap) }
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(dateTitle)
                    .font(.headline)
                (Text(weekday) + Text("  ·  ") + Text(doseCountText))
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
                HStack(spacing: 6) {
                    substanceDots
                    Text(substanceSummary)
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
        if !states.isEmpty || !markers.isEmpty {
            // One unified renderer: curves rise from a shared baseline and any
            // duration-less doses rest on it as colour-coded dots. A pure-meds
            // day is simply the baseline with its dots — no special-case strip.
            // `showNowIndicator: false` — these are historical cards, so the
            // axis-less "now" dot would only add noise.
            TimelineGraphView(
                substances: states,
                currentTime: .now,
                compact: true,
                markers: markers,
                stackRedoses: stackRedoses,
                showNowIndicator: false,
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
