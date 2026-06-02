import SwiftUI

/// Shared spacing scale for the timeline graph and its host views. One source of
/// truth so the canvas inset, card insets, and label bands stay in proportion
/// instead of drifting across five unrelated magic numbers.
enum GraphMetrics {
    /// Inset between the card edge and the drawn curves on the full graph.
    static let canvasInset: CGFloat = 8
    /// Inset on compact thumbnails — kept tight so small cards aren't eaten by padding.
    static let compactInset: CGFloat = 2
    /// Padding inside the hosting card / section.
    static let cardInset: CGFloat = 12
    /// Vertical rhythm between stacked graph elements.
    static let section: CGFloat = 12
    /// Height of the clock-time label band below the full graph.
    static let axisLabels: CGFloat = 16
    /// Height of the relative-hour label band above the full graph.
    static let topLabels: CGFloat = 12
    /// Resting height of the embedded full graph in day/entry detail.
    static let embedded: CGFloat = 168
}

/// A dose without duration data, shown as a timestamp marker on the graph.
struct DoseMarker: Hashable, Sendable {
    let substanceName: String
    let timestamp: Date
    let colorHex: String
    let amount: Double
    let unit: String
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

    private var store: [TimelineGraphView.DerivedKey: TimelineGraphView.Derived] = [:]
    private var order: [TimelineGraphView.DerivedKey] = []
    private let limit = 120

    func cached(_ key: TimelineGraphView.DerivedKey) -> TimelineGraphView.Derived? {
        store[key]
    }

    func insert(_ value: TimelineGraphView.Derived, for key: TimelineGraphView.DerivedKey) {
        if store[key] == nil { order.append(key) }
        store[key] = value
        while order.count > limit {
            let evicted = order.removeFirst()
            store[evicted] = nil
        }
    }
}

struct TimelineGraphView: View {
    let substances: [ActiveSubstanceState]
    let currentTime: Date
    let compact: Bool
    var markers: [DoseMarker] = []
    var stackRedoses: Bool = false
    /// Draws the per-curve "now" dot at `currentTime`. Meaningful on the live
    /// session accessory and the full detail graph; off for the historical
    /// journal thumbnails, where it's an axis-less artifact.
    var showNowIndicator: Bool = true
    /// When set (case-insensitive substance name), that curve renders at full
    /// strength and every other curve is dimmed — drives the fullscreen legend's
    /// tap-to-isolate. Nil means the normal active/worn-off emphasis applies.
    var highlighted: String? = nil
    /// Desired visible window in minutes, set by the fullscreen detail view's
    /// window presets (4h/8h/12h/24h). `nil` means "fit everything" (the All
    /// preset / the embedded default). Applied to `zoom` on appear and whenever
    /// it changes; the user can still pinch/pan afterwards. Ignored when
    /// `compact`.
    var presetSpanMinutes: Double? = nil
    /// Bounds the axis to a single 24h day. When set, the scrollable extent and
    /// every span computation are capped at 1440 min so a late-night long-acting
    /// dose can't stretch the axis past midnight (an entry stays on its own day
    /// instead of bleeding a 30h tail into the next). The Live Activity and
    /// now-pill leave this off — they frame a rolling session, not a calendar
    /// day. Curves past the cap are simply clipped at the right edge.
    var dayBounded: Bool = false

    // Zoom & pan state (only active when !compact)
    @State private var zoom: CGFloat = 1.0
    @State private var panOffset: Double = 0
    @State private var gestureStartZoom: CGFloat = 1.0
    @State private var gestureStartPan: Double = 0
    /// X position (canvas points) of the active scrub rule, or nil at rest.
    /// Drives the inspection lollipop: a vertical rule + per-curve dots + the
    /// SwiftUI callout. Only set on the full graph (`!compact`).
    @State private var scrubX: CGFloat? = nil

    // MARK: - Memoized geometry

    /// All input-derived geometry that does **not** depend on zoom/pan/scrub —
    /// computed exactly once in `init` so the `Canvas` closure and the span
    /// accessors read O(1) stored values instead of re-walking the PK curves on
    /// every property access. This collapses the former recomputation diamond
    /// (each `visibleSpan`/`totalSpan` read re-ran the 240-step `renderedTail`
    /// scan ~10×, and `earliestDose` re-mapped + re-`min`'d the dose array on
    /// every one of its 24 call sites) down to a single evaluation per instance.
    struct Derived: Sendable {
        let earliestDose: Date
        let maxDoseBySubstance: [String: Double]
        let stackedGroups: [[ActiveSubstanceState]]
        let peakCurveValue: Double
        let yNormalization: Double
        /// `renderedTail(threshold: 0.04)` — the full scrollable extent.
        let rawDataTail: Double
        /// `renderedTail(threshold: 0.20, framing: true)` — labeled-active window.
        let rawActivityTail: Double
    }

    /// Identity for the model cache: everything `computeDerived` actually
    /// consumes. Deliberately excludes `currentTime` (used only as the
    /// empty-input fallback) so a live view whose `.now` ticks each frame still
    /// hits the cache, and excludes `compact`/`showNowIndicator`/`highlighted`
    /// (presentation-only, not part of the curve geometry).
    struct DerivedKey: Hashable, Sendable {
        let substances: [ActiveSubstanceState]
        let markers: [DoseMarker]
        let stackRedoses: Bool
        let dayBounded: Bool
    }

    /// The memoized geometry, computed **off the main thread** and delivered
    /// asynchronously. `nil` until the background pass finishes (the graph shows
    /// an empty placeholder and pops in) — except on a cache hit, where `init`
    /// seeds it synchronously so a re-scrolled or revisited card renders with no
    /// flicker. See ``TimelineModelCache``.
    @State private var derivedBox: Derived?

    /// Benign zero model so the rendering accessors stay total even if a layout
    /// pass touches them before `derivedBox` is populated (the body shows the
    /// placeholder, not the graph, in that window).
    private static let emptyDerived = Derived(
        earliestDose: .distantPast,
        maxDoseBySubstance: [:],
        stackedGroups: [],
        peakCurveValue: 0.0001,
        yNormalization: 20,
        rawDataTail: 1,
        rawActivityTail: 1,
    )

    private var derived: Derived { derivedBox ?? Self.emptyDerived }

    private var derivedKey: DerivedKey {
        DerivedKey(substances: substances, markers: markers, stackRedoses: stackRedoses, dayBounded: dayBounded)
    }

    init(
        substances: [ActiveSubstanceState],
        currentTime: Date,
        compact: Bool,
        markers: [DoseMarker] = [],
        stackRedoses: Bool = false,
        showNowIndicator: Bool = true,
        highlighted: String? = nil,
        presetSpanMinutes: Double? = nil,
        dayBounded: Bool = false,
        synchronous: Bool = false,
    ) {
        self.substances = substances
        self.currentTime = currentTime
        self.compact = compact
        self.markers = markers
        self.stackRedoses = stackRedoses
        self.showNowIndicator = showNowIndicator
        self.highlighted = highlighted
        self.presetSpanMinutes = presetSpanMinutes
        self.dayBounded = dayBounded
        let key = DerivedKey(substances: substances, markers: markers, stackRedoses: stackRedoses, dayBounded: dayBounded)
        if synchronous {
            // Live Activity / widget snapshots render in one synchronous pass —
            // `.task` never fires before the snapshot is taken — so compute (or
            // reuse) the model inline. The cost is fine off the scroll hot path.
            if let cached = TimelineModelCache.shared.cached(key) {
                _derivedBox = State(initialValue: cached)
            } else {
                let model = Self.computeDerived(
                    substances: substances, markers: markers,
                    stackRedoses: stackRedoses, dayBounded: dayBounded, currentTime: currentTime,
                )
                TimelineModelCache.shared.insert(model, for: key)
                _derivedBox = State(initialValue: model)
            }
        } else {
            // Synchronous cache read only — never compute here. A hit renders
            // immediately (no placeholder frame); a miss leaves `nil` and the
            // `.task` computes off-main, popping the curves in when ready.
            _derivedBox = State(initialValue: TimelineModelCache.shared.cached(key))
        }
    }

    /// Resolve the model: cache hit → adopt; miss → compute on a background
    /// executor, cache it, then publish. Runs from `.task(id:)`, so it re-fires
    /// only when the inputs actually change.
    private func loadModel() async {
        let key = derivedKey
        if let cached = TimelineModelCache.shared.cached(key) {
            if derivedBox == nil { derivedBox = cached }
            return
        }
        let subs = substances
        let mks = markers
        let sr = stackRedoses
        let db = dayBounded
        let ct = currentTime
        let model = await Task.detached(priority: .userInitiated) {
            PerfLog.time("computeDerived(bg n=\(subs.count))", thresholdMs: 0.5) {
                Self.computeDerived(substances: subs, markers: mks, stackRedoses: sr, dayBounded: db, currentTime: ct)
            }
        }.value
        TimelineModelCache.shared.insert(model, for: key)
        derivedBox = model
    }

    private var earliestDose: Date { derived.earliestDose }

    /// Height reserved for time labels below the graph
    private var labelAreaHeight: CGFloat {
        compact ? 0 : GraphMetrics.axisLabels
    }

    /// Height reserved for relative time labels above the graph
    private var topLabelAreaHeight: CGFloat {
        compact ? 0 : GraphMetrics.topLabels
    }

    /// Full scrollable extent — the latest minute the tallest *rendered* curve
    /// is still above ~4 % of full graph height. Found by sampling the actual
    /// drawn envelope rather than each dose's own-peak %, so a flat near-zero
    /// tail is cut regardless of stacking or height scaling. Capped at the
    /// display window so a multi-day half-life can't stretch the axis to weeks.
    private var dataSpan: Double {
        spanIncludingMarkers(derived.rawDataTail)
    }

    /// Add marker (duration-less dose) positions to a computed span so they
    /// still land on the visible axis.
    private func spanIncludingMarkers(_ base: Double) -> Double {
        var maxEnd = base
        for marker in markers {
            let offset = marker.timestamp.timeIntervalSince(earliestDose) / 60
            maxEnd = max(maxEnd, offset + 60)
        }
        // Live/today view: keep the "now" indicator on-axis when it sits just
        // past the last curve (everything worn off, but the session is still
        // current). Historical days pass a `currentTime` of `.now` that's days
        // later, so the 3 h margin excludes them. Skipped for compact
        // thumbnails, which don't draw a now-line.
        if !compact {
            let nowMin = currentTime.timeIntervalSince(earliestDose) / 60
            if nowMin >= 0, nowMin <= maxEnd + 180 {
                maxEnd = max(maxEnd, nowMin)
            }
        }
        return min(max(maxEnd, 1), displayCapMinutes)
    }

