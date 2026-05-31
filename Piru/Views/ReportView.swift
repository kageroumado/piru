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

    private var filteredEntries: [DoseEntry] {
        let range = dateRange
        return allEntries.filter { $0.timestamp >= range.start && $0.timestamp <= range.end }
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

                    HStack {
                        Label("Usage Entries", systemImage: "list.bullet")
                        Spacer()
                        Text("\(entryCount)")
                            .foregroundStyle(Theme.secondaryLabel)
                    }

                    HStack {
                        Label("Interaction Alerts", systemImage: "exclamationmark.triangle")
                        Spacer()
                        let count = getInteractions().count
                        Text("\(count)")
                            .foregroundStyle(count > 0 ? .orange : Theme.secondaryLabel)
                    }
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                    }
                }
            }
            .sheet(item: $shareItem) { item in
                ShareSheet(items: [item.url])
            }
        }
    }

    // MARK: - Actions

    private func getInteractions() -> [InteractionResult] {
        let substances = Array(Set(filteredEntries.map(\.substance)))
        return InteractionChecker.checkBatch(substances, against: filteredEntries)
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
            )
        }

        let doseSnapshots = dailyDoseItems.map { item in
            PDFReportGenerator.DailyDoseSnapshot(
                substance: item.substance,
                amount: item.amount,
                unit: item.unit,
                route: item.route.displayName,
                sortOrder: item.sortOrder,
            )
        }

        let interactionSnapshots = getInteractions().map { i in
            PDFReportGenerator.InteractionSnapshot(
                severity: i.severity,
                substanceA: i.substanceA,
                substanceB: i.substanceB,
                description: i.description,
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

        let pdfData = PDFReportGenerator.generate(from: data)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let filename = "Piru Report \(formatter.string(from: .now)).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? pdfData.write(to: url)

        isGenerating = false
        shareItem = PDFShareItem(url: url)
    }
}

// MARK: - Share Sheet

struct PDFShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}
