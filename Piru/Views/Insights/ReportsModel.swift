import SwiftData
import SwiftUI

@Observable
@MainActor
final class ReportsModel {
    enum ExportMode: String, CaseIterable {
        case latest
        case byDate

        var displayName: LocalizedStringResource {
            switch self {
            case .latest: "Latest"
            case .byDate: "By Date"
            }
        }
    }

    // MARK: - Mode

    var mode: ExportMode = .latest

    // MARK: - Latest mode

    var selectedSessions: Set<UUID> = []

    // MARK: - By Date mode

    var customStart: Date = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
    var customEnd: Date = .now

    // MARK: - Substance filter

    var substanceFilterExpanded = false
    /// Empty = all included (no filter). Non-empty = only those substances.
    var substanceFilter: Set<String> = []

    // MARK: - Export state

    var isExporting = false
    var shareRequest: ShareRequest?

    /// What the share sheet presents. Each export makes a new request, so the
    /// sheet's identity holds for as long as that request is shown.
    struct ShareRequest: Identifiable {
        let id = UUID()
        let items: [Any]
    }

    // MARK: - Derived state

    private(set) var substancesInScope: [String] = []
    private(set) var entryCountInScope = 0
    private(set) var sessionSummaries: [SessionSummary] = []

    struct SessionSummary: Identifiable, Equatable {
        let id: UUID
        let startDate: Date
        let timeLabel: String
        let title: String?
        let substanceSummary: String
        let doseCount: Int
    }

    // MARK: - Recompute

    func recompute(sessions: [Session], entries: [DoseEntry]) {
        rebuildSessionSummaries(sessions)
        rebuildScope(sessions: sessions, entries: entries)
    }

    private func rebuildSessionSummaries(_ sessions: [Session]) {
        let clock = Date.FormatStyle.dateTime.hour().minute()
        sessionSummaries = sessions.prefix(15).compactMap { session in
            let doses = (session.doses ?? []).sorted { $0.timestamp < $1.timestamp }
            guard !doses.isEmpty else { return nil }

            let start = doses[0].timestamp
            let end = doses[doses.count - 1].timestamp
            let timeLabel = end.timeIntervalSince(start) >= 60
                ? "\(start.formatted(clock)) – \(end.formatted(clock))"
                : start.formatted(clock)

            var displayNames: [String] = []
            var seenDisplay = Set<String>()
            for name in doses.map(\.substance) {
                let shown = SubstanceLibrary.lookup(name)?.displayTitle ?? name
                if seenDisplay.insert(shown.lowercased()).inserted { displayNames.append(shown) }
            }

            let summary: String
            if displayNames.count <= 3 {
                summary = displayNames.joined(separator: ", ")
            } else {
                let head = displayNames.prefix(3).joined(separator: ", ")
                summary = String(localized: "\(head) +\(displayNames.count - 3) more")
            }

            return SessionSummary(
                id: session.id,
                startDate: session.startDate,
                timeLabel: timeLabel,
                title: session.title,
                substanceSummary: summary,
                doseCount: doses.count,
            )
        }
    }

    private func rebuildScope(sessions: [Session], entries: [DoseEntry]) {
        let scopeEntries: [DoseEntry] = switch mode {
        case .latest:
            if selectedSessions.isEmpty {
                []
            } else {
                sessions
                    .filter { selectedSessions.contains($0.id) }
                    .flatMap { $0.doses ?? [] }
            }
        case .byDate:
            entries.filter { $0.timestamp >= customStart && $0.timestamp <= customEnd }
        }

        var seen = Set<String>()
        var subs: [String] = []
        for entry in scopeEntries {
            if seen.insert(entry.substance).inserted { subs.append(entry.substance) }
        }
        substancesInScope = subs.sorted()
        entryCountInScope = scopeEntries.count

        let currentFilter = substanceFilter
        if !currentFilter.isEmpty {
            substanceFilter = currentFilter.filter { substancesInScope.contains($0) }
            if substanceFilter.count == substancesInScope.count { substanceFilter = [] }
        }
    }

    // MARK: - Scope queries

    var hasScope: Bool {
        switch mode {
        case .latest: !selectedSessions.isEmpty
        case .byDate: entryCountInScope > 0
        }
    }

    var filteredSubstanceCount: Int {
        substanceFilter.isEmpty ? substancesInScope.count : substanceFilter.count
    }

    // MARK: - Selection

    func toggleSession(_ id: UUID) {
        if selectedSessions.contains(id) {
            selectedSessions.remove(id)
        } else {
            selectedSessions.insert(id)
        }
    }

    func selectAllSessions() {
        selectedSessions = Set(sessionSummaries.map(\.id))
    }

    func deselectAllSessions() {
        selectedSessions.removeAll()
    }

    // MARK: - Substance filter

    func isSubstanceIncluded(_ substance: String) -> Bool {
        substanceFilter.isEmpty || substanceFilter.contains(substance)
    }

    func toggleSubstance(_ substance: String) {
        if substanceFilter.isEmpty {
            substanceFilter = Set(substancesInScope)
            substanceFilter.remove(substance)
        } else if substanceFilter.contains(substance) {
            substanceFilter.remove(substance)
            if substanceFilter.isEmpty { substanceFilter = [] }
        } else {
            substanceFilter.insert(substance)
            if substanceFilter.count == substancesInScope.count { substanceFilter = [] }
        }
    }

    func selectAllSubstances() {
        substanceFilter = []
    }

    func deselectAllSubstances() {
        substanceFilter = Set([""])
    }

    // MARK: - Date range for clinical report

