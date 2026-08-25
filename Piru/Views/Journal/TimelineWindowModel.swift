import SwiftData
import SwiftUI

/// Owns a continuous-timeline window's derived state: the dose snapshots
/// (Sendable value copies of the journal, background meds excluded) and a
/// bounded per-instance memo of evaluated windows, computed off-main. Serves
/// ``ActiveNowWindowGraph``; windows are hour-aligned by the caller so keys
/// stay stable across minute ticks.
///
/// Memoization key = (window, content hash of the doses that window can see) —
/// logging a new dose only re-keys the windows its curve actually reaches.
@Observable
@MainActor
final class TimelineWindowModel {
    /// Curve-bearing value snapshots of the journal's doses, oldest first.
    /// Background meds (``DoseEntry/isBackgroundMed``) are excluded exactly like
    /// the session graphs: maintenance doses never draw a curve.
    private(set) var snapshots: [ActiveSubstanceState] = []

    /// Activity window per snapshot (aligned with `snapshots`), cached at
    /// rebuild time — ``TimelineWindowEvaluator/activityInterval(of:)`` runs a
    /// Newton `ka` solve per dose, far too costly to re-run per window per body
    /// pass just to cull.
    private var activityIntervals: [DateInterval] = []

    /// Bumped whenever `snapshots` changes content — the graph folds it into its
    /// `.task` identity so they re-request after a rebuild.
    private(set) var revision = 0

    /// Evaluated windows, content-addressed. Bounded so years of scrolled
    /// history can't grow it without limit (evicts oldest-inserted first).
    private(set) var plots: [WindowKey: TimelineWindowEvaluator.WindowPlot] = [:]
    private var insertionOrder: [WindowKey] = []
    private var inFlight: Set<WindowKey> = []
    private static let cacheLimit = 240

    /// Shared y-scale input: the highest sample across every loaded window.
    private(set) var peakValue = 0.0

    /// The most recently published plot — the graph's stale fallback. When a
    /// dose add/edit re-keys the current window, the memo lookup misses until
    /// the async rebuild lands; drawing this (time-remapped) in the meantime
    /// keeps the curves on screen instead of blanking to bare chrome.
    private(set) var lastPlot: TimelineWindowEvaluator.WindowPlot?

    struct WindowKey: Hashable {
        let start: Date
        let end: Date
        let dosesHash: Int
    }

    /// Rebuild the snapshots from the live entries. Cheap when nothing changed
    /// (content-compared); the plot memo survives because its keys are
    /// content-addressed — only windows whose visible doses changed re-key.
    func rebuild(entries: [DoseEntry], colors: [SubstanceColor]) async {
        // Resolve against the warm batch cache so per-entry resolution is a
        // dict hit, not cold SQL (same discipline as `JournalModel`).
        await SubstanceStore.shared.ensureAllLoaded()
        let acute = entries.filter { !$0.isBackgroundMed }
        let (states, _) = ActiveSubstanceState.timeline(for: acute, colors: colors)
        let sorted = states.sorted { $0.doseTimestamp < $1.doseTimestamp }
        guard sorted != snapshots else { return }
        snapshots = sorted
        activityIntervals = sorted.map { TimelineWindowEvaluator.activityInterval(of: $0) }
        revision += 1
    }

    /// The content-addressed key for a window under the current snapshots.
    /// Culling uses the cached activity intervals, so this is a cheap linear
    /// scan safe to run from the view's `body`.
    func key(start: Date, end: Date) -> WindowKey {
        let window = DateInterval(start: start, end: max(end, start))
        var hasher = Hasher()
        for (index, dose) in snapshots.enumerated() where activityIntervals[index].intersects(window) {
            hasher.combine(dose)
        }
        return WindowKey(start: start, end: end, dosesHash: hasher.finalize())
    }

    func plot(for key: WindowKey) -> TimelineWindowEvaluator.WindowPlot? {
        plots[key]
    }

    /// Evaluate a window off-main and publish it into the memo. No-op when
    /// the window is already cached or being computed.
    func requestPlot(start: Date, end: Date, sampleCount: Int = TimelineWindowEvaluator.defaultSampleCount) async {
        let key = key(start: start, end: end)
        guard plots[key] == nil, !inFlight.contains(key) else { return }
        inFlight.insert(key)
        defer { inFlight.remove(key) }
        let doses = snapshots
        let plot = await Task.detached(priority: .userInitiated) {
            TimelineWindowEvaluator.evaluate(doses: doses, from: start, to: end, sampleCount: sampleCount)
        }.value
        insert(plot, for: key)
    }

    private func insert(_ plot: TimelineWindowEvaluator.WindowPlot, for key: WindowKey) {
        if plots[key] == nil {
            insertionOrder.append(key)
        }
        plots[key] = plot
        lastPlot = plot
        var evictedPeak = false
        while insertionOrder.count > Self.cacheLimit {
            let evicted = insertionOrder.removeFirst()
            evictedPeak = evictedPeak || (plots[evicted]?.peakValue ?? 0) >= peakValue
            plots[evicted] = nil
        }
        if evictedPeak {
            peakValue = plots.values.map(\.peakValue).max() ?? 0
        } else {
            peakValue = max(peakValue, plot.peakValue)
        }
    }
}
