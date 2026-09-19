import Foundation

/// A session rendered as the document psychonauts share: what was taken, then
/// every observation at its T+ offset, then the descriptors grouped by domain
/// with the moment each was first noted, then the summary. Built once on the
/// main actor into value types (every substance and vocabulary lookup
/// pre-resolved), rendered as Markdown anywhere.
///
/// English on purpose — like the JSON exports, it is the portable form; the
/// on-screen session is the localized one.
struct TripReport {
    let title: String?
    let sessionStart: Date
    let doses: [Dose]
    let notes: [Note]
    let summary: String?

    struct Dose: Identifiable {
        let id: UUID
        let timestamp: Date
        let name: String
        let amount: Double
        let unit: String
        let route: String
        /// A dose with no amount; the table prints `?` for it.
        var isUnknownDose = false
        /// The modeled phase boundaries as clock times, in order, when the
        /// substance carries duration data. Empty for a dose that draws no
        /// curve — the report then simply has no course to state for it.
        var phases: [Phase] = []

        var amountDisplay: String {
            isUnknownDose ? "?" : amount.doseFormatted
        }
    }

    /// One modeled moment of a dose's arc, named in the portable English the
    /// rest of this document is written in.
    struct Phase: Hashable {
        let label: String
        let at: Date

        /// The column order the modeled-course table prints, so every row lines
        /// up even when a dose has no onset phase to state.
        static let reportLabels = ["kicks in", "peak begins", "starts wearing off", "effects end"]
    }

    struct Note: Identifiable {
        let id: UUID
        let timestamp: Date
        let kind: SessionNote.Kind
        let text: String
        let shulgin: Int?
        let mood: Int?
        let energy: Int?
        let social: Int?
        let worked: Int?
        let heartRate: Int?
        /// Descriptor concepts the vocabulary resolves, in the order they were
        /// chosen.
        let descriptors: [Descriptor]
    }

    struct Descriptor: Hashable {
        let id: String
        let name: String
        let domain: String
    }

    /// One descriptor's first appearance, for the by-domain table.
    struct FirstNoted: Hashable {
        let descriptor: Descriptor
        let at: Date
    }

    var isEmpty: Bool {
        notes.isEmpty
    }

    /// The substances taken, in order of first dose, each once.
    var substances: [String] {
        var seen = Set<String>()
        return doses.map(\.name).filter { seen.insert($0).inserted }
    }

    // MARK: - Build

    /// Whether a report exists for the session: at least one timeline note
    /// with content (the summary alone is the session's, not a report's).
    @MainActor
    static func hasNotes(_ session: Session) -> Bool {
        (session.notes ?? []).contains { $0.kind != .summary && $0.hasContent }
    }

    @MainActor
    static func build(session: Session) -> TripReport {
        let ontology = SubjectiveEffectOntology.shared
        let doses = session.orderedDoses.map { entry in
            Dose(
                id: entry.id,
                timestamp: entry.timestamp,
                name: DoseTitle.resolve(for: entry),
                amount: entry.amount,
                unit: entry.unit,
                route: entry.route.displayName,
                isUnknownDose: entry.isUnknownDose,
                phases: phases(for: entry),
            )
        }
        let notes = session.orderedNotes.filter { $0.kind != .summary && $0.hasContent }.map { note in
            Note(
                id: note.id,
                timestamp: note.timestamp,
                kind: note.kind,
                text: note.text,
                shulgin: note.shulgin,
                mood: note.mood,
                energy: note.energy,
                social: note.social,
                worked: note.worked,
                heartRate: note.heartRate.map { Int($0.rounded()) },
                descriptors: note.descriptors.compactMap { id in
                    ontology.concept(id: id).map { Descriptor(id: id, name: $0.name, domain: $0.domain) }
                },
            )
        }
        return TripReport(
            title: session.title,
            sessionStart: session.startDate,
            doses: doses,
            notes: notes,
            summary: session.note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? session.note : nil,
        )
    }

    /// The modeled course of one dose as clock times. Read off the same
    /// ``ActiveSubstanceState`` the timeline draws, so a report and the curve
    /// it was written against cannot disagree.
    ///
    /// These are population-median phase boundaries, not a measurement of this
    /// session — the footer says so, once.
    @MainActor
    private static func phases(for entry: DoseEntry) -> [Phase] {
        guard let state = ActiveSubstanceState.from(entry: entry, colorHex: "#888888") else { return [] }
        func at(_ minutes: Double) -> Date { entry.timestamp.addingTimeInterval(minutes * 60) }
        var rows = [
            Phase(label: "kicks in", at: at(state.onsetEndMinutes)),
            Phase(label: "peak begins", at: at(state.comeupEndMinutes)),
            Phase(label: "starts wearing off", at: at(state.peakEndMinutes)),
            Phase(label: "effects end", at: at(max(state.offsetEndMinutes, state.totalMinutes))),
        ]
        // A profile with no onset phase puts "kicks in" on the dose itself,
        // which says nothing.
        if state.onsetEndMinutes <= 0 { rows.removeFirst() }
        return rows
    }