    var reportDateRange: (start: Date, end: Date) {
        switch mode {
        case .latest:
            guard !selectedSessions.isEmpty else { return (.now, .now) }
            let selected = sessionSummaries.filter { selectedSessions.contains($0.id) }
            let start = selected.map(\.startDate).min() ?? .now
            let end = Date.now
            return (start, end)
        case .byDate:
            return (customStart, customEnd)
        }
    }

    // MARK: - Export actions

    #if canImport(UIKit)
        /// The Journal Summary PDF for the scope: the entries in range that pass the
        /// substance filter, the daily meds, and the interactions among them, written
        /// to a temporary file whose URL is returned.
        func exportJournalSummary(
            entries: [DoseEntry], dailyItems: [DailyDoseItem], colors: [SubstanceColor],
        ) async -> URL {
            let range = reportDateRange
            let filteredEntries = entries.filter {
                $0.timestamp >= range.start && $0.timestamp <= range.end
                    && isSubstanceIncluded($0.substance)
            }

            let entrySnapshots = filteredEntries.map { entry in
                PDFReportGenerator.EntrySnapshot(
                    substance: entry.substance,
                    amount: entry.amount,
                    unit: entry.unit,
                    route: entry.route.displayName,
                    timestamp: entry.timestamp,
                    notes: entry.notes,
                    isUnknownDose: entry.isUnknownDose,
                    identityKey: entry.identityKey,
                    routeRaw: entry.route.rawValue,
                    substanceID: SubstanceStore.shared.substanceID(forNameOrAlias: entry.substance),
                    halfLifeMinutes: SubstanceLibrary.lookup(entry.substance)?.halfLifeMinutes,
                    combinationName: entry.combinationName,
                )
            }

            let products = CustomSubstanceStore.shared.productMeds
            let doseSnapshots = dailyItems.map { item in
                PDFReportGenerator.DailyDoseSnapshot(
                    substance: item.substance,
                    amount: item.amount,
                    unit: item.unit,
                    route: item.route.displayName,
                    sortOrder: item.sortOrder,
                    identityKey: item.identityKey,
                    routeRaw: item.route.rawValue,
                    product: products[item.substance.lowercased()],
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

            let tintMap = colors.tintMap
            let journalSummary = SummaryStatsResolver.report(
                entries: filteredEntries, tintMap: tintMap, start: range.start, end: range.end,
                journalStart: entries.map(\.timestamp).min(),
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
            let compressed = SummaryStats.compressInteractions(compressedRaw)
            let findings = SummaryStats.findings(report: journalSummary, interactions: compressed)

            var data = PDFReportGenerator.ReportData(
                entries: entrySnapshots,
                dailyDoseItems: doseSnapshots,
                interactions: interactionSnapshots,
                startDate: range.start,
                endDate: range.end,
                notes: "",
                patientName: "",
            )
            data.clinical = journalSummary
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

            return url
        }
    #endif

    func exportSessionImages(
        sessions: [Session], colors: [SubstanceColor], scheme: ColorScheme,
    ) async -> [PlatformImage] {
        var images: [PlatformImage] = []
        let stackRedoses = UserDefaults(suiteName: AppIdentity.appGroup)?.bool(forKey: "stackRedoses") ?? true
        for session in sessions {
            guard selectedSessions.contains(session.id) else { continue }
            let entries = (session.doses ?? []).sorted { $0.timestamp < $1.timestamp }
            guard !entries.isEmpty else { continue }
            let dateText = session.startDate.formatted(date: .abbreviated, time: .omitted)
            if let image = SessionShareImage.render(
                title: session.title ?? "",
                dateText: dateText,
                entries: entries,
                colors: colors,
                stackRedoses: stackRedoses,
                scheme: scheme,
            ) {
                images.append(image)
            }
        }
        return images
    }

    func exportStitchedImage(_ images: [PlatformImage]) -> PlatformImage? {
        guard !images.isEmpty else { return nil }
        #if canImport(UIKit)
            let spacing: CGFloat = 24
            let totalHeight = images.reduce(CGFloat(0)) { $0 + $1.size.height } + spacing * CGFloat(images.count - 1)
            let maxWidth = images.reduce(CGFloat(0)) { max($0, $1.size.width) }

            let renderer = UIGraphicsImageRenderer(size: CGSize(width: maxWidth, height: totalHeight))
            return renderer.image { _ in
                var y: CGFloat = 0
                for image in images {
                    let x = (maxWidth - image.size.width) / 2
                    image.draw(at: CGPoint(x: x, y: y))
                    y += image.size.height + spacing
                }
            }
        #else
            return images.first
        #endif
    }

    func exportMarkdown(sessions: [Session], colors: [SubstanceColor]) async -> String {
        var parts: [String] = []
        for session in sessions {
            guard selectedSessions.contains(session.id) else { continue }
            let entries = (session.doses ?? []).sorted { $0.timestamp < $1.timestamp }
            guard !entries.isEmpty else { continue }
            if let export = SessionStateExport.build(from: entries, colors: colors, notes: session.orderedNotes) {
                parts.append(export.markdown())
            }
        }
        return parts.joined(separator: "\n\n---\n\n")
    }

    /// The selected sessions that have at least one timeline note — the ones
    /// a trip report exists for.
    func sessionsWithNotes(in sessions: [Session]) -> [Session] {
        sessions.filter { selectedSessions.contains($0.id) && TripReport.hasNotes($0) }
    }

    /// One trip report per selected session with notes, oldest first, joined
    /// as a single Markdown document. Empty when no selected session has notes.
    func exportTripReports(sessions: [Session]) -> String {
        sessionsWithNotes(in: sessions)
            .sorted { $0.startDate < $1.startDate }
            .map { TripReport.build(session: $0).markdown() }
            .joined(separator: "\n\n---\n\n")
    }
}
