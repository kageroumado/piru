import SwiftUI

/// The day-detail's dose-row list. Takes value inputs only — `entries` for the
/// row actions, prebuilt `displays` for rendering — so it skips re-evaluation
/// when the parent re-runs for graph-state toggles.
struct SessionEntryListSection: View {
    let entries: [DoseEntry]
    let displays: [DayEntryDisplay]
    let isRecentDay: Bool

    var body: some View {
        Section {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                DayEntryRow(
                    entry: entry,
                    display: displays[index],
                    showRelativeTime: isRecentDay,
                    canSplit: index != 0,
                )
                .equatable()
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
        guard let first = entries.first?.timestamp,
              let last = entries.last?.timestamp,
              last > first else { return countText }
        return "\(countText) · \(last.timeIntervalSince(first).durationHM)"
    }
}
