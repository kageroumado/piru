import SwiftUI

/// The day-detail's dose-row list, with the session's notes interleaved in time
/// order. Takes value inputs only — `entries` for the row actions, prebuilt
/// `displays` for rendering, and the notes likewise — so it skips re-evaluation
/// when the parent re-runs for graph-state toggles.
struct SessionEntryListSection: View {
    let entries: [DoseEntry]
    let displays: [DayEntryDisplay]
    let notes: [SessionNote]
    let noteDisplays: [SessionNoteDisplay]
    let sessionID: UUID
    let isRecentDay: Bool

    /// One row of the merged timeline. Doses and notes are indexed into their
    /// own arrays so the rows keep their narrow value inputs.
    private enum Item: Identifiable {
        case dose(Int)
        case note(Int)

        var id: String {
            switch self {
            case let .dose(index): "dose-\(index)"
            case let .note(index): "note-\(index)"
            }
        }
    }

    /// Doses and notes merged by timestamp; a note at the same instant as a dose
    /// follows it.
    private var items: [Item] {
        var merged: [(Date, Int, Item)] = entries.indices.map { (entries[$0].timestamp, 0, .dose($0)) }
        merged += noteDisplays.indices.map { (noteDisplays[$0].timestamp, 1, .note($0)) }
        merged.sort { ($0.0, $0.1) < ($1.0, $1.1) }
        return merged.map(\.2)
    }

    var body: some View {
        Section {
            ForEach(items) { item in
                switch item {
                case let .dose(index):
                    DayEntryRow(
                        entry: entries[index],
                        display: displays[index],
                        showRelativeTime: isRecentDay,
                        canSplit: index != 0,
                    )
                    .equatable()
                    .id(entries[index].id)
                case let .note(index):
                    SessionNoteRow(
                        note: notes[index],
                        display: noteDisplays[index],
                        sessionID: sessionID,
                        showRelativeTime: isRecentDay,
                    )
                    .equatable()
                    .id(noteDisplays[index].id)
                }
            }
        } footer: {
            Text(footerText)
        }
    }

    /// The dose count and, for a multi-dose session, its span — moved off a section
    /// *header* (a bare counter that only bought breathing room) into the footer,
    /// where a count-plus-duration reads as a proper caption and the entries lead
    /// straight into their card.
    private var footerText: String {
        let countText = entries.count == 1
            ? String(localized: "1 dose")
            : String(localized: "\(entries.count) doses")
        let noteText = noteDisplays.isEmpty ? "" : " · " + (noteDisplays.count == 1
            ? String(localized: "1 note")
            : String(localized: "\(noteDisplays.count) notes"))
        guard let first = entries.first?.timestamp,
              let last = entries.last?.timestamp,
              last > first else { return countText + noteText }
        return "\(countText) · \(last.timeIntervalSince(first).durationHM)" + noteText
    }
}
