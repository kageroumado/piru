import SwiftData
import SwiftUI

/// One dose row in the day detail. Extracted from the inline `ForEach` body so
/// SwiftUI builds (and caches the generic metadata for) a single named row type
/// instead of re-instantiating the deep `NavigationLink`+swipe+contextMenu
/// modifier chain per entry on every list rebuild — which dominated day-view
/// entry as `makeViewList` + `swift_conformsToProtocol` churn.
struct DayEntryRow: View, Equatable {
    /// The dose model — used only by the swipe/menu *actions* (never read in
    /// `body`), so it never makes the row observe the entry. Kept out of `==`:
    /// all displayed content is compared via `display`, which is rebuilt from
    /// the entry upstream whenever it changes.
    let entry: DoseEntry
    let display: DayEntryDisplay
    let showRelativeTime: Bool
    /// `true` for any dose after the first — splitting "here" leaves doses behind.
    let canSplit: Bool

    @Environment(\.appNavigator) private var navigator
    @Environment(\.sessionEditingService) private var editing
    @Environment(\.modelContext) private var modelContext

    /// Compare on the render-ready `display` (a value type) + the two flags
    /// only — never on the `entry` reference (a SwiftData `@Model`; two refs to
    /// the same object always compare equal, which would freeze content updates).
    /// So a detail-screen toggle that leaves this row's data unchanged skips its
    /// body entirely.
    static func == (lhs: DayEntryRow, rhs: DayEntryRow) -> Bool {
        lhs.display == rhs.display
            && lhs.showRelativeTime == rhs.showRelativeTime
            && lhs.canSplit == rhs.canSplit
    }

    var body: some View {
        // A plain Button (not a NavigationLink) so the disclosure chevron lives
        // inside the row, aligned with the dose, rather than system-centered on the
        // full row height. Tighter vertical insets than the grouped default.
        Button {
            navigator.push(.entry(timestamp: display.core.timestamp, id: display.core.entryID))
        } label: {
            EntryRowView(display: display, showRelativeTime: showRelativeTime)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { editing.delete(entry, in: modelContext) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                editing.requestEdit(entry)
                navigator.push(.entry(timestamp: entry.timestamp, id: entry.id))
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.orange)
        }
        .contextMenu {
            Button { editing.requestAdjustTime(entry) } label: {
                Label("Adjust Time", systemImage: "clock")
            }
            Button { editing.requestRecolor(entry.substance) } label: {
                Label("Change Color", systemImage: "paintbrush")
            }
            Button {
                editing.requestEdit(entry)
                navigator.push(.entry(timestamp: entry.timestamp, id: entry.id))
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            if canSplit {
                Button { editing.split(at: entry, in: modelContext) } label: {
                    Label("Split Session Here", systemImage: "scissors")
                }
            }
            Button { editing.requestMove(entry) } label: {
                Label("Move to Session…", systemImage: "arrow.right.arrow.left")
            }
            Divider()
            Button(role: .destructive) { editing.delete(entry, in: modelContext) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
