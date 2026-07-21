import SwiftData
import SwiftUI

/// Owns the continuous ribbon's derived state: the dose snapshots (Sendable
/// value copies of the journal, background meds excluded) and a bounded
/// per-instance memo of evaluated tile windows, computed off-main.
///
/// Memoization key = (tile window, content hash of the doses that tile can
/// see). Tile windows are wall-clock-stable (see ``TimelineRibbonView``), and
/// ``TimelineWindowEvaluator/relevantDoses(_:from:to:)`` culling means logging a
/// new dose only re-keys the tiles its curve actually reaches — scrolled-back
/// history stays a cache hit.
@Observable
@MainActor
final class TimelineRibbonModel {
    /// Curve-bearing value snapshots of the journal's doses, oldest first.
    /// Background meds (``DoseEntry/isBackgroundMed``) are excluded exactly like
    /// the session graphs: maintenance doses never draw a curve.
    private(set) var snapshots: [ActiveSubstanceState] = []

    /// Activity window per snapshot (aligned with `snapshots`), cached at
    /// rebuild time — ``TimelineWindowEvaluator/activityInterval(of:)`` runs a
    /// Newton `ka` solve per dose, far too costly to re-run per tile per body
    /// pass just to cull.
    private var activityIntervals: [DateInterval] = []

    /// Bumped whenever `snapshots` changes content — tiles fold it into their
    /// `.task` identity so they re-request after a rebuild.
    private(set) var revision = 0

    /// Evaluated windows, content-addressed. Bounded so years of scrolled
    /// history can't grow it without limit (evicts oldest-inserted first).
    private(set) var plots: [TileKey: TimelineWindowEvaluator.WindowPlot] = [:]
    private var insertionOrder: [TileKey] = []
    private var inFlight: Set<TileKey> = []
    private static let cacheLimit = 240

    /// Shared y-scale input: the highest sample across every loaded tile.
    private(set) var peakValue = 0.0

    struct TileKey: Hashable {
        let start: Date
        let end: Date
        let dosesHash: Int
    }

    var earliestDose: Date? {
        snapshots.first?.doseTimestamp
    }

    /// Normalization matching the session graph's policy: fill the height with
    /// the tallest loaded curve, but never amplify silence more than 20×.
    var yNormalization: Double {
        peakValue > 0 ? min(1 / peakValue, 20) : 1
    }

    /// Rebuild the snapshots from the live entries. Cheap when nothing changed
    /// (content-compared); the plot memo survives because its keys are
    /// content-addressed — only tiles whose visible doses changed re-key.
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

    /// The content-addressed key for a tile window under the current snapshots.
    /// Culling uses the cached activity intervals, so this is a cheap linear
    /// scan safe to run from a tile's `body`.
    func key(start: Date, end: Date) -> TileKey {
        let window = DateInterval(start: start, end: max(end, start))
        var hasher = Hasher()
        for (index, dose) in snapshots.enumerated() where activityIntervals[index].intersects(window) {
            hasher.combine(dose)
        }
        return TileKey(start: start, end: end, dosesHash: hasher.finalize())
    }

    func plot(for key: TileKey) -> TimelineWindowEvaluator.WindowPlot? {
        plots[key]
    }

    /// Evaluate a tile window off-main and publish it into the memo. No-op when
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

    private func insert(_ plot: TimelineWindowEvaluator.WindowPlot, for key: TileKey) {
        if plots[key] == nil {
            insertionOrder.append(key)
        }
        plots[key] = plot
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
