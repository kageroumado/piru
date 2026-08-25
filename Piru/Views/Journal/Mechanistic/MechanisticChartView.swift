import SwiftUI

/// The mechanistic effect chart for one lens: a windowed felt-effect curve on a
/// fixed session-wide axis, panned by dragging and zoomed by pinching, with a
/// thin pan indicator at the bottom edge and a "now" line + dot on the curve.
/// Custom `Canvas` (the app's precedent for PK curves), matching the approved
/// `app-timeline` prototype.
///
/// Fills the height it's given so it lines up with the classic timeline graph
/// (the host sizes both from ``GraphMetrics``). No card of its own — it sits in a
/// grouped section like the timeline graph does.
/// One named curve in a multi-plan comparison. Given these, a chart draws each
/// as a plain colored line on a shared axis — no area fill and no crash recolor,
/// because in a comparison the color has to mean *which plan*, not *how it's
/// going*. Two red-tinted crashes would be indistinguishable.
struct MechanisticComparisonSeries: Identifiable, Equatable {
    let id: String
    let timeline: EffectTimeline
    let color: Color

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.color == rhs.color && lhs.timeline.t.count == rhs.timeline.t.count
    }
}

struct MechanisticChartView: View {
    let result: MechanisticSessionModel.Result
    let lens: EffectLens
    let startDate: Date
    /// Hours since session start for the "now" indicator (clamped to the window).
    let nowHours: Double
    /// Dose tick positions + colors, supplied by the host (not baked into
    /// `result`) so a recolor updates the marks without re-simulating.
    let doseMarks: [MechanisticSessionModel.DoseMark]
    let vitals: SessionVitals?
    /// When `false`, the chart frames the whole session (no pan window) and
    /// claims no drag/pinch gestures — so a scrolling stack of these charts (the
    /// Effect Estimates overview) scrolls freely instead of each card trapping
    /// the drag. Interactive (the default) keeps the panned/zoomed window.
    var interactive: Bool = true
    /// Seed the initial window to the whole session span rather than a zoomed
    /// sub-window. The overview stack frames each full session yet still allows
    /// pinch-zoom; session detail leaves this off (it opens zoomed around now).
    var startFramed: Bool = false
    /// When non-empty, these curves are drawn instead of `result`'s own — a
    /// comparison of several plans on one axis. `result` still supplies the time
    /// extent and (unless overridden) the axis.
    var comparison: [MechanisticComparisonSeries] = []
    /// A shared axis spanning every compared plan. Without it each plan would be
    /// drawn against its own `result`'s range and two different doses could look
    /// identical — the exact comparison the chart is there to make.
    var axisOverride: MechanisticSessionModel.AxisRange?
    /// Wall-clock labels along the bottom axis. Meaningless for a hypothetical
    /// whose start date is synthetic, so the estimator turns them off and keeps
    /// only the elapsed-hours row.
    var showsClockAxis: Bool = true

    /// Visible window width in hours (zoom). Seeded on appear.
    @State private var winW: Double = 5.5
    /// Left edge of the visible window in hours.
    @State private var winStart: Double = 0
    /// Window left-edge captured at the start of a pan.
    @State private var panAnchor: Double?
    /// Window captured at the start of a pinch so zoom pivots about a fixed hour.
    @State private var zoomAnchor: (win: Double, start: Double)?
    /// Measured width of the chart canvas, for gesture math (never `UIScreen`).
    @State private var chartWidth: CGFloat = 320
    /// Whether the initial window has been framed (once, on first measurement).
    @State private var seeded = false

    private enum Metric {
        /// Horizontal content inset. Strokes and labels must stay clear of the
        /// hosting card's rounded corners — content drawn into the corner-arc
        /// zone gets sliced — so the chart keeps a concentric margin instead of
        /// bleeding edge to edge.
        static let edge: CGFloat = 14
        /// Top band: elapsed-hours labels ride at the very top, the dose dots
        /// below them at the curve region's upper edge.
        static let top: CGFloat = 24
        static let labelBand: CGFloat = 18
        static let doseDot: CGFloat = 8
        static let minWindow: Double = 0.75
        /// The bpm mapped to the bottom / span of the chart band by the Safety
        /// lens's heart-rate trace (55–125 bpm covers rest → hard exertion).
        static let hrFloorBPM: Double = 55
        static let hrSpanBPM: Double = 70
        /// Points of breathing room before the first / after the last dose, kept
        /// constant on screen regardless of zoom (converted to hours per frame).
        static let endPad: CGFloat = 16
    }

