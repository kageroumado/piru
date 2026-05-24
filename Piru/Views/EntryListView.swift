import SwiftUI
import SwiftData

// MARK: - Journal Grouping

enum JournalGrouping: String, CaseIterable {
    case recent = "Recent"
    case byDay = "Days"
    case bySubstance = "Substance"
    case byCategory = "Category"

    var icon: String {
        switch self {
        case .recent: "clock"
        case .byDay: "calendar"
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
    @Query(sort: \DoseEntry.timestamp, order: .reverse, transaction: .init(animation: nil)) private var entries: [DoseEntry]
    @Query private var substanceColors: [SubstanceColor]

    @Binding var searchText: String
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
            let endOfDay = Calendar.current.startOfDay(for: end).addingTimeInterval(86400)
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

    @State private var cachedDayGroups: [(date: Date, entries: [DoseEntry])] = []
    @State private var cachedSubstanceGroups: [(name: String, entries: [DoseEntry])] = []
    @State private var cachedCategoryGroups: [(category: SubstanceCategory, entries: [DoseEntry])] = []
    @State private var cachedColorMap: [String: Color] = [:]
    @State private var collapsedSubstances: Set<String> = []
    @State private var collapsedCategories: Set<SubstanceCategory> = []

    private var allUsedTags: [String] {
        var counts: [String: Int] = [:]
        for entry in entries {
            for tag in entry.tags { counts[tag, default: 0] += 1 }
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
            // a new day at midnight.
            let grouped = Dictionary(grouping: filtered) { entry in
                calendar.sessionDayStart(for: entry.timestamp)
            }
            cachedDayGroups = grouped.sorted { $0.key > $1.key }
                .map { (date: $0.key, entries: $0.value) }

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
            // Filters + tag chips header
            VStack(alignment: .leading, spacing: 0) {
                filterBar

                if !allUsedTags.isEmpty && grouping == .byDay {
                    tagChipBar
                        .transition(.opacity)
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .animation(.easeInOut(duration: 0.2), value: grouping == .byDay)

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
        .navigationTitle("Journal")
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
                availableCategories: allUsedCategories
            )
            .presentationDetents([.medium, .large])
            .onDisappear { rebuildGroups() }
        }
        .sheet(isPresented: $showingCalendar) {
            calendarSheet
                .presentationDetents([.medium])
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 8) {
            // Grouping picker
            Menu {
                ForEach(JournalGrouping.allCases, id: \.self) { mode in
                    Button {
                        grouping = mode
                    } label: {
                        Label(mode.displayName, systemImage: mode.icon)
                    }
                }
            } label: {
                Label(grouping.displayName, systemImage: grouping.icon)
                    .font(.subheadline.weight(.medium))
                    .frame(height: 28)
                    .padding(.horizontal, 10)
                    .background(Color(.secondarySystemFill))
                    .clipShape(Capsule())
            }

            // Calendar button
            Button {
                showingCalendar = true
            } label: {
                Image(systemName: "calendar")
                    .font(.subheadline.weight(.medium))
                    .frame(height: 28)
                    .padding(.horizontal, 10)
                    .background(Color(.secondarySystemFill))
                    .clipShape(Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)

            // Filter button
            Button {
                showingFilters = true
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.subheadline.weight(.medium))
                    .frame(height: 28)
                    .padding(.horizontal, 10)
                    .background(hasActiveFilters ? Theme.accent.opacity(0.2) : Color(.secondarySystemFill))
                    .foregroundStyle(hasActiveFilters ? Theme.accent : .secondary)
                    .clipShape(Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .animation(.snappy, value: hasActiveFilters)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Tag Chip Bar

    private var tagChipBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(allUsedTags, id: \.self) { tag in
                    Button {
                        withAnimation(.snappy) {
                            selectedTag = selectedTag == tag ? nil : tag
                            rebuildGroups()
                        }
                    } label: {
                        Text("#\(tag)")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(selectedTag == tag ? Theme.accent : Color(.secondarySystemFill))
                            .foregroundStyle(selectedTag == tag ? .white : .secondary)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Recent (Flat) Content

    @ViewBuilder
    private var recentContent: some View {
        ForEach(filteredEntries) { entry in
            NavigationLink(value: PushRoute.entry(timestamp: entry.timestamp)) {
                SubstanceEntryRow(entry: entry, colorMap: cachedColorMap)
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        }
    }

    // MARK: - Day Grouped Content

    @ViewBuilder
    private var dayGroupedContent: some View {
        ForEach(cachedDayGroups, id: \.date) { day in
            NavigationLink(value: PushRoute.day(date: day.date)) {
                DayCardView(date: day.date, entries: day.entries, colorMap: cachedColorMap)
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        }
    }

    // MARK: - Substance Grouped Content

    @ViewBuilder
    private var substanceGroupedContent: some View {
        ForEach(cachedSubstanceGroups, id: \.name) { group in
            let isCollapsed = collapsedSubstances.contains(group.name)
            Section {
                if !isCollapsed {
                    ForEach(group.entries) { entry in
                        NavigationLink(value: PushRoute.entry(timestamp: entry.timestamp)) {
                            SubstanceEntryRow(entry: entry, colorMap: cachedColorMap)
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
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

    @ViewBuilder
    private var categoryGroupedContent: some View {
        ForEach(cachedCategoryGroups, id: \.category) { group in
            let isCollapsed = collapsedCategories.contains(group.category)
            Section {
                if !isCollapsed {
                    ForEach(group.entries) { entry in
                        NavigationLink(value: PushRoute.entry(timestamp: entry.timestamp)) {
                            SubstanceEntryRow(entry: entry, colorMap: cachedColorMap)
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
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
                "Try a different search term."
            )
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
                }
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

    var body: some View {
        HStack(spacing: 12) {
            if let color = colorMap[entry.substance.lowercased()] {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 3)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.substance)
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 4) {
                    Text("\(entry.amount.doseFormatted) \(entry.unit) — \(String(localized: entry.route.localizedName))")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(entry.timestamp.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.caption)
                Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
            }
            .foregroundStyle(Theme.secondaryLabel)
        }
        .padding(.vertical, 2)
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

struct DayCardView: View {
    let date: Date
    let entries: [DoseEntry]
    let colorMap: [String: Color]

    private var dateTitle: String {
        date.formatted(.dateTime.day().month(.wide).year())
    }

    private var subtitle: String {
        date.formatted(.dateTime.weekday(.wide))
    }

    private var substanceSummary: String {
        let names = entries.map(\.substance)
        let unique = (NSOrderedSet(array: names).array as? [String]) ?? names
        if unique.count <= 3 {
            return unique.joined(separator: ", ")
        }
        let first = unique.prefix(3).joined(separator: ", ")
        return String(localized: "\(first) +\(unique.count - 3) more")
    }

    private var barColors: [Color] {
        let names = entries.map(\.substance)
        let unique = (NSOrderedSet(array: names).array as? [String]) ?? names
        let colors = unique.compactMap { name in
            colorMap[name.lowercased()]
        }
        if colors.isEmpty { return [Theme.accent] }
        var seen = Set<String>()
        return colors.filter { color in
            let desc = color.description
            if seen.contains(desc) { return false }
            seen.insert(desc)
            return true
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    barColors.count == 1
                        ? AnyShapeStyle(barColors[0])
                        : AnyShapeStyle(LinearGradient(
                            colors: barColors,
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                )
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 4) {
                Text(dateTitle)
                    .font(.headline)
                Text(substanceSummary)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            .padding(.vertical, 4)
        }
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
            .background(Theme.background)
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

    private var calendar: Calendar { Calendar.current }

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
        let end = start.addingTimeInterval(86400)
        return entries.filter { $0.timestamp >= start && $0.timestamp < end }.count
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
                ForEach(daysInMonth(), id: \.self) { item in
                    if item.day == 0 {
                        Color.clear.frame(height: 36)
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
                            .frame(height: 36)
                            .frame(maxWidth: .infinity)
                            .background(
                                calendar.isDateInToday(date)
                                    ? Theme.accent.opacity(0.15)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                        }
                    }
                }
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding(.top)
    }

    private struct CalendarDay: Hashable {
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
        for _ in 0..<leadingBlanks {
            days.append(CalendarDay(year: comps.year!, month: comps.month!, day: 0))
        }
        for day in range {
            days.append(CalendarDay(year: comps.year!, month: comps.month!, day: day))
        }
        return days
    }
}
