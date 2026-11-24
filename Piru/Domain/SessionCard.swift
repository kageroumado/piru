import Foundation

/// One session's card model, with its timeline inputs precomputed (in
/// `JournalModel.rebuildGroups`) so the card's mini graph never re-derives PK
/// curves while scrolling. Text — time label, substance summary, dose count — is
/// formatted **once here** rather than on every `SessionCardView` body pass.
/// Equatable so SwiftUI can skip a `SessionCardView` body re-eval when the parent
/// hands it a content-identical card: the progressive derive republishes the
/// card array (prefix paint, then tail), and without this every card would
/// re-render on the second pass. All stored fields are Equatable (value types, plus `@Model`
/// `Session`/`DoseEntry` which compare by identity, and `ActiveSubstanceState` /
/// `DoseMarker` which are `Hashable`).
struct SessionCard: Identifiable, Equatable {
    /// The session's stable id, used for navigation. For a (rare) session-less
    /// straggler this is a fresh UUID and the card is non-navigable.
    let id: UUID
    /// The models the card was built from, for an action taken on the card (a
    /// tap's route, the context menu). A view's `body` reads the card's own
    /// fields instead: the card outlives a commit by one debounced regroup,
    /// and a deleted model's attributes trap on read.
    let session: Session?
    let entries: [DoseEntry]
    /// ``Session/id``, `nil` for a session-less straggler.
    let sessionID: UUID?
    /// Each dose's timestamp, in `entries` order.
    let doseTimestamps: [Date]
    let states: [ActiveSubstanceState]
    let markers: [DoseMarker]
    let isMaintenance: Bool
    let startDate: Date
    /// User-given session title, if any.
    let title: String?
    /// Clock label — a single start time, or "start – end" for a span.
    let timeLabel: String
    let uniqueSubstances: [String]
    let substanceSummary: String
    let doseCountText: String

    /// Built once rather than per card — the clock format is constant.
    private static let clock = Date.FormatStyle.dateTime.hour().minute()

    init(session: Session?, entries: [DoseEntry], states: [ActiveSubstanceState], markers: [DoseMarker]) {
        self.session = session
        self.entries = entries
        self.states = states
        self.markers = markers
        sessionID = session?.id
        id = sessionID ?? UUID()
        doseTimestamps = entries.map(\.timestamp)
        title = session?.title
        isMaintenance = session?.isMaintenance ?? (!entries.isEmpty && entries.allSatisfy(\.isBackgroundMed))

        let start = doseTimestamps.first ?? session?.startDate ?? .now
        startDate = start
        if let end = doseTimestamps.last, end.timeIntervalSince(start) >= 60 {
            timeLabel = "\(start.formatted(Self.clock)) – \(end.formatted(Self.clock))"
        } else {
            timeLabel = start.formatted(Self.clock)
        }

        // Order-preserving dedup without the NSOrderedSet/NSObject bridge — this
        // runs per windowed card inside the synchronous regroup, so the bridge
        // showed up in first-render profiles.
        var seen = Set<String>()
        var unique: [String] = []
        // Dose titles ("Concerta" for a Concerta dose), deduped independently so
        // two aliases of the same drug collapse to one.
        var seenDisplay = Set<String>()
        var display: [String] = []
        for entry in entries {
            let name = entry.substance
            if seen.insert(name).inserted { unique.append(name) }
            let shown = DoseTitle.resolve(for: entry)
            if seenDisplay.insert(shown.lowercased()).inserted { display.append(shown) }
        }
        uniqueSubstances = unique
        if display.count <= 3 {
            substanceSummary = display.joined(separator: ", ")
        } else {
            let first = display.prefix(3).joined(separator: ", ")
            substanceSummary = String(localized: "\(first) +\(display.count - 3) more")
        }
        doseCountText = entries.count == 1
            ? String(localized: "1 entry")
            : String(localized: "\(entries.count) entries")
    }
}

/// A day header plus the sessions that started that day — the unit the Journal
/// list renders as a `Section`.
struct SessionDay: Identifiable, Equatable {
    let date: Date
    let dateTitle: String
    let weekday: String
    let sessions: [SessionCard]
    var id: Date {
        date
    }

    init(date: Date, sessions: [SessionCard]) {
        self.date = date
        self.sessions = sessions
        // `date` names a journal day, so Today is the journal day now falls in.
        let cal = Calendar.current
        if cal.isJournalDayToday(date) {
            dateTitle = String(localized: "Today")
        } else if cal.isJournalDayYesterday(date) {
            dateTitle = String(localized: "Yesterday")
        } else {
            dateTitle = SessionDateTitle.day(date)
        }
        weekday = date.formatted(.dateTime.weekday(.wide))
    }
}

/// The date a session is titled by when the user gave it no title.
enum SessionDateTitle {
    /// "August 30", with the year only when it differs from the current one.
    static func day(_ date: Date) -> String {
        let base = Date.FormatStyle.dateTime.day().month(.wide)
        let sameYear = Calendar.current.isDate(date, equalTo: .now, toGranularity: .year)
        return date.formatted(sameYear ? base : base.year())
    }

    /// "Saturday, August 30": the session screen's title for an untitled session,
    /// which the session row, the card's share sheet and the entry screen's
    /// session link all repeat.
    static func full(_ date: Date) -> String {
        "\(date.formatted(.dateTime.weekday(.wide))), \(day(date))"
    }
}
