import Foundation
import SwiftData
import WidgetKit

/// The single choke point for **mutating the dose log**, and the one place a "the dose log changed"
/// signal is emitted. Derived caches (the tolerance engine) subscribe via ``changeStream()`` and refresh
/// in the background, so no user-interactive path ever triggers a heavy recompute.
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
@Observable @MainActor
final class DoseLogService {
    static let shared = DoseLogService()

    /// Monotonic commit counter, bumped once per committed dose-log change. Views key `.task(id:)`
    /// off this instead of hashing model arrays in `body` — one observed `Int`, one invalidation
    /// per commit, and no per-field Observation subscriptions on the models themselves.
    private(set) var revision = 0

    /// One continuation per live subscriber — ``changed()`` broadcasts to all of them.
    @ObservationIgnored private var changeContinuations: [UUID: AsyncStream<Void>.Continuation] = [:]

    /// The in-flight deferred-bookkeeping task. Superseded (not abandoned) by a
    /// fresh ``scheduleDeferredBookkeeping(forSubstances:in:bookkeeping:)`` — see
    /// that method's note on why pending work accumulates rather than dropping.
    @ObservationIgnored private var deferralTask: Task<Void, Never>?
    /// Substances whose inventory still needs a scoped recompute, unioned across
    /// every schedule since the last flush.
    @ObservationIgnored private var pendingSubstances: Set<String> = []
    /// Per-site notification work (one closure per commit) still owed, run in
    /// order on the next flush. `@MainActor` — they touch `@Model` entries.
    @ObservationIgnored private var pendingBookkeeping: [@MainActor () -> Void] = []

    /// A fresh stream of dose-log change ticks for one subscriber. Every caller MUST mint its
    /// own stream: `AsyncStream` is single-consumer, and several loops iterating a shared one
    /// compete — each tick resumes exactly one of them, so the others silently go stale.
    /// `bufferingNewest(1)`: a burst coalesces to a single pending tick (consumers debounce
    /// regardless) and the most recent signal is never dropped.
    func changeStream() -> AsyncStream<Void> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        changeContinuations[id] = continuation
        continuation.onTermination = { _ in
            Task { @MainActor in
                DoseLogService.shared.changeContinuations[id] = nil
            }
        }
        return stream
    }

    /// Delay before the deferred bookkeeping runs — long enough to clear a
    /// sheet's dismissal animation so it doesn't drop frames.
    private static let deferralDelay: Duration = .milliseconds(450)

    /// Canonical single-dose log: insert, assign its session, save, fire harm-reduction notifications,
    /// then signal. For the entry-form path and the Watch receiver — callers that log exactly one dose.
    func log(_ entry: DoseEntry, in context: ModelContext, recentEntries: [DoseEntry] = []) {
        context.insert(entry)
        SessionService.assignSession(for: entry, in: context)
        try? context.save()
        DoseNotificationManager.doseLogged(entry: entry, recentEntries: recentEntries, in: context)
        // A logged dose may satisfy a routine — reconcile so its remaining
        // follow-up re-asks for today are cancelled.
        DoseNotificationManager.syncMedReminders(in: context)
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
        revision += 1
        for continuation in changeContinuations.values {
            continuation.yield(())
        }
    }

    /// Schedule the post-commit bookkeeping that **isn't on screen** — the scoped
    /// inventory recompute (its stock math runs off-main), the per-entry
    /// harm-reduction notifications, and one `WidgetCenter` timeline reload — to
    /// run *after* the UI transition settles. This is the work that, run
    /// synchronously before `dismiss()`, dropped frames on the dismissal: the
    /// blanket `InventoryService.recomputeAll` (O(items × doses) on main) and the
    /// `reloadAllTimelines()` IPC.
    ///
    /// Uses the utility-`Task` + `Task.sleep` deferral idiom (not
    /// `DispatchQueue.main.asyncAfter`): cancellable, and the scheduler can stall
    /// it further while the main actor is busy — "run it when resources are
    /// free." A rapid second commit **supersedes** the timer but *accumulates*
    /// its work: `substances` is unioned and the `bookkeeping` closure is queued,
    /// so coalescing only ever merges the two flushes (one widget reload, one
    /// inventory pass over the union) — it never drops a recompute or a
    /// notification. `bookkeeping` carries the site-specific notification work
    /// (e.g. `DoseNotificationManager.doseLogged` per created entry); the
    /// inventory recompute + widget reload are owned here.
    func scheduleDeferredBookkeeping(
        forSubstances substances: Set<String>,
        in context: ModelContext,
        bookkeeping: @escaping @MainActor () -> Void = {},
    ) {
        pendingSubstances.formUnion(substances)
        pendingBookkeeping.append(bookkeeping)
        deferralTask?.cancel()
        deferralTask = Task(priority: .utility) { [weak self] in
            try? await Task.sleep(for: Self.deferralDelay)
            guard !Task.isCancelled, let self else { return }
            let substances = self.pendingSubstances
            let bookkeeping = self.pendingBookkeeping
            self.pendingSubstances = []
            self.pendingBookkeeping = []
            await InventoryService.recompute(forSubstances: substances, offMainIn: context)
            for work in bookkeeping {
                work()
            }
            // Batched commits (quick-log tray, import) may satisfy a routine —
            // reconcile so its remaining follow-up re-asks are cancelled.
            DoseNotificationManager.syncMedReminders(in: context)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
