import SwiftUI

struct TimelineGraphView: View, Equatable {
    let substances: [ActiveSubstanceState]
    let currentTime: Date
    let compact: Bool
    var markers: [DoseMarker] = []
    /// Session notes on the time axis (full graph only): a tappable glyph per
    /// note in the top label band, plus the Shulgin step lane for rated ones.
    var noteMarkers: [NoteMarker] = []
    /// Tap on a note glyph, by note id. Nil leaves the glyphs inert.
    var onNoteTap: ((UUID) -> Void)?
    var stackRedoses: Bool = false
    /// Draws the per-curve "now" dot at `currentTime`. Meaningful on the live
    /// session accessory and the full detail graph; off for the historical
    /// journal thumbnails, where it's an axis-less artifact.
    var showNowIndicator: Bool = true
    /// How far ahead of `currentTime` the real "now" may already have drifted, in
    /// minutes. `0` draws the usual hairline rule.
    ///
    /// For the Live Activity this is non-zero and honest. The graph is a static
    /// image between renders, and ActivityKit gives an app no way to schedule
    /// arbitrary repaints — so by the time the Lock Screen is actually looked at,
    /// true "now" is somewhere between the instant this was drawn and the next
    /// repaint. A 2.5pt rule claims a precision the platform does not permit.
    /// Instead the indicator becomes a translucent band running forward from the
    /// drawn instant, with the crisp edge at the moment we do know: "you are
    /// somewhere in here."
    var nowUncertaintyMinutes: Double = 0
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
    /// Optional Apple Health vitals (heart rate + blood pressure) for this
    /// session's window. When present and non-empty on the full graph, a
    /// companion "cardio lane" is drawn below the effect curves, sharing the
    /// same time axis (so it pans/zooms/scrubs in lockstep). `nil` — the
    /// default — leaves the graph exactly as before, so the fullscreen detail,
    /// export image, and widgets are unaffected.
    var vitals: SessionVitals?
    /// Whether the host graph is in its enlarged (tapped-open) state — grows the
    /// vitals lane along with the effect region so the trace gets more room.
    var vitalsBandEnlarged: Bool = false
    /// When set (the live/current session), the graph opens zoomed to a window
    /// framed around `currentTime` instead of the full extent, so the action
    /// happening *now* is front and center. Past sessions leave it `false` and
    /// open full-extent. Ignored when `compact` or a `presetSpanMinutes` is set.
    var focusAroundNow: Bool = false
    /// Draws the graph as a bordered chart rather than inside a filled card: side
    /// verticals + a bottom origin line (square corners, top-left open), with a
    /// tighter horizontal inset since there's no rounded card corner to clear. Set
    /// only by the session-detail host; every compact/thumbnail/widget context
    /// leaves it off.
    var chartFrame: Bool = false

    // Zoom & pan state (only active when !compact)
    @State private var zoom: CGFloat = 1.0
    @State private var panOffset: Double = 0
    @State private var gestureStartZoom: CGFloat = 1.0
    @State private var gestureStartPan: Double = 0
    /// X position (canvas points) of the active scrub rule, or nil at rest.
    /// Drives the inspection lollipop: a vertical rule + per-curve dots + the
    /// SwiftUI callout. Only set on the full graph (`!compact`).
    @State private var scrubX: CGFloat? = nil
    /// Latest touch x (canvas points), captured by a simultaneous min-distance-0
    /// tracker. The scrub long-press carries no location, and its sequenced drag
    /// stays nil until the finger *moves* — so a stationary hold had nothing to
    /// position the rule with. This lets a motionless hold inspect at the touch.
    @State private var lastTouchX: CGFloat = 0

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

