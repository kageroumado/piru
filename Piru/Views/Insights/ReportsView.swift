import SwiftData
import SwiftUI

struct ReportsView: View {
    @Query(sort: \Session.startDate, order: .reverse) private var sessions: [Session]
    @Query(sort: \DoseEntry.timestamp, order: .reverse) private var allEntries: [DoseEntry]
    @Query(sort: \DailyDoseItem.sortOrder) private var dailyItems: [DailyDoseItem]
    @Query private var substanceColors: [SubstanceColor]

    @Environment(\.colorScheme) private var colorScheme

    @State private var model = ReportsModel()
    @State private var showingSessionPicker = false

    private var scopeToken: Int {
        var hasher = Hasher()
        hasher.combine(model.mode)
        hasher.combine(model.selectedSessions)
        hasher.combine(model.customStart)
        hasher.combine(model.customEnd)
        hasher.combine(DoseLogService.shared.revision)
        return hasher.finalize()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                modePicker
                scopeSummary
                if model.hasScope {
                    exportCards
                    substanceFilter
                }
            }
            .padding(.horizontal)
            .padding(.top, 4)
            .padding(.bottom, 80)
        }
        .background(Theme.background)
        .task(id: scopeToken) {
            await SubstanceStore.shared.ensureAllLoaded()
            model.recompute(sessions: sessions, entries: allEntries)
        }
        .sheet(isPresented: $showingSessionPicker) {
            SessionPickerSheet(model: model, sessions: model.sessionSummaries)
        }
        .sheet(item: shareItemBinding) { item in
            ShareSheet(items: item.items)
        }
    }

    // MARK: - Mode Picker

    private var modePicker: some View {
        Picker("Mode", selection: $model.mode) {
            ForEach(ReportsModel.ExportMode.allCases, id: \.self) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.vertical, 4)
    }

    // MARK: - Scope Summary

    private var scopeSummary: some View {
        VStack(spacing: 0) {
            switch model.mode {
            case .latest:
                latestSummaryRow
            case .byDate:
                dateRangeRows
            }
        }
        .themeCard()
    }

    private var latestSummaryRow: some View {
        Button { showingSessionPicker = true } label: {
            HStack {
                Image(systemName: "calendar")
                    .foregroundStyle(Theme.accent)
                if model.selectedSessions.isEmpty {
                    Text("Select sessions")
                        .foregroundStyle(Theme.secondaryLabel)
                } else {
                    Text("\(model.selectedSessions.count) of \(model.sessionSummaries.count) sessions")
                        .foregroundStyle(.primary)
                    Text("· \(model.entryCountInScope) entries")
                        .foregroundStyle(Theme.secondaryLabel)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryLabel)
            }
            .font(.subheadline)
            .padding(16)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Select sessions"))
        .accessibilityValue(Text("\(model.selectedSessions.count) selected"))
    }

    private var dateRangeRows: some View {
        VStack(spacing: 0) {
            DatePicker("From", selection: $model.customStart, displayedComponents: .date)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            Divider().padding(.leading, 16)
            DatePicker("To", selection: $model.customEnd, displayedComponents: .date)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            if model.entryCountInScope > 0 {
                Divider().padding(.leading, 16)
                HStack {
                    Text("\(model.entryCountInScope) entries across \(model.substancesInScope.count) substances")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Export Cards

    private var exportCards: some View {
        VStack(spacing: 0) {
            ExportCard(
                icon: "doc.richtext",
                tint: .red,
                title: "Clinical Report",
                description: "Key findings, medication summary, dose trends — for your doctor",
            ) {
                await generateClinicalReport()
            }

            cardDivider

            ExportCard(
                icon: "photo.on.rectangle.angled",
                tint: .blue,
                title: "Session Images",
                description: model.mode == .latest
                    ? "\(model.selectedSessions.count) sessions as individual images"
                    : "Sessions in this range as individual images",
            ) {
                await exportImages(stitched: false)
            }

            cardDivider

            ExportCard(
                icon: "rectangle.portrait.on.rectangle.portrait",
                tint: .teal,
                title: "Stitched Image",
                description: "All selected sessions in one tall image",
            ) {
                await exportImages(stitched: true)
            }

            cardDivider

            ExportCard(
                icon: "doc.plaintext",
                tint: .orange,
                title: "Markdown",
                description: "Plain-text session data — for notes, AI, or records",
            ) {
                await exportMarkdownAction()
            }

            cardDivider

            ExportCard(
                icon: "quote.opening",
                tint: .purple,
                title: "Trip Report",
                description: tripReportDescription,
            ) {
                await exportTripReportsAction()
            }
        }
        .themeCard()
    }

    /// Says up front how many of the selected sessions have notes, so a tap
    /// with nothing to export is never a surprise.
    private var tripReportDescription: LocalizedStringKey {
        switch model.sessionsWithNotes(in: selectedSessionObjects).count {
        case 0: "Notes at their T+ offsets, descriptors by domain — none of the selected sessions has notes yet"
        case 1: "Notes at their T+ offsets, descriptors by domain — 1 session with notes"
        case let count: "Notes at their T+ offsets, descriptors by domain — \(count) sessions with notes"
        }
    }

    private var cardDivider: some View {
        Divider().padding(.leading, 58)
    }

    // MARK: - Substance Filter

    private var substanceFilter: some View {
        VStack(spacing: 0) {
            Button { model.substanceFilterExpanded.toggle() } label: {
                HStack {
                    Image(systemName: "line.3.horizontal.decrease")
                        .foregroundStyle(Theme.accent)
                    Text("Substances")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(model.filteredSubstanceCount) of \(model.substancesInScope.count)")
                        .foregroundStyle(Theme.secondaryLabel)
                    Image(systemName: model.substanceFilterExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.secondaryLabel)
                }
                .font(.subheadline)
                .padding(16)
            }
            .buttonStyle(.plain)

            if model.substanceFilterExpanded {
                Divider().padding(.leading, 16)

                HStack {
                    Spacer()
                    Button {
                        if model.substanceFilter.isEmpty {
                            model.deselectAllSubstances()
                        } else {
                            model.selectAllSubstances()
                        }
                    } label: {
                        Text(model.substanceFilter.isEmpty ? "Deselect All" : "Select All")
                            .font(.caption)
                            .foregroundStyle(Theme.accent)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)

                ForEach(model.substancesInScope, id: \.self) { substance in
                    Button { model.toggleSubstance(substance) } label: {
                        HStack(spacing: 12) {
                            let included = model.isSubstanceIncluded(substance)
                            Image(systemName: included ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(included ? Theme.accent : Theme.secondaryLabel)
                            Text(SubstanceLibrary.lookup(substance)?.displayTitle ?? substance)
                                .foregroundStyle(.primary)
                                .font(.subheadline)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 8)
            }
        }
        .themeCard()
    }

    // MARK: - Export actions

    private func generateClinicalReport() async {
        model.isExporting = true
        defer { model.isExporting = false }

        let range = model.reportDateRange
        let filteredEntries = allEntries.filter {
            $0.timestamp >= range.start && $0.timestamp <= range.end
                && model.isSubstanceIncluded($0.substance)
        }

        let entrySnapshots = filteredEntries.map { entry in
            PDFReportGenerator.EntrySnapshot(
                substance: entry.substance,
                amount: entry.amount,
                unit: entry.unit,
                route: entry.route.displayName,
                timestamp: entry.timestamp,
                notes: entry.notes,
                identityKey: entry.identityKey,
                routeRaw: entry.route.rawValue,
                substanceID: SubstanceStore.shared.substanceID(forNameOrAlias: entry.substance),
                halfLifeMinutes: SubstanceLibrary.lookup(entry.substance)?.halfLifeMinutes,
            )
        }

        let doseSnapshots = dailyItems.map { item in
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

        let substances = Array(Set(filteredEntries.map(\.substance)))
        let interactions = InteractionChecker.checkBatch(substances, against: filteredEntries, policy: .warn)
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

        let hexMap = substanceColors.reduce(into: [String: String]()) { $0[$1.substance] = $1.hexColor }
        let clinicalReport = ClinicalStatsResolver.report(
            entries: filteredEntries, hexMap: hexMap, start: range.start, end: range.end,
        )

        let compressedRaw = interactionSnapshots.map {
            (
                severity: $0.severity,
                substanceA: $0.substanceA,
                substanceB: $0.substanceB,
                description: $0.description,
                drugClassesA: $0.drugClassesA,
                drugClassesB: $0.drugClassesB,
            )
        }
        let compressed = ClinicalStats.compressInteractions(compressedRaw)
        let findings = ClinicalStats.findings(report: clinicalReport, interactions: compressed)

        var data = PDFReportGenerator.ReportData(
            entries: entrySnapshots,
            dailyDoseItems: doseSnapshots,
            interactions: interactionSnapshots,
            startDate: range.start,
            endDate: range.end,
            notes: model.notes,
            patientName: model.patientName,
        )
        data.clinical = clinicalReport
        data.findings = findings
        data.compressedInteractions = compressed

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let filename = "Piru Report \(formatter.string(from: .now)).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        await Task.detached {
            let pdfData = PDFReportGenerator.generate(from: data)
            try? pdfData.write(to: url)
        }.value

        model.shareItems = [url]
    }

    private func exportImages(stitched: Bool) async {
        model.isExporting = true
        defer { model.isExporting = false }

        let images = await model.exportSessionImages(
            sessions: selectedSessionObjects,
            colors: substanceColors,
            scheme: colorScheme,
        )
        guard !images.isEmpty else { return }

        if stitched, let composite = model.exportStitchedImage(images) {
            model.shareItems = [composite]
        } else {
            model.shareItems = images
        }
    }

    private func exportMarkdownAction() async {
        model.isExporting = true
        defer { model.isExporting = false }

        let md = await model.exportMarkdown(sessions: selectedSessionObjects, colors: substanceColors)
        guard !md.isEmpty else { return }
        model.shareItems = [md]
    }

    private func exportTripReportsAction() async {
        let md = model.exportTripReports(sessions: selectedSessionObjects)
        guard !md.isEmpty else { return }
        model.shareItems = [md]
    }

    // MARK: - Helpers

    private var selectedSessionObjects: [Session] {
        sessions.filter { model.selectedSessions.contains($0.id) }
    }

    private var shareItemBinding: Binding<ShareableItems?> {
        Binding(
            get: { model.shareItems.map { ShareableItems(items: $0) } },
            set: { _ in model.shareItems = nil },
        )
    }
}

// MARK: - ShareableItems

private struct ShareableItems: Identifiable {
    let id = UUID()
    let items: [Any]
}

// MARK: - Session Picker Sheet

private struct SessionPickerSheet: View {
    @Bindable var model: ReportsModel
    let sessions: [ReportsModel.SessionSummary]
    @Environment(\.dismiss) private var dismiss

    private static let dayFormat = Date.FormatStyle.dateTime
        .weekday(.abbreviated)
        .month(.abbreviated)
        .day()

    var body: some View {
        NavigationStack {
            List {
                ForEach(sessions) { summary in
                    Button { model.toggleSession(summary.id) } label: {
                        HStack(spacing: 12) {
                            let selected = model.selectedSessions.contains(summary.id)
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected ? Theme.accent : Theme.secondaryLabel)
                                .imageScale(.large)
                                .animation(.default, value: selected)

                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    if let title = summary.title {
                                        Text(title)
                                            .font(.subheadline.weight(.semibold))
                                    }
                                    Text(summary.startDate.formatted(Self.dayFormat))
                                        .font(.subheadline.weight(summary.title == nil ? .semibold : .regular))
                                        .foregroundStyle(summary.title == nil ? .primary : Theme.secondaryLabel)
                                }

                                HStack(spacing: 6) {
                                    Text(summary.timeLabel)
                                        .font(.caption)
                                        .foregroundStyle(Theme.secondaryLabel)
                                    Text("·")
                                        .font(.caption)
                                        .foregroundStyle(Theme.secondaryLabel)
                                    Text(summary.substanceSummary)
                                        .font(.caption)
                                        .foregroundStyle(Theme.secondaryLabel)
                                        .lineLimit(1)
                                }
                            }

                            Spacer()

                            Text(summary.doseCount == 1
                                ? String(localized: "1 dose")
                                : String(localized: "\(summary.doseCount) doses"))
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryLabel)
                                .monospacedDigit()
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(model.selectedSessions.contains(summary.id) ? .isSelected : [])
                }
            }
            .navigationTitle("Select Sessions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.body.weight(.semibold))
                    }
                    .accessibilityLabel(Text("Close"))
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        if model.selectedSessions.count == sessions.count {
                            model.deselectAllSessions()
                        } else {
                            model.selectAllSessions()
                        }
                    } label: {
                        Text(model.selectedSessions.count == sessions.count
                            ? "Deselect All" : "Select All")
                            .font(.subheadline)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Export Card

private struct ExportCard: View {
    let icon: String
    let tint: Color
    let title: LocalizedStringKey
    let description: LocalizedStringKey
    let action: () async -> Void

    @State private var isRunning = false

    var body: some View {
        Button {
            guard !isRunning else { return }
            isRunning = true
            Task {
                await action()
                isRunning = false
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .frame(width: 28, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if isRunning {
                    ProgressView()
                        .tint(tint)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
            .padding(16)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}
