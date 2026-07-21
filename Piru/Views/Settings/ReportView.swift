import SwiftData
import SwiftUI

struct ReportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var allEntries: [DoseEntry]
    @Query(sort: \DailyDoseItem.sortOrder) private var dailyDoseItems: [DailyDoseItem]

    @State private var selectedRange: DateRange = .last30
    @State private var customStart: Date = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
    @State private var customEnd: Date = .now
    @State private var patientName: String = ""
    @State private var notes: String = ""
    @State private var isGenerating = false
    @State private var shareItem: PDFShareItem?
    /// Entries within the selected range + their interaction check, recomputed
    /// only when the range or the data changes — not in `body` on every
    /// keystroke of the name/notes fields.
    @State private var filteredEntries: [DoseEntry] = []
    @State private var interactions: [InteractionResult] = []

    enum DateRange: String, CaseIterable {
        case last7 = "Last 7 Days"
        case last30 = "Last 30 Days"
        case last90 = "Last 90 Days"
        case allTime = "All Time"
        case custom = "Custom"

        var days: Int? {
            switch self {
            case .last7: 7
            case .last30: 30
            case .last90: 90
            case .allTime: nil
            case .custom: nil
            }
        }

        var displayName: LocalizedStringResource {
            switch self {
            case .last7: "Last 7 Days"
            case .last30: "Last 30 Days"
            case .last90: "Last 90 Days"
            case .allTime: "All Time"
            case .custom: "Custom"
            }
        }
    }

    private var dateRange: (start: Date, end: Date) {
        let end = Date.now
        if selectedRange == .custom {
            return (customStart, customEnd)
        }
        if let days = selectedRange.days {
            let start = Calendar.current.date(byAdding: .day, value: -days, to: end) ?? end
            return (start, end)
        }
        let earliest = allEntries.map(\.timestamp).min() ?? end
        return (earliest, end)
    }

    /// Recompute token: the selected range plus the entries' content.
    private var filterToken: Int {
        var hasher = Hasher()
        hasher.combine(selectedRange)
        hasher.combine(customStart)
        hasher.combine(customEnd)
        hasher.combine(EntriesFingerprint.make(allEntries))
        return hasher.finalize()
    }

    private var entryCount: Int {
        filteredEntries.count
    }

    private var substanceCount: Int {
        Set(filteredEntries.map(\.substance)).count
    }

    var body: some View {
        NavigationStack {
            List {
                // Patient Name
                Section {
                    TextField("Name (for the report header)", text: $patientName)
                } header: {
                    Text("Patient Name (Optional)")
                }

                // Date Range
                Section {
                    Picker("Period", selection: $selectedRange) {
                        ForEach(DateRange.allCases, id: \.self) { range in
                            Text(range.displayName).tag(range)
                        }
                    }

                    if selectedRange == .custom {
                        DatePicker("From", selection: $customStart, displayedComponents: .date)
                        DatePicker("To", selection: $customEnd, displayedComponents: .date)
                    }
                } header: {
                    Text("Date Range")
                } footer: {
                    Text("\(entryCount) entries across \(substanceCount) substances")
                        .foregroundStyle(Theme.secondaryLabel)
                }

                // Preview
                Section("Report Includes") {
                    HStack {
                        Label("Current Medications", systemImage: "pills")
                        Spacer()
                        Text("\(dailyDoseItems.count)")
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                    .accessibilityElement(children: .combine)

                    HStack {
                        Label("Usage Entries", systemImage: "list.bullet")
                        Spacer()
                        Text("\(entryCount)")
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                    .accessibilityElement(children: .combine)

                    HStack {
                        Label("Interaction Alerts", systemImage: "exclamationmark.triangle")
                        Spacer()
                        let count = interactions.count
                        Text("\(count)")
                            .foregroundStyle(count > 0 ? .orange : Theme.secondaryLabel)
                    }
                    .accessibilityElement(children: .combine)
                }

                // Notes
                Section {
                    TextField("Add notes for your doctor...", text: $notes, axis: .vertical)
                        .lineLimit(3 ... 8)
                } header: {
                    Text("Notes (Optional)")
                } footer: {
                    Text("These notes will appear at the end of the PDF report.")
                }

                // Generate
                Section {
                    Button {
                        generateReport()
                    } label: {
                        HStack {
                            Spacer()
                            if isGenerating {
                                ProgressView()
                                    .tint(Theme.accent)
                            } else {
                                Label("Generate PDF Report", systemImage: "doc.richtext")
                                    .font(.headline)
                            }
                            Spacer()
                        }
                    }
                    .disabled(entryCount == 0 || isGenerating)
                    .foregroundStyle(entryCount == 0 ? Theme.secondaryLabel : Theme.accent)
                }
            }
            .navigationTitle("Medical Report")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: filterToken) { recomputeFiltered() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel(Text("Close"))
                }
            }
            .sheet(item: $shareItem) { item in
                ShareSheet(items: [item.url])
            }
        }
    }

    // MARK: - Actions

    private func recomputeFiltered() {
        let range = dateRange
        filteredEntries = allEntries.filter { $0.timestamp >= range.start && $0.timestamp <= range.end }
        let substances = Array(Set(filteredEntries.map(\.substance)))
        interactions = InteractionChecker.checkBatch(substances, against: filteredEntries, policy: .explore)
    }

    private func generateReport() {
        isGenerating = true

        let entrySnapshots = filteredEntries.map { entry in
            PDFReportGenerator.EntrySnapshot(
                substance: entry.substance,
                amount: entry.amount,
                unit: entry.unit,
                route: entry.route.displayName,
                timestamp: entry.timestamp,
                notes: entry.notes,
                tags: entry.tags,
                identityKey: entry.identityKey,
                routeRaw: entry.route.rawValue,
            )
        }

        let doseSnapshots = dailyDoseItems.map { item in
            PDFReportGenerator.DailyDoseSnapshot(
                substance: item.substance,
                amount: item.amount,
                unit: item.unit,
                route: item.route.displayName,
                sortOrder: item.sortOrder,
                identityKey: item.identityKey,
                routeRaw: item.route.rawValue,
            )
        }

        let interactionSnapshots = interactions.map { i in
            PDFReportGenerator.InteractionSnapshot(
                severity: i.severity,
                substanceA: i.substanceA,
                substanceB: i.substanceB,
                description: i.description,
                drugClassesA: InteractionChecker.drugClasses(for: i.substanceA),
                drugClassesB: InteractionChecker.drugClasses(for: i.substanceB),
            )
        }

        let range = dateRange

        let data = PDFReportGenerator.ReportData(
            entries: entrySnapshots,
            dailyDoseItems: doseSnapshots,
            interactions: interactionSnapshots,
            startDate: range.start,
            endDate: range.end,
            notes: notes,
            patientName: patientName,
        )

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let filename = "Piru Report \(formatter.string(from: .now)).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        Task {
            // The snapshot is plain Sendable value types with every
            // MainActor-bound lookup (drug classes) pre-resolved above, so
            // both the PDF render and the file write run off the main actor —
            // see the note on `PDFReportGenerator`.
            await Task.detached {
                let pdfData = PDFReportGenerator.generate(from: data)
                try? pdfData.write(to: url)
            }.value

            isGenerating = false
            shareItem = PDFShareItem(url: url)
        }
    }
}

// MARK: - Share Sheet

struct PDFShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// UIKit share sheet wrapper, kept over `ShareLink` because these flows present
/// the sheet *programmatically* after async work (PDF render, encrypted export)
/// — `ShareLink` only presents from its own tap. Also used by `ContentView`.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}