    /// The model computed in `init` on the `synchronous:` path, held as a plain
    /// stored property rather than `@State`.
    ///
    /// This is what unfroze the Live Activity graph. `State(initialValue:)` is
    /// honored **only on the first construction of a given view identity**; on
    /// every later evaluation of that same identity the stored value wins and the
    /// seed is silently discarded. A Live Activity keeps its identity across
    /// content-state updates, so the curves stayed pinned to whatever dose set
    /// existed at the first render — and since ``DerivedKey`` deliberately excludes
    /// `currentTime`, the frozen model also froze `earliestDose`, the graph's
    /// entire x-axis anchor. Back-dating a dose therefore redrew every curve
    /// against a stale origin. Restarting the activity was the only fix, because
    /// `Activity.request` was the only thing that minted a new identity.
    ///
    /// A plain `let` is recomputed by `init` on every evaluation, so it always
    /// reflects the state being rendered. The async path is untouched.
    private let synchronousDerived: TimelineCurveModel.Derived?

    private var derived: TimelineCurveModel.Derived {
        synchronousDerived ?? derivedBox ?? Self.emptyDerived
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
              lhs.nowUncertaintyMinutes == rhs.nowUncertaintyMinutes,
              lhs.highlighted == rhs.highlighted,
              lhs.presetSpanMinutes == rhs.presetSpanMinutes,
              lhs.markers == rhs.markers,
              lhs.noteMarkers == rhs.noteMarkers,
              lhs.vitals == rhs.vitals,
              lhs.vitalsBandEnlarged == rhs.vitalsBandEnlarged,
              lhs.focusAroundNow == rhs.focusAroundNow,
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
        noteMarkers: [NoteMarker] = [],
        onNoteTap: ((UUID) -> Void)? = nil,
        stackRedoses: Bool = false,
        showNowIndicator: Bool = true,
        nowUncertaintyMinutes: Double = 0,
        highlighted: String? = nil,
        presetSpanMinutes: Double? = nil,
        dayBounded: Bool = false,
        vitals: SessionVitals? = nil,
        vitalsBandEnlarged: Bool = false,
        focusAroundNow: Bool = false,
        chartFrame: Bool = false,
        synchronous: Bool = false,
    ) {
        self.substances = substances
        self.currentTime = currentTime
        self.compact = compact
        self.markers = markers
        self.noteMarkers = noteMarkers
        self.onNoteTap = onNoteTap
        self.stackRedoses = stackRedoses
        self.showNowIndicator = showNowIndicator
        self.nowUncertaintyMinutes = nowUncertaintyMinutes
        self.highlighted = highlighted
        self.presetSpanMinutes = presetSpanMinutes
        self.dayBounded = dayBounded
        self.vitals = vitals
        self.vitalsBandEnlarged = vitalsBandEnlarged
        self.focusAroundNow = focusAroundNow
        self.chartFrame = chartFrame
        let key = DerivedKey(substances: substances, markers: markers, stackRedoses: stackRedoses, dayBounded: dayBounded)
        if synchronous {
            // Live Activity / widget snapshots render in one synchronous pass —
            // `.task` never fires before the snapshot is taken — so compute (or
            // reuse) the model inline. The cost is fine off the scroll hot path.
            let model: TimelineCurveModel.Derived
            if let cached = TimelineModelCache.shared.cached(key) {
                model = cached
            } else {
                model = TimelineCurveModel.computeDerived(
                    substances: substances, markers: markers,
                    stackRedoses: stackRedoses, dayBounded: dayBounded, currentTime: currentTime,
                )
                TimelineModelCache.shared.insert(model, for: key)
            }
            // Held in a plain `let`, not `@State` — see `synchronousDerived`.
            synchronousDerived = model
            _derivedBox = State(initialValue: model)
            _loadedKey = State(initialValue: key)
        } else {
            synchronousDerived = nil
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
        // Another path (the journal's batch prewarm, or this card's superseded
        // predecessor) is already computing this key — adopt its result rather
        // than computing the same model twice.
        if !TimelineModelCache.shared.claim(key) {
            guard let model = await TimelineModelCache.shared.computed(key),
                  !Task.isCancelled else { return }
            derivedBox = model
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
        // Caching under the key is always safe, even for a superseded task.
        TimelineModelCache.shared.insert(model, for: key)
        // Inputs changed mid-compute: `.task(id:)` canceled this task, but the
        // detached child doesn't throw, so we'd otherwise publish a stale model
        // *after* the replacement task already finished (e.g. on a cache hit).
        guard !Task.isCancelled else { return }
        derivedBox = model
        loadedKey = key
    }

    private var earliestDose: Date {
        derived.earliestDose
    }

    /// The drawing engine — a value snapshot of everything the Canvas pass
    /// reads, rebuilt on every body evaluation so it always reflects the state
    /// being rendered. Never cached in `@State` (that would re-freeze the Live
    /// Activity the way `synchronousDerived`'s doc describes).
    private var renderer: TimelineGraphRenderer {
        TimelineGraphRenderer(
            substances: substances,
            markers: markers,
            noteMarkers: noteMarkers,
            derived: derived,
            currentTime: currentTime,
            compact: compact,
            stackRedoses: stackRedoses,
            showNowIndicator: showNowIndicator,
            nowUncertaintyMinutes: nowUncertaintyMinutes,
            highlighted: highlighted,
            chartFrame: chartFrame,
            vitals: vitals,
            vitalsBandEnlarged: vitalsBandEnlarged,
            laneMode: laneMode,
            showCompactMarkers: showCompactMarkers,
            scrubX: scrubX,
        )
    }

    /// The visible-window snapshot handed to the renderer, computed from the
    /// zoom/pan state by the windowing math below.
    private var viewport: TimelineGraphRenderer.Viewport {
        TimelineGraphRenderer.Viewport(
            visibleStart: visibleStart,
            visibleSpan: visibleSpan,
            totalSpan: totalSpan,
            maxPanOffset: maxPanOffset,
        )
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
        // past the last curve (a dose still within its window, but its own curve
        // has peaked and fallen). Gated on `hasActiveNow` so a session where
        // *everything* has worn off doesn't balloon the axis out to a now-line
        // that no longer draws. Historical days pass a `currentTime` days later,
        // excluded by the 3 h margin anyway. Skipped for compact thumbnails.
        if !compact, renderer.hasActiveNow {
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
        // Claim misses up front on the main actor (the cache is main-isolated) —
        // a claim makes this batch the sole computer of each key, so a visible
        // card whose own `loadModel` arrives meanwhile awaits the result instead
        // of computing the same model in parallel — then do the expensive curve
        // math off-main and insert the results back.
        let pending: [(key: DerivedKey, substances: [ActiveSubstanceState], markers: [DoseMarker])] =
            inputs.compactMap { input in
                guard !input.substances.isEmpty || !input.markers.isEmpty else { return nil }
                let key = DerivedKey(
                    substances: input.substances, markers: input.markers,
                    stackRedoses: stackRedoses, dayBounded: dayBounded,
                )
                guard TimelineModelCache.shared.claim(key) else { return nil }
                return (key, input.substances, input.markers)
            }
        guard !pending.isEmpty else { return }
        let now = Date.now
        Task.detached(priority: .utility) {
            // Insert per item, not batched at the end: `inputs` arrive in
            // display order, so the visible cards' waiters resolve first,
            // while later days are still computing.
            for item in pending {
                let model = TimelineCurveModel.computeDerived(
                    substances: item.substances, markers: item.markers,
                    stackRedoses: stackRedoses, dayBounded: dayBounded, currentTime: now,
                )
                await MainActor.run {
                    TimelineModelCache.shared.insert(model, for: item.key)
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

    /// Whether stacked lanes are used at all (user-toggleable). When off, busy
    /// days always overlay every curve on one graph regardless of substance count.
    @AppStorage(LaneModeDefaults.enabledKey, store: UserDefaults(suiteName: LaneModeDefaults.suite))
    private var laneModeEnabled = LaneModeDefaults.enabledDefault

    /// Distinct-substance count at or above which overlapping translucent fills
    /// collapse into curve soup, so the day renders as stacked per-substance
    /// lanes (small multiples) instead. User-configurable.
    @AppStorage(LaneModeDefaults.thresholdKey, store: UserDefaults(suiteName: LaneModeDefaults.suite))
    private var laneModeThreshold = LaneModeDefaults.thresholdDefault

    /// Distinct substances drawn on the graph (by lowercased name).
    private var distinctSubstanceCount: Int {
        Set(substances.map { $0.substanceName.lowercased() }).count
    }

    /// Switch a busy day from overlapping curves to stacked lanes. Gated to the
    /// roomy day surfaces (`dayBounded`, non-compact) — thumbnails stay a glance
    /// of texture, and the live accessory keeps its single-baseline look — and to
    /// the user's lane-mode preference.
    private var laneMode: Bool {
        laneModeEnabled && !compact && dayBounded && distinctSubstanceCount >= laneModeThreshold
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

    /// One-utterance VoiceOver summary of the graph at `currentTime`, built from
    /// the same scrub sampling the callout uses so the two never disagree.
    private var accessibilitySummary: Text {
        let nowMinutes = currentTime.timeIntervalSince(earliestDose) / 60
        let samples = renderer.scrubSamples(atMinute: nowMinutes)
        guard !samples.isEmpty else { return Text("No active doses") }
        var parts: [String] = samples.prefix(4).map { sample in
            let percent = Int((sample.value * 100).rounded())
            if let phase = sample.phase {
                return String(localized: "\(sample.name) in \(String(localized: phase)) at \(percent) percent")
            }
            return String(localized: "\(sample.name) at \(percent) percent")
        }
        // The marked region is drawn, so it has to be spoken too.
        if renderer.heavyThresholdHeight != nil {
            parts.append(String(localized: "This curve reaches the heavy dose range"))
        }
        return Text(verbatim: parts.joined(separator: ", "))
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
            // Thumbnails ride inside card buttons that already speak the
            // session — an unlabeled Canvas would only double-read there.
            graphCanvas
                .accessibilityHidden(true)
        } else {
            GeometryReader { geo in
                let geom = renderer.geometry(for: geo.size)
                ZStack(alignment: .topLeading) {
                    graphCanvas
                        .contentShape(Rectangle())
                        .gesture(panZoomGesture(graphWidth: geom.width))
                        .highPriorityGesture(scrubGesture(geom: geom))
                        .simultaneousGesture(touchTrackingGesture())
                        .onTapGesture(count: 2) {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                zoom = 1.0
                                panOffset = 0
                                gestureStartZoom = 1.0
                                gestureStartPan = 0
                            }
                        }
                    noteGlyphs(geom: geom)
                    scrubCallout(geom: geom)
                }
            }
            // Inlined equivalent of the app target's `chartSummaryAccessibility`
            // helper — this file also compiles into the widget targets, which
            // don't include Piru/Views/Components.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Timeline"))
            .accessibilityValue(accessibilitySummary)
            .onAppear {
                if focusAroundNow, presetSpanMinutes == nil {
                    frameAroundNow()
                } else {
                    frameToPreset(presetSpanMinutes)
                }
            }
            .onChange(of: presetSpanMinutes) { _, newValue in
                withAnimation(.easeInOut(duration: 0.3)) { frameToPreset(newValue) }
            }
        }
    }

    /// Window a live session opens framed to (minutes), and where `now` sits in it
    /// (a third from the left — a little recent past, more of the unfolding curve).
    private static let focusSpanMinutes: Double = 360
    private static let nowFraction: Double = 1.0 / 3.0

    /// Open zoomed around `currentTime` for the live session. Falls back to the
    /// full extent when the whole session already fits the focus window.
    private func frameAroundNow() {
        guard !compact, autoFitSpan > 0, totalSpan > 0 else { return }
        let focus = Self.focusSpanMinutes
        guard totalSpan > focus else { frameToPreset(nil); return }
        zoom = min(max(minZoom, CGFloat(autoFitSpan / focus)), 10)
        gestureStartZoom = zoom
        let nowMinutes = currentTime.timeIntervalSince(earliestDose) / 60
        panOffset = min(max(0, nowMinutes - focus * Self.nowFraction), totalSpan - focus)
        gestureStartPan = panOffset
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
    private func scrubGesture(geom: TimelineGraphRenderer.GraphGeometry) -> some Gesture {
        LongPressGesture(minimumDuration: 0.25, maximumDistance: 12)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                // `.second(true, …)` fires the moment the long press completes;
                // the drag value is nil until the finger moves, so fall back to
                // the tracked touch position to inspect on a stationary hold.
                if case let .second(true, drag) = value {
                    let x = drag?.location.x ?? lastTouchX
                    scrubX = min(max(x, geom.inset), geom.inset + geom.width)
                }
            }
            .onEnded { _ in
                scrubX = nil
            }
    }

    /// Records the live touch position so the scrub long-press has somewhere to
    /// place the rule even when the finger never moves. Min-distance 0 → fires on
    /// touch-down; simultaneous → never steals the pan or scrub gestures.
    private func touchTrackingGesture() -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { lastTouchX = $0.location.x }
    }

    /// The floating readout above the scrub rule: scrubbed clock time plus each
    /// present curve's name and intensity, and the heart rate. SwiftUI (not Canvas
    /// text) so it localizes and respects Dynamic Type. Non-interactive; clamped.
    @ViewBuilder
    private func scrubCallout(geom: TimelineGraphRenderer.GraphGeometry) -> some View {
        if let scrubX, geom.width > 0 {
            let minute = visibleStart + Double((scrubX - geom.inset) / geom.width) * visibleSpan
            let samples = renderer.scrubSamples(atMinute: minute)
            let heartRate = renderer.scrubHeartRate(atMinute: minute)
            if !samples.isEmpty || heartRate != nil {
                let calloutWidth: CGFloat = 158
                let maxLeft = max(4, geom.width + geom.inset * 2 - calloutWidth - 4)
                let left = min(max(scrubX - calloutWidth / 2, 4), maxLeft)
                VStack(alignment: .leading, spacing: 3) {
                    Text(renderer.scrubClockTime(atMinute: minute))
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
                            VStack(alignment: .trailing, spacing: 0) {
                                Text(verbatim: "\(Int((sample.value * 100).rounded()))%")
                                    .font(.caption2.weight(.medium).monospacedDigit())
                                    .foregroundStyle(.secondary)
                                if let phase = sample.phase {
                                    Text(phase)
                                        .font(.system(size: 9).weight(.medium))
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    if let heartRate {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(VitalsPalette.heart)
                                .frame(width: 7, height: 7)
                            Text("Heart rate")
                                .font(.caption2)
                                .lineLimit(1)
                            Spacer(minLength: 6)
                            Text("\(heartRate) bpm")
                                .font(.caption2.weight(.medium).monospacedDigit())
                                .foregroundStyle(VitalsPalette.heart)
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

    /// One tappable glyph per note, placed on the time axis in the band above
    /// the curves (where the relative-hour labels live). SwiftUI overlays rather
    /// than Canvas marks so each is a real button with a real hit target; they
    /// re-place on every pan/zoom because `body` re-runs with the viewport.
    @ViewBuilder
    private func noteGlyphs(geom: TimelineGraphRenderer.GraphGeometry) -> some View {
        if !noteMarkers.isEmpty, geom.width > 0, visibleSpan > 0 {
            let size: CGFloat = 16
            ForEach(noteMarkers) { marker in
                let minute = marker.timestamp.timeIntervalSince(earliestDose) / 60
                let x = geom.inset + CGFloat((minute - visibleStart) / visibleSpan) * geom.width
                if x >= geom.inset - size / 2, x <= geom.inset + geom.width + size / 2 {
                    Button {
                        onNoteTap?(marker.id)
                    } label: {
                        Image(systemName: Self.glyph(for: marker.kind))
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: size, height: size)
                            .background(Color.accentColor, in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .contentShape(Circle().inset(by: -6))
                    .accessibilityLabel(Text("Note"))
                    .position(x: x, y: max(size / 2, geom.top - size / 2 - 1))
                }
            }
        }
    }

    /// The glyph for a note kind: a quote for an observation, a bell for a
    /// check-in, lines for the summary.
    static func glyph(for kind: SessionNote.Kind) -> String {
        switch kind {
        case .observation: "quote.opening"
        case .checkIn: "bell.fill"
        case .summary: "text.alignleft"
        }
    }

    private var graphCanvas: some View {
        Canvas { context, size in
            let r = renderer
            r.draw(in: context, size: size, geom: r.geometry(for: size), viewport: viewport)
        }
        .clipped()
    }
}
