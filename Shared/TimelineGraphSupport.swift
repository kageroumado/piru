import SwiftUI

// Metrics, stored preferences, and the model cache behind the timeline graph.
// Split out of `TimelineGraphView.swift` when that file passed the 2500-line
// cap; none of this is the view itself, and every one of these types is read
// from outside it (Settings, the host cards, the export image, the widget).

/// Shared spacing scale for the timeline graph and its host views. One source of
/// truth so the canvas inset, card insets, and label bands stay in proportion
/// instead of drifting across five unrelated magic numbers.
enum GraphMetrics {
    /// Inset between the card edge and the drawn curves on the full graph.
    /// Sized so strokes and axis labels stay clear of the hosting card's
    /// rounded-corner arc — content drawn into that zone gets sliced.
    static let canvasInset: CGFloat = 14
    /// Inset on compact thumbnails — kept tight so small cards aren't eaten by padding.
    static let compactInset: CGFloat = 2
    /// Vertical breathing for the bordered chart host — the curves run flush to the
    /// side frame horizontally, but keep a small gap above/below so the peak and
    /// baseline don't jam the top label band and the origin line.
    static let chartFrameVInset: CGFloat = 8
    /// Padding inside the hosting card / section.
    static let cardInset: CGFloat = 12
    /// Height of the clock-time label band below the full graph.
    static let axisLabels: CGFloat = 16
    /// Height of the relative-hour label band above the full graph.
    static let topLabels: CGFloat = 12
    /// Resting height of the embedded full graph in day/entry detail.
    static let embedded: CGFloat = 168
    /// Enlarged (tapped-open) height for overlapping-curve days.
    static let enlarged: CGFloat = 320
    /// Height of the companion vitals (heart-rate) lane drawn below the effect
    /// curves, plus the gap separating it from them. Added to the canvas height
    /// only on the full graph when the session has heart-rate data, so the
    /// effect region keeps its normal size and the lane sits in the extra space.
    /// Grows with the enlarged graph so the trace gets more room too.
    static func vitalsBand(enlarged: Bool) -> CGFloat {
        enlarged ? 74 : 54
    }
    static let vitalsBandGap: CGFloat = 8
    static func vitalsBandTotal(enlarged: Bool) -> CGFloat {
        vitalsBand(enlarged: enlarged) + vitalsBandGap
    }
    /// Height of the Shulgin-rating step lane drawn under the effect curves
    /// (above the vitals lane when both are present), plus its gap. Added to
    /// the canvas only when a session note carries a rating.
    static let shulginLane: CGFloat = 30
    static let shulginLaneGap: CGFloat = 6
    static var shulginLaneTotal: CGFloat {
        shulginLane + shulginLaneGap
    }

    /// Timeline height. Overlapping-curve days use the fixed embedded/enlarged
    /// heights; lane-mode days grow with the lane count so each horizon strip
    /// keeps a readable minimum. Single source of truth for the day-detail
    /// section, the export image, and anywhere else that sizes the graph.
    static func graphHeight(
        enlarged: Bool, curveLaneCount: Int, markerLaneCount: Int,
        laneModeEnabled: Bool, laneModeThreshold: Int,
    ) -> CGFloat {
        let base = enlarged ? Self.enlarged : embedded
        let laneCount = curveLaneCount + markerLaneCount
        guard laneModeEnabled, laneCount >= laneModeThreshold else { return base }
        let axisOverhead: CGFloat = 40
        let ideal = CGFloat(curveLaneCount) * curveLaneHeight(enlarged: enlarged)
            + CGFloat(markerLaneCount) * markerLaneHeight + axisOverhead
        return max(base, min(ideal, enlarged ? 560 : 380))
    }

    /// Room a curve lane wants: enough for a Bateman hump to have a shape.
    static func curveLaneHeight(enlarged: Bool) -> CGFloat {
        enlarged ? 46 : 32
    }

    /// Room a pin-only lane wants — a name and a row of lollipops, neither of
    /// which needs vertical space to be read. Duration-less substances get their
    /// own labeled lane (better than an unlabelled cluster of dots at the graph's
    /// foot), but at a curve's share of the height a session with four of them
    /// spent most of the canvas on rows carrying two dots each.
    static let markerLaneHeight: CGFloat = 22
}