    // MARK: - T+ offsets

    /// `T+1:20` style offset from the session start; minutes zero-padded, a
    /// leading minus for a note placed before the first dose.
    nonisolated static func tPlus(_ interval: TimeInterval) -> String {
        let totalMinutes = Int((abs(interval) / 60).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        let sign = interval < 0 && totalMinutes > 0 ? "−" : ""
        return String(format: "T%@+%d:%02d", sign, hours, minutes)
    }

    func tPlus(_ date: Date) -> String {
        Self.tPlus(date.timeIntervalSince(sessionStart))
    }

    // MARK: - Descriptors by domain

    /// Every descriptor noted in the session, grouped by domain (domains in
    /// order of first appearance), each carrying the timestamp it was first
    /// noted at.
    var descriptorsByDomain: [(domain: String, first: [FirstNoted])] {
        var firstSeen: [Descriptor: Date] = [:]
        var domainOrder: [String] = []
        for note in notes {
            for descriptor in note.descriptors where firstSeen[descriptor] == nil {
                firstSeen[descriptor] = note.timestamp
                if !domainOrder.contains(descriptor.domain) { domainOrder.append(descriptor.domain) }
            }
        }
        return domainOrder.map { domain in
            let rows = firstSeen
                .filter { $0.key.domain == domain }
                .map { FirstNoted(descriptor: $0.key, at: $0.value) }
                .sorted { ($0.at, $0.descriptor.name) < ($1.at, $1.descriptor.name) }
            return (domain, rows)
        }
    }

    // MARK: - Structure line

    /// The structured part of a note as one line: `++ · about right · mood +2 ·
    /// energy −1 · social +3 · ♥ 84` — every piece optional, nothing invented.
    /// Empty when the note has no structure.
    nonisolated static func structureLine(
        shulgin: Int?, mood: Int?, energy: Int?, social: Int? = nil, worked: Int? = nil,
        heartRate: Int?,
    ) -> String {
        var parts: [String] = []
        if let shulgin, let glyph = ShulginScale.glyph(shulgin) { parts.append(glyph) }
        if let worked, let word = WorkedScale.exportWord(worked) { parts.append(word) }
        if let mood { parts.append("mood \(signed(mood))") }
        if let energy { parts.append("energy \(signed(energy))") }
        if let social { parts.append("social \(signed(social))") }
        if let heartRate { parts.append("♥ \(heartRate)") }
        return parts.joined(separator: " · ")
    }

    nonisolated static func signed(_ value: Int) -> String {
        value > 0 ? "+\(value)" : value < 0 ? "−\(abs(value))" : "0"
    }

    /// A note flattened to one text line (the structure, the descriptors, then
    /// the text) for formats with a single text field per note (PsyLog).
    @MainActor
    static func flattenedLine(for note: SessionNote) -> String {
        let ontology = SubjectiveEffectOntology.shared
        var pieces: [String] = []
        let structure = structureLine(
            shulgin: note.shulgin, mood: note.mood, energy: note.energy,
            social: note.social, worked: note.worked,
            heartRate: note.heartRate.map { Int($0.rounded()) },
        )
        if !structure.isEmpty { pieces.append("[\(structure)]") }
        let descriptors = note.descriptors.compactMap(ontology.name(for:))
        if !descriptors.isEmpty {
            pieces.append("[" + descriptors.joined(separator: ", ") + "]")
        }
        if !note.text.isEmpty { pieces.append(note.text) }
        return pieces.joined(separator: " ")
    }

    // MARK: - Markdown

    /// The mood/energy cell of the timeline table: `+2 / 0`, with `–` for a
    /// side not captured and empty when neither was.
    nonisolated static func moodEnergyCell(mood: Int?, energy: Int?, heartRate: Int? = nil) -> String {
        var cell = ""
        if mood != nil || energy != nil {
            cell = (mood.map(signed) ?? "–") + " / " + (energy.map(signed) ?? "–")
        }
        if let heartRate {
            cell += (cell.isEmpty ? "" : " · ") + "♥ \(heartRate)"
        }
        return cell
    }

    /// Text made safe for one Markdown table cell: pipes escaped, line breaks
    /// kept as `<br>` so a multi-paragraph note stays one row.
    nonisolated static func cell(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "<br>")
    }