    private var range: MechanisticSessionModel.AxisRange {
        axisOverride ?? result.ranges[lens.rawValue] ?? .init(hi: 1, lo: 0)
    }

    /// Scrollable extent — the real content span, not the padded simulation
    /// extent. So a short session's window shows everything and no scroller
    /// appears.
    private var span: Double {
        result.contentSpan
    }

    /// Left edge of the scrollable extent: the first dose, not the session's
    /// hour 0. A session whose start predates its earliest surviving dose
    /// (e.g. after a dose edit/delete) would otherwise open on hours of
    /// flat nothing before the first curve rises.
    private var contentStart: Double {
        min(max(0, doseMarks.map(\.hours).min() ?? 0), span)
    }

    /// The visible-content length the window/zoom/scroller frame.
    private var contentLength: Double {
        max(Metric.minWindow, span - contentStart)
    }

    /// A non-interactive chart has no gestures, so it has no window to remember:
    /// it always frames its whole content, derived fresh from the current result
    /// rather than from `@State` seeded once on first layout. Seeded state was
    /// wrong here — a grid cell's window kept the default 5.5 h and silently
    /// cropped curves that ran longer.
    private var visibleWindow: (start: Double, width: Double) {
        guard interactive else { return (clampStart(contentStart - edgePad), contentLength) }
        return (winStart, winW)
    }

