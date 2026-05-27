import SwiftUI
import SwiftData
import ActivityKit

struct DayDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appNavigator) private var navigator
    @Query private var entries: [DoseEntry]
    @Query private var substanceColors: [SubstanceColor]
    @AppStorage("stackRedoses", store: UserDefaults(suiteName: "group.dev.yumeji.piru")) private var stackRedoses = false

    @State private var entryToAdjustTime: DoseEntry?
    @State private var showColorPicker = false
    @State private var colorPickerSubstance = ""
    @State private var graphExpanded = true
    @State private var dayInteractions: [InteractionResult] = []
    @State private var exportedImage: UIImage?
    @State private var showShareSheet = false
    @State private var isExporting = false

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
        // Use the configured session-day window so a late-night dose shows
        // up under the same day card the user tapped.
        let start = Calendar.current.sessionDayStart(for: date)
        let end = start.addingTimeInterval(86400)
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
            Group {
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
                        if graphExpanded {
                            VStack(spacing: 8) {
                                if isToday {
                                    HStack {
                                        Spacer()
                                        Button("Live Activity") {
                                            restartLiveActivity()
                                        }
                                        .font(.caption)
                                        .buttonStyle(.plain)
                                        .foregroundStyle(Theme.accent)
                                    }
                                    .padding(.horizontal, 12)
                                }
                                TimelineGraphView(
                                    substances: substanceStates,
                                    currentTime: .now,
                                    compact: false,
                                    markers: doseMarkers,
                                    stackRedoses: stackRedoses
                                )
                                .frame(height: 160)
                            }
                        }
                    } header: {
                        Button {
                            withAnimation { graphExpanded.toggle() }
                        } label: {
                            HStack {
                                Label("Timeline", systemImage: "chart.xyaxis.line")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.semibold))
                                    .rotationEffect(.degrees(graphExpanded ? 90 : 0))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    } footer: {
                        if graphExpanded {
                            Text("Pinch to zoom in or out")
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6))
                }

                // Entries
                Section("\(entries.count) entr\(entries.count == 1 ? "y" : "ies")") {
                    ForEach(entries) { entry in
                        NavigationLink(value: PushRoute.entry(timestamp: entry.timestamp)) {
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
                                navigator.present(.entryEdit(timestamp: entry.timestamp))
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.orange)
                        }
                        .contextMenu {
                            Button {
                                entryToAdjustTime = entry
                            } label: {
                                Label("Adjust Time", systemImage: "clock")
                            }
                            Button {
                                colorPickerSubstance = entry.substance
                                showColorPicker = true
                            } label: {
                                Label("Change Color", systemImage: "paintbrush")
                            }
                            Button {
                                navigator.present(.entryEdit(timestamp: entry.timestamp))
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            Divider()
                            Button(role: .destructive) {
                                deleteEntry(entry)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
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
            .listRowBackground(Theme.cardBackground)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("\(dayOfWeek), \(dateTitle)")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: entries.count) {
            await loadInteractions()
        }
        .toolbar {
            if !entries.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        exportDayLog()
                    } label: {
                        if isExporting {
                            ProgressView()
                                .tint(Theme.accent)
                        } else {
                            Image(systemName: "camera")
                        }
                    }
                    .disabled(isExporting)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    navigator.present(.entryForm(prefill: nil))
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $entryToAdjustTime) { entry in
            NavigationStack {
                TimeAdjustSheet(entry: entry)
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showShareSheet) {
            if let image = exportedImage {
                DayLogShareSheet(image: image)
                    .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: $showColorPicker) {
            SubstanceColorPickerView(
                substanceName: colorPickerSubstance,
                takenColors: Array(substanceColors).takenColorMap
            ) { hex in
                if let existing = substanceColors.first(where: { $0.substance.lowercased() == colorPickerSubstance.lowercased() }) {
                    existing.hexColor = hex
                } else {
                    modelContext.insert(SubstanceColor(substance: colorPickerSubstance, hexColor: hex))
                }
                showColorPicker = false
            }
            .presentationDetents([.large])
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

        withAnimation {
            modelContext.delete(entry)
        }

        // Also remove from live activity if active
        ActiveSessionManager.shared.removeDose(
            substanceName: name,
            timestamp: timestamp,
            allColors: Array(substanceColors)
        )
    }

    private func colorFor(_ entry: DoseEntry) -> Color {
        Array(substanceColors).colorMap[entry.substance.lowercased()] ?? Theme.accent
    }

    private func exportDayLog() {
        isExporting = true
        let entriesCopy = entries.map { entry in
            DayLogImageExporter.EntryData(
                substance: entry.substance,
                amount: entry.amount,
                unit: entry.unit,
                route: entry.route,
                timestamp: entry.timestamp,
                notes: entry.notes,
                tags: entry.tags,
                category: SubstanceLibrary.lookupByNameOrAlias(entry.substance)?.category,
                doseLevel: SubstanceLibrary.lookupByNameOrAlias(entry.substance)?.doseRange(for: entry.route)?.level(for: entry.amount),
                colorHex: Array(substanceColors).hexColorMap[entry.substance.lowercased()]
            )
        }
        let exportDate = date
        Task {
            let image = DayLogImageExporter.generateImage(
                date: exportDate,
                entries: entriesCopy
            )
            isExporting = false
            if let image {
                exportedImage = image
                showShareSheet = true
            }
        }
    }

    private func restartLiveActivity() {
        ActiveSessionManager.shared.restartFromEntries(
            entries,
            allColors: Array(substanceColors)
        )
        LiveActivityManager.shared.sessionDidChange()
    }

}

private struct DayLogShareSheet: UIViewControllerRepresentable {
    let image: UIImage

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct TimeAdjustSheet: View {
    @Bindable var entry: DoseEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            DatePicker("Date & Time", selection: $entry.timestamp)
        }
        .navigationTitle("Adjust Time")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: { Image(systemName: "xmark") }
            }
        }
    }
}
