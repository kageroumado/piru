import Foundation
import os
import SwiftData
import WidgetKit

private nonisolated let logger = Logger(subsystem: "dev.yumeji.piru", category: "DoseLog")

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
/// save → harm-reduction notifications → signal) for callers that log exactly one dose (the entry
/// form path, the Watch receiver). ``logBatch(_:colors:in:beforeSave:deferredBookkeeping:)`` is the
/// batch entry point: many inserts behind one `save()` for frame-budget reasons (the quick-log tray,
/// both daily-med surfaces), with site-specific mutations riding the same commit via `beforeSave` and
/// per-entry notification work deferred past the dismissal via `deferredBookkeeping`. Import keeps its
/// own commit shape and just calls ``changed()`` afterward.
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

    /// Batch log: insert every dose, assign sessions, commit once, then run the shared post-commit
    /// pipeline (live-session update → change signal → deferred bookkeeping). `colors` is the caller's
    /// current `SubstanceColor` snapshot; a first-time substance gets a deterministic palette color
    /// inserted in the same commit and visible to the Live Activity immediately. `beforeSave` runs
    /// extra mutations inside the same commit (e.g. quick-log chip curation), so the per-save `@Query`
    /// invalidation storm fires once. `deferredBookkeeping` carries per-entry notification work into
    /// ``scheduleDeferredBookkeeping(forSubstances:in:bookkeeping:)``'s post-dismissal flush. An empty
    /// batch is a complete no-op — no save, no signal.
    func logBatch(
        _ doses: [(entry: DoseEntry, substance: Substance?)],
        colors: [SubstanceColor],
        in context: ModelContext,
        beforeSave: () -> Void = {},
        deferredBookkeeping: @escaping @MainActor () -> Void = {},
    ) {
        guard !doses.isEmpty else { return }
        var colors = colors
        for (entry, _) in doses {
            context.insert(entry)
            SessionService.assignSession(for: entry, in: context)
            // Auto-assign a stable palette color for a brand-new substance up
            // front (deterministic hash, the same color the graph uses),
            // tracking it in the local snapshot so the live session picks it up
            // immediately without a store round-trip.
            if !colors.hasColor(for: entry.substance) {
                let newColor = SubstanceColor(
                    substance: entry.substance,
                    hexColor: PresetColor.deterministic(for: entry.substance).hex,
                )
                context.insert(newColor)
                colors.append(newColor)
            }
        }
        beforeSave()
        do {
            try context.save()
        } catch {
            // Callers fire their success feedback and dismissal before this
            // commit (deliberately — the sheet must slide immediately), so a
            // failure here leaves the live session showing doses the store
            // doesn't have. The inserts stay pending on the context, so the
            // next save — SwiftData's autosave or the next commit — retries
            // them; record it loudly instead of vanishing the evidence.
            logger.fault("Batch dose commit save failed for \(doses.count) dose(s): \(error)")
        }
        ActiveSessionManager.shared.addDoses(entries: doses, allColors: colors)
        changed()
        scheduleDeferredBookkeeping(
            forSubstances: Set(doses.map(\.entry.substance)),
            in: context,
            bookkeeping: deferredBookkeeping,
        )
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
    /// on-main inventory recompute and the `reloadAllTimelines()` IPC.
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
            await InventoryService.recompute(forSubstances: substances, replayingOffMainIn: context)
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