/// UserDefaults keys, defaults, and bounds for the lane-mode ("small multiples")
/// preference. One source of truth so the Settings UI, the host views that size
/// the graph card, and the graph's own gate all agree. Stored in the app group
/// suite so the widget/Live Activity honor the same choice as the main app.
enum LaneModeDefaults {
    static let suite = "group.dev.yumeji.piru"
    static let enabledKey = "stackedLanesEnabled"
    static let thresholdKey = "laneModeThreshold"
    static let enabledDefault = true
    static let thresholdDefault = 4
    /// Allowed stepper range — needs ≥2 distinct substances before lanes mean
    /// anything, and beyond ~8 the day is busy by any measure.
    static let thresholdRange = 2 ... 8
}

/// UserDefaults key and default for the session-detail "Expand Graph" preference.
/// Persisting it means a user who prefers the taller inline timeline keeps it
/// across every session and launch, instead of it resetting each time the view
/// appears. Both the session toolbar toggle and the Journal settings toggle read
/// and write this one key.
enum SessionGraphDefaults {
    static let suite = "group.dev.yumeji.piru"
    static let enlargedKey = "sessionGraphEnlarged"
    static let enlargedDefault = false
}

/// A dose without duration data, shown as a timestamp marker on the graph.
struct DoseMarker: Hashable {
    let substanceName: String
    let timestamp: Date
    let colorHex: String
    let amount: Double
    let unit: String
}

/// A session note placed on the graph's time axis. `shulgin` (0…4) feeds the
/// Shulgin step lane; `kind` picks the glyph.
struct NoteMarker: Hashable, Identifiable {
    let id: UUID
    let timestamp: Date
    let kind: SessionNote.Kind
    let shulgin: Int?
}

/// Process-wide cache of computed timeline geometry, keyed by curve inputs.
///
/// The PK-curve geometry is expensive to derive but identical for the same
/// doses, so we compute each once (off the main thread) and reuse it. This is
/// what makes re-scrolling the journal and returning from a day detail instant:
/// the value-typed ``TimelineGraphView/DerivedKey`` matches even though the
/// `ActiveSubstanceState` instances were rebuilt, so the lookup hits. Bounded
/// LRU so a long history doesn't grow it without limit.
@MainActor
final class TimelineModelCache {
    static let shared = TimelineModelCache()

    private var store: [TimelineGraphView.DerivedKey: TimelineCurveModel.Derived] = [:]
    private var order: [TimelineGraphView.DerivedKey] = []
    private let limit = 120

    /// Keys some path has claimed and is computing right now. The journal's
    /// batch prewarm and each visible card's own load used to race here and
    /// compute the same models twice; a claim makes the first taker the only
    /// computer, and everyone else awaits its ``insert(_:for:)``.
    private var inFlight: Set<TimelineGraphView.DerivedKey> = []
    private var waiters: [TimelineGraphView.DerivedKey: [CheckedContinuation<TimelineCurveModel.Derived, Never>]] = [:]

    func cached(_ key: TimelineGraphView.DerivedKey) -> TimelineCurveModel.Derived? {
        store[key]
    }

    /// Claim `key` for computation. `false` when it's already cached or another
    /// path holds the claim — then adopt the cache hit or await ``computed(_:)``
    /// instead of duplicating the work. A successful claim MUST end in
    /// ``insert(_:for:)`` (the compute can't fail and detached children run to
    /// completion even when their `.task` is superseded), or waiters hang.
    func claim(_ key: TimelineGraphView.DerivedKey) -> Bool {
        guard store[key] == nil, !inFlight.contains(key) else { return false }
        inFlight.insert(key)
        return true
    }

    /// The model for a key someone else claimed: resolves when their
    /// ``insert(_:for:)`` lands, immediately on a cache hit, or `nil` when the
    /// key is neither cached nor in flight (the caller should claim + compute).
    func computed(_ key: TimelineGraphView.DerivedKey) async -> TimelineCurveModel.Derived? {
        if let hit = store[key] { return hit }
        guard inFlight.contains(key) else { return nil }
        return await withCheckedContinuation { continuation in
            waiters[key, default: []].append(continuation)
        }
    }

    func insert(_ value: TimelineCurveModel.Derived, for key: TimelineGraphView.DerivedKey) {
        inFlight.remove(key)
        if store[key] == nil { order.append(key) }
        store[key] = value
        while order.count > limit {
            let evicted = order.removeFirst()
            store[evicted] = nil
        }
        for waiter in waiters.removeValue(forKey: key) ?? [] {
            waiter.resume(returning: value)
        }
    }
}
