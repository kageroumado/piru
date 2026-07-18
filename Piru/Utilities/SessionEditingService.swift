import SwiftData
import SwiftUI

/// App-wide per-dose editing actions for the journal's session detail.
///
/// Env-injected so `DayEntryRow` invokes them directly instead of taking a
/// fistful of parent closures. Closures defeat SwiftUI's view-value comparison,
/// so the old eight-closure row re-evaluated on *every* unrelated detail-screen
/// toggle (graph expand, timeline enlarge, interactions expand, any sheet) —
/// re-running the heavy per-row substance resolve N times. With the actions
/// behind this stable env reference the row becomes `Equatable` on its display
/// value alone and SwiftUI skips it when nothing it shows changed.
///
/// The transient `*ToAdjustTime` / `*ToMove` / `*ToRecolor` intents are written
/// by a row's context-menu action and observed by `SessionDetailView` to drive
/// its sheets; the mutations run against the passed `ModelContext`.
@MainActor
@Observable
final class SessionEditingService {
    static let shared = SessionEditingService()

    /// A request to recolor a substance — `Identifiable` so it drives a
    /// `.sheet(item:)` without a closure binding.
    struct RecolorRequest: Identifiable {
        let id = UUID()
        let substanceName: String
    }

    /// Set by a row action; `SessionDetailView` presents the matching sheet.
    var entryToAdjustTime: DoseEntry?
    var entryToMove: DoseEntry?
    var recolorRequest: RecolorRequest?

    private init() {}

    func requestAdjustTime(_ entry: DoseEntry) {
        entryToAdjustTime = entry
    }
    func requestMove(_ entry: DoseEntry) {
        entryToMove = entry
    }
    func requestRecolor(_ substanceName: String) {
        recolorRequest = RecolorRequest(substanceName: substanceName)
    }

    /// Delete a dose, drop its pending reminders, and keep the live session /
    /// Live Activity snapshot in sync. Colors are fetched from the context so
    /// the row doesn't have to thread a `@Query` array through.
    func delete(_ entry: DoseEntry, in context: ModelContext) {
        // Capture before delete — the entry is invalid afterwards.
        let id = entry.id
        let name = entry.substance
        let timestamp = entry.timestamp

        DoseNotificationManager.doseDeleted(entryID: id, timestamp: timestamp)
        withAnimation {
            context.delete(entry)
        }

        let colors = (try? context.fetch(FetchDescriptor<SubstanceColor>())) ?? []
        ActiveSessionManager.shared.removeDose(
            id: id,
            substanceName: name,
            timestamp: timestamp,
            allColors: colors,
        )
    }

    /// Split the owning session so `entry` and every later dose become a new
    /// session. Derives the session from the dose's relationship.
    func split(at entry: DoseEntry, in context: ModelContext) {
        guard let session = entry.session else { return }
        withAnimation { _ = SessionService.split(session, at: entry, in: context) }
    }
}

extension EnvironmentValues {
    @Entry var sessionEditingService: SessionEditingService = .shared
}
