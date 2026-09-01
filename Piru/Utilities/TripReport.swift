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
        /// Resolved descriptor concepts, in the order they were chosen.
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

    // MARK: - Build

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
                descriptors: note.descriptors.map { id in
                    let concept = ontology.concept(id: id)
                    return Descriptor(id: id, name: concept?.name ?? id, domain: concept?.domain ?? "other")
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
        if !note.descriptors.isEmpty {
            pieces.append("[" + note.descriptors.map(ontology.name(for:)).joined(separator: ", ") + "]")
        }
        if !note.text.isEmpty { pieces.append(note.text) }
        return pieces.joined(separator: " ")
    }

    // MARK: - Markdown

    func markdown(locale: Locale = .current, calendar: Calendar = .current) -> String {
        let time = DateFormatter()
        time.locale = locale
        time.calendar = calendar
        time.timeStyle = .short
        time.dateStyle = .none
        let dateOnly = DateFormatter()
        dateOnly.locale = locale
        dateOnly.calendar = calendar
        dateOnly.dateStyle = .long
        dateOnly.timeStyle = .none

        var out: [String] = []
        out.append("# " + (title ?? "Trip report") + " — " + dateOnly.string(from: sessionStart))
        out.append("")
        out.append("- **Session started:** \(time.string(from: sessionStart))")
        out.append("- **Doses:** \(doses.count) · **Notes:** \(notes.count)")
        if let last = notes.last {
            out.append("- **Last note:** \(tPlus(last.timestamp))")
        }
        out.append("")

        out.append("## Doses")
        out.append("")
        out.append("| T+ | Time | Substance | Dose | Route |")
        out.append("|---|---|---|---|---|")
        for dose in doses {
            out.append("| \(tPlus(dose.timestamp)) | \(time.string(from: dose.timestamp)) | \(dose.name) | \(dose.amount.doseFormatted) \(dose.unit) | \(dose.route.lowercased()) |")
        }
        out.append("")

        out.append("## Timeline")
        out.append("")
        if notes.isEmpty {
            out.append("_No notes yet._")
            out.append("")
        }
        for note in notes {
            var head = "**\(tPlus(note.timestamp))** (\(time.string(from: note.timestamp)))"
            if note.kind == .checkIn { head += " · check-in" }
            let structure = Self.structureLine(shulgin: note.shulgin, mood: note.mood, energy: note.energy, heartRate: note.heartRate)
            if !structure.isEmpty { head += " · " + structure }
            out.append("- " + head)
            if !note.text.isEmpty {
                for line in note.text.split(separator: "\n", omittingEmptySubsequences: false) {
                    out.append("  " + (line.isEmpty ? "" : String(line)))
                }
            }
            if !note.descriptors.isEmpty {
                out.append("  _" + note.descriptors.map(\.name).joined(separator: " · ") + "_")
            }
        }
        out.append("")

        let grouped = descriptorsByDomain
        if !grouped.isEmpty {
            out.append("## Descriptors by domain")
            out.append("")
            out.append("First noted at the T+ shown. Vocabulary: SubFxOnEx (drug.community).")
            out.append("")
            for (domain, rows) in grouped {
                out.append("### " + domain.capitalized)
                for row in rows {
                    out.append("- \(row.descriptor.name) — \(tPlus(row.at))")
                }
                out.append("")
            }
        }

        if let summary {
            out.append("## Summary")
            out.append("")
            out.append(summary)
            out.append("")
        }

        out.append("---")
        out.append("_A record, not advice. Written with Piru._")
        return out.joined(separator: "\n")
    }
}
