import SwiftData
import SwiftUI

// MARK: - Journal Grouping

enum JournalGrouping: String, CaseIterable {
    case recent = "Recent"
    case byDay = "Days"
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
    @State private var showingFilters = false
    @State private var showingCalendar = false

    // Filter state
    @State private var filterStartDate: Date? = nil
    @State private var filterEndDate: Date? = nil
    @State private var filterSubstances: Set<String> = []
    @State private var filterCategories: Set<SubstanceCategory> = []

    private var hasActiveFilters: Bool {
        filterStartDate != nil || filterEndDate != nil ||
            !filterSubstances.isEmpty || !filterCategories.isEmpty
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

        // Date range filter
        if let start = filterStartDate {
            let startOfDay = Calendar.current.startOfDay(for: start)
            result = result.filter { $0.timestamp >= startOfDay }
        }
        if let end = filterEndDate {
            let endOfDay = Calendar.current.startOfDay(for: end).addingTimeInterval(86_400)
            result = result.filter { $0.timestamp < endOfDay }
        }

        // Substance filter
        if !filterSubstances.isEmpty {
            result = result.filter { filterSubstances.contains($0.substance) }
        }

        // Category filter
        if !filterCategories.isEmpty {
            result = result.filter { entry in
                if let substance = SubstanceLibrary.lookupByNameOrAlias(entry.substance) {
                    return filterCategories.contains(substance.category)
                }
                return false
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

    private var allUsedTags: [String] {
        var counts: [String: Int] = [:]
        for entry in entries {
            for tag in entry.tags {
                counts[tag, default: 0] += 1
            }
        }
        return counts.sorted { $0.value > $1.value }.map(\.key)
    }

    private var allUsedSubstances: [String] {
        let names = entries.map(\.substance)
        return (NSOrderedSet(array: names).array as? [String]) ?? Array(Set(names))
    }

    private var allUsedCategories: [SubstanceCategory] {
        var seen = Set<SubstanceCategory>()
        var result: [SubstanceCategory] = []
        for entry in entries {
            if let substance = SubstanceLibrary.lookupByNameOrAlias(entry.substance) {
                if seen.insert(substance.category).inserted {
                    result.append(substance.category)
                }
            }
        }
        return result.sorted { $0.rawValue < $1.rawValue }
    }

    private func rebuildGroups() {
        let calendar = Calendar.current
        let filtered = filteredEntries

        switch grouping {
        case .recent:
            break // Uses filteredEntries directly, no grouping needed

        case .byDay:
            // Group by session day (configurable cutoff hour) so a 02:00
            // dose joins the previous evening's session instead of starting
            // a new day at midnight. Precompute each day's timeline here so
            // the per-card Canvas doesn't re-derive curves on every scroll.
            let grouped = Dictionary(grouping: filtered) { entry in
                calendar.sessionDayStart(for: entry.timestamp)
            }
            let colors = Array(substanceColors)
            cachedDayGroups = grouped.sorted { $0.key > $1.key }.map { date, dayEntries in
                let timeline = ActiveSubstanceState.timeline(for: dayEntries, colors: colors)
                return DayGroup(date: date, entries: dayEntries, states: timeline.states, markers: timeline.markers)
            }

        case .bySubstance:
            let grouped = Dictionary(grouping: filtered, by: \.substance)
            cachedSubstanceGroups = grouped.sorted { $0.value.count > $1.value.count }
                .map { (name: $0.key, entries: $0.value) }

        case .byCategory:
            let grouped = Dictionary(grouping: filtered) { entry -> SubstanceCategory in
                SubstanceLibrary.lookupByNameOrAlias(entry.substance)?.category ?? .other
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
            if filteredEntries.isEmpty {
                emptyState
            }
        }
        .task {
            rebuildColorMap()
            rebuildGroups()
        }
        .task(id: entries.count) {
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            rebuildGroups()
        }
        .onChange(of: searchText) { rebuildGroups() }
        .onChange(of: selectedTag) { rebuildGroups() }
        .onChange(of: grouping) { rebuildGroups() }
        .onChange(of: substanceColors.count) { rebuildColorMap() }
        .sheet(isPresented: $showingFilters) {
            JournalFilterSheet(
                startDate: $filterStartDate,
                endDate: $filterEndDate,
                selectedSubstances: $filterSubstances,
                selectedCategories: $filterCategories,
                availableSubstances: allUsedSubstances,
                availableCategories: allUsedCategories,
            )
            .presentationDetents([.medium, .large])
            .presentationBackground(.regularMaterial)
            .onDisappear { rebuildGroups() }
        }
        .sheet(isPresented: $showingCalendar) {
            calendarSheet
                .presentationDetents([.medium])
                .presentationBackground(.regularMaterial)
        }
    }

    // MARK: - Header Controls

    /// Journal-specific controls injected into the app header. The grouping
    /// picker is the primary, accent-tinted control; the filter funnel fills +
    /// tints when a filter is active (Mail's idiom) so a narrowed list never
    /// looks like the full one. Each is its own glass capsule inside the
    /// header's shared `GlassEffectContainer`.
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

        Button {
            showingFilters = true
        } label: {
            // Always accent to match the grouping pill and ••• menu; the active
            // state reads from the filled funnel variant, not a colour swap.
            Image(systemName: hasActiveFilters
                ? "line.3.horizontal.decrease.circle.fill"
                : "line.3.horizontal.decrease")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .glassEffect(.regular, in: .circle)
        .animation(.snappy, value: hasActiveFilters)
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
        ForEach(filteredEntries) { entry in
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
                    filterStartDate = date
                    filterEndDate = date
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
        colorMap[entry.substance.lowercased()] ?? Theme.accent
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
            if let color = colorMap[name.lowercased()] {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
            }
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
        uniqueSubstances.prefix(4).map { colorMap[$0.lowercased()] ?? Theme.accent }
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
        if !states.isEmpty {
            // At least one dose has a PK curve — draw the real timeline (markers
            // ride on top of it).
            TimelineGraphView(
                substances: states,
                currentTime: .now,
                compact: true,
                markers: markers,
                stackRedoses: stackRedoses,
            )
            .frame(width: 96, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .allowsHitTesting(false)
        } else if !markers.isEmpty {
            // No curves (e.g. a day of supplements/meds without duration data).
            // A scatter of points on an empty axis reads as broken, so show a
            // purpose-built dose timeline: colour-coded marks placed by time.
            DoseMarkerStrip(markers: markers, dayStart: date, colorMap: colorMap)
                .frame(width: 96, height: 52)
        }
    }
}

/// Compact "lollipop" timeline for days whose doses have no PK curve: each dose
/// is a colour-coded dot on a thin stem, positioned along a faint baseline by
/// its time of day. A legible alternative to scattering markers on a blank axis.
private struct DoseMarkerStrip: View {
    let markers: [DoseMarker]
    let dayStart: Date
    let colorMap: [String: Color]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let inset: CGFloat = 5
            let baseY = h * 0.70
            let dotY = h * 0.32
            ZStack {
                Capsule()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: w - inset * 2, height: 2)
                    .position(x: w / 2, y: baseY)
                ForEach(Array(markers.enumerated()), id: \.offset) { _, marker in
                    let x = inset + fraction(marker.timestamp) * (w - inset * 2)
                    let color = colorMap[marker.substanceName.lowercased()] ?? Theme.accent
                    Rectangle()
                        .fill(color.opacity(0.45))
                        .frame(width: 1.5, height: baseY - dotY)
                        .position(x: x, y: (baseY + dotY) / 2)
                    Circle()
                        .fill(color)
                        .frame(width: 7, height: 7)
                        .position(x: x, y: dotY)
                }
            }
        }
    }

    /// Fraction (0...1) of the 24h session day at which the dose occurred.
    private func fraction(_ date: Date) -> Double {
        min(max(date.timeIntervalSince(dayStart) / 86_400, 0), 1)
    }
}

// MARK: - Journal Filter Sheet

struct JournalFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var startDate: Date?
    @Binding var endDate: Date?
    @Binding var selectedSubstances: Set<String>
    @Binding var selectedCategories: Set<SubstanceCategory>
    let availableSubstances: [String]
    let availableCategories: [SubstanceCategory]

    @State private var tempStart: Date = .now
    @State private var tempEnd: Date = .now
    @State private var hasDateRange = false
    @State private var substanceSearch = ""

    var body: some View {
        NavigationStack {
            List {
                Group {
                    // Date range section
                    Section("Date Range") {
                        Toggle("Filter by dates", isOn: $hasDateRange)
                        if hasDateRange {
                            DatePicker("From", selection: $tempStart, displayedComponents: .date)
                            DatePicker("To", selection: $tempEnd, displayedComponents: .date)
                        }
                    }

                    // Category section
                    if !availableCategories.isEmpty {
                        Section("Category") {
                            ForEach(availableCategories, id: \.self) { category in
                                Button {
                                    toggleCategory(category)
                                } label: {
                                    HStack {
                                        Image(systemName: category.icon)
                                            .foregroundStyle(category.color)
                                            .frame(width: 24)
                                        Text(category.displayName)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        if selectedCategories.contains(category) {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(Theme.accent)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Substance section
                    Section("Substance") {
                        TextField("Search substances...", text: $substanceSearch)
                        let filtered = substanceSearch.isEmpty ? availableSubstances :
                            availableSubstances.filter { $0.localizedCaseInsensitiveContains(substanceSearch) }
                        ForEach(filtered, id: \.self) { name in
                            Button {
                                toggleSubstance(name)
                            } label: {
                                HStack {
                                    Text(name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if selectedSubstances.contains(name) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Theme.accent)
                                    }
                                }
                            }
                        }
                    }

                    if startDate != nil || endDate != nil || !selectedSubstances.isEmpty || !selectedCategories.isEmpty || hasDateRange {
                        Section {
                            Button("Reset Filters", role: .destructive) {
                                startDate = nil
                                endDate = nil
                                selectedSubstances = []
                                selectedCategories = []
                                hasDateRange = false
                                dismiss()
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .listRowBackground(Theme.cardBackground)
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Filter Journal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        if hasDateRange {
                            startDate = tempStart
                            endDate = tempEnd
                        } else {
                            startDate = nil
                            endDate = nil
                        }
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark").fontWeight(.semibold)
                    }
                }
            }
            .onAppear {
                hasDateRange = startDate != nil || endDate != nil
                if let s = startDate { tempStart = s }
                if let e = endDate { tempEnd = e }
            }
        }
    }

    private func toggleSubstance(_ name: String) {
        if selectedSubstances.contains(name) {
            selectedSubstances.remove(name)
        } else {
            selectedSubstances.insert(name)
        }
    }

    private func toggleCategory(_ category: SubstanceCategory) {
        if selectedCategories.contains(category) {
            selectedCategories.remove(category)
        } else {
            selectedCategories.insert(category)
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
