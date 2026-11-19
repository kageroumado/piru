import SwiftData
import SwiftUI

/// Adjusts a single dose's timestamp in place, then keeps the session accessory,
/// Live Activity, and pending reminders in sync with the new time on dismiss.
struct TimeAdjustSheet: View {
    @Bindable var entry: DoseEntry
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.sessionEditingService) private var editing
    @State private var originalTimestamp: Date?

    var body: some View {
        Form {
            DatePicker("Date & Time", selection: $entry.timestamp)
        }
        .navigationTitle("Adjust Time")
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .accessibilityLabel(Text("Close"))
            }
        }
        .onAppear { if originalTimestamp == nil { originalTimestamp = entry.timestamp } }
        .onDisappear {
            if let originalTimestamp { editing.retimed(entry, from: originalTimestamp, in: modelContext) }
        }
    }
}
