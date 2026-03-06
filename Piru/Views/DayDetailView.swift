import SwiftUI
import SwiftData
import ActivityKit

struct DayDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var entries: [DoseEntry]
    @Query private var substanceColors: [SubstanceColor]

    @State private var showingForm = false
    @State private var entryToEdit: DoseEntry?
    @State private var graphExpanded = true
    @State private var dayInteractions: [InteractionResult] = []

    private var substanceStates: [ActiveSubstanceState] {
        let colorMap = Array(substanceColors).hexColorMap
        return entries.compactMap { entry in
            let hex = colorMap[entry.substance.lowercased()] ?? "007AFF"
            return ActiveSubstanceState.from(entry: entry, colorHex: hex)
        }
    }

    private var doseMarkers: [DoseMarker] {
        let colorMap = Array(substanceColors).hexColorMap
        return entries.compactMap { entry in
            // Only include entries that have no duration data (no curve on graph)
            guard ActiveSubstanceState.from(entry: entry, colorHex: "000000") == nil else { return nil }
            let hex = colorMap[entry.substance.lowercased()] ?? "007AFF"
            return DoseMarker(substanceName: entry.substance, timestamp: entry.timestamp, colorHex: hex, amount: entry.amount, unit: entry.unit)
        }
    }

    let date: Date

    init(date: Date) {
        self.date = date
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
        _entries = Query(
            filter: #Predicate<DoseEntry> { entry in
                entry.timestamp >= start && entry.timestamp < end
            },
            sort: \DoseEntry.timestamp
        )
    }


    private var cumulativeDoses: [(substance: String, total: Double, unit: String, count: Int)] {
        var grouped: [String: (total: Double, unit: String, count: Int)] = [:]
        for entry in entries {
            let key = entry.substance.lowercased()
            if let existing = grouped[key] {
                grouped[key] = (total: existing.total + entry.amount, unit: existing.unit, count: existing.count + 1)
            } else {
                grouped[key] = (total: entry.amount, unit: entry.unit, count: 1)
            }
        }
        return grouped
            .filter { $0.value.count > 1 }
            .map { (substance: $0.key.capitalized, total: $0.value.total, unit: $0.value.unit, count: $0.value.count) }
            .sorted { $0.substance < $1.substance }
    }

    private var dateTitle: String {
        date.formatted(.dateTime.day().month(.wide).year())
    }

    private var dayOfWeek: String {
        date.formatted(.dateTime.weekday(.wide))
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    var body: some View {
        List {
            if entries.isEmpty {
                ContentUnavailableView(
                    "No Entries",
                    systemImage: "pill",
                    description: Text("No substances logged on this day.")
                )
            } else {
                // Timeline graph
                if !substanceStates.isEmpty || !doseMarkers.isEmpty {
                    Section {
                        DisclosureGroup(isExpanded: $graphExpanded) {
                            TimelineGraphView(
                                substances: substanceStates,
                                currentTime: .now,
                                compact: false,
                                markers: doseMarkers
                            )
                            .frame(height: 160)
                            .overlay(alignment: .topTrailing) {
                                if isToday {
                                    Button("Live Activity") {
                                        restartLiveActivity()
                                    }
                                    .font(.caption)
                                    .buttonStyle(.plain)
                                    .foregroundStyle(Theme.accent)
                                }
                            }
                        } label: {
                            Label("Timeline", systemImage: "chart.xyaxis.line")
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                }

                // Entries
                Section("\(entries.count) entr\(entries.count == 1 ? "y" : "ies")") {
                    ForEach(entries) { entry in
                        NavigationLink(value: entry) {
                            EntryRowView(entry: entry, color: colorFor(entry))
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteEntry(entry)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                entryToEdit = entry
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.orange)
                        }
                    }
                }

                // Cumulative doses
                if !cumulativeDoses.isEmpty {
                    Section("Cumulative Doses") {
                        ForEach(cumulativeDoses, id: \.substance) { item in
                            HStack {
                                Text(item.substance)
                                    .font(.subheadline)
                                Spacer()
                                Text("\(item.total.doseFormatted) \(item.unit)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.accent)
                                Text("(\(item.count)x)")
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryLabel)
                            }
                        }

                        NavigationLink {
                            ComedownGuideView()
                        } label: {
                            Label("Recovery tips", systemImage: "heart.text.clipboard")
                                .font(.subheadline)
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }

                // Interaction warnings at bottom
                if !dayInteractions.isEmpty {
                    Section {
                        ForEach(Array(dayInteractions.enumerated()), id: \.offset) { _, warning in
                            InteractionWarningRow(warning: warning)
                        }
                    } header: {
                        Text(dayInteractions.count == 1 ? "Interaction Warning" : "\(dayInteractions.count) Interaction Warnings")
                            .foregroundStyle((dayInteractions.first?.severity ?? .caution).color)
                    }
                }
            }
        }
        .navigationTitle("\(dayOfWeek), \(dateTitle)")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: entries.count) {
            await loadInteractions()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingForm = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingForm) {
            EntryFormView()
        }
        .sheet(item: $entryToEdit) { entry in
            EntryFormView(entry: entry)
        }
    }

    private func loadInteractions() async {
        let names = Array(Set(entries.map(\.substance)))
        if names.count >= 2 {
            self.dayInteractions = InteractionChecker.checkBatch(names, against: [])
        } else {
            self.dayInteractions = []
        }
    }

    private func deleteEntry(_ entry: DoseEntry) {
        let name = entry.substance
        let timestamp = entry.timestamp

        modelContext.delete(entry)

        // Also remove from live activity if active
        LiveActivityManager.shared.removeDose(
            substanceName: name,
            timestamp: timestamp,
            allColors: Array(substanceColors)
        )
    }

    private func colorFor(_ entry: DoseEntry) -> Color {
        Array(substanceColors).colorMap[entry.substance.lowercased()] ?? Theme.accent
    }

    private func restartLiveActivity() {
        LiveActivityManager.shared.restartFromEntries(
            entries,
            allColors: Array(substanceColors)
        )
    }

}
