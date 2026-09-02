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
    }

    struct Note: Identifiable {
        let id: UUID
        let timestamp: Date
        let kind: SessionNote.Kind
        let text: String
        let shulgin: Int?
        let mood: Int?
        let energy: Int?
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

    /// The structured part of a note as one line: `++ · mood +2 · energy −1 ·
    /// ♥ 84` — every piece optional, nothing invented. Empty when the note has
    /// no structure.
    nonisolated static func structureLine(shulgin: Int?, mood: Int?, energy: Int?, heartRate: Int?) -> String {
        var parts: [String] = []
        if let shulgin, let glyph = ShulginScale.glyph(shulgin) { parts.append(glyph) }
        if let mood { parts.append("mood \(signed(mood))") }
        if let energy { parts.append("energy \(signed(energy))") }
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
            out.append("| \(tPlus(dose.timestamp)) | \(time.string(from: dose.timestamp)) | \(Self.cell(dose.name)) | \(dose.amount.doseFormatted) \(dose.unit) | \(dose.route.lowercased()) |")
        }
        out.append("")

        out.append("## Timeline")
        out.append("")
        out.append("| T+ | Time | Shulgin | Mood / Energy | Note |")
        out.append("|---|---|---|---|---|")
        for note in notes {
            let shulgin = note.shulgin.flatMap(ShulginScale.glyph) ?? ""
            let moodEnergy = Self.moodEnergyCell(mood: note.mood, energy: note.energy, heartRate: note.heartRate)
            var text: [String] = []
            if note.kind == .checkIn { text.append("**Check-in**") }
            if !note.text.isEmpty { text.append(Self.cell(note.text)) }
            if !note.descriptors.isEmpty { text.append("_" + note.descriptors.map(\.name).joined(separator: " · ") + "_") }
            out.append("| \(tPlus(note.timestamp)) | \(time.string(from: note.timestamp)) | \(shulgin) | \(moodEnergy) | \(text.joined(separator: " — ")) |")
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