    var body: some View {
        chartCanvas
            .contentShape(.rect)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                chartWidth = width
                // Seed from the *measured* width (edgePad depends on it) — the
                // first geometry pass runs before the first frame, unlike
                // `onAppear`, whose ordering against it isn't guaranteed.
                if !seeded {
                    seeded = true
                    seedWindow()
                }
            }
            // Pinch-zoom (two-finger) never fights the List's one-finger scroll, so
            // it stays live whenever interactive. Pan (one-finger drag) would trap a
            // vertical scroll, so it only arms once zoomed in — a framed overview card
            // scrolls freely until you pinch into it, then pans within the zoom.
            .gesture(panGesture, including: interactive && isZoomedIn ? .all : .none)
            .simultaneousGesture(zoomGesture, including: interactive ? .all : .none)
            // A raw Canvas is invisible to VoiceOver — expose the lens plus its
            // sampled now-state and the curve's peak as one element.
            .accessibilityElement()
            .accessibilityLabel(Text(lens.label))
            .accessibilityValue(accessibilitySummary)
    }

    /// "Now Good; peaked Euphoric 45 min after the first dose" — the whole
    /// curve's shape in one sentence, since VoiceOver can't scrub the Canvas.
    private var accessibilitySummary: Text {
        let now = Text(lens.readout(nowValue))
        guard let peak = peakPoint else { return now }
        let offset = DosePK.shortDuration(minutes: max(0, peak.hour - contentStart) * 60)
        if peak.hour > min(nowHours, span) + 0.05 {
            return Text("Now \(now); expected to peak \(Text(lens.readout(peak.value))) about \(offset) after the first dose")
        }
        return Text("Now \(now); peaked \(Text(lens.readout(peak.value))) about \(offset) after the first dose")
    }

    /// The lens channel's maximum and when it occurs, from the modeled timeline.
    private var peakPoint: (value: Double, hour: Double)? {
        guard let channel = lens.channel else { return nil }
        let series = result.timeline[keyPath: channel]
        let t = result.timeline.t
        guard series.count == t.count,
              let maxIndex = series.indices.max(by: { series[$0] < series[$1] })
        else { return nil }
        return (series[maxIndex], t[maxIndex])
    }

    /// Whether the window is tighter than the full content — pan is only useful
    /// (and only armed) here, and the bottom pan indicator shows.
    private var isZoomedIn: Bool {
        winW < contentLength - 0.01
    }

    private var nowValue: Double {
        result.value(of: lens, atHour: min(nowHours, span))
    }
    private var nowIsCrash: Bool {
        lens.isSigned && nowValue < 0
    }

    // MARK: Main chart

    private var chartCanvas: some View {
        Canvas { context, size in
            let geo = geometry(for: size, top: Metric.top, bottom: Metric.labelBand)
            drawGrid(&context, geo)
            drawElapsedLabels(&context, geo)
            drawCurve(&context, geo)
            if lens.pairsVitals { drawHeartRate(&context, geo) }
            drawDoseTicks(&context, geo)
            drawNow(&context, geo)
            drawPanIndicator(&context, size)
        }
    }

    /// A 2pt track at the very bottom showing the visible window within the
    /// scrollable content (first dose → content end) — the same non-interactive
    /// indicator as the classic timeline (you pan by dragging the chart). Only
    /// when there's something to scroll to.
    private func drawPanIndicator(_ context: inout GraphicsContext, _ size: CGSize) {
        let window = visibleWindow
        guard window.width < contentLength - 0.01 else { return }
        let y = size.height - 1.5
        let trackX = Metric.edge
        let trackW = max(1, size.width - Metric.edge * 2)
        var track = Path()
        track.move(to: CGPoint(x: trackX, y: y))
        track.addLine(to: CGPoint(x: trackX + trackW, y: y))
        context.stroke(track, with: .color(.secondary.opacity(0.18)), lineWidth: 2)
        let start = trackX + CGFloat(max(0, window.start - contentStart) / contentLength) * trackW
        let end = trackX + CGFloat(min(contentLength, window.start + window.width - contentStart) / contentLength) * trackW
        var seg = Path()
        seg.move(to: CGPoint(x: start, y: y))
        seg.addLine(to: CGPoint(x: max(start, end), y: y))
        context.stroke(seg, with: .color(.secondary.opacity(0.55)), lineWidth: 2)
    }

    // MARK: - Drawing geometry

    private struct Geometry {
        let rect: CGRect
        let winStart: Double
        let winW: Double
        let range: MechanisticSessionModel.AxisRange
        let signed: Bool

        func x(_ hour: Double) -> CGFloat {
            rect.minX + CGFloat((hour - winStart) / winW) * rect.width
        }
        func y(_ value: Double) -> CGFloat {
            rect.minY + CGFloat((range.hi - value) / range.span) * rect.height
        }
        var zeroY: CGFloat {
            signed ? y(0) : rect.maxY
        }
    }

    private func geometry(for size: CGSize, top: CGFloat, bottom: CGFloat) -> Geometry {
        // Only the left/right edges are inset; curves fill the card vertically.
        let rect = CGRect(
            x: Metric.edge, y: top,
            width: max(1, size.width - Metric.edge * 2),
            height: max(1, size.height - top - bottom),
        )
        let window = visibleWindow
        return Geometry(rect: rect, winStart: window.start, winW: window.width, range: range, signed: lens.isSigned)
    }

    private func indexRange(_ geo: Geometry) -> (Int, Int) {
        let t = result.timeline.t
        guard !t.isEmpty else { return (0, 0) }
        let a = geo.winStart, b = geo.winStart + geo.winW
        var i0 = 0, i1 = t.count - 1
        for (i, tt) in t.enumerated() {
            if tt <= a { i0 = i }
            if tt <= b { i1 = i }
        }
        return (i0, min(i1 + 1, t.count - 1))
    }

    // MARK: - Drawing

    private func drawGrid(_ context: inout GraphicsContext, _ geo: Geometry) {
        let a = geo.winStart, b = geo.winStart + geo.winW
        let step: Double = geo.winW > 8 ? 4 : geo.winW > 4 ? 2 : 1
        var hour = (a / step).rounded(.up) * step
        while hour <= b {
            let x = geo.x(hour)
            // Hour lines are dotted; substance lines (drawn later) are solid.
            var line = Path()
            line.move(to: CGPoint(x: x, y: geo.rect.minY))
            line.addLine(to: CGPoint(x: x, y: geo.rect.maxY))
            context.stroke(line, with: .color(.primary.opacity(0.22)), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
            // Skip labels whose text would spill past the content margin into
            // the card's corner zone and get sliced. Grid line and ticks still draw.
            if showsClockAxis, x >= geo.rect.minX + 8, x <= geo.rect.maxX - 8 {
                var label = context.resolve(Text(clockShort(hour)).font(.system(size: 10)))
                label.shading = .color(.secondary)
                context.draw(label, at: CGPoint(x: x, y: geo.rect.maxY + 10))
            }
            // Two small ticks between this hour and the next labeled one.
            for frac in [1.0 / 3.0, 2.0 / 3.0] {
                let tx = geo.x(hour + step * frac)
                guard tx >= geo.rect.minX, tx <= geo.rect.maxX else { continue }
                var tick = Path()
                tick.move(to: CGPoint(x: tx, y: geo.rect.maxY))
                tick.addLine(to: CGPoint(x: tx, y: geo.rect.maxY - 4))
                context.stroke(tick, with: .color(.secondary.opacity(0.4)), lineWidth: 1)
            }
            hour += step
        }
        if geo.signed {
            var zero = Path()
            zero.move(to: CGPoint(x: geo.rect.minX, y: geo.zeroY))
            zero.addLine(to: CGPoint(x: geo.rect.maxX, y: geo.zeroY))
            context.stroke(zero, with: .color(.secondary.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            // Name the zero line once, so "below the baseline = comedown/sedation"
            // is legible from the chart itself and not only the caption. Sits just
            // above the line at the far left, left-anchored so it never centers on
            // top of the first dose dot (which rides the same line). The reserved
            // comedown room below the line is what makes it read as *horizontal*.
            var base = context.resolve(Text("baseline").font(.system(size: 8, weight: .medium)))
            base.shading = .color(.secondary.opacity(0.6))
            context.draw(base, at: CGPoint(x: geo.rect.minX + 2, y: geo.zeroY - 7), anchor: .leading)
        }
    }

    /// Elapsed-hours labels ("0h · 4h · 8h" since the first dose) along the very
    /// top, mirroring the classic timeline's top scale. Drawn at the top band, well
    /// clear of the mid-baseline dose dots, so a busy session still keeps its scale.
    private func drawElapsedLabels(_ context: inout GraphicsContext, _ geo: Geometry) {
        let step: Double = geo.winW > 8 ? 4 : geo.winW > 4 ? 2 : 1
        var elapsed = 0.0
        while contentStart + elapsed <= span {
            let x = geo.x(contentStart + elapsed)
            defer { elapsed += step }
            guard x >= geo.rect.minX + 8, x <= geo.rect.maxX - 8 else { continue }
            var label = context.resolve(
                Text(verbatim: String(localized: "\(Int(elapsed))h"))
                    .font(.system(size: 9, weight: .medium, design: .rounded)),
            )
            label.shading = .color(.secondary.opacity(0.55))
            context.draw(label, at: CGPoint(x: x, y: 8))
        }
    }

    private func drawCurve(_ context: inout GraphicsContext, _ geo: Geometry) {
        guard let channel = lens.channel else { return }
        guard comparison.isEmpty else {
            for plan in comparison {
                drawComparisonCurve(&context, geo, timeline: plan.timeline, channel: channel, color: plan.color)
            }
            return
        }
        let series = result.timeline[keyPath: channel]
        let t = result.timeline.t
        let (i0, i1) = indexRange(geo)
        guard i1 > i0, series.count == t.count else { return }

        var posArea = Path()
        posArea.move(to: CGPoint(x: geo.x(t[i0]), y: geo.zeroY))
        for i in i0 ... i1 {
            posArea.addLine(to: CGPoint(x: geo.x(t[i]), y: geo.y(max(series[i], 0))))
        }
        posArea.addLine(to: CGPoint(x: geo.x(t[i1]), y: geo.zeroY))
        posArea.closeSubpath()
        context.fill(posArea, with: .linearGradient(
            Gradient(colors: [lens.color.opacity(0.34), lens.color.opacity(0.05)]),
            startPoint: CGPoint(x: 0, y: geo.rect.minY),
            endPoint: CGPoint(x: 0, y: geo.zeroY),
        ))

        if geo.signed {
            var negArea = Path()
            negArea.move(to: CGPoint(x: geo.x(t[i0]), y: geo.zeroY))
            for i in i0 ... i1 {
                negArea.addLine(to: CGPoint(x: geo.x(t[i]), y: geo.y(min(series[i], 0))))
            }
            negArea.addLine(to: CGPoint(x: geo.x(t[i1]), y: geo.zeroY))
            negArea.closeSubpath()
            context.fill(negArea, with: .color(EffectLens.crash.opacity(0.2)))
        }

        for i in i0 ..< i1 {
            let v0 = series[i], v1 = series[i + 1]
            var seg = Path()
            seg.move(to: CGPoint(x: geo.x(t[i]), y: geo.y(v0)))
            seg.addLine(to: CGPoint(x: geo.x(t[i + 1]), y: geo.y(v1)))
            let crashing = geo.signed && (v0 < 0 || v1 < 0)
            context.stroke(seg, with: .color(crashing ? EffectLens.crash : lens.color), style: StrokeStyle(lineWidth: 2.6, lineJoin: .round))
        }
    }

    /// One plan's line: a plain stroke in the plan's color. No fill and no crash
    /// red — overlapping translucent fills blend into a third color that reads as
    /// a third plan, and a value-based recolor would break the color↔plan tie.
    private func drawComparisonCurve(
        _ context: inout GraphicsContext,
        _ geo: Geometry,
        timeline: EffectTimeline,
        channel: KeyPath<EffectTimeline, [Double]>,
        color: Color,
    ) {
        let series = timeline[keyPath: channel]
        let t = timeline.t
        guard series.count == t.count, t.count > 1 else { return }
        let i0 = 0, i1 = t.count - 1

        var path = Path()
        for i in i0 ... i1 {
            let point = CGPoint(x: geo.x(t[i]), y: geo.y(series[i]))
            if i == i0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2.4, lineJoin: .round))
    }

    private func drawHeartRate(_ context: inout GraphicsContext, _ geo: Geometry) {
        guard let samples = vitals?.heartRate, samples.count > 1 else { return }
        let a = geo.winStart, b = geo.winStart + geo.winW
        var path = Path()
        var started = false
        for sample in samples {
            let hour = sample.date.timeIntervalSince(startDate) / 3_600
            guard hour >= a - 0.5, hour <= b + 0.5 else { continue }
            let norm = (Double(sample.bpm) - Metric.hrFloorBPM) / Metric.hrSpanBPM
            let y = geo.rect.maxY - CGFloat(min(max(norm, 0), 1)) * geo.rect.height
            let point = CGPoint(x: geo.x(hour), y: y)
            if started { path.addLine(to: point) } else { path.move(to: point); started = true }
        }
        // The app-wide HR crimson (matches the row chips and the timeline cardio
        // lane), dashed so it can't be read as part of the solid danger curve —
        // the Safety lens color is a near-identical red.
        context.stroke(path, with: .color(VitalsPalette.heart), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round, dash: [4, 3]))
    }

    private func drawDoseTicks(_ context: inout GraphicsContext, _ geo: Geometry) {
        let a = geo.winStart, b = geo.winStart + geo.winW
        for mark in doseMarks where mark.hours >= a - 0.1 && mark.hours <= b + 0.1 {
            let x = geo.x(mark.hours)
            let color = Color(hex: mark.colorHex)
            // A faint full-height guide (so a dose lines up across the stacked
            // charts) with the marker dot sitting ON the neutral baseline — "a dose
            // happened at this time", not a value spiking to the top. On signed
            // lenses the baseline floats above the chart floor (comedown room
            // reserved below), so the dot rides the zero line, not the bottom edge.
            var line = Path()
            line.move(to: CGPoint(x: x, y: geo.rect.minY))
            line.addLine(to: CGPoint(x: x, y: geo.rect.maxY))
            context.stroke(line, with: .color(color.opacity(0.28)), style: StrokeStyle(lineWidth: 1.5, dash: [2, 3]))
            let r = Metric.doseDot / 2
            let dot = Path(ellipseIn: CGRect(x: x - r, y: geo.zeroY - r, width: Metric.doseDot, height: Metric.doseDot))
            context.fill(dot, with: .color(color))
        }
    }

    private func drawNow(_ context: inout GraphicsContext, _ geo: Geometry) {
        let now = min(nowHours, span)
        guard now >= geo.winStart, now <= geo.winStart + geo.winW else { return }
        let x = geo.x(now)
        var line = Path()
        line.move(to: CGPoint(x: x, y: geo.rect.minY - 2))
        line.addLine(to: CGPoint(x: x, y: geo.rect.maxY))
        let color = nowIsCrash ? EffectLens.crash : lens.color
        context.stroke(line, with: .color(color), lineWidth: 1.5)
        let y = geo.y(nowValue)
        context.fill(Path(ellipseIn: CGRect(x: x - 4.5, y: y - 4.5, width: 9, height: 9)), with: .color(color))
        context.fill(Path(ellipseIn: CGRect(x: x - 2, y: y - 2, width: 4, height: 4)), with: .color(.white))
        drawNowReadout(&context, geo, at: CGPoint(x: x, y: y), color: color)
    }

    /// The current-state word ("Good", "Wired", "Low", …) pinned to the now-dot —
    /// the glanceable readout, tied to the exact height it describes rather than
    /// floating in the section header. Only for a still-unfolding session, where
    /// "now" is meaningful (a finished session reads its whole shape instead).
    /// Sits beside the now-line (never centered on it, or the full-height stroke
    /// would bisect the word) and above the dot, flipping to the left when the dot
    /// is near the right edge.
    private func drawNowReadout(_ context: inout GraphicsContext, _ geo: Geometry, at dot: CGPoint, color: Color) {
        guard nowHours < span - 0.05 else { return }
        let word = lens.readout(nowValue)
        guard word != "" else { return }
        var text = context.resolve(Text(word).font(.system(size: 11, weight: .semibold, design: .rounded)))
        text.shading = .color(color)
        let size = text.measure(in: geo.rect.size)
        let gap: CGFloat = 7
        // Right of the line by default; flip left if the label would spill past
        // the content margin.
        let toRight = dot.x + gap + size.width <= geo.rect.maxX - 2
        let anchor: UnitPoint = toRight ? .leading : .trailing
        let tx = toRight ? dot.x + gap : dot.x - gap
        // Above the dot, clamped so a dot near the top/bottom keeps the word in-frame.
        let ty = min(
            max(dot.y - size.height / 2 - 6, geo.rect.minY + size.height / 2),
            geo.rect.maxY - size.height / 2,
        )
        context.draw(text, at: CGPoint(x: tx, y: ty), anchor: anchor)
    }

    // MARK: - Gestures

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                // A two-finger pinch also moves its centroid, so the drag
                // recognizes alongside the magnification — let the zoom own
                // `winStart` for the duration of the pinch or the two fight
                // over it frame by frame.
                guard zoomAnchor == nil else { return }
                let base = panAnchor ?? winStart
                if panAnchor == nil { panAnchor = base }
                winStart = clampStart(base - Double(value.translation.width / max(1, chartWidth)) * winW)
            }
            .onEnded { _ in panAnchor = nil }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let anchor = zoomAnchor ?? (winW, winStart)
                if zoomAnchor == nil {
                    zoomAnchor = anchor
                    // Drop any in-flight pan anchor so a drag that outlives the
                    // pinch re-anchors at the post-zoom window instead of
                    // jumping back to its pre-pinch capture.
                    panAnchor = nil
                }
                let pivot = anchor.start + anchor.win / 2
                let newW = min(contentLength, max(Metric.minWindow, anchor.win / value.magnification))
                winW = newW
                winStart = clampStart(pivot - newW / 2)
            }
            .onEnded { _ in zoomAnchor = nil }
    }

    /// Small over-scroll so the session's start/end aren't flush against the
    /// edge — the graph's "safe area". A fixed ~16pt on screen, expressed in
    /// hours for the current zoom so it stays visually constant.
    private var edgePad: Double {
        Double(Metric.endPad / max(1, chartWidth)) * winW
    }

    private func clampStart(_ value: Double) -> Double {
        let lo = contentStart - edgePad
        let hi = max(lo, span - winW + edgePad)
        return min(max(value, lo), hi)
    }

    private func seedWindow() {
        // Overview cards frame the whole session at once so the whole curve is
        // visible. When interactive, pinch-zoom can still tighten the window from
        // here; when not, it stays a static full-span overview.
        if !interactive || startFramed {
            winW = contentLength
            winStart = clampStart(contentStart - edgePad)
            return
        }
        // A little wider than before — the earlier default sat too zoomed in.
        winW = min(7.5, contentLength)
        if nowHours < span {
            // Active session (effects still unfolding): put "now" a third of the
            // way in, so the recent past and the near future are both visible.
            winStart = clampStart(nowHours - winW / 3)
        } else {
            // Past session: frame from just before the first dose so the action is
            // on screen instead of the flat tail.
            winStart = clampStart(contentStart - edgePad)
        }
    }

    // MARK: - Time formatting

    private func clockShort(_ hour: Double) -> String {
        Self.hourFormatter.string(from: startDate.addingTimeInterval(hour * 3_600))
    }

    private static let hourFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("j")
        return f
    }()
}
