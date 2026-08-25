import SwiftData
import SwiftUI

/// Adjusts a single dose's timestamp in place, then keeps the session accessory,
/// Live Activity, and pending reminders in sync with the new time on dismiss.
struct TimeAdjustSheet: View {
    @Bindable var entry: DoseEntry
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var substanceColors: [SubstanceColor]
    @State private var originalTimestamp: Date?

    var body: some View {
        Form {
            DatePicker("Date & Time", selection: $entry.timestamp)
        }
        .navigationTitle("Adjust Time")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .accessibilityLabel(Text("Cancel"))
            }
        }
        .onAppear { if originalTimestamp == nil { originalTimestamp = entry.timestamp } }
        .onDisappear {
            // Keep the session accessory + Live Activity in sync with the edited
            // time (they read ActiveSessionManager's snapshot, not SwiftData).
            guard let original = originalTimestamp, original != entry.timestamp else { return }
            entry.session?.refreshDoseBounds()
            ActiveSessionManager.shared.refreshEditedEntry(
                previousTimestamp: original,
                entry: entry,
                allColors: Array(substanceColors),
            )
            // Pending reminders are keyed to the old timestamp — a moved dose
            // must drop them and reschedule from its new time.
            DoseNotificationManager.doseRescheduled(entry: entry, previousTimestamp: original, in: modelContext)
            DoseLogService.shared.changed()
        }
    }
}