    /// Empirically find where the rendered curve envelope returns toward
    /// baseline: the latest minute at which the tallest drawn curve still
    /// exceeds `threshold` of full graph height. Params/scale are precomputed
    /// once (not per sample) so the scan stays cheap.
    ///
    /// When `framing` is true, curves that never decay below `threshold` within
    /// the window (persistent long-acting background like a daily maintenance
    /// med) are dropped from the envelope, so they don't drag the default frame
    /// out to days and crush the acute action. They still count toward the full
    /// scrollable extent (`framing: false`). If every curve is persistent, none
    /// are dropped, so a long-acting-only day still shows its curve.
    private nonisolated static func renderedTail(
        threshold: Double,
        framing: Bool,
        substances: [ActiveSubstanceState],
        stackedGroups: [[ActiveSubstanceState]],
        earliestDose: Date,
        yNorm: Double,
        maxDose: [String: Double],
        stackRedoses: Bool,
        displayCap: Double,
    ) -> Double {
        var curves: [(Double) -> Double] = []
        var upper: Double = 1

        if stackRedoses {
            for group in stackedGroups {
                let params = group.map { Self.pkParams(for: $0) }
                for (di, dose) in group.enumerated() {
                    let offset = dose.doseTimestamp.timeIntervalSince(earliestDose) / 60
                    upper = max(upper, offset + Self.curveExtent(for: dose, params: params[di]))
                }
                curves.append { t in Self.stackedIntensity(atGlobalMinutes: t, group: group, params: params, earliestDose: earliestDose) * yNorm }
            }
        } else {
            for s in substances {
                let params = Self.pkParams(for: s)
                let offset = s.doseTimestamp.timeIntervalSince(earliestDose) / 60
                let scale = Self.heightScale(for: s, substances: substances, maxDose: maxDose)
                upper = max(upper, offset + Self.curveExtent(for: s, params: params))
                curves.append { t in
                    let local = t - offset
                    return local >= 0 ? Self.intensity(at: local, for: s, params: params) * scale * yNorm : 0
                }
            }
        }
        upper = min(upper, displayCap)

        var contributing = curves
        if framing {
            let transient = curves.filter { $0(upper) < threshold }
            if !transient.isEmpty { contributing = transient }
        }

        let steps = 240
        var lastActive: Double = 0
        for i in 0 ... steps {
            let t = Double(i) / Double(steps) * upper
            var h = 0.0
            for curve in contributing {
                h = max(h, curve(t))
                if h >= threshold { break }
            }
            if h >= threshold { lastActive = t }
        }
        return max(lastActive, 1)
    }

    /// Build the entire ``Derived`` model in dependency order — once, in `init`.
    /// Every helper it calls is `static`/pure precisely so this can run before
    /// the view's stored properties are initialized.
    private nonisolated static func computeDerived(
        substances: [ActiveSubstanceState],
        markers: [DoseMarker],
        stackRedoses: Bool,
        dayBounded: Bool,
        currentTime: Date,
    ) -> Derived {
        let earliest = (substances.map(\.doseTimestamp) + markers.map(\.timestamp)).min() ?? currentTime
        var maxDose: [String: Double] = [:]
        for s in substances {
            let key = s.substanceName.lowercased()
            maxDose[key] = max(maxDose[key] ?? 0, s.amount)
        }
        let groups = stackRedoses ? Self.stackedGroups(of: substances) : []
        let peak = Self.peakCurveValue(
            substances: substances,
            stackedGroups: groups,
            earliestDose: earliest,
            maxDose: maxDose,
            stackRedoses: stackRedoses,
        )
        let yNorm = min(1.0 / peak, 20.0)
        let displayCap = dayBounded ? 24 * 60 : maxDisplayMinutes
        let dataTail = Self.renderedTail(threshold: 0.04, framing: false, substances: substances, stackedGroups: groups, earliestDose: earliest, yNorm: yNorm, maxDose: maxDose, stackRedoses: stackRedoses, displayCap: displayCap)
        let activityTail = Self.renderedTail(threshold: 0.20, framing: true, substances: substances, stackedGroups: groups, earliestDose: earliest, yNorm: yNorm, maxDose: maxDose, stackRedoses: stackRedoses, displayCap: displayCap)
        return Derived(
            earliestDose: earliest,
            maxDoseBySubstance: maxDose,
            stackedGroups: groups,
            peakCurveValue: peak,
            yNormalization: yNorm,
            rawDataTail: dataTail,
            rawActivityTail: activityTail,
        )
    }

    /// Off-main prewarm: compute and cache the ``Derived`` geometry for a batch of
    /// dose sets so the matching cards later render as *synchronous cache hits* —
    /// `init` seeds `derivedBox` from the cache, so there's no `Color.clear`→graph
    /// branch flip and no per-card `Task.detached` while scrolling. The journal
    /// calls this right after it (re)builds its day groups; cards already in the
    /// cache are skipped, so a re-scroll costs nothing.
    @MainActor
    static func prewarm(
        _ inputs: [(substances: [ActiveSubstanceState], markers: [DoseMarker])],
        stackRedoses: Bool,
        dayBounded: Bool,
    ) {
        // Resolve misses up front on the main actor (the cache is main-isolated),
        // then do the expensive curve math off-main and insert the results back.
        let pending: [(key: DerivedKey, substances: [ActiveSubstanceState], markers: [DoseMarker])] =
            inputs.compactMap { input in
                guard !input.substances.isEmpty || !input.markers.isEmpty else { return nil }
                let key = DerivedKey(
                    substances: input.substances, markers: input.markers,
                    stackRedoses: stackRedoses, dayBounded: dayBounded,
                )
                guard TimelineModelCache.shared.cached(key) == nil else { return nil }
                return (key, input.substances, input.markers)
            }
        guard !pending.isEmpty else { return }
        let now = Date.now
        Task.detached(priority: .utility) {
            var results: [(DerivedKey, Derived)] = []
            results.reserveCapacity(pending.count)
            for item in pending {
                let model = computeDerived(
                    substances: item.substances, markers: item.markers,
                    stackRedoses: stackRedoses, dayBounded: dayBounded, currentTime: now,
                )
                results.append((item.key, model))
            }
            await MainActor.run {
                for (key, model) in results { TimelineModelCache.shared.insert(model, for: key) }
            }
        }
    }

    /// Hard cap on the timeline window (48h). Activity past this is clipped so
    /// the meaningful first two days stay legible.
    private nonisolated static let maxDisplayMinutes: Double = 48 * 60

    /// Effective ceiling for the axis window. A day-bounded host (journal card,
    /// day detail) clamps to 24h; everything else keeps the 48h default.
    private var displayCapMinutes: Double {
        dayBounded ? 24 * 60 : Self.maxDisplayMinutes
    }

    /// Above this many duration-less doses, the compact baseline dots stop
    /// adding information and collapse into a noisy smear — so on a curve-rich
    /// day we drop them entirely (the curves already read as "busy"). A
    /// curve-less day always shows them: they're the card's only content.
    private static let maxCompactMarkers: Int = 5

    /// Whether to render the compact baseline + its dose dots. Skipped on busy
    /// curve days where the dots are redundant clutter; always on when there
    /// are no curves to carry the card.
    private var showCompactMarkers: Bool {
        guard compact, !markers.isEmpty else { return false }
        return substances.isEmpty || markers.count <= Self.maxCompactMarkers
    }

    /// At or above this many distinct substances, overlapping translucent fills
    /// stop conveying information and collapse into curve soup — so a day this
    /// busy renders as stacked per-substance lanes (small multiples) instead.
    /// Internal so hosts can size the graph to keep each lane readable.
    static let laneModeThreshold: Int = 4

    /// Distinct substances drawn on the graph (by lowercased name).
    private var distinctSubstanceCount: Int {
        Set(substances.map { $0.substanceName.lowercased() }).count
    }

    /// Switch a busy day from overlapping curves to stacked lanes. Gated to the
    /// roomy day surfaces (`dayBounded`, non-compact) — thumbnails stay a glance
    /// of texture, and the live accessory keeps its single-baseline look.
    private var laneMode: Bool {
        !compact && dayBounded && distinctSubstanceCount >= Self.laneModeThreshold
    }

    /// One lane per distinct substance, in first-dose order, carrying every dose
    /// of that substance so redoses share a lane.
    private struct LaneGroup {
        let name: String
        let colorHex: String
        let doses: [ActiveSubstanceState]
    }

    private var laneGroups: [LaneGroup] {
        var order: [String] = []
        var doses: [String: [ActiveSubstanceState]] = [:]
        var colorOf: [String: String] = [:]
        for s in substances {
            let key = s.substanceName.lowercased()
            if doses[key] == nil {
                order.append(key)
                colorOf[key] = s.colorHex
            }
            doses[key, default: []].append(s)
        }
        return order.map { key in
            LaneGroup(name: doses[key]!.first!.substanceName, colorHex: colorOf[key]!, doses: doses[key]!)
        }
    }

    /// Target number of time labels on the x-axis for consistency.
    private nonisolated static let targetTickCount: Int = 8

    /// Choose a clean tick interval that yields ~8 labels for the given span.
    private nonisolated static func intervalForSpan(_ span: Double) -> Double {
        let candidates: [Double] = [15, 30, 60, 120, 240, 480, 720, 1_440]
        let ideal = span / Double(targetTickCount)
        return candidates.first { $0 >= ideal } ?? 1_440
    }

    /// Full scrollable extent — ends exactly where the last curve does, so a
    /// panned-out view has no empty axis past the data. (No rounding up to a
    /// tick boundary; ticks land wherever they fall inside the window.)
    private var totalSpan: Double {
        compact ? autoFitSpan : dataSpan
    }

    /// The labeled-active window: earliest dose to the latest *subjective* end
    /// (`totalMinutes`), ignoring the long elimination tails. A long-acting
    /// compound's days-long tail therefore doesn't crush the acute action into
    /// the left edge — the tail stays reachable by panning past this window.
    private var activitySpan: Double {
        spanIncludingMarkers(derived.rawActivityTail)
    }

    /// Span shown at rest (`zoom == 1`). Normally the full extent — but when a
    /// long elimination tail makes that more than 1.6× the labeled-active
    /// window, we frame just the activity window instead (the tail stays
    /// reachable by panning). This keeps simple days showing everything with no
    /// scrollbar, while long-acting compounds no longer crush the acute action.
    private var autoFitSpan: Double {
        let activityInterval = Self.intervalForSpan(activitySpan)
        let activity = max(ceil(activitySpan / activityInterval) * activityInterval, 1)
        let full = max(dataSpan, 1)
        // Reframe when the low tail adds real dead axis (> 2.5 h past the
        // clearly-active window). Short curves with a small tail show whole.
        return full - activity > 150 ? activity : full
    }

    /// Max dose amount per substance name, used to scale curve heights proportionally.
    private var maxDoseBySubstance: [String: Double] { derived.maxDoseBySubstance }

    /// Height scale factor combining dose intensity (vs heavy threshold) and
    /// relative scaling when multiple doses of the same substance are present.
    /// The multi-dose multiplier preserves PsychonautWiki-style behavior where
    /// a 17g alcohol next to a 34g alcohol renders at roughly half the height.
    private func heightScale(for substance: ActiveSubstanceState) -> Double {
        Self.heightScale(for: substance, substances: substances, maxDose: derived.maxDoseBySubstance)
    }

    private nonisolated static func heightScale(
        for substance: ActiveSubstanceState,
        substances: [ActiveSubstanceState],
        maxDose: [String: Double],
    ) -> Double {
        var scale = substance.doseIntensity
        let key = substance.substanceName.lowercased()
        if let m = maxDose[key], m > 0 {
            let count = substances.count(where: { $0.substanceName.lowercased() == key })
            if count > 1 {
                scale *= max(0.2, substance.amount / m)
            }
        }
        return max(0.05, scale)
    }

    /// Highest curve peak across all substances/groups. Used to normalize the
    /// y-axis so the tallest curve fills the height — a lone low dose then
    /// reaches the top instead of rendering as a flat sliver, and multiple
    /// curves keep their relative proportions.
    private nonisolated static func peakCurveValue(
        substances: [ActiveSubstanceState],
        stackedGroups: [[ActiveSubstanceState]],
        earliestDose: Date,
        maxDose: [String: Double],
        stackRedoses: Bool,
    ) -> Double {
        if stackRedoses {
            var maxV = 0.0
            for group in stackedGroups {
                let (s, e) = Self.stackedGroupRange(group, earliestDose: earliestDose)
                guard e > s else { continue }
                let params = group.map { Self.pkParams(for: $0) }
                let steps = 48
                for i in 0 ... steps {
                    let t = s + Double(i) / Double(steps) * (e - s)
                    maxV = max(maxV, Self.stackedIntensity(atGlobalMinutes: t, group: group, params: params, earliestDose: earliestDose))
                }
            }
            return max(maxV, 0.0001)
        } else {
            return max(substances.map { Self.heightScale(for: $0, substances: substances, maxDose: maxDose) }.max() ?? 1, 0.0001)
        }
    }

