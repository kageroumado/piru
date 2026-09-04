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

    // MARK: - Clinical report fields

    var reportOptionsExpanded = false
    var patientName = ""
    var notes = ""

    // MARK: - Export state

    var isExporting = false
    var exportProgress: String?
    var shareItems: [Any]?

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
        let substances: [String]
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

            var seen = Set<String>()
            var unique: [String] = []
            var displayNames: [String] = []
            var seenDisplay = Set<String>()
            for name in doses.map(\.substance) {
                if seen.insert(name).inserted { unique.append(name) }
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
                substances: unique,
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

    var selectedSessionCount: Int {
        switch mode {
        case .latest: selectedSessions.count
        case .byDate: 0
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

    // MARK: - Export actions (wired in a later pass)

    func exportSessionImages(
        sessions: [Session], colors: [SubstanceColor], scheme: ColorScheme,
    ) async -> [PlatformImage] {
        var images: [PlatformImage] = []
        let stackRedoses = UserDefaults(suiteName: "group.dev.yumeji.piru")?.bool(forKey: "stackRedoses") ?? true
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
