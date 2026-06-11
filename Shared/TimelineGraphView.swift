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
struct DoseMarker: Hashable {
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

    private var store: [TimelineGraphView.DerivedKey: TimelineCurveModel.Derived] = [:]
    private var order: [TimelineGraphView.DerivedKey] = []
    private let limit = 120

    func cached(_ key: TimelineGraphView.DerivedKey) -> TimelineCurveModel.Derived? {
        store[key]
    }

    func insert(_ value: TimelineCurveModel.Derived, for key: TimelineGraphView.DerivedKey) {
        if store[key] == nil { order.append(key) }
        store[key] = value
        while order.count > limit {
            let evicted = order.removeFirst()
            store[evicted] = nil
        }
    }
}

struct TimelineGraphView: View, Equatable {
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
    var highlighted: String?
    /// Desired visible window in minutes, set by the fullscreen detail view's
    /// window presets (4h/8h/12h/24h). `nil` means "fit everything" (the All
    /// preset / the embedded default). Applied to `zoom` on appear and whenever
    /// it changes; the user can still pinch/pan afterwards. Ignored when
    /// `compact`.
    var presetSpanMinutes: Double?
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

    /// Identity for the model cache: everything `computeDerived` actually
    /// consumes. Deliberately excludes `currentTime` (used only as the
    /// empty-input fallback) so a live view whose `.now` ticks each frame still
    /// hits the cache, and excludes `compact`/`showNowIndicator`/`highlighted`
    /// (presentation-only, not part of the curve geometry).
    struct DerivedKey: Hashable {
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
    @State private var derivedBox: TimelineCurveModel.Derived?

    /// The ``DerivedKey`` that ``derivedBox`` was computed for. Lets ``loadModel``
    /// tell "already showing the model for *this* key" (skip — the common
    /// re-appear/scroll case) from "showing a *stale* model for a previous key"
    /// (adopt the new one). Without it, deleting a dose left the old curves drawn
    /// whenever the smaller post-deletion set was already cached: the `.task`
    /// re-fired, hit the cache, but the old guard refused to overwrite a non-nil
    /// box, so the lines persisted while the live-drawn phase background updated.
    @State private var loadedKey: DerivedKey?

    /// Benign zero model so the rendering accessors stay total even if a layout
    /// pass touches them before `derivedBox` is populated (the body shows the
    /// placeholder, not the graph, in that window).
    private static let emptyDerived = TimelineCurveModel.Derived(
        earliestDose: .distantPast,
        maxDoseBySubstance: [:],
        stackedGroups: [],
        peakCurveValue: 0.0001,
        yNormalization: 20,
        rawDataTail: 1,
        rawActivityTail: 1,
    )

    private var derived: TimelineCurveModel.Derived {
        derivedBox ?? Self.emptyDerived
    }