    /// Multiplier mapping the tallest curve to full height (capped so a tiny
    /// floor value can't blow up beyond the graph).
    private var yNormalization: Double { derived.yNormalization }

    /// Compression exponent applied to each curve's *amplitude* — the peak
    /// height it's scaled to — never to its time-varying shape. Linear
    /// (`1.0`) makes a threshold dose beside a heavy one collapse to an
    /// unreadable sliver and its long elimination skirt hug the axis. `< 1`
    /// lifts the low end (a 10 %-of-peak dose rises to ~32 % at `0.5`) while
    /// pinning the tallest curve at full height and preserving dose ordering.
    /// Because only the amplitude is scaled, onset/peak/offset proportions —
    /// and the relative tail length — are untouched; the light dose simply
    /// reads as a real hump instead of a flat smear.
    private static let amplitudeGamma: Double = 0.5

    /// Map a linear normalized amplitude in `[0, 1]` to its display height,
    /// compressing the low end so faint doses stay legible next to heavy ones.
    private func compressedAmplitude(_ amplitude: Double) -> Double {
        pow(min(max(amplitude, 0), 1), Self.amplitudeGamma)
    }

    /// Lowest zoom that still has meaning: the value at which the visible window
    /// equals the full extent. At rest (`zoom == 1`) we frame `autoFitSpan`; a
    /// long elimination tail makes `autoFitSpan < totalSpan`, so zooming *out*
    /// to reveal that tail needs a sub-1 zoom. The embedded graph never sets
    /// `zoom` below 1, so this only loosens the floor for the fullscreen view's
    /// "All" preset and pinch-out. Capped at 1 so simple days can't zoom past
    /// their own data.
    private var minZoom: CGFloat {
        guard !compact, totalSpan > 0, autoFitSpan > 0 else { return 1 }
        return min(1, CGFloat(autoFitSpan / totalSpan))
    }

    private var effectiveZoom: CGFloat {
        compact ? 1 : min(max(minZoom, zoom), 10)
    }

    /// Visible window. At rest this is `autoFitSpan` (the activity window);
    /// pinch-zoom shrinks it further. Capped at the full extent so it can never
    /// exceed what there is to show.
    private var visibleSpan: Double {
        min(autoFitSpan / Double(effectiveZoom), totalSpan)
    }

    private var visibleStart: Double {
        guard !compact else { return 0 }
        let maxPan = max(0, totalSpan - visibleSpan)
        return min(max(0, panOffset), maxPan)
    }

    private var maxPanOffset: Double {
        max(0, totalSpan - visibleSpan)
    }

    /// How prominently a curve is drawn. On a busy day only the curves active
    /// *now* (or an isolated one) read at full strength; worn-off history and
    /// non-isolated curves fade back so the graph collapses to what matters.
    private enum CurveEmphasis {
        case full // active now, or the isolated substance
        case faded // worn-off history
        case dimmed // a non-isolated curve while another is isolated

        var fillOpacity: Double {
            switch self {
            case .full: 0.15
            case .faded: 0.06
            case .dimmed: 0.12
            }
        }

        var strokeOpacity: Double {
            switch self {
            case .full: 1
            case .faded, .dimmed: 0.3
            }
        }
    }

    /// True when `currentTime` falls inside at least one curve's active window —
    /// i.e. the session is live *right now*. Worn-off fading only makes sense
    /// then: a fully historical day has no "now" on the axis to contrast
    /// against, so fading every curve would just wash the whole graph out.
    private var hasActiveNow: Bool {
        guard showNowIndicator else { return false }
        return substances.contains { s in
            let elapsed = currentTime.timeIntervalSince(s.doseTimestamp) / 60
            return elapsed >= 0 && elapsed <= s.totalMinutes
        }
    }

    /// Emphasis for a curve given legend isolation and whether its effect window
    /// still includes `currentTime`. Compact contexts (thumbnails, accessory,
    /// Live Activity) and fully historical days always render at full strength —
    /// emphasis is a live, busy-full-graph declutter, not a global restyle.
    private func emphasis(name: String, isActive: Bool) -> CurveEmphasis {
        guard !compact else { return .full }
        if let highlighted, !highlighted.isEmpty {
            return highlighted.caseInsensitiveCompare(name) == .orderedSame ? .full : .dimmed
        }
        guard hasActiveNow else { return .full }
        return isActive ? .full : .faded
    }

    // MARK: - Geometry

    /// The drawable rectangle of the canvas, derived once from the view size so
    /// the `Canvas` closure, the pan/scrub gestures, and the callout overlay all
    /// map points ⇄ minutes through identical math.
    private struct GraphGeometry {
        let inset: CGFloat
        let top: CGFloat
        let width: CGFloat
        let height: CGFloat
    }

    private func graphGeometry(for size: CGSize) -> GraphGeometry {
        let inset: CGFloat = compact ? GraphMetrics.compactInset : GraphMetrics.canvasInset
        return GraphGeometry(
            inset: inset,
            top: inset + topLabelAreaHeight,
            width: size.width - inset * 2,
            height: size.height - labelAreaHeight - topLabelAreaHeight - inset * 2,
        )
    }

    // MARK: - Scrub inspection

    /// One curve's value at a scrubbed instant, used by both the in-canvas dots
    /// and the SwiftUI callout. `value` is the normalized [0, 1] height.
    private struct ScrubSample: Identifiable {
        let id: Int
        let name: String
        let color: Color
        let value: Double
        let elapsed: Double
    }

    /// Every curve present at `global` minutes (since `earliestDose`), sorted
    /// strongest-first. Handles both stacked and per-dose rendering so the
    /// readout matches whatever the canvas drew.
    private func scrubSamples(atMinute global: Double) -> [ScrubSample] {
        let yNorm = yNormalization
        var out: [ScrubSample] = []
        if stackRedoses {
            for (gi, group) in stackedGroups.enumerated() {
                guard let first = group.first else { continue }
                let (gStart, gEnd) = stackedGroupRange(group)
                guard global >= gStart, global <= gEnd else { continue }
                let params = group.map { pkParams(for: $0) }
                let v = min(1, max(0, stackedIntensity(atGlobalMinutes: global, group: group, params: params) * yNorm))
                guard v > 0.01 else { continue }
                out.append(ScrubSample(id: gi, name: first.substanceName, color: Color(hex: first.colorHex), value: v, elapsed: global - gStart))
            }
        } else {
            for (i, s) in substances.enumerated() {
                let offset = s.doseTimestamp.timeIntervalSince(earliestDose) / 60
                let local = global - offset
                let params = pkParams(for: s)
                guard local >= 0, local <= curveExtent(for: s, params: params) else { continue }
                let v = min(1, max(0, intensity(at: local, for: s, params: params) * heightScale(for: s) * yNorm))
                guard v > 0.01 else { continue }
                out.append(ScrubSample(id: i, name: s.substanceName, color: Color(hex: s.colorHex), value: v, elapsed: local))
            }
        }
        return out.sorted { $0.value > $1.value }
    }

    /// Index of the strongest curve whose effect window includes `currentTime`,
    /// in per-dose order. The resting now-dot is drawn on only this curve.
    private func frontmostActiveIndex(yNorm: Double) -> Int? {
        var best = -1.0
        var bestIdx: Int? = nil
        for (i, s) in substances.enumerated() {
            let elapsed = currentTime.timeIntervalSince(s.doseTimestamp) / 60
            guard elapsed >= 0, elapsed <= s.totalMinutes else { continue }
            let v = intensity(at: elapsed, for: s, params: pkParams(for: s)) * heightScale(for: s) * yNorm
            if v > best { best = v; bestIdx = i }
        }
        return bestIdx
    }

    /// Stacked-mode counterpart: the strongest group at `nowGlobal`.
    private func frontmostActiveStackedIndex(yNorm: Double, nowGlobal: Double) -> Int? {
        var best = -1.0
        var bestIdx: Int? = nil
        for (gi, group) in stackedGroups.enumerated() {
            let (gStart, gEnd) = stackedGroupRange(group)
            guard nowGlobal >= gStart, nowGlobal <= gEnd else { continue }
            let params = group.map { pkParams(for: $0) }
            let v = stackedIntensity(atGlobalMinutes: nowGlobal, group: group, params: params) * yNorm
            if v > best { best = v; bestIdx = gi }
        }
        return bestIdx
    }

    private func scrubClockTime(atMinute global: Double) -> String {
        Self.timeLabelFormatter.string(from: earliestDose.addingTimeInterval(global * 60))
    }

    var body: some View {
        Group {
            if derivedBox != nil {
                loadedGraph
            } else {
                // Empty, correctly-sized placeholder while the geometry is
                // derived off-main; the curves pop in when ready (instant on a
                // cache hit, since `init` seeds `derivedBox` synchronously).
                Color.clear
            }
        }
        .task(id: derivedKey) { await loadModel() }
    }

