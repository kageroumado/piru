import SwiftUI
import SwiftData

struct EntryListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DoseEntry.timestamp, order: .reverse, transaction: .init(animation: nil)) private var entries: [DoseEntry]
    @Query private var substanceColors: [SubstanceColor]

    @Binding var searchText: String
    @State private var selectedTag: String? = nil

    private var filteredEntries: [DoseEntry] {
        guard !searchText.isEmpty else {
            if let selectedTag {
                return entries.filter { $0.tags.contains(selectedTag) }
            }
            return entries
        }
        let query = searchText
        if query.hasPrefix("#") {
            let tagQuery = String(query.dropFirst()).lowercased()
            guard !tagQuery.isEmpty else { return entries }
            return entries.filter { entry in
                entry.tags.contains { $0.localizedCaseInsensitiveContains(tagQuery) }
            }
        }
        return entries.filter {
            $0.substance.localizedCaseInsensitiveContains(query) ||
            ($0.notes?.localizedCaseInsensitiveContains(query) ?? false) ||
            $0.tags.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    @State private var cachedDayGroups: [(date: Date, entries: [DoseEntry])] = []
    @State private var cachedColorMap: [String: Color] = [:]

    private var allUsedTags: [String] {
        var counts: [String: Int] = [:]
        for entry in entries {
            for tag in entry.tags { counts[tag, default: 0] += 1 }
        }
        return counts.sorted { $0.value > $1.value }.map(\.key)
    }

    private func rebuildDayGroups() {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredEntries) { entry in
            calendar.startOfDay(for: entry.timestamp)
        }
        cachedDayGroups = grouped.sorted { $0.key > $1.key }
            .map { (date: $0.key, entries: $0.value) }
    }

    private func rebuildColorMap() {
        cachedColorMap = Array(substanceColors).colorMap
    }

    var body: some View {
        VStack(spacing: 0) {
            if !allUsedTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(allUsedTags, id: \.self) { tag in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedTag = selectedTag == tag ? nil : tag
                                }
                                rebuildDayGroups()
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
                    .padding(.vertical, 8)
                }
            }
            List {
            if cachedDayGroups.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No Entries" : "No Results",
                    systemImage: searchText.isEmpty ? "pill" : "magnifyingglass",
                    description: Text(searchText.isEmpty ? "Tap + to log your first entry." : "Try a different search term.")
                )
            } else {
                ForEach(cachedDayGroups, id: \.date) { day in
                    NavigationLink(value: day.date) {
                        DayCardView(date: day.date, entries: day.entries, colorMap: cachedColorMap)
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
            }
        }
        .listStyle(.plain)
        .task {
            rebuildColorMap()
            rebuildDayGroups()
        }
        .task(id: entries.count) {
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            rebuildDayGroups()
        }
        .onChange(of: searchText) { rebuildDayGroups() }
        .onChange(of: selectedTag) { rebuildDayGroups() }
        .onChange(of: substanceColors.count) { rebuildColorMap() }
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
        return "\(first) +\(unique.count - 3) more"
    }

    private var barColors: [Color] {
        let names = entries.map(\.substance)
        let unique = (NSOrderedSet(array: names).array as? [String]) ?? names
        let colors = unique.compactMap { name in
            colorMap[name.lowercased()]
        }
        if colors.isEmpty { return [Theme.accent] }
        // Deduplicate while preserving order
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
            // Color bar
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