    /// Equatable so call sites can wrap the graph in `.equatable()` and let
    /// SwiftUI skip re-evaluating its `body` — and therefore re-running the
    /// `Canvas`, which rebuilds every 240-step curve path — when a parent
    /// re-render (a journal `rebuildAll`, a scroll, a sibling's 60 s tick)
    /// leaves the graph's actual inputs unchanged. Internal `@State` (zoom /
    /// pan / scrub / the derived box) is preserved and still drives its own
    /// updates; this only gates *parent-driven* redraws.
    ///
    /// `currentTime` is compared only when the now-indicator is on — there it
    /// moves the now-dot and flips active/worn-off emphasis, so compare at
    /// minute granularity so a per-frame `.now` doesn't thrash the Canvas.
    /// Historical thumbnails (`showNowIndicator == false`) ignore it entirely;
    /// their curves are all in the past and don't move.
    static func == (lhs: TimelineGraphView, rhs: TimelineGraphView) -> Bool {
        guard lhs.compact == rhs.compact,
              lhs.stackRedoses == rhs.stackRedoses,
              lhs.dayBounded == rhs.dayBounded,
              lhs.showNowIndicator == rhs.showNowIndicator,
              lhs.highlighted == rhs.highlighted,
              lhs.presetSpanMinutes == rhs.presetSpanMinutes,
              lhs.markers == rhs.markers,
              lhs.substances == rhs.substances
        else { return false }
        guard lhs.showNowIndicator else { return true }
        return Int(lhs.currentTime.timeIntervalSinceReferenceDate / 60)
            == Int(rhs.currentTime.timeIntervalSinceReferenceDate / 60)
    }

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
                let model = TimelineCurveModel.computeDerived(
                    substances: substances, markers: markers,
                    stackRedoses: stackRedoses, dayBounded: dayBounded, currentTime: currentTime,
                )
                TimelineModelCache.shared.insert(model, for: key)
                _derivedBox = State(initialValue: model)
            }
            _loadedKey = State(initialValue: key)
        } else {
            // Synchronous cache read only — never compute here. A hit renders
            // immediately (no placeholder frame); a miss leaves `nil` and the
            // `.task` computes off-main, popping the curves in when ready.
            let cached = TimelineModelCache.shared.cached(key)
            _derivedBox = State(initialValue: cached)
            _loadedKey = State(initialValue: cached != nil ? key : nil)
        }
    }

    /// Resolve the model: cache hit → adopt; miss → compute on a background
    /// executor, cache it, then publish. Runs from `.task(id:)`, so it re-fires
    /// only when the inputs actually change.
    private func loadModel() async {
        let key = derivedKey
        // Already displaying the model for this exact key (re-appear / scroll /
        // a live `.now` tick) — nothing to recompute or re-assign.
        if loadedKey == key, derivedBox != nil { return }
        if let cached = TimelineModelCache.shared.cached(key) {
            derivedBox = cached
            loadedKey = key
            return
        }
        let subs = substances
        let mks = markers
        let sr = stackRedoses
        let db = dayBounded
        let ct = currentTime
        let model = await Task.detached(priority: .userInitiated) {
            TimelineCurveModel.computeDerived(substances: subs, markers: mks, stackRedoses: sr, dayBounded: db, currentTime: ct)
        }.value
        TimelineModelCache.shared.insert(model, for: key)
        derivedBox = model
        loadedKey = key
    }

    private var earliestDose: Date {
        derived.earliestDose
    }

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
            var results: [(DerivedKey, TimelineCurveModel.Derived)] = []
            results.reserveCapacity(pending.count)
            for item in pending {
                let model = TimelineCurveModel.computeDerived(
                    substances: item.substances, markers: item.markers,
                    stackRedoses: stackRedoses, dayBounded: dayBounded, currentTime: now,
                )
                results.append((item.key, model))
            }
            await MainActor.run {
                for (key, model) in results {
                    TimelineModelCache.shared.insert(model, for: key)
                }
            }
        }
    }

    /// Effective ceiling for the axis window. A day-bounded host (journal card,
    /// day detail) clamps to 24h; everything else keeps the 48h default.
    private var displayCapMinutes: Double {
        dayBounded ? 24 * 60 : TimelineCurveModel.maxDisplayMinutes
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
    private var laneGroups: [TimelineCurveModel.LaneGroup] {
        TimelineCurveModel.laneGroups(of: substances)
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
        let activityInterval = TimelineCurveModel.intervalForSpan(activitySpan)
        let activity = max(ceil(activitySpan / activityInterval) * activityInterval, 1)
        let full = max(dataSpan, 1)
        // Reframe when the low tail adds real dead axis (> 2.5 h past the
        // clearly-active window). Short curves with a small tail show whole.
        return full - activity > 150 ? activity : full
    }

    /// Max dose amount per substance name, used to scale curve heights proportionally.
    private var maxDoseBySubstance: [String: Double] {
        derived.maxDoseBySubstance
    }

    /// Single-dose (non-stacked) height: the same saturating Hill link applied
    /// to this dose's magnitude, so a lone dose and a stacked group of the same
    /// total agree on height. The *unclamped* magnitude already encodes relative
    /// dose size (a 17 g alcohol renders ~half a 34 g, a heavy dose saturates),
    /// so no separate multi-dose multiplier is needed. `substances`/`maxDose`
    /// are retained for call-site symmetry with the stacked path.
    private func heightScale(for substance: ActiveSubstanceState) -> Double {
        TimelineCurveModel.heightScale(for: substance, substances: substances, maxDose: derived.maxDoseBySubstance)
    }

    /// Multiplier mapping the tallest curve to full height (capped so a tiny
    /// floor value can't blow up beyond the graph).
    private var yNormalization: Double {
        derived.yNormalization
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
                let params = group.map { TimelineCurveModel.pkParams(for: $0) }
                let v = min(1, max(0, stackedIntensity(atGlobalMinutes: global, group: group, params: params) * yNorm))
                guard v > 0.01 else { continue }
                out.append(ScrubSample(id: gi, name: first.substanceName, color: Color(hex: first.colorHex), value: v, elapsed: global - gStart))
            }
        } else {
            for (i, s) in substances.enumerated() {
                let offset = s.doseTimestamp.timeIntervalSince(earliestDose) / 60
                let local = global - offset
                let params = TimelineCurveModel.pkParams(for: s)
                guard local >= 0, local <= TimelineCurveModel.curveExtent(for: s, params: params) else { continue }
                let v = min(1, max(0, TimelineCurveModel.intensity(at: local, for: s, params: params) * heightScale(for: s) * yNorm))
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
            let v = TimelineCurveModel.intensity(at: elapsed, for: s, params: TimelineCurveModel.pkParams(for: s)) * heightScale(for: s) * yNorm
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
            let params = group.map { TimelineCurveModel.pkParams(for: $0) }
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
        let target = min(max(span ?? totalSpan, 1), totalSpan)
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
            var context = context
            let geom = graphGeometry(for: size)
            let graphInset = geom.inset
            let graphTop = geom.top
            let graphWidth = geom.width
            let graphHeight = geom.height

            // Clip every draw to the inset plot column. A curve is drawn out to
            // `curveExtent` (its ~1.5 % taper), which can run a hair past the
            // at-rest visible span (a 4 %-height threshold) — so its elimination
            // tail would otherwise bleed into the right inset and clip at the bare
            // canvas edge, leaving the curve flush-right but inset-left (the
            // asymmetric-padding bug). Clipping to `[graphInset, width-graphInset]`
            // makes both margins exactly `graphInset`. Labels anchor inside this
            // band, so they're unaffected; the full height is kept for the
            // top/bottom label rows.
            context.clip(to: Path(CGRect(
                x: graphInset, y: 0,
                width: max(0, size.width - graphInset * 2), height: size.height,
            )))

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

            // Phase bands (bottom layer — onset/come-up/peak/offset regions for a
            // lone substance, like the curve tuner). Self-guards on count == 1.
            drawPhaseBands(
                context: context,
                size: size,
                visibleStart: vStart,
                visibleSpan: vSpan,
                graphTop: graphTop,
                graphHeight: graphHeight,
                graphInset: graphInset,
            )

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
                    with: .color(.primary.opacity(0.55)),
                    lineWidth: compact ? 1 : 2,
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
                    let scale = TimelineCurveModel.compressedAmplitude(heightScale(for: substance) * yNorm)
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
                        let y = graphTop + graphHeight - CGFloat(TimelineCurveModel.intensity(at: elapsed, for: substance, params: TimelineCurveModel.pkParams(for: substance)) * scale) * graphHeight * 0.93
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
        let markerLanes = TimelineCurveModel.markerOnlyLanes(excluding: curveLanes, markers: markers)
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
                let groups = TimelineCurveModel.stackedGroups(of: lane.doses)
                // Per-lane peak across the summed envelopes so this substance's
                // tallest moment fills the lane, independent of the others.
                var peak = 1e-6
                for group in groups {
                    let (gs, ge) = stackedGroupRange(group)
                    guard ge > gs else { continue }
                    let params = group.map { TimelineCurveModel.pkParams(for: $0) }
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
                    let params = TimelineCurveModel.pkParams(for: dose)
                    let hs = heightScale(for: dose)
                    let end = TimelineCurveModel.curveExtent(for: dose, params: params)
                    let steps = 40
                    for j in 0 ... steps {
                        let t = Double(j) / Double(steps) * end
                        peak = max(peak, TimelineCurveModel.intensity(at: t, for: dose, params: params) * hs)
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

                // "You are here" dot on this lane's frontmost active dose, so a
                // busy day still marks the present per-substance — matching the
                // overlapping/stacked renderers.
                if showNowIndicator, scrubX == nil {
                    let nowGlobal = currentTime.timeIntervalSince(earliestDose) / 60
                    let nowX = graphInset + CGFloat((nowGlobal - visibleStart) / visibleSpan) * graphWidth
                    if nowX >= graphInset, nowX <= graphInset + graphWidth {
                        var bestV = -1.0
                        for dose in lane.doses {
                            let offset = dose.doseTimestamp.timeIntervalSince(earliestDose) / 60
                            let elapsed = nowGlobal - offset
                            guard elapsed >= 0, elapsed <= dose.totalMinutes else { continue }
                            let v = TimelineCurveModel.intensity(at: elapsed, for: dose, params: TimelineCurveModel.pkParams(for: dose)) * heightScale(for: dose) * norm
                            bestV = max(bestV, v)
                        }
                        if bestV >= 0 {
                            let y = baseline - CGFloat(min(1, max(0, bestV))) * amplitude * 0.93
                            drawNowDot(context, x: nowX, y: y, color: color)
                        }
                    }
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
        let params = group.map { TimelineCurveModel.pkParams(for: $0) }
        let steps = compact ? 48 : 140

        var vs: [Double] = []
        vs.reserveCapacity(steps + 1)
        for i in 0 ... steps {
            let t = gStart + Double(i) / Double(steps) * gSpan
            vs.append(stackedIntensity(atGlobalMinutes: t, group: group, params: params) * norm)
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

        // "You are here" dot, read from the same smoothed sample array so it
        // stays glued to the rendered envelope.
        if showNowIndicator, scrubX == nil {
            let nowGlobal = currentTime.timeIntervalSince(earliestDose) / 60
            if nowGlobal >= gStart, nowGlobal <= gEnd {
                let nowX = graphInset + CGFloat((nowGlobal - visibleStart) / visibleSpan) * graphWidth
                if nowX >= graphInset, nowX <= graphInset + graphWidth {
                    let idx = max(0, min(Double(steps), (nowGlobal - gStart) / gSpan * Double(steps)))
                    let lo = Int(idx.rounded(.down))
                    let hi = min(lo + 1, steps)
                    let frac = idx - Double(lo)
                    let v = min(1, max(0, vs[lo] * (1 - frac) + vs[hi] * frac))
                    let y = baseline - CGFloat(v) * amplitude * 0.93
                    drawNowDot(context, x: nowX, y: y, color: color)
                }
            }
        }
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

    // swiftlint:disable function_parameter_count

    /// A single duration-less dose as a lollipop: a thin stem rising from the
    /// lane baseline to a filled, ringed head at `headCenterY`. The stem grounds
    /// the dose to the time axis while the head gives it the vertical presence of
    /// a curve's hump, so an instant dose reads as a real logged event rather
    /// than a stray fleck on an otherwise empty lane. Mirrors the marker-line +
    /// circle treatment the non-lane overlay already uses.
    ///
    /// The parameters are flat lane/viewport geometry scalars for a single
    /// Canvas draw pass, so the count exemption beats a one-off wrapper struct.
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

    // swiftlint:enable function_parameter_count

    /// The "you are here" dot: a filled, white-ringed circle on a curve at the
    /// current moment. Shared by the overlapping, stacked, and lane renderers so
    /// every graph marks the present the same way.
    private func drawNowDot(_ context: GraphicsContext, x: CGFloat, y: CGFloat, color: Color, size: CGFloat = 7) {
        let dot = Path(ellipseIn: CGRect(x: x - size / 2, y: y - size / 2, width: size, height: size))
        context.fill(dot, with: .color(color))
        context.stroke(dot, with: .color(.white.opacity(0.85)), lineWidth: 1)
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
            let params = TimelineCurveModel.pkParams(for: substance)
            let drawEnd = TimelineCurveModel.curveExtent(for: substance, params: params)
            var pts: [CGPoint] = []
            pts.reserveCapacity(steps + 1)
            for i in 0 ... steps {
                let t = Double(i) / Double(steps) * drawEnd
                let x = graphInset + CGFloat((substanceOffset + t - visibleStart) / visibleSpan) * graphWidth
                let y = graphTop + graphHeight - CGFloat(TimelineCurveModel.intensity(at: t, for: substance, params: params) * scale) * graphHeight * 0.93
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
            let params = TimelineCurveModel.pkParams(for: substance)
            let drawEnd = TimelineCurveModel.curveExtent(for: substance, params: params)

            let startX = graphInset + CGFloat((substanceOffset - visibleStart) / visibleSpan) * graphWidth
            path.move(to: CGPoint(x: startX, y: baseline))

            var pts: [CGPoint] = []
            pts.reserveCapacity(steps + 1)
            for i in 0 ... steps {
                let t = Double(i) / Double(steps) * drawEnd
                let x = graphInset + CGFloat((substanceOffset + t - visibleStart) / visibleSpan) * graphWidth
                let y = graphTop + graphHeight - CGFloat(TimelineCurveModel.intensity(at: t, for: substance, params: params) * scale) * graphHeight * 0.93
                pts.append(CGPoint(x: x, y: y))
            }
            addSmoothCurve(pts, to: &path, startNew: false)

            let endX = graphInset + CGFloat((substanceOffset + drawEnd - visibleStart) / visibleSpan) * graphWidth
            path.addLine(to: CGPoint(x: endX, y: baseline))
            path.closeSubpath()
        }
    }

    /// Append a smooth curve through `pts` using a **monotone** cubic Hermite
    /// spline (Fritsch–Carlson tangents) converted to cubic Bézier segments.
    ///
    /// The earlier uniform Catmull-Rom rendered the sampled PK points smoothly
    /// but overshot at sharp transitions: a fast-onset dose (kratom) sits flat at
    /// baseline through the onset, then rises near-vertically — Catmull-Rom's
    /// averaged tangent at that corner dipped the spline *below the baseline*
    /// before the rise (the "broken curve" artifact) and could bulge *above* the
    /// flat peak plateau. Fritsch–Carlson clamps each tangent so the interpolant
    /// stays monotone within every monotone data run: zero slope at extrema (a
    /// rounded peak, a clean baseline touchdown) and no excursion past the data.
    /// Because x is strictly increasing for a sampled curve we interpolate y as a
    /// function of x, so the guarantee holds in screen space directly.
    ///
    /// When `startNew` is false the current point is assumed to be `pts[0]` (used
    /// by the fill path, which has already moved to the baseline start).
    private func addSmoothCurve(_ pts: [CGPoint], to path: inout Path, startNew: Bool) {
        guard pts.count >= 2 else {
            if let p = pts.first { startNew ? path.move(to: p) : path.addLine(to: p) }
            return
        }
        let n = pts.count

        // Secant slopes dy/dx between consecutive samples. x increases left→right,
        // so dx > 0; guard against a degenerate coincident pair anyway.
        var delta = [Double](repeating: 0, count: n - 1)
        for i in 0 ..< n - 1 {
            let dx = Double(pts[i + 1].x - pts[i].x)
            delta[i] = dx != 0 ? Double(pts[i + 1].y - pts[i].y) / dx : 0
        }

        // Fritsch–Carlson tangents: average adjacent secants, force zero at any
        // sign change (local extremum), and cap magnitude at 3× the smaller
        // neighbouring secant so a cubic segment can't overshoot its endpoints.
        var m = [Double](repeating: 0, count: n)
        m[0] = delta[0]
        m[n - 1] = delta[n - 2]
        for i in 1 ..< n - 1 {
            if delta[i - 1] * delta[i] <= 0 {
                m[i] = 0
            } else {
                let avg = (delta[i - 1] + delta[i]) / 2
                let lim = 3 * min(abs(delta[i - 1]), abs(delta[i]))
                m[i] = min(max(avg, -lim), lim)
            }
        }

        if startNew { path.move(to: pts[0]) } else { path.addLine(to: pts[0]) }
        for i in 0 ..< n - 1 {
            let dx = Double(pts[i + 1].x - pts[i].x)
            let c1 = CGPoint(x: pts[i].x + CGFloat(dx / 3), y: pts[i].y + CGFloat(m[i] * dx / 3))
            let c2 = CGPoint(x: pts[i + 1].x - CGFloat(dx / 3), y: pts[i + 1].y - CGFloat(m[i + 1] * dx / 3))
            path.addCurve(to: pts[i + 1], control1: c1, control2: c2)
        }
    }

    // MARK: - Stacked Rendering

    /// Groups substance states by lowercased substance name, preserving original order.
    private var stackedGroups: [[ActiveSubstanceState]] {
        derived.stackedGroups
    }

    /// Combined intensity of a group at a given global time (minutes since
    /// earliestDose) — the **upper envelope** (max) of the per-dose curves, each
    /// weighted by its `doseIntensity`.
    ///
    /// This is deliberately *not* a numeric sum. The curve is a coarse subjective
    /// approximation (a flat-topped plateau, not a precise plasma trace), so
    /// summing two overlapping doses produced a stepped, far-too-wavy shape — two
    /// plateaus adding to 2× in the overlap and dropping back on the flanks — that
    /// read as arithmetic rather than as one sustained effect. The envelope
    /// instead merges overlapping redoses into a single clean plateau (as smooth
    /// as one dose, just longer), a bigger redose still rises higher where it
    /// dominates, and well-separated doses keep their distinct humps. The caller
    /// normalizes by the combined peak (`peakCurveValue`); the effect-site
    /// low-pass then rounds the hand-off where one dose overtakes another.
    /// `params` holds the precomputed Bateman fit per dose, aligned to `group`.
    private func stackedIntensity(atGlobalMinutes global: Double, group: [ActiveSubstanceState], params: [TimelineCurveModel.PKCurveParams]) -> Double {
        TimelineCurveModel.stackedIntensity(atGlobalMinutes: global, group: group, params: params, earliestDose: derived.earliestDose)
    }

    private func stackedGroupRange(_ group: [ActiveSubstanceState]) -> (start: Double, end: Double) {
        TimelineCurveModel.stackedGroupRange(group, earliestDose: derived.earliestDose)
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
            let params = group.map { TimelineCurveModel.pkParams(for: $0) }
            let activeEnd = group.map { $0.doseTimestamp.timeIntervalSince(earliestDose) / 60 + $0.totalMinutes }.max() ?? gEnd
            let emph = emphasis(name: first.substanceName, isActive: nowGlobal >= gStart && nowGlobal <= activeEnd)

            // Sample the merged curve `Hill(Σ magnitude·bell)`. The Hill
            // superposition is already smooth and keeps overlapping crests flat,
            // so no post-hoc envelope low-pass is needed — and spread-out redoses
            // whose bells don't overlap stay as distinct humps (correct: they're
            // separate experiences), instead of being fused into one dome.
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
                let factor = TimelineCurveModel.compressedAmplitude(groupPeak) / groupPeak
                if factor != 1 {
                    for i in vs.indices {
                        vs[i] *= factor
                    }
                }
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

    /// Shaded onset / come-up / peak / offset regions behind the curve, mirroring
    /// the curve tuner's legend so the phases are legible at a glance. Drawn only
    /// for a **single substance's single dose** (the "open a card for it" case) —
    /// multiple curves or a redose stack would overlap into mud, so they stay
    /// unbanded. Compact thumbnails skip it (too small for labels).
    private func drawPhaseBands(
        context: GraphicsContext,
        size: CGSize,
        visibleStart: Double,
        visibleSpan: Double,
        graphTop: CGFloat,
        graphHeight: CGFloat,
        graphInset: CGFloat,
    ) {
        guard !compact, substances.count == 1, let s = substances.first else { return }
        let graphWidth = size.width - graphInset * 2
        guard graphWidth > 0, visibleSpan > 0 else { return }
        let doseOffset = s.doseTimestamp.timeIntervalSince(earliestDose) / 60

        // Use the same synthesized come-up the curve is fit to, so the blue
        // band tracks the rendered rise even when the source data lists no
        // come-up phase (otherwise the curve climbs through a "peak"-coloured
        // band with no come-up band at all).
        let peakEndForBands = max(s.peakEndMinutes, s.onsetEndMinutes + 2)
        let comeupEndForBands = TimelineCurveModel.effectiveComeupEnd(for: s, onsetEnd: s.onsetEndMinutes, peakEnd: peakEndForBands)
        let bands: [(start: Double, end: Double, color: Color)] = [
            (0, s.onsetEndMinutes, Color(hex: "9B9BA1")),
            (s.onsetEndMinutes, comeupEndForBands, Color(hex: "3A8DEF")),
            (comeupEndForBands, s.peakEndMinutes, Color(hex: "34C759")),
            (s.peakEndMinutes, s.offsetEndMinutes, Color(hex: "FF9F0A")),
        ]

        let leftBound = graphInset
        let rightBound = graphInset + graphWidth

        // Clip the whole band block to a rounded rect so its outer corners are
        // concentric with the hosting card instead of square against it. Scoped to
        // a layer so the rounding affects only the bands, not the curve/gridlines.
        // Internal phase boundaries stay crisp — only edges meeting a corner round.
        let plotRect = CGRect(x: graphInset, y: graphTop, width: graphWidth, height: graphHeight)
        context.drawLayer { layer in
            layer.clip(to: Path(roundedRect: plotRect, cornerRadius: 10, style: .continuous))
            for band in bands {
                guard band.end > band.start else { continue }
                let gStart = doseOffset + band.start
                let gEnd = doseOffset + band.end
                let rawX0 = graphInset + CGFloat((gStart - visibleStart) / visibleSpan) * graphWidth
                let rawX1 = graphInset + CGFloat((gEnd - visibleStart) / visibleSpan) * graphWidth
                let x0 = min(max(rawX0, leftBound), rightBound)
                let x1 = min(max(rawX1, leftBound), rightBound)
                guard x1 - x0 > 0.5 else { continue }

                // Background tint only — the curve's shape already names the phases,
                // and labels would collide with the line.
                layer.fill(
                    Path(CGRect(x: x0, y: graphTop, width: x1 - x0, height: graphHeight)),
                    with: .color(band.color.opacity(0.12)),
                )
            }
        }
    }

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
        let interval = TimelineCurveModel.intervalForSpan(visibleSpan)

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

        let interval = TimelineCurveModel.intervalForSpan(visibleSpan)

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
