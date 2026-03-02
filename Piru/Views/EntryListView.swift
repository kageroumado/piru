import SwiftUI
import SwiftData

struct EntryListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DoseEntry.timestamp, order: .reverse) private var entries: [DoseEntry]
    @Query private var substanceColors: [SubstanceColor]

    @Binding var searchText: String

    private var filteredEntries: [DoseEntry] {
        guard !searchText.isEmpty else { return entries }
        return entries.filter {
            $0.substance.localizedCaseInsensitiveContains(searchText) ||
            ($0.notes?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    private var dayGroups: [(date: Date, entries: [DoseEntry])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredEntries) { entry in
            calendar.startOfDay(for: entry.timestamp)
        }
        return grouped.sorted { $0.key > $1.key }
            .map { (date: $0.key, entries: $0.value) }
    }

    private var colorMap: [String: Color] {
        Array(substanceColors).colorMap
    }

    var body: some View {
        List {
            if dayGroups.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No Entries" : "No Results",
                    systemImage: searchText.isEmpty ? "pill" : "magnifyingglass",
                    description: Text(searchText.isEmpty ? "Tap + to log your first entry." : "Try a different search term.")
                )
            } else {
                ForEach(dayGroups, id: \.date) { day in
                    NavigationLink(value: day.date) {
                        DayCardView(date: day.date, entries: day.entries, colorMap: colorMap)
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
            }
        }
        .listStyle(.plain)
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
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        }
    }
}
