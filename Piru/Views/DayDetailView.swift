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
    @State private var substanceStates: [ActiveSubstanceState] = []
    @State private var dayInteractions: [InteractionResult] = []

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
                if !substanceStates.isEmpty {
                    Section {
                        DisclosureGroup(isExpanded: $graphExpanded) {
                            TimelineGraphView(
                                substances: substanceStates,
                                currentTime: .now,
                                compact: false
                            )
                            .frame(height: 160)
                        } label: {
                            Label("Timeline", systemImage: "chart.xyaxis.line")
                        }
                    }
                }

                // Entries
                Section("\(entries.count) entr\(entries.count == 1 ? "y" : "ies")") {
                    ForEach(entries) { entry in
                        NavigationLink(value: entry) {
                            EntryRowView(entry: entry)
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

                // Interaction warnings at bottom
                if !dayInteractions.isEmpty {
                    Section {
                        ForEach(Array(dayInteractions.enumerated()), id: \.offset) { _, warning in
                            InteractionWarningRow(warning: warning)
                        }
                    } header: {
                        Label(
                            dayInteractions.count == 1 ? "Interaction Warning" : "\(dayInteractions.count) Interaction Warnings",
                            systemImage: dayInteractions.first?.severity == .dangerous
                                ? "exclamationmark.triangle.fill" : "exclamationmark.triangle"
                        )
                        .foregroundStyle((dayInteractions.first?.severity ?? .caution).color)
                    }
                }
            }
        }
        .navigationTitle("\(dayOfWeek), \(dateTitle)")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: entries.count) {
            await loadAsyncData()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    if isToday && !entries.isEmpty {
                        Button {
                            restartLiveActivity()
                        } label: {
                            Image(systemName: "bolt.heart.fill")
                        }
                    }
                    Button {
                        showingForm = true
                    } label: {
                        Image(systemName: "plus")
                    }
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

    private func loadAsyncData() async {
        let colorMap = Dictionary(
            substanceColors.map { ($0.substance.lowercased(), $0.hexColor) },
            uniquingKeysWith: { _, last in last }
        )

        var states: [ActiveSubstanceState] = []
        for entry in entries {
            let matched = SubstanceLibrary.search(entry.substance).first {
                $0.name.lowercased() == entry.substance.lowercased()
            }
            guard let substance = matched,
                  let duration = substance.duration(for: entry.route) else { continue }

            let boundaries = duration.phaseBoundaries
            let hex = colorMap[entry.substance.lowercased()] ?? "007AFF"

            states.append(ActiveSubstanceState(
                substanceName: entry.substance,
                colorHex: hex,
                doseTimestamp: entry.timestamp,
                amount: entry.amount,
                unit: entry.unit,
                route: entry.route.displayName,
                onsetEndMinutes: boundaries.onsetEnd,
                comeupEndMinutes: boundaries.comeupEnd,
                peakEndMinutes: boundaries.peakEnd,
                offsetEndMinutes: boundaries.offsetEnd,
                afterglowEndMinutes: duration.afterglow != nil ? boundaries.afterglowEnd : nil,
                totalMinutes: duration.estimatedTotalMinutes
            ))
        }

        let names = Array(Set(entries.map(\.substance)))
        let interactions: [InteractionResult]
        if names.count >= 2 {
            interactions = InteractionChecker.checkBatch(names, against: [])
        } else {
            interactions = []
        }

        self.substanceStates = states
        self.dayInteractions = interactions
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

    private func restartLiveActivity() {
        LiveActivityManager.shared.restartFromEntries(
            entries,
            allColors: Array(substanceColors)
        )
    }

}
