import Foundation
import SwiftData

/// The single choke point for **mutating the dose log**, and the one place a "the dose log changed"
/// signal is emitted. Derived caches (the tolerance engine) subscribe to ``changes`` and refresh in the
/// background, so no user-interactive path ever triggers a heavy recompute.
///
/// ## Why a service, not a notification
/// SwiftData exposes no public save notification, and the dose-write paths are scattered (quick-log
/// tray, entry form, daily-dose log, edits/deletes, import, and the planned Watch `WCSessionDelegate`).
/// Routing them through one type makes the change signal impossible to forget and gives a single seam to
/// optimize later. The watch is *phone-authoritative* (`Specs/apple-watch-companion.md`): its doses
/// arrive over WatchConnectivity and the phone inserts them here, in-process — so this remains the sole
/// writer and SwiftData History (a cross-process tool) isn't needed.
///
/// ## Canonical vs. batch
/// ``log(_:in:recentEntries:)`` is the canonical single-dose pipeline (insert → session assignment →
/// save → harm-reduction notifications → signal) for new callers (the entry form path, the Watch
/// receiver). Paths that batch many inserts behind one `save()` for frame-budget reasons (the quick-log
/// tray, import) keep their own commit and just call ``changed()`` afterward — funneling each row through
/// `log()` would break that intentional batching and double the per-row side effects they already run.
@MainActor
final class DoseLogService {
    static let shared = DoseLogService()

    /// Emits once per committed dose-log change. `bufferingNewest(1)`: a burst coalesces to a single
    /// pending tick (the consumer debounces regardless) and the most recent signal is never dropped.
    let changes: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    init() {
        (changes, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    /// Canonical single-dose log: insert, assign its session, save, fire harm-reduction notifications,
    /// then signal. For the entry-form path and the Watch receiver — callers that log exactly one dose.
    func log(_ entry: DoseEntry, in context: ModelContext, recentEntries: [DoseEntry] = []) {
        context.insert(entry)
        SessionService.assignSession(for: entry, in: context)
        try? context.save()
        DoseNotificationManager.doseLogged(entry: entry, recentEntries: recentEntries)
        changed()
    }

    /// Delete a dose, save, and signal.
    func delete(_ entry: DoseEntry, in context: ModelContext) {
        context.delete(entry)
        try? context.save()
        changed()
    }

    /// Announce that the dose log changed after a commit the caller performed itself — an in-place edit,
    /// the quick-log tray's batched multi-insert, or an import. The caller owns insert/edit + `save()`;
    /// this only emits the change tick that wakes the derived caches.
    func changed() {
        continuation.yield(())
    }
}