    /// The report as a Markdown document: a title naming the substances and
    /// the date, one line of counts, a dose table, the notes as a timeline
    /// table (T+, clock time, Shulgin, mood/energy, text), the descriptors by
    /// domain with the T+ each was first noted, the summary, and the footer.
    func markdown(locale: Locale = .current, calendar: Calendar = .current) -> String {
        let time = DateFormatter()
        time.locale = locale
        time.calendar = calendar
        time.timeZone = calendar.timeZone
        time.timeStyle = .short
        time.dateStyle = .none
        let dateOnly = DateFormatter()
        dateOnly.locale = locale
        dateOnly.calendar = calendar
        dateOnly.timeZone = calendar.timeZone
        dateOnly.dateStyle = .long
        dateOnly.timeStyle = .none

        var out: [String] = []
        let substanceLine = substances.joined(separator: " + ")
        let headline = title ?? (substanceLine.isEmpty ? "Trip report" : substanceLine)
        out.append("# \(headline) — \(dateOnly.string(from: sessionStart))")
        out.append("")
        if title != nil, !substanceLine.isEmpty {
            out.append("**\(substanceLine)**")
            out.append("")
        }
        var facts = [
            "Started \(time.string(from: sessionStart))",
            doses.count == 1 ? "1 dose" : "\(doses.count) doses",
            notes.count == 1 ? "1 note" : "\(notes.count) notes",
        ]
        if let last = notes.last { facts.append("last note at \(tPlus(last.timestamp))") }
        out.append(facts.joined(separator: " · "))
        out.append("")

        out.append("## Doses")
        out.append("")
        out.append("| T+ | Time | Substance | Dose | Route |")
        out.append("|---|---|---|---|---|")
        for dose in doses {
            out.append("| \(tPlus(dose.timestamp)) | \(time.string(from: dose.timestamp)) | \(Self.cell(dose.name)) | \(dose.amountDisplay) \(dose.unit) | \(dose.route.lowercased()) |")
        }
        out.append("")

        let course = doses.filter { !$0.phases.isEmpty }
        if !course.isEmpty {
            out.append("## Modeled course")
            out.append("")
            out.append("Population-median phase boundaries for each dose, as clock times — what was expected, to read the notes against.")
            out.append("")
            out.append("| Substance | " + Phase.reportLabels.joined(separator: " | ") + " |")
            out.append("|---" + String(repeating: "|---", count: Phase.reportLabels.count) + "|")
            for dose in course {
                let byLabel = Dictionary(dose.phases.map { ($0.label, $0.at) }, uniquingKeysWith: { first, _ in first })
                let cells = Phase.reportLabels.map { label in
                    byLabel[label].map { time.string(from: $0) } ?? "–"
                }
                out.append("| \(Self.cell(dose.name)) | " + cells.joined(separator: " | ") + " |")
            }
            out.append("")
        }

        // Only the columns this session actually recorded: an empty Shulgin
        // column down a stimulant report is noise, and a reader cannot tell it
        // apart from a session where nobody rated anything.
        let hasShulgin = notes.contains { $0.shulgin != nil }
        let hasWorked = notes.contains { $0.worked != nil }
        let hasMoodEnergy = notes.contains { $0.mood != nil || $0.energy != nil || $0.heartRate != nil }
        let hasSocial = notes.contains { $0.social != nil }
        var headers = ["T+", "Time"]
        if hasWorked { headers.append("Worked") }
        if hasShulgin { headers.append("Shulgin") }
        if hasMoodEnergy { headers.append("Mood / Energy") }
        if hasSocial { headers.append("Social") }
        headers.append("Note")

        out.append("## Timeline")
        out.append("")
        out.append("| " + headers.joined(separator: " | ") + " |")
        out.append("|" + String(repeating: "---|", count: headers.count))
        for note in notes {
            var cells = [tPlus(note.timestamp), time.string(from: note.timestamp)]
            if hasWorked { cells.append(note.worked.flatMap(WorkedScale.exportWord) ?? "") }
            if hasShulgin { cells.append(note.shulgin.flatMap(ShulginScale.glyph) ?? "") }
            if hasMoodEnergy {
                cells.append(Self.moodEnergyCell(mood: note.mood, energy: note.energy, heartRate: note.heartRate))
            }
            if hasSocial { cells.append(note.social.map(Self.signed) ?? "") }
            var text: [String] = []
            if note.kind == .checkIn { text.append("**Check-in**") }
            if !note.text.isEmpty { text.append(Self.cell(note.text)) }
            if !note.descriptors.isEmpty { text.append("_" + note.descriptors.map(\.name).joined(separator: " · ") + "_") }
            cells.append(text.joined(separator: " — "))
            out.append("| " + cells.joined(separator: " | ") + " |")
        }
        out.append("")

        let grouped = descriptorsByDomain
        if !grouped.isEmpty {
            out.append("## Descriptors by domain")
            out.append("")
            out.append("First noted at the T+ shown. Vocabulary: SubFxOnEx (drug.community).")
            out.append("")
            out.append("| Domain | Descriptor | First noted |")
            out.append("|---|---|---|")
            for (domain, rows) in grouped {
                for row in rows {
                    out.append("| \(domain.capitalized) | \(Self.cell(row.descriptor.name)) | \(tPlus(row.at)) |")
                }
            }
            out.append("")
        }

        if let summary {
            out.append("## Summary")
            out.append("")
            out.append(summary)
            out.append("")
        }

        out.append("---")
        out.append("")
        out.append("_Not medical advice. A record of one session, written with Piru._")
        return out.joined(separator: "\n")
    }
}