    @ViewBuilder
    private var loadedGraph: some View {
        if compact {
            graphCanvas
        } else {
            GeometryReader { geo in
                let geom = graphGeometry(for: geo.size)
                ZStack(alignment: .topLeading) {
                    graphCanvas
                        .contentShape(Rectangle())
                        .gesture(panZoomGesture(graphWidth: geom.width))
                        .highPriorityGesture(scrubGesture(geom: geom))
                        .onTapGesture(count: 2) {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                zoom = 1.0
                                panOffset = 0
                                gestureStartZoom = 1.0
                                gestureStartPan = 0
                            }
                        }
                    scrubCallout(geom: geom)
                }
            }
            .onAppear { frameToPreset(presetSpanMinutes) }
            .onChange(of: presetSpanMinutes) { _, newValue in
                withAnimation(.easeInOut(duration: 0.3)) { frameToPreset(newValue) }
            }
        }
    }

    /// Reframe the visible window to a preset span (or the full extent when
    /// `nil`). Translates a target minute-span into the internal `zoom` the
    /// renderer already understands, clamped to `[minZoom, 10]`, and snaps the
    /// pan back to the start so the window is deterministic. Only meaningful on
    /// the fullscreen detail view; the embedded graph never sets a preset.
    private func frameToPreset(_ span: Double?) {
        guard !compact, autoFitSpan > 0, totalSpan > 0 else { return }
        let target = min(max((span ?? totalSpan), 1), totalSpan)
        let z = CGFloat(autoFitSpan / target)
        zoom = min(max(minZoom, z), 10)
        gestureStartZoom = zoom
        panOffset = 0
        gestureStartPan = 0
    }

    /// One-finger drag pans the timeline; two-finger pinch zooms around its
    /// anchor. Composed simultaneously so a pinch mid-drag still tracks. The
    /// drag maps screen translation → minutes through the live `visibleSpan`,
    /// anchored on `gestureStartPan` so the mapping is absolute, not cumulative.
    private func panZoomGesture(graphWidth: CGFloat) -> some Gesture {
        SimultaneousGesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    guard graphWidth > 0 else { return }
                    let dxMinutes = -Double(value.translation.width) / Double(graphWidth) * visibleSpan
                    panOffset = min(max(0, gestureStartPan + dxMinutes), maxPanOffset)
                }
                .onEnded { _ in
                    gestureStartPan = panOffset
                },
            MagnifyGesture()
                .onChanged { value in
                    let fit = autoFitSpan
                    let full = totalSpan
                    guard fit > 0, full > 0 else { return }
                    let newZoom = max(Double(minZoom), min(10.0, gestureStartZoom * value.magnification))
                    let oldVisibleSpan = min(fit / Double(max(1, gestureStartZoom)), full)
                    let newVisibleSpan = min(fit / Double(newZoom), full)
                    let anchorX = Double(value.startAnchor.x)
                    let minuteAtAnchor = gestureStartPan + anchorX * oldVisibleSpan
                    let newPan = minuteAtAnchor - anchorX * newVisibleSpan
                    let maxPan = max(0, full - newVisibleSpan)
                    zoom = newZoom
                    panOffset = min(max(0, newPan), maxPan)
                }
                .onEnded { _ in
                    gestureStartZoom = zoom
                    gestureStartPan = panOffset
                },
        )
    }

    /// Hold-then-drag to inspect: a long press arms the scrub so a quick drag
    /// still pans, then the finger position becomes `scrubX`. High-priority so
    /// it pre-empts the pan once armed; releasing clears the rule.
    private func scrubGesture(geom: GraphGeometry) -> some Gesture {
        LongPressGesture(minimumDuration: 0.25, maximumDistance: 12)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                if case let .second(true, drag?) = value {
                    scrubX = min(max(drag.location.x, geom.inset), geom.inset + geom.width)
                }
            }
            .onEnded { _ in
                scrubX = nil
            }
    }

    /// The floating readout above the scrub rule: scrubbed clock time plus each
    /// present curve's name and intensity. SwiftUI (not Canvas text) so it
    /// localizes and respects Dynamic Type. Non-interactive; clamped on-screen.
    @ViewBuilder
    private func scrubCallout(geom: GraphGeometry) -> some View {
        if let scrubX, geom.width > 0 {
            let minute = visibleStart + Double((scrubX - geom.inset) / geom.width) * visibleSpan
            let samples = scrubSamples(atMinute: minute)
            if !samples.isEmpty {
                let calloutWidth: CGFloat = 158
                let maxLeft = max(4, geom.width + geom.inset * 2 - calloutWidth - 4)
                let left = min(max(scrubX - calloutWidth / 2, 4), maxLeft)
                VStack(alignment: .leading, spacing: 3) {
                    Text(scrubClockTime(atMinute: minute))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(samples.prefix(4)) { sample in
                        HStack(spacing: 5) {
                            Circle()
                                .fill(sample.color)
                                .frame(width: 7, height: 7)
                            Text(sample.name)
                                .font(.caption2)
                                .lineLimit(1)
                            Spacer(minLength: 6)
                            Text(verbatim: "\(Int((sample.value * 100).rounded()))%")
                                .font(.caption2.weight(.medium).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(width: calloutWidth, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.separator, lineWidth: 0.5),
                )
                .offset(x: left, y: max(geom.top - 4, 2))
                .allowsHitTesting(false)
            }
        }
    }

    private var graphCanvas: some View {
        Canvas { context, size in
            #if DEBUG
            let __perfT0 = CFAbsoluteTimeGetCurrent()
            defer {
                let ms = (CFAbsoluteTimeGetCurrent() - __perfT0) * 1000
                if ms >= 1 { PerfLog.note("canvas \(compact ? "compact" : "full") \(String(format: "%.1f", ms))ms") }
            }
            #endif
            let geom = graphGeometry(for: size)
            let graphInset = geom.inset
            let graphTop = geom.top
            let graphWidth = geom.width
            let graphHeight = geom.height

            let vStart = visibleStart
            let vSpan = visibleSpan
            guard vSpan > 0, graphHeight > 0 else { return }

            let diamondSize: CGFloat = 3

            // Pre-compute marker positions for two-pass rendering (lines behind,
            // diamonds on top). Full graph only — compact thumbnails render
            // markers as dots on the shared baseline instead (see below).
            let markerSlots: [(marker: DoseMarker, x: CGFloat, cy: CGFloat)]
            if !compact, !laneMode, !markers.isEmpty {
                var slots: [(marker: DoseMarker, slot: Int)] = []
                var groups: [[Int]] = []
                for (i, marker) in markers.enumerated() {
                    let matched = groups.firstIndex { group in
                        group.contains { j in
                            abs(markers[j].timestamp.timeIntervalSince(marker.timestamp)) < 120
                        }
                    }
                    if let gi = matched {
                        let slotIndex = groups[gi].count
                        groups[gi].append(i)
                        slots.append((marker: marker, slot: slotIndex))
                    } else {
                        groups.append([i])
                        slots.append((marker: marker, slot: 0))
                    }
                }

                // Group slots by their x position for even vertical distribution
                let groupedSlots: [[Int]] = groups
                markerSlots = slots.compactMap { item in
                    let markerOffset = item.marker.timestamp.timeIntervalSince(earliestDose) / 60
                    let rawX = graphInset + CGFloat((markerOffset - vStart) / vSpan) * graphWidth
                    guard rawX >= -5, rawX <= size.width + 5 else { return nil }
                    let x = max(graphInset + diamondSize + 1, rawX)

                    // Find which group this marker belongs to
                    let groupIndex = groupedSlots.firstIndex { group in
                        group.contains { j in
                            abs(markers[j].timestamp.timeIntervalSince(item.marker.timestamp)) < 120
                        }
                    } ?? 0
                    _ = groupedSlots[groupIndex].count

                    // Stack diamonds from the bottom of the graph upward, clamped to graph area
                    let usableBottom = graphTop + graphHeight - diamondSize - 2
                    let usableTop = graphTop + diamondSize + 2
                    let spacing = diamondSize * 2 + 4
                    let cy = max(usableTop, usableBottom - CGFloat(item.slot) * spacing)
                    return (marker: item.marker, x: x, cy: cy)
                }
            } else {
                markerSlots = []
            }

            // Tick marks & gridlines (behind everything)
            if !compact {
                drawTickMarks(
                    context: context,
                    size: size,
                    visibleStart: vStart,
                    visibleSpan: vSpan,
                    graphTop: graphTop,
                    graphHeight: graphHeight,
                    graphInset: graphInset,
                )
            }

            // Pass 1: Marker lines (subtle pink gradient behind diamonds)
            let markerLineColor = Color(hex: "FFAACC")
            for item in markerSlots {
                let topY = item.cy + diamondSize
                let bottomY = graphTop + graphHeight

                var linePath = Path()
                linePath.move(to: CGPoint(x: item.x, y: topY))
                linePath.addLine(to: CGPoint(x: item.x, y: bottomY))
                context.stroke(
                    linePath,
                    with: .linearGradient(
                        Gradient(colors: [markerLineColor.opacity(0.35), markerLineColor.opacity(0.05)]),
                        startPoint: CGPoint(x: item.x, y: topY),
                        endPoint: CGPoint(x: item.x, y: bottomY),
                    ),
                    lineWidth: 0.75,
                )
            }

            // "Now" indicator — a full-height vertical line at the current
            // moment. The per-curve dot alone reads poorly against the filled
            // area, so the line answers "where are we now" at a glance. Drawn
            // behind the curves (Health-style) so the dose dots still sit on
            // top of it.
            let nowMinutes = currentTime.timeIntervalSince(earliestDose) / 60
            let nowX = graphInset + CGFloat((nowMinutes - vStart) / vSpan) * graphWidth
            // Skip on compact thumbnails: a full-height line on a 96pt card reads
            // as a stray glitch, not a "you are here" cue.
            if !compact, scrubX == nil, nowMinutes >= 0, nowX >= graphInset, nowX <= graphInset + graphWidth {
                var nowLine = Path()
                nowLine.move(to: CGPoint(x: nowX, y: graphTop))
                nowLine.addLine(to: CGPoint(x: nowX, y: graphTop + graphHeight))
                context.stroke(
                    nowLine,
                    with: .color(.primary.opacity(0.4)),
                    lineWidth: compact ? 1 : 1.5,
                )
            }

            // Pan-extent indicator — a 2pt track at the very bottom showing the
            // visible window's position within the full scrollable extent.
            // Replaces the removed slider; non-interactive, only when there's
            // overflow to pan.
            if !compact, maxPanOffset > 1, totalSpan > 0 {
                let trackY = size.height - 1.5
                var track = Path()
                track.move(to: CGPoint(x: graphInset, y: trackY))
                track.addLine(to: CGPoint(x: graphInset + graphWidth, y: trackY))
                context.stroke(track, with: .color(.secondary.opacity(0.18)), lineWidth: 2)
                let segStart = graphInset + CGFloat(vStart / totalSpan) * graphWidth
                let segEnd = graphInset + CGFloat((vStart + vSpan) / totalSpan) * graphWidth
                var seg = Path()
                seg.move(to: CGPoint(x: segStart, y: trackY))
                seg.addLine(to: CGPoint(x: segEnd, y: trackY))
                context.stroke(seg, with: .color(.secondary.opacity(0.55)), lineWidth: 2)
            }

            // Compact baseline — the single axis that grounds both the curves
            // and the dose dots that rest on it. Drawn only when there are dots
            // to carry (or no curves at all), so the live session accessory
            // (curves only, no markers) stays unadorned.
            let compactBaselineY = graphTop + graphHeight
            if showCompactMarkers {
                var base = Path()
                base.move(to: CGPoint(x: graphInset, y: compactBaselineY))
                base.addLine(to: CGPoint(x: graphInset + graphWidth, y: compactBaselineY))
                context.stroke(base, with: .color(.secondary.opacity(0.25)), lineWidth: 1)
            }

            // Substance curves
            if laneMode {
                drawLanes(
                    context: context,
                    visibleStart: vStart,
                    visibleSpan: vSpan,
                    graphWidth: graphWidth,
                    graphHeight: graphHeight,
                    graphInset: graphInset,
                    graphTop: graphTop,
                )
            } else if stackRedoses {
                drawStackedCurves(
                    context: context,
                    visibleStart: vStart,
                    visibleSpan: vSpan,
                    graphWidth: graphWidth,
                    graphHeight: graphHeight,
                    graphInset: graphInset,
                    graphTop: graphTop,
                )
            } else {
                let yNorm = yNormalization
                let frontmostNow: Int? = (showNowIndicator && scrubX == nil) ? frontmostActiveIndex(yNorm: yNorm) : nil
                for (idx, substance) in substances.enumerated() {
                    let color = Color(hex: substance.colorHex)
                    let substanceOffset = substance.doseTimestamp.timeIntervalSince(earliestDose) / 60
                    let scale = compressedAmplitude(heightScale(for: substance) * yNorm)
                    let elapsed = currentTime.timeIntervalSince(substance.doseTimestamp) / 60
                    let emph = emphasis(
                        name: substance.substanceName,
                        isActive: elapsed >= 0 && elapsed <= substance.totalMinutes,
                    )

                    let fillPath = intensityFillPath(
                        for: substance,
                        substanceOffset: substanceOffset,
                        visibleStart: vStart,
                        visibleSpan: vSpan,
                        graphWidth: graphWidth,
                        graphHeight: graphHeight,
                        graphInset: graphInset,
                        graphTop: graphTop,
                        scale: scale,
                    )
                    // On the home-page thumbnails the area fill turns into mud
                    // once several curves overlap, so drop it on busy compact
                    // graphs and let the strokes carry the shape.
                    if !compact || substances.count <= 3 {
                        context.fill(fillPath, with: .color(color.opacity(emph.fillOpacity)))
                    }

                    let strokePath = intensityStrokePath(
                        for: substance,
                        substanceOffset: substanceOffset,
                        visibleStart: vStart,
                        visibleSpan: vSpan,
                        graphWidth: graphWidth,
                        graphHeight: graphHeight,
                        graphInset: graphInset,
                        graphTop: graphTop,
                        scale: scale,
                    )
                    context.stroke(
                        strokePath,
                        with: .color(color.opacity(emph.strokeOpacity)),
                        lineWidth: compact ? 1.5 : 2,
                    )

                    if showNowIndicator, scrubX == nil, idx == frontmostNow, emph == .full, elapsed >= 0, elapsed <= substance.totalMinutes {
                        let minutePos = substanceOffset + elapsed
                        let x = graphInset + CGFloat((minutePos - vStart) / vSpan) * graphWidth
                        let y = graphTop + graphHeight - CGFloat(intensity(at: elapsed, for: substance, params: pkParams(for: substance)) * scale) * graphHeight * 0.93
                        if x >= -5, x <= graphWidth + 5 {
                            let dotSize: CGFloat = compact ? 5 : 7
                            let dot = Path(ellipseIn: CGRect(
                                x: x - dotSize / 2,
                                y: y - dotSize / 2,
                                width: dotSize,
                                height: dotSize,
                            ))
                            context.fill(dot, with: .color(color))
                            context.stroke(dot, with: .color(.white.opacity(0.8)), lineWidth: 1)
                        }
                    }
                }
            }

            // Pass 2: Marker circles (drawn on top of substance curves)
            for item in markerSlots {
                let color = Color(hex: item.marker.colorHex)
                let circle = Path(ellipseIn: CGRect(
                    x: item.x - diamondSize,
                    y: item.cy - diamondSize,
                    width: diamondSize * 2,
                    height: diamondSize * 2,
                ))
                context.fill(circle, with: .color(color))
                context.stroke(circle, with: .color(.white.opacity(0.6)), lineWidth: 0.8)
            }

            // Scrub readout — a vertical rule the user drags, with a dot on every
            // curve present at that instant. Supersedes the resting now-dot while
            // active; the SwiftUI callout renders the labels on top.
            if !compact, let sx = scrubX {
                let clampedX = min(max(sx, graphInset), graphInset + graphWidth)
                var rule = Path()
                rule.move(to: CGPoint(x: clampedX, y: graphTop))
                rule.addLine(to: CGPoint(x: clampedX, y: graphTop + graphHeight))
                context.stroke(rule, with: .color(.primary.opacity(0.55)), lineWidth: 1)

                let minute = vStart + Double((clampedX - graphInset) / graphWidth) * vSpan
                for sample in scrubSamples(atMinute: minute) where !laneMode {
                    let y = graphTop + graphHeight - CGFloat(sample.value) * graphHeight * 0.93
                    let dotSize: CGFloat = 7
                    let dot = Path(ellipseIn: CGRect(
                        x: clampedX - dotSize / 2,
                        y: y - dotSize / 2,
                        width: dotSize,
                        height: dotSize,
                    ))
                    context.fill(dot, with: .color(sample.color))
                    context.stroke(dot, with: .color(.white.opacity(0.85)), lineWidth: 1)
                }
            }

            // Compact: duration-less doses rest as small colour-coded dots on the
            // shared baseline, placed by time. Replaces the stacked floating
            // circles, which read as scattered noise at thumbnail size.
            if showCompactMarkers {
                let r: CGFloat = 2.5
                for marker in markers {
                    let offset = marker.timestamp.timeIntervalSince(earliestDose) / 60
                    let rawX = graphInset + CGFloat((offset - vStart) / vSpan) * graphWidth
                    guard rawX >= graphInset - 1, rawX <= graphInset + graphWidth + 1 else { continue }
                    let x = min(max(graphInset + r, rawX), graphInset + graphWidth - r)
                    let dot = Path(ellipseIn: CGRect(
                        x: x - r,
                        y: compactBaselineY - r * 2,
                        width: r * 2,
                        height: r * 2,
                    ))
                    context.fill(dot, with: .color(Color(hex: marker.colorHex)))
                    context.stroke(dot, with: .color(.white.opacity(0.5)), lineWidth: 0.5)
                }
            }

            if !compact {
                drawTimeLabels(
                    context: context,
                    size: size,
                    visibleStart: vStart,
                    visibleSpan: vSpan,
                    inset: graphTop,
                    graphHeight: graphHeight,
                )
                drawRelativeTimeLabels(
                    context: context,
                    size: size,
                    visibleStart: vStart,
                    visibleSpan: vSpan,
                    inset: graphInset,
                    graphTop: graphTop,
                )
            }
        }
        .clipped()
    }

    // MARK: - Lane Rendering (small multiples)

    /// Render a busy day as stacked per-substance lanes. Each lane is an
    /// independent horizon strip: its own baseline, its own vertical scale (so a
    /// faint dose reads as a real hump beside a heavy one), the substance name
    /// inline as a label. The lanes share the x-axis, the gridlines, the now-line
    /// and the scrub rule — only the y-mapping is partitioned. Reuses the same
    /// Bateman path builders, just handed a lane-local top/height.
    private func drawLanes(
        context: GraphicsContext,
        visibleStart: Double,
        visibleSpan: Double,
        graphWidth: CGFloat,
        graphHeight: CGFloat,
        graphInset: CGFloat,
        graphTop: CGFloat,
    ) {
        let curveLanes = laneGroups
        // Duration-less substances get their own labelled lanes too, rather than
        // an unlabelled cluster of dots dumped at the graph's foot — which read
        // as stray, disconnected points overlapping the bottom lane. Every
        // substance is one labelled horizon strip: curves get a hump, instant
        // doses get a baseline row of dots.
        let markerLanes = markerOnlyLanes(excluding: curveLanes)
        let rowCount = curveLanes.count + markerLanes.count
        guard rowCount > 0 else { return }
        let laneHeight = graphHeight / CGFloat(rowCount)
        // Headroom above each curve and a gap above the baseline keep adjacent
        // lanes from touching; floored so very tight lanes still draw.
        let topHeadroom: CGFloat = min(10, laneHeight * 0.28)
        let bottomGap: CGFloat = 2
        let labelInset: CGFloat = 4

        for (i, lane) in curveLanes.enumerated() {
            let laneTop = graphTop + CGFloat(i) * laneHeight
            let baseline = laneTop + laneHeight - bottomGap
            let amplitude = max(laneHeight - topHeadroom - bottomGap, 6)
            let laneGraphTop = baseline - amplitude
            let color = Color(hex: lane.colorHex)

            // Hairline separating this lane from the one above.
            if i > 0 {
                var sep = Path()
                sep.move(to: CGPoint(x: graphInset, y: laneTop))
                sep.addLine(to: CGPoint(x: graphInset + graphWidth, y: laneTop))
                context.stroke(sep, with: .color(.secondary.opacity(0.12)), lineWidth: 0.5)
            }

            // With redose stacking on, the lane shows one summed envelope per
            // route (matching the global stacked view) instead of a pile of
            // overlapping per-dose humps; otherwise each dose draws on its own.
            if stackRedoses {
                let groups = Self.stackedGroups(of: lane.doses)
                // Per-lane peak across the summed envelopes so this substance's
                // tallest moment fills the lane, independent of the others.
                var peak = 1e-6
                for group in groups {
                    let (gs, ge) = stackedGroupRange(group)
                    guard ge > gs else { continue }
                    let params = group.map { pkParams(for: $0) }
                    let steps = 40
                    for j in 0 ... steps {
                        let t = gs + Double(j) / Double(steps) * (ge - gs)
                        peak = max(peak, stackedIntensity(atGlobalMinutes: t, group: group, params: params))
                    }
                }
                let norm = 1.0 / peak
                for group in groups {
                    drawStackedLaneGroup(group, context: context, color: color, norm: norm, baseline: baseline, amplitude: amplitude, visibleStart: visibleStart, visibleSpan: visibleSpan, graphWidth: graphWidth, graphInset: graphInset)
                }
            } else {
                // Per-lane peak so this substance's tallest moment fills the lane,
                // regardless of how it compares to other substances.
                var peak = 1e-6
                for dose in lane.doses {
                    let params = pkParams(for: dose)
                    let hs = heightScale(for: dose)
                    let end = curveExtent(for: dose, params: params)
                    let steps = 40
                    for j in 0 ... steps {
                        let t = Double(j) / Double(steps) * end
                        peak = max(peak, intensity(at: t, for: dose, params: params) * hs)
                    }
                }
                let norm = 1.0 / peak

                for dose in lane.doses {
                    let offset = dose.doseTimestamp.timeIntervalSince(earliestDose) / 60
                    let scale = heightScale(for: dose) * norm
                    let fill = intensityFillPath(
                        for: dose,
                        substanceOffset: offset,
                        visibleStart: visibleStart,
                        visibleSpan: visibleSpan,
                        graphWidth: graphWidth,
                        graphHeight: amplitude,
                        graphInset: graphInset,
                        graphTop: laneGraphTop,
                        scale: scale,
                    )
                    context.fill(fill, with: .color(color.opacity(0.16)))
                    let stroke = intensityStrokePath(
                        for: dose,
                        substanceOffset: offset,
                        visibleStart: visibleStart,
                        visibleSpan: visibleSpan,
                        graphWidth: graphWidth,
                        graphHeight: amplitude,
                        graphInset: graphInset,
                        graphTop: laneGraphTop,
                        scale: scale,
                    )
                    context.stroke(stroke, with: .color(color.opacity(0.9)), lineWidth: 1.6)
                }
            }

            drawLaneLabel(lane.name, color: color, context: context, laneTop: laneTop, graphInset: graphInset, labelInset: labelInset)

            // A substance can carry both curve doses and duration-less doses (a
            // route with no duration data); draw the latter as low lollipops on
            // this lane's own baseline so they stay attached to their substance
            // without the head punching up through the curve above.
            let attachedLabelWidth = labelInset + 10 + CGFloat(lane.name.count) * 5.5
            for marker in markers where marker.substanceName.lowercased() == lane.name.lowercased() {
                drawMarkerLollipop(marker, context: context, baseline: baseline, laneTop: laneTop, amplitude: min(amplitude, 46), liftFraction: 0.3, labelWidth: attachedLabelWidth, radius: 3.5, visibleStart: visibleStart, visibleSpan: visibleSpan, graphWidth: graphWidth, graphInset: graphInset, color: color)
            }
        }

        // Each duration-less substance as its own labelled lane below the curves.
        for (j, lane) in markerLanes.enumerated() {
            let i = curveLanes.count + j
            let laneTop = graphTop + CGFloat(i) * laneHeight
            let baseline = laneTop + laneHeight - bottomGap
            let color = Color(hex: lane.colorHex)

            if i > 0 {
                var sep = Path()
                sep.move(to: CGPoint(x: graphInset, y: laneTop))
                sep.addLine(to: CGPoint(x: graphInset + graphWidth, y: laneTop))
                context.stroke(sep, with: .color(.secondary.opacity(0.12)), lineWidth: 0.5)
            }

            drawLaneLabel(lane.name, color: color, context: context, laneTop: laneTop, graphInset: graphInset, labelInset: labelInset)

            // Heads ride high in the lane so a real stem drops to the baseline;
            // only markers that actually fall under the name label (near the left
            // edge) are held down to clear it — the rest get the full lane.
            let amplitude = max(laneHeight - topHeadroom - bottomGap, 6)
            let r = min(5.5, max(3.5, amplitude * 0.34))
            let labelWidth = labelInset + 10 + CGFloat(lane.name.count) * 5.5
            for marker in lane.markers {
                drawMarkerLollipop(marker, context: context, baseline: baseline, laneTop: laneTop, amplitude: amplitude, liftFraction: 0.72, labelWidth: labelWidth, radius: r, visibleStart: visibleStart, visibleSpan: visibleSpan, graphWidth: graphWidth, graphInset: graphInset, color: color)
            }
        }
    }

    /// Draw one stacked redose group's summed envelope inside a lane, normalized
    /// by the lane's own peak (`norm`) and mapped to the lane's `baseline` and
    /// `amplitude`. Mirrors ``drawStackedCurves`` — superpose the per-dose
    /// intensities, then (for a genuine redose stack) pass the envelope through
    /// the effect-site low-pass so frequent redoses read as one smooth session
    /// hump rather than a spiky sawtooth.
    private func drawStackedLaneGroup(
        _ group: [ActiveSubstanceState],
        context: GraphicsContext,
        color: Color,
        norm: Double,
        baseline: CGFloat,
        amplitude: CGFloat,
        visibleStart: Double,
        visibleSpan: Double,
        graphWidth: CGFloat,
        graphInset: CGFloat,
    ) {
        let (gStart, gEnd) = stackedGroupRange(group)
        let gSpan = gEnd - gStart
        guard gSpan > 0 else { return }
        let params = group.map { pkParams(for: $0) }
        let steps = compact ? 48 : 140
        let dt = gSpan / Double(steps)
        let tau = min(max(gSpan * 0.04, 12), 90)

        var vs: [Double] = []
        vs.reserveCapacity(steps + 1)
        for i in 0 ... steps {
            let t = gStart + Double(i) / Double(steps) * gSpan
            vs.append(stackedIntensity(atGlobalMinutes: t, group: group, params: params) * norm)
        }
        if group.count > 1 {
            vs = effectSiteSmoothed(vs, dtMinutes: dt, tauMinutes: tau)
        }

        var pts: [CGPoint] = []
        pts.reserveCapacity(steps + 1)
        for i in 0 ... steps {
            let t = gStart + Double(i) / Double(steps) * gSpan
            let x = graphInset + CGFloat((t - visibleStart) / visibleSpan) * graphWidth
            let y = baseline - CGFloat(min(1.0, max(0, vs[i]))) * amplitude * 0.93
            pts.append(CGPoint(x: x, y: y))
        }

        var fill = Path()
        let startX = graphInset + CGFloat((gStart - visibleStart) / visibleSpan) * graphWidth
        fill.move(to: CGPoint(x: startX, y: baseline))
        addSmoothCurve(pts, to: &fill, startNew: false)
        let endX = graphInset + CGFloat((gEnd - visibleStart) / visibleSpan) * graphWidth
        fill.addLine(to: CGPoint(x: endX, y: baseline))
        fill.closeSubpath()
        context.fill(fill, with: .color(color.opacity(0.16)))

        var stroke = Path()
        addSmoothCurve(pts, to: &stroke, startNew: true)
        context.stroke(stroke, with: .color(color.opacity(0.9)), lineWidth: 1.6)
    }

    /// A duration-less substance rendered as its own lane: a name label plus a
    /// baseline row of dots, one per dose.
    private struct MarkerLane {
        let name: String
        let colorHex: String
        let markers: [DoseMarker]
    }

    /// Distinct marker substances with no curve lane, in first-dose order — each
    /// becomes its own labelled lane so a logged dose never floats unattached.
    private func markerOnlyLanes(excluding curveLanes: [LaneGroup]) -> [MarkerLane] {
        let curveNames = Set(curveLanes.map { $0.name.lowercased() })
        var order: [String] = []
        var byKey: [String: [DoseMarker]] = [:]
        var meta: [String: (name: String, colorHex: String)] = [:]
        for marker in markers {
            let key = marker.substanceName.lowercased()
            guard !curveNames.contains(key) else { continue }
            if byKey[key] == nil {
                order.append(key)
                meta[key] = (marker.substanceName, marker.colorHex)
            }
            byKey[key, default: []].append(marker)
        }
        return order.map { MarkerLane(name: meta[$0]!.name, colorHex: meta[$0]!.colorHex, markers: byKey[$0]!) }
    }

    /// Colour swatch + substance name at a lane's top-left.
    private func drawLaneLabel(_ name: String, color: Color, context: GraphicsContext, laneTop: CGFloat, graphInset: CGFloat, labelInset: CGFloat) {
        let dotR: CGFloat = 3
        let dot = Path(ellipseIn: CGRect(x: graphInset + labelInset, y: laneTop + labelInset, width: dotR * 2, height: dotR * 2))
        context.fill(dot, with: .color(color))
        let label = context.resolve(
            Text(name)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary),
        )
        context.draw(label, at: CGPoint(x: graphInset + labelInset + dotR * 2 + 4, y: laneTop + labelInset + dotR), anchor: .leading)
    }

    /// A single duration-less dose as a lollipop: a thin stem rising from the
    /// lane baseline to a filled, ringed head at `headCenterY`. The stem grounds
    /// the dose to the time axis while the head gives it the vertical presence of
    /// a curve's hump, so an instant dose reads as a real logged event rather
    /// than a stray fleck on an otherwise empty lane. Mirrors the marker-line +
    /// circle treatment the non-lane overlay already uses.
    private func drawMarkerLollipop(_ marker: DoseMarker, context: GraphicsContext, baseline: CGFloat, laneTop: CGFloat, amplitude: CGFloat, liftFraction: CGFloat, labelWidth: CGFloat, radius r: CGFloat, visibleStart: Double, visibleSpan: Double, graphWidth: CGFloat, graphInset: CGFloat, color: Color) {
        let off = marker.timestamp.timeIntervalSince(earliestDose) / 60
        let rawX = graphInset + CGFloat((off - visibleStart) / visibleSpan) * graphWidth
        guard rawX >= graphInset - 1, rawX <= graphInset + graphWidth + 1 else { return }
        let x = min(max(graphInset + r, rawX), graphInset + graphWidth - r)

        // Float the head at a fraction of the lane height, but never higher than
        // the name label allows — and only markers whose x falls under the label
        // (near the left edge) are held down; the rest float free for a full stem.
        let lifted = baseline - amplitude * liftFraction
        let minHeadY = x < graphInset + labelWidth ? laneTop + 13 + r : laneTop + r + 2
        let headCenterY = min(max(lifted, minHeadY), baseline - r * 0.4)

        // Stem fades toward the foot so it reads as grounded rather than a hard
        // full-strength rule competing with the curves.
        var stem = Path()
        stem.move(to: CGPoint(x: x, y: baseline))
        stem.addLine(to: CGPoint(x: x, y: headCenterY))
        context.stroke(
            stem,
            with: .linearGradient(
                Gradient(colors: [color.opacity(0.2), color.opacity(0.85)]),
                startPoint: CGPoint(x: x, y: baseline),
                endPoint: CGPoint(x: x, y: headCenterY),
            ),
            lineWidth: 3,
        )

        let head = Path(ellipseIn: CGRect(x: x - r, y: headCenterY - r, width: r * 2, height: r * 2))
        context.fill(head, with: .color(color))
    }

    // MARK: - Path Builders

    private func intensityStrokePath(
        for substance: ActiveSubstanceState,
        substanceOffset: Double,
        visibleStart: Double,
        visibleSpan: Double,
        graphWidth: CGFloat,
        graphHeight: CGFloat,
        graphInset: CGFloat,
        graphTop: CGFloat,
        scale: Double = 1.0,
    ) -> Path {
        Path { path in
            let steps = compact ? 48 : 140
            let params = pkParams(for: substance)
            let drawEnd = curveExtent(for: substance, params: params)
            var pts: [CGPoint] = []
            pts.reserveCapacity(steps + 1)
            for i in 0 ... steps {
                let t = Double(i) / Double(steps) * drawEnd
                let x = graphInset + CGFloat((substanceOffset + t - visibleStart) / visibleSpan) * graphWidth
                let y = graphTop + graphHeight - CGFloat(intensity(at: t, for: substance, params: params) * scale) * graphHeight * 0.93
                pts.append(CGPoint(x: x, y: y))
            }
            addSmoothCurve(pts, to: &path, startNew: true)
        }
    }

    private func intensityFillPath(
        for substance: ActiveSubstanceState,
        substanceOffset: Double,
        visibleStart: Double,
        visibleSpan: Double,
        graphWidth: CGFloat,
        graphHeight: CGFloat,
        graphInset: CGFloat,
        graphTop: CGFloat,
        scale: Double = 1.0,
    ) -> Path {
        Path { path in
            let steps = compact ? 48 : 140
            let baseline = graphTop + graphHeight
            let params = pkParams(for: substance)
            let drawEnd = curveExtent(for: substance, params: params)

            let startX = graphInset + CGFloat((substanceOffset - visibleStart) / visibleSpan) * graphWidth
            path.move(to: CGPoint(x: startX, y: baseline))

            var pts: [CGPoint] = []
            pts.reserveCapacity(steps + 1)
            for i in 0 ... steps {
                let t = Double(i) / Double(steps) * drawEnd
                let x = graphInset + CGFloat((substanceOffset + t - visibleStart) / visibleSpan) * graphWidth
                let y = graphTop + graphHeight - CGFloat(intensity(at: t, for: substance, params: params) * scale) * graphHeight * 0.93
                pts.append(CGPoint(x: x, y: y))
            }
            addSmoothCurve(pts, to: &path, startNew: false)

            let endX = graphInset + CGFloat((substanceOffset + drawEnd - visibleStart) / visibleSpan) * graphWidth
            path.addLine(to: CGPoint(x: endX, y: baseline))
            path.closeSubpath()
        }
    }

    // MARK: - Intensity (mechanistic Bateman PK curve)

    /// Absorption / elimination rate constants for a one-compartment Bateman
    /// curve, fit to a dose's subjective duration profile. Precomputed once per
    /// curve — the `estimateKa` Newton solve is far too costly to run per pixel.
    struct PKCurveParams {
        let ka: Double
        let ke: Double
        let cmax: Double
    }

    /// Fit a Bateman curve to a dose's subjective phase timing.
    ///
    /// The duration phases describe *subjective effect*, not plasma
    /// concentration, so they are not literally Bateman-shaped (a Bateman peak
    /// always satisfies `tmax < 1/ke`, which a long "peak" plateau violates). We
    /// therefore map the phases onto the closest well-formed one-compartment
    /// curve rather than reproduce them:
    ///
    /// - **Elimination (`ke`)** is chosen so the curve decays to ~5 % of its
    ///   peak by `totalMinutes` — the curve fades out exactly when the listed
    ///   effects end, keeping it consistent with the axis (also built from
    ///   `totalMinutes`).
    /// - **Absorption (`ka`)** is chosen so the peak lands at the centre of the
    ///   subjective peak plateau, clamped just inside `1/ke` so the curve stays
    ///   well-formed. A long plateau pushes the target peak late, driving
    ///   `ka → ke` and naturally yielding the broad, rounded `ke·t·e^(−ke·t)`
    ///   top — a sustained peak without the artificial flat trapezoid lid.
    func pkParams(for s: ActiveSubstanceState) -> PKCurveParams { Self.pkParams(for: s) }

    nonisolated static func pkParams(for s: ActiveSubstanceState) -> PKCurveParams {
        let total = max(s.totalMinutes, 1)
        let peakCenter = (s.comeupEndMinutes + s.peakEndMinutes) / 2
        // Decay to 5% of peak by `total`; anchor the window on the peak centre
        // but never let it collapse to nothing.
        let decayWindow = max(total - min(peakCenter, total * 0.5), total * 0.25)
        let ke = log(20) / decayWindow
        // Floor the peak time at a few minutes so a very short-duration
        // substance still shows a visible up-slope rather than a vertical wall.
        // A feasible Bateman peak must also satisfy tmax < 1/ke — clamp inside.
        // Critically, do NOT cap absorption *relative to* elimination: a
        // long-half-life compound has fast absorption and a slow tail
        // (ka ≫ ke), and a ratio cap would wrongly push its peak out by hours.
        let tmaxTarget = min(max(peakCenter, 8), 0.85 / ke)
        let ka = PKModel.estimateKa(timeToPeak: tmaxTarget, ke: ke)
        let cmax = max(PKModel.cmax(ke: ke, ka: ka), 1e-9)
        return PKCurveParams(ka: ka, ke: ke, cmax: cmax)
    }

    /// Normalized [0, 1] effect intensity at `minutes` past dose, from the
    /// fitted Bateman curve. Unbounded above `totalMinutes` — the curve decays
    /// naturally toward zero, so callers draw it to `curveExtent(for:)` and it
    /// tails smoothly to baseline rather than being cut off mid-descent.
    private func intensity(at minutes: Double, for s: ActiveSubstanceState, params: PKCurveParams) -> Double {
        Self.intensity(at: minutes, for: s, params: params)
    }

    private nonisolated static func intensity(at minutes: Double, for s: ActiveSubstanceState, params: PKCurveParams) -> Double {
        guard minutes >= 0 else { return 0 }
        let c = PKModel.concentration(at: minutes, ke: params.ke, ka: params.ka)
        let e = min(1, max(0, c / params.cmax))
        return e * toleranceGate(at: minutes, for: s) * tailTaper(at: minutes, for: s)
    }

    /// Gentle far-tail taper: eases the descending limb to baseline over the
    /// final stretch of the offset so a long, shallow elimination skirt doesn't
    /// crawl across the axis. Onset, peak, and the early offset are untouched —
    /// the fade only starts well into the offset (`offsetTaperStart` of the way
    /// from `peakEnd` to `totalMinutes`) and reaches zero just past the
    /// subjective end, which for these `ke`-fitted curves coincides with the old
    /// 4 %-of-peak draw extent. Tachyphylaxis curves already crash to baseline
    /// via ``toleranceGate``, so they're left alone.
    private nonisolated static func tailTaper(at minutes: Double, for s: ActiveSubstanceState) -> Double {
        guard s.tachyphylaxis == 0 else { return 1 }
        let total = max(s.totalMinutes, 1)
        let start = s.peakEndMinutes + (total - s.peakEndMinutes) * Self.offsetTaperStart
        let end = total * Self.offsetTaperEnd
        guard end > start, minutes > start else { return 1 }
        let x = min(1, (minutes - start) / (end - start))
        let smooth = x * x * (3 - 2 * x)
        return 1 - smooth
    }

    /// Where the far-tail taper begins, as a fraction of the offset window
    /// (`peakEnd → total`). Higher = gentler (fades later, less of the tail cut).
    private nonisolated static let offsetTaperStart: Double = 0.55
    /// Where the far-tail taper reaches baseline, as a multiple of `totalMinutes`
    /// — just past the subjective end so the curve lands on the axis cleanly.
    private nonisolated static let offsetTaperEnd: Double = 1.05

    /// Acute-tolerance (tachyphylaxis) multiplier on the descending limb. For
    /// `s.tachyphylaxis == 0` it's identity, so non-tolerant compounds keep the
    /// pure Bateman offset. For releasers (stimulants, empathogens) the felt
    /// effect crashes faster than plasma: across the offset window
    /// `[peakEnd, total]` we fade the curve by up to `tachyphylaxis` via a
    /// smoothstep, so it lands at baseline by `totalMinutes` instead of trailing
    /// off on the slow elimination tail. Onset and peak are untouched.
    private nonisolated static func toleranceGate(at minutes: Double, for s: ActiveSubstanceState) -> Double {
        let kappa = s.tachyphylaxis
        guard kappa > 0 else { return 1 }
        let peakEnd = s.peakEndMinutes
        let end = max(s.totalMinutes, peakEnd + 1)
        guard minutes > peakEnd else { return 1 }
        let x = min(1, (minutes - peakEnd) / (end - peakEnd))
        let smooth = x * x * (3 - 2 * x)
        return max(0, 1 - kappa * smooth)
    }

    /// Minutes after the dose at which the fitted curve has decayed to ~1 % of
    /// its peak — the point past which nothing meaningful remains to draw. Used
    /// as the per-curve draw end so the descent tails smoothly to baseline,
    /// instead of being guillotined at `totalMinutes` (which sits at ~5 % and
    /// leaves a vertical cliff). Never shorter than `totalMinutes`; capped at
    /// the display window so a long elimination tail can't stretch the axis.
    private func curveExtent(for s: ActiveSubstanceState, params: PKCurveParams) -> Double {
        Self.curveExtent(for: s, params: params)
    }

    private nonisolated static func curveExtent(for s: ActiveSubstanceState, params: PKCurveParams) -> Double {
        // Acute-tolerance curves are gated to baseline by `totalMinutes`, so
        // there's no slow elimination tail to draw past it — extending further
        // would only lay a flat near-zero line on the axis.
        if s.tachyphylaxis > 0 {
            return min(s.totalMinutes, Self.maxDisplayMinutes)
        }
        // 4 % of peak: low enough to read as "done", high enough that the axis
        // doesn't stretch across a long invisible near-zero tail. The residual
        // drop to baseline at this point is only a few px.
        let cut = PKModel.timeToFraction(0.04, ke: params.ke, ka: params.ka, maxMinutes: Self.maxDisplayMinutes)
        return min(max(cut, s.totalMinutes), Self.maxDisplayMinutes)
    }

    /// Append a smooth curve through `pts` using a uniform Catmull-Rom spline
    /// converted to cubic Bézier segments — renders the sampled PK points as a
    /// continuous biological shape instead of faceted line segments. When
    /// `startNew` is false the current point is assumed to be `pts[0]` (used by
    /// the fill path, which has already moved to the baseline start).
    private func addSmoothCurve(_ pts: [CGPoint], to path: inout Path, startNew: Bool) {
        guard pts.count >= 2 else {
            if let p = pts.first { startNew ? path.move(to: p) : path.addLine(to: p) }
            return
        }
        if startNew { path.move(to: pts[0]) } else { path.addLine(to: pts[0]) }
        for i in 0 ..< pts.count - 1 {
            let p0 = pts[max(i - 1, 0)]
            let p1 = pts[i]
            let p2 = pts[i + 1]
            let p3 = pts[min(i + 2, pts.count - 1)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
    }

    /// Zero-phase one-pole low-pass over evenly-spaced samples — a discrete
    /// effect-site (PK/PD) filter. Frequent redoses produce a spiky summed
    /// *plasma* curve, but subjective *effect* lags and integrates it, so the
    /// sawtooth becomes one smooth session envelope. Running the filter forward
    /// then backward cancels phase lag so the peak doesn't drift in time.
    private func effectSiteSmoothed(_ v: [Double], dtMinutes: Double, tauMinutes: Double) -> [Double] {
        guard v.count > 2, dtMinutes > 0, tauMinutes > 0 else { return v }
        let alpha = 1 - exp(-dtMinutes / tauMinutes)
        var out = v
        for i in 1 ..< out.count { out[i] = out[i - 1] + alpha * (out[i] - out[i - 1]) }
        for i in stride(from: out.count - 2, through: 0, by: -1) { out[i] = out[i + 1] + alpha * (out[i] - out[i + 1]) }
        return out
    }

    // MARK: - Stacked Rendering

    /// Groups substance states by lowercased substance name, preserving original order.
    private var stackedGroups: [[ActiveSubstanceState]] { derived.stackedGroups }

    private nonisolated static func stackedGroups(of substances: [ActiveSubstanceState]) -> [[ActiveSubstanceState]] {
        // Group by (substance, route) so that e.g. insufflated heroin and smoked
        // heroin draw as separate curves even when "Stack Redoses" is on. Doses
        // of the same substance via the same route still stack into a combined
        // curve as before.
        var order: [String] = []
        var buckets: [String: [ActiveSubstanceState]] = [:]
        for s in substances {
            let key = "\(s.substanceName.lowercased())|\(s.route.lowercased())"
            if buckets[key] == nil {
                order.append(key)
                buckets[key] = [s]
            } else {
                buckets[key]?.append(s)
            }
        }
        return order.compactMap { buckets[$0] }
    }

    /// Raw summed intensity of a group at a given global time (minutes since
    /// earliestDose). Each dose contributes `intensity(localT) * doseIntensity`.
    ///
    /// The sum is intentionally **not** clamped here: clamping to 1.0 would pin
    /// overlapping redoses flat at the ceiling and carve an artificial dip
    /// between them (an implausible "M"). Instead the caller normalizes by the
    /// true combined peak (`peakCurveValue`), so superposed doses render as a
    /// single rounded envelope — what real serial-dose plasma curves look like.
    /// `params` holds the precomputed Bateman fit per dose, aligned to `group`.
    private func stackedIntensity(atGlobalMinutes global: Double, group: [ActiveSubstanceState], params: [PKCurveParams]) -> Double {
        Self.stackedIntensity(atGlobalMinutes: global, group: group, params: params, earliestDose: derived.earliestDose)
    }

    private nonisolated static func stackedIntensity(atGlobalMinutes global: Double, group: [ActiveSubstanceState], params: [PKCurveParams], earliestDose: Date) -> Double {
        var sum = 0.0
        for (i, dose) in group.enumerated() {
            let offset = dose.doseTimestamp.timeIntervalSince(earliestDose) / 60
            let local = global - offset
            guard local >= 0 else { continue }
            sum += Self.intensity(at: local, for: dose, params: params[i]) * dose.doseIntensity
        }
        return sum
    }

    private func stackedGroupRange(_ group: [ActiveSubstanceState]) -> (start: Double, end: Double) {
        Self.stackedGroupRange(group, earliestDose: derived.earliestDose)
    }

    private nonisolated static func stackedGroupRange(_ group: [ActiveSubstanceState], earliestDose: Date) -> (start: Double, end: Double) {
        var start = Double.greatestFiniteMagnitude
        var end = 0.0
        for dose in group {
            let offset = dose.doseTimestamp.timeIntervalSince(earliestDose) / 60
            start = min(start, offset)
            end = max(end, offset + Self.curveExtent(for: dose, params: Self.pkParams(for: dose)))
        }
        return (start, end)
    }

    private func drawStackedCurves(
        context: GraphicsContext,
        visibleStart: Double,
        visibleSpan: Double,
        graphWidth: CGFloat,
        graphHeight: CGFloat,
        graphInset: CGFloat,
        graphTop: CGFloat,
    ) {
        let baseline = graphTop + graphHeight
        let steps = compact ? 60 : 200
        let yNorm = yNormalization

        let nowGlobal = currentTime.timeIntervalSince(earliestDose) / 60
        let frontmostNow: Int? = (showNowIndicator && scrubX == nil) ? frontmostActiveStackedIndex(yNorm: yNorm, nowGlobal: nowGlobal) : nil
        for (gi, group) in stackedGroups.enumerated() {
            guard let first = group.first else { continue }
            let color = Color(hex: first.colorHex)
            let (gStart, gEnd) = stackedGroupRange(group)
            let gSpan = gEnd - gStart
            guard gSpan > 0 else { continue }
            let params = group.map { pkParams(for: $0) }
            let activeEnd = group.map { $0.doseTimestamp.timeIntervalSince(earliestDose) / 60 + $0.totalMinutes }.max() ?? gEnd
            let emph = emphasis(name: first.substanceName, isActive: nowGlobal >= gStart && nowGlobal <= activeEnd)

            // Sample the summed curve, then (for genuine redose stacks) pass it
            // through an effect-site low-pass so frequent redoses read as one
            // smooth session envelope rather than a spiky plasma sawtooth.
            let dt = gSpan / Double(steps)
            let tau = min(max(gSpan * 0.04, 12), 90)
            var vs: [Double] = []
            vs.reserveCapacity(steps + 1)
            for i in 0 ... steps {
                let t = gStart + Double(i) / Double(steps) * gSpan
                vs.append(stackedIntensity(atGlobalMinutes: t, group: group, params: params) * yNorm)
            }
            // Compress this group's amplitude (its peak) the same way the
            // non-stacked path does, scaling the whole sampled envelope by a
            // single factor so a light group lifts off the axis without
            // deforming its shape.
            if let groupPeak = vs.max(), groupPeak > 0 {
                let factor = compressedAmplitude(groupPeak) / groupPeak
                if factor != 1 {
                    for i in vs.indices { vs[i] *= factor }
                }
            }
            if group.count > 1 {
                vs = effectSiteSmoothed(vs, dtMinutes: dt, tauMinutes: tau)
            }

            func curveValue(atFraction f: Double) -> Double {
                let idx = max(0, min(Double(steps), f * Double(steps)))
                let lo = Int(idx.rounded(.down))
                let hi = min(lo + 1, steps)
                let frac = idx - Double(lo)
                return min(1.0, max(0, vs[lo] * (1 - frac) + vs[hi] * frac))
            }

            var pts: [CGPoint] = []
            pts.reserveCapacity(steps + 1)
            for i in 0 ... steps {
                let t = gStart + Double(i) / Double(steps) * gSpan
                let x = graphInset + CGFloat((t - visibleStart) / visibleSpan) * graphWidth
                let y = baseline - CGFloat(min(1.0, max(0, vs[i]))) * graphHeight * 0.93
                pts.append(CGPoint(x: x, y: y))
            }

            var fillPath = Path()
            let startX = graphInset + CGFloat((gStart - visibleStart) / visibleSpan) * graphWidth
            fillPath.move(to: CGPoint(x: startX, y: baseline))
            addSmoothCurve(pts, to: &fillPath, startNew: false)
            let endX = graphInset + CGFloat((gEnd - visibleStart) / visibleSpan) * graphWidth
            fillPath.addLine(to: CGPoint(x: endX, y: baseline))
            fillPath.closeSubpath()
            // On the home-page thumbnails the fills turn into a single blob once
            // several curves overlap, so drop them on busy compact graphs and
            // let the strokes carry the shape.
            if !compact || stackedGroups.count <= 3 {
                context.fill(fillPath, with: .color(color.opacity(emph.fillOpacity)))
            }

            var strokePath = Path()
            addSmoothCurve(pts, to: &strokePath, startNew: true)
            context.stroke(strokePath, with: .color(color.opacity(emph.strokeOpacity)), lineWidth: compact ? 1.5 : 2)

            // Small tick glyphs at each redose time along the baseline so the user
            // can see where additional doses contributed to the curve.
            if group.count > 1, !compact {
                for dose in group {
                    let offset = dose.doseTimestamp.timeIntervalSince(earliestDose) / 60
                    let x = graphInset + CGFloat((offset - visibleStart) / visibleSpan) * graphWidth
                    guard x >= -5, x <= graphWidth + 5 else { continue }
                    var tick = Path()
                    tick.move(to: CGPoint(x: x, y: baseline))
                    tick.addLine(to: CGPoint(x: x, y: baseline - 5))
                    context.stroke(tick, with: .color(color.opacity(emph == .full ? 0.75 : 0.3)), lineWidth: 1.5)
                }
            }

            // Current-time dot on the summed curve. Must use the SAME normalized
            // value as `point(at:)` above — `stackedIntensity * yNorm`, clamped —
            // or the dot detaches from the curve whenever `yNorm` shifts (e.g. a
            // dose is added/removed and the graph rescales to fill the height).
            let elapsedGlobal = currentTime.timeIntervalSince(earliestDose) / 60
            if showNowIndicator, scrubX == nil, gi == frontmostNow, emph == .full, elapsedGlobal >= gStart, elapsedGlobal <= gEnd {
                let x = graphInset + CGFloat((elapsedGlobal - visibleStart) / visibleSpan) * graphWidth
                // Read from the same smoothed sample array as the curve so the
                // dot stays glued to it.
                let v = curveValue(atFraction: (elapsedGlobal - gStart) / gSpan)
                let y = baseline - CGFloat(v) * graphHeight * 0.93
                if x >= -5, x <= graphWidth + 5 {
                    let dotSize: CGFloat = compact ? 5 : 7
                    let dot = Path(ellipseIn: CGRect(
                        x: x - dotSize / 2,
                        y: y - dotSize / 2,
                        width: dotSize,
                        height: dotSize,
                    ))
                    context.fill(dot, with: .color(color))
                    context.stroke(dot, with: .color(.white.opacity(0.8)), lineWidth: 1)
                }
            }
        }
    }

    // MARK: - Tick Marks

    private func drawTickMarks(
        context: GraphicsContext,
        size: CGSize,
        visibleStart: Double,
        visibleSpan: Double,
        graphTop: CGFloat,
        graphHeight: CGFloat,
        graphInset: CGFloat,
    ) {
        let graphWidth = size.width - graphInset * 2
        let calendar = Calendar.current
        let interval = Self.intervalForSpan(visibleSpan)

        let graphOrigin = earliestDose
        let windowStart = graphOrigin.addingTimeInterval(visibleStart * 60)
        let windowEnd = graphOrigin.addingTimeInterval((visibleStart + visibleSpan) * 60)

        let startHour = calendar.component(.hour, from: windowStart)
        let startMinute = calendar.component(.minute, from: windowStart)
        let totalStartMinutes = Double(startHour * 60 + startMinute)
        let firstTickMinutes = ceil(totalStartMinutes / interval) * interval
        let firstTickDate = calendar.startOfDay(for: windowStart)
            .addingTimeInterval(firstTickMinutes * 60)

        var tickDate = firstTickDate

        while tickDate <= windowEnd {
            let minuteOffset = tickDate.timeIntervalSince(graphOrigin) / 60
            let x = graphInset + CGFloat((minuteOffset - visibleStart) / visibleSpan) * graphWidth

            if x >= graphInset, x <= size.width - graphInset {
                // Subtle full-height gridline
                var gridLine = Path()
                gridLine.move(to: CGPoint(x: x, y: graphTop))
                gridLine.addLine(to: CGPoint(x: x, y: graphTop + graphHeight))
                context.stroke(gridLine, with: .color(.primary.opacity(0.08)), lineWidth: 0.5)

                // Small tick mark at bottom edge
                var bottomTick = Path()
                bottomTick.move(to: CGPoint(x: x, y: graphTop + graphHeight))
                bottomTick.addLine(to: CGPoint(x: x, y: graphTop + graphHeight + 4))
                context.stroke(bottomTick, with: .color(.primary.opacity(0.25)), lineWidth: 0.75)

                // Small tick mark at top edge
                var topTick = Path()
                topTick.move(to: CGPoint(x: x, y: graphTop))
                topTick.addLine(to: CGPoint(x: x, y: graphTop - 3))
                context.stroke(topTick, with: .color(.primary.opacity(0.2)), lineWidth: 0.5)
            }
            tickDate = tickDate.addingTimeInterval(interval * 60)
        }
    }

    // MARK: - Time Labels

    private static let timeLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("j:mm")
        return f
    }()

    private static let timeHourFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("j")
        return f
    }()

    private func drawTimeLabels(
        context: GraphicsContext,
        size: CGSize,
        visibleStart: Double,
        visibleSpan: Double,
        inset: CGFloat,
        graphHeight: CGFloat,
    ) {
        let graphWidth = size.width - inset * 2
        let labelY = inset + graphHeight + labelAreaHeight / 2 + 2
        let calendar = Calendar.current

        let interval = Self.intervalForSpan(visibleSpan)

        // Graph origin is earliestDose shifted left by padding
        let graphOrigin = earliestDose
        let windowStart = graphOrigin.addingTimeInterval(visibleStart * 60)
        let windowEnd = graphOrigin.addingTimeInterval((visibleStart + visibleSpan) * 60)

        // First tick is at the graph origin (already clock-aligned)
        let startHour = calendar.component(.hour, from: windowStart)
        let startMinute = calendar.component(.minute, from: windowStart)
        let totalStartMinutes = Double(startHour * 60 + startMinute)
        let firstTickMinutes = ceil(totalStartMinutes / interval) * interval
        let firstTickDate = calendar.startOfDay(for: windowStart)
            .addingTimeInterval(firstTickMinutes * 60)

        var tickDate = firstTickDate
        let minLabelSpacing: CGFloat = 8
        var lastLabelRight: CGFloat = -.infinity

        while tickDate <= windowEnd {
            let minuteOffset = tickDate.timeIntervalSince(graphOrigin) / 60
            let x = inset + CGFloat((minuteOffset - visibleStart) / visibleSpan) * graphWidth

            if x >= 0, x <= size.width {
                let minute = calendar.component(.minute, from: tickDate)
                let hour = calendar.component(.hour, from: tickDate)
                let label: String = if minute == 0, hour == 0 {
                    "12 AM"
                } else if minute == 0 {
                    Self.timeHourFormatter.string(from: tickDate)
                } else {
                    Self.timeLabelFormatter.string(from: tickDate)
                }

                let text = Text(label).font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(.primary.opacity(0.6))
                let resolved = context.resolve(text)
                let labelWidth = resolved.measure(in: size).width

                let labelLeft: CGFloat = if x < 20 {
                    x
                } else if x > size.width - 20 {
                    x - labelWidth
                } else {
                    x - labelWidth / 2
                }

                if labelLeft >= lastLabelRight + minLabelSpacing {
                    let anchor: UnitPoint = if x < 20 {
                        .leading
                    } else if x > size.width - 20 {
                        .trailing
                    } else {
                        .center
                    }
                    context.draw(resolved, at: CGPoint(x: x, y: labelY), anchor: anchor)
                    lastLabelRight = labelLeft + labelWidth
                }
            }
            tickDate = tickDate.addingTimeInterval(interval * 60)
        }
    }

    // MARK: - Relative Time Labels

    private func drawRelativeTimeLabels(
        context: GraphicsContext,
        size: CGSize,
        visibleStart: Double,
        visibleSpan: Double,
        inset: CGFloat,
        graphTop _: CGFloat,
    ) {
        let graphWidth = size.width - inset * 2
        let labelY = inset + 4
        // Determine hour step based on visible span
        let hourStep: Int
        let visibleHours = visibleSpan / 60
        if visibleHours <= 4 { hourStep = 1 }
        else if visibleHours <= 12 { hourStep = 2 }
        else if visibleHours <= 24 { hourStep = 4 }
        else { hourStep = 6 }

        // Always step in whole hours to avoid duplicates
        var hour = 0
        let maxHours = Int(ceil(dataSpan / 60))
        var lastLabelRight: CGFloat = -.infinity
        let minSpacing: CGFloat = 8

        while hour <= maxHours {
            let minutePos = Double(hour) * 60
            let x = inset + CGFloat((minutePos - visibleStart) / visibleSpan) * graphWidth

            if x >= -10, x <= size.width + 10 {
                let label = "\(hour)h"

                let text = Text(label)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary.opacity(0.5))
                let resolved = context.resolve(text)
                let labelWidth = resolved.measure(in: size).width

                let labelLeft: CGFloat = if x < 15 {
                    x
                } else if x > size.width - 15 {
                    x - labelWidth
                } else {
                    x - labelWidth / 2
                }

                if labelLeft >= lastLabelRight + minSpacing {
                    let anchor: UnitPoint = if x < 15 {
                        .leading
                    } else if x > size.width - 15 {
                        .trailing
                    } else {
                        .center
                    }
                    context.draw(resolved, at: CGPoint(x: x, y: labelY), anchor: anchor)
                    lastLabelRight = labelLeft + labelWidth
                }
            }
            hour += hourStep
        }
    }
}
