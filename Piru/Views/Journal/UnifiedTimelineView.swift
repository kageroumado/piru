import SwiftData
import SwiftUI

/// A vertically scrollable timeline of all dose entries — one **continuous
/// strip of time** running upward: the newest moment is at the top and every
/// scroll downward goes further into the past, through day boundaries without
/// a seam. A day tag sits in the label gutter at the top of each slice as a
/// marker; the curves and the axis flow straight past it.
///
/// The scale is uniform (points per minute, adjustable by zoom); only
/// doseless stretches are compressed, capped so an empty night costs a
/// bounded strip — and the compression is visible as hour ticks bunching
/// together, not as a symbol. Compression can be turned off entirely for a
/// stable 1:1 scale.
///
/// The strip shows absolute time labels on the left (hour ruler + per-dose
/// times), a per-substance PK spine, and dose cards connected to their true
/// position on the axis. Doses belonging to one ``Session`` are wrapped in a
/// tappable envelope that opens the session detail — the timeline → session
/// → dose hierarchy.
struct UnifiedTimelineView: View {
    @Query(sort: \DoseEntry.timestamp, order: .reverse) private var entries: [DoseEntry]
    @Query private var substanceColors: [SubstanceColor]
    @State private var model = UnifiedTimelineModel()
    @State private var showingCalendar = false
    @GestureState private var pinchScale: CGFloat = 1
    @AppStorage("timelineZoom", store: UserDefaults(suiteName: "group.dev.yumeji.piru")) private var zoom = 1.0
    @AppStorage("timelineCompression", store: UserDefaults(suiteName: "group.dev.yumeji.piru")) private var compressGaps = true
    @AppStorage("timelinePKCurves", store: UserDefaults(suiteName: "group.dev.yumeji.piru")) private var pkCurves = false
    @AppStorage("timelineStrengthScaling", store: UserDefaults(suiteName: "group.dev.yumeji.piru")) private var strengthScaling = true
    @AppStorage("timelineShowsAxis", store: UserDefaults(suiteName: "group.dev.yumeji.piru")) private var showsAxis = true
    @AppStorage("timelineBubbleStyle", store: UserDefaults(suiteName: "group.dev.yumeji.piru")) private var bubbleStyle = TimelineBubbleStyle.full
    @Environment(\.appNavigator) private var navigator

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if entries.isEmpty {
                        emptyState
                    } else if model.days.isEmpty {
                        ProgressView()
                            .padding(.top, 80)
                    } else {
                        ForEach(model.days) { day in
                            TimelineDayContent(
                                day: day,
                                onEntryTap: { entry in
                                    // A lone dose draws no session envelope, so its
                                    // bubble is the only way into the session — notes,
                                    // check-ins and splitting live there, and the entry
                                    // stays one tap further in.
                                    if let session = entry.session, session.doses?.count == 1 {
                                        navigator.push(.session(id: session.id))
                                    } else {
                                        navigator.push(.entry(timestamp: entry.timestamp, id: entry.id))
                                    }
                                },
                                onSessionTap: { sessionID in
                                    navigator.push(.session(id: sessionID))
                                },
                            )
                            .id(day.date)
                        }
                    }
                }
                .padding(.bottom, 40)
                .scaleEffect(x: 1, y: pinchScale, anchor: .top)
            }
            .background(Theme.background)
            .simultaneousGesture(magnification)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    TimelineOptionsMenu(
                        zoom: $zoom,
                        compressGaps: $compressGaps,
                        pkCurves: $pkCurves,
                        strengthScaling: $strengthScaling,
                        showsAxis: $showsAxis,
                        bubbleStyle: $bubbleStyle,
                    ) {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingCalendar = true
                    } label: {
                        Image(systemName: "calendar")
                    }
                    .accessibilityLabel(Text("Jump to Date"))
                }
            }
            .sheet(isPresented: $showingCalendar) {
                calendarSheet(proxy: proxy)
                    .presentationDetents([.medium])
                    .presentationBackground(.regularMaterial)
            }
            .task(id: rebuildKey) {
                await model.rebuild(
                    entries: entries,
                    colors: substanceColors,
                    colorMap: substanceColors.colorMap,
                    revision: DoseLogService.shared.revision,
                    zoom: zoom,
                    compressGaps: compressGaps,
                    pkCurves: pkCurves,
                    strengthScaling: strengthScaling,
                    showsAxis: showsAxis,
                    bubbleStyle: bubbleStyle,
                )
            }
        }
    }

    private var rebuildKey: String {
        "\(DoseLogService.shared.revision)|\(zoom)|\(compressGaps)|\(pkCurves)|\(strengthScaling)|\(showsAxis)|\(bubbleStyle.rawValue)"
    }

    /// Pinch on the graph: preview by stretching vertically while the fingers
    /// are down, then commit the factor into the real layout scale on release.
    private var magnification: some Gesture {
        MagnifyGesture()
            .updating($pinchScale) { value, state, _ in
                state = min(max(value.magnification, 0.7), 1.6)
            }
            .onEnded { value in
                zoom = min(max(zoom * value.magnification, TimelineZoom.range.lowerBound), TimelineZoom.range.upperBound)
            }
    }

    private func calendarSheet(proxy: ScrollViewProxy) -> some View {
        NavigationStack {
            JournalCalendarView(
                entries: entries,
                onSelectDate: { date in
                    showingCalendar = false
                    jump(to: date, proxy: proxy)
                },
            )
            .navigationTitle("Jump to Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { showingCalendar = false } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(Text("Close"))
                }
            }
        }
    }

    /// Scroll to the newest built day at or before the picked date (the list is
    /// newest-first), falling back to the oldest. Days build progressively, so
    /// give a still-running build a moment to finish before targeting.
    private func jump(to date: Date, proxy: ScrollViewProxy) {
        let target = Calendar.current.startOfDay(for: date)
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard let day = model.days.first(where: { $0.date <= target }) ?? model.days.last else { return }
            withAnimation {
                proxy.scrollTo(day.date, anchor: .top)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Entries Yet",
            systemImage: "clock",
            description: Text("Your dose timeline will appear here once you log something."),
        )
        .padding(.top, 60)
    }
}

// MARK: - Model

/// Owns the precomputed strip. All the expensive work — substance lookups, PK
/// curve sampling, remaining-fraction math, the global time map, geometry —
/// happens here once per (dose-log revision, zoom, compression), after the
/// store is warm, so day slices render from plain values and `body` stays
/// cheap while scrolling.
@MainActor @Observable
final class UnifiedTimelineModel {
    private(set) var days: [TimelineDayLayout] = []
    /// Key the current `days` were fully built from; partial (cancelled)
    /// builds never set it, so they are redone on next appearance.
    private var builtKey: String?

    func rebuild(
        entries: [DoseEntry],
        colors: [SubstanceColor],
        colorMap: [String: Color],
        revision: Int,
        zoom: Double,
        compressGaps: Bool,
        pkCurves: Bool,
        strengthScaling: Bool,
        showsAxis: Bool,
        bubbleStyle: TimelineBubbleStyle,
    ) async {
        let key = "\(revision)|\(zoom)|\(compressGaps)|\(pkCurves)|\(strengthScaling)|\(showsAxis)|\(bubbleStyle.rawValue)|\(entries.count)"
        if key == builtKey, !days.isEmpty { return }
        await SubstanceStore.shared.ensureAllLoaded()
        guard !Task.isCancelled else { return }

        guard var builder = TimelineStripBuilder(
            entries: entries,
            colors: colors,
            colorMap: colorMap,
            zoom: zoom,
            compressGaps: compressGaps,
            style: TimelineDayLayout.Style(
                showsAxis: showsAxis,
                bubbleStyle: bubbleStyle,
                pkMode: pkCurves,
                strengthScaling: strengthScaling,
            ),
        ) else {
            days = []
            builtKey = key
            return
        }

        // Progressive build: publish the most recent slices as soon as they
        // are ready (the visible top of the strip), then keep appending in
        // chunks, yielding between them so a multi-year log never blocks the
        // UI.
        var built: [TimelineDayLayout] = []
        built.reserveCapacity(builder.sliceCount)
        for index in 0 ..< builder.sliceCount {
            built.append(builder.layout(sliceAt: index))
            if index == 9 || (index > 9 && (index - 9).isMultiple(of: 30)) {
                days = built
                await Task.yield()
                guard !Task.isCancelled else { return }
            }
        }
        days = built
        builtKey = key
    }
}

// MARK: - Day header pill

/// The day marker at the top of each slice — a two-line tag (relative day or
/// weekday, then the date) floating at the slice's leading edge, across the
/// axis. Opaque, so the ruler and axis it covers stay covered at every zoom.
struct TimelineDayHeader: View {
    let date: Date
    let isToday: Bool
    /// A fixed width for the tag, or `nil` to hug its text.
    let width: CGFloat?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                if isToday {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 6, height: 6)
                }
                Text(primaryText)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(isToday ? .primary : Theme.secondaryLabel)
            }
            Text(date.formatted(.dateTime.month(.abbreviated).day()))
                .font(.system(size: 9.5, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.secondaryLabel.opacity(0.8))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .frame(width: width, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.background)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
                }
        }
        .accessibilityElement(children: .combine)
    }

    private var primaryText: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return String(localized: "Today") }
        if calendar.isDateInYesterday(date) { return String(localized: "Yesterday") }
        return date.formatted(.dateTime.weekday(.abbreviated))
    }
}

// MARK: - Day slice

/// One day slice of the strip. Axis on: the strip layout
/// (``TimelineStripDayContent``); axis off: the bubbles as a plain list
/// (``TimelineListDayContent``).
struct TimelineDayContent: View {
    let day: TimelineDayLayout
    let onEntryTap: (DoseEntry) -> Void
    let onSessionTap: (UUID) -> Void

    var body: some View {
        if day.style.showsAxis {
            TimelineStripDayContent(day: day, onEntryTap: onEntryTap, onSessionTap: onSessionTap)
        } else {
            TimelineListDayContent(day: day, onEntryTap: onEntryTap, onSessionTap: onSessionTap)
        }
    }
}

/// The strip layout of one day: a single full-width canvas (hour ruler,
/// axis, curves, connectors, Now) with the time capsules, dose dots and the
/// glass bubble column layered over it. The curves get the lane from the axis
/// to the bubbles' right edge and run under the bubbles — the eye reconstructs
/// the covered part — except with strength scaling off, when every curve
/// reaches full amplitude and the lane stops 8 pt short of the bubbles so the
/// peaks stay visible.
struct TimelineStripDayContent: View {
    let day: TimelineDayLayout
    let onEntryTap: (DoseEntry) -> Void
    let onSessionTap: (UUID) -> Void

    /// Horizontal inset of every bubble within its column, so a session
    /// envelope's edge stays visible around the bubbles it wraps.
    private static let bubbleInset: CGFloat = 8
    /// Clearance between a full-amplitude curve and the bubbles when the
    /// lane must stop short of them.
    private static let peakClearance: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let bubbleWidth = TimelineDoseBubble.width(for: day.style.bubbleStyle)
            let columnWidth = bubbleWidth + 2 * Self.bubbleInset
            let columnX = geo.size.width - TimelineGutter.edgeInset - columnWidth
            let bubbleLeft = columnX + Self.bubbleInset
            let bubbleRight = columnX + columnWidth - Self.bubbleInset

            ZStack(alignment: .topLeading) {
                strip(bubbleLeft: bubbleLeft, bubbleRight: bubbleRight)
                capsules
                doseDots
                bubbleColumn(width: columnWidth)
                    .offset(x: columnX)
            }
        }
        .frame(height: day.totalHeight)
        .overlay(alignment: .topLeading) {
            TimelineDayHeader(date: day.date, isToday: day.isToday, width: nil)
                .padding(.leading, TimelineGutter.edgeInset)
                .padding(.top, 4)
        }
    }

    // MARK: Gutter overlays

    private var capsules: some View {
        ForEach(day.cardGroups.filter(\.showsTimeLabel)) { group in
            TimelineTimeCapsule(date: group.representativeTime)
                .position(x: TimelineGutter.edgeInset + TimelineGutter.capsuleWidth / 2, y: group.centerY)
        }
    }

    /// Dose dots on the axis — the primary "something was taken here" mark,
    /// drawn above the capsules so a capsule hanging across the axis is
    /// pinned by its dot.
    private var doseDots: some View {
        ForEach(Array(day.doseDots.enumerated()), id: \.offset) { _, dot in
            Circle()
                .fill(dot.color)
                .frame(width: 8, height: 8)
                .padding(1.5)
                .background(Theme.background, in: Circle())
                .position(x: TimelineGutter.axisX, y: dot.y)
                .accessibilityHidden(true)
        }
    }

    // MARK: Bubble column

    private func bubbleColumn(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(day.envelopes) { envelope in
                SessionEnvelopeButton { onSessionTap(envelope.id) }
                    .frame(width: width, height: envelope.yEnd - envelope.yStart)
                    .offset(y: envelope.yStart)
            }

            GlassEffectContainer {
                ZStack(alignment: .topLeading) {
                    ForEach(day.cardGroups) { group in
                        VStack(spacing: TimelineDayLayout.cardSpacing) {
                            ForEach(group.items) { item in
                                TimelineDoseBubble(
                                    item: item,
                                    style: day.style.bubbleStyle,
                                    pkMode: day.style.pkMode,
                                ) { onEntryTap(item.entry) }
                            }
                        }
                        .padding(.horizontal, Self.bubbleInset)
                        .offset(y: group.topY)
                    }
                }
            }
        }
        .frame(width: width, alignment: .topLeading)
    }

    // MARK: The strip canvas

    /// Height of one canvas tile. A slice at high zoom with compression off
    /// runs many thousands of points tall, and one full-width canvas that
    /// tall exceeds what Core Animation rasterizes — it silently draws
    /// nothing. Each tile draws the whole slice translated to its origin, so
    /// the tiles join seamlessly.
    private static let tileHeight: CGFloat = 1024

    private func strip(bubbleLeft: CGFloat, bubbleRight: CGFloat) -> some View {
        let tileYs = Array(stride(from: CGFloat(0), to: max(day.totalHeight, 1), by: Self.tileHeight))
        return ForEach(tileYs, id: \.self) { tileY in
            Canvas { context, size in
                context.translateBy(x: 0, y: -tileY)
                drawStrip(
                    in: &context,
                    size: CGSize(width: size.width, height: day.totalHeight),
                    bubbleLeft: bubbleLeft,
                    bubbleRight: bubbleRight,
                )
            }
            .frame(height: min(Self.tileHeight, day.totalHeight - tileY))
            .offset(y: tileY)
        }
    }

    private func drawStrip(in context: inout GraphicsContext, size: CGSize, bubbleLeft: CGFloat, bubbleRight: CGFloat) {
        let mapHeight = day.mapHeight
        guard mapHeight > 0 else { return }

        let axisX = TimelineGutter.axisX
        let laneRight = day.style.strengthScaling ? bubbleRight : bubbleLeft - Self.peakClearance
        let curveWidth = max(0, laneRight - axisX)

        // Hour gridlines across the lane; in a compressed gap they bunch
        // together, which is what says "time is squeezed here".
        for tick in day.hourTicks {
            var line = Path()
            line.move(to: CGPoint(x: axisX, y: tick.y))
            line.addLine(to: CGPoint(x: size.width, y: tick.y))
            context.stroke(line, with: .color(Color.primary.opacity(0.06)), lineWidth: 0.5)
        }

        drawAxis(in: &context, size: size, axisX: axisX)

        // Per-substance curves — normalized to the substance's own
        // all-time peak so widths mean the same thing on every day and a
        // curve crosses day boundaries without a jump.
        for series in day.series {
            guard series.points.count > 1 else { continue }

            var fill = Path()
            fill.move(to: CGPoint(x: axisX, y: series.points[0].y))
            for p in series.points {
                fill.addLine(to: CGPoint(x: axisX + curveWidth * CGFloat(p.v), y: p.y))
            }
            fill.addLine(to: CGPoint(x: axisX, y: series.points[series.points.count - 1].y))
            fill.closeSubpath()
            context.fill(fill, with: .color(series.color.opacity(0.12)))

            var stroke = Path()
            for (i, p) in series.points.enumerated() {
                let pt = CGPoint(x: axisX + curveWidth * CGFloat(p.v), y: p.y)
                if i == 0 { stroke.move(to: pt) } else { stroke.addLine(to: pt) }
            }
            context.stroke(stroke, with: .color(series.color.opacity(0.75)), lineWidth: 1.5)
        }

        drawHourLabels(in: &context, size: size)

        // Connectors from each dose's position on the axis to its bubble.
        for connector in day.connectors {
            var path = Path()
            path.move(to: CGPoint(x: axisX, y: connector.fromY))
            path.addLine(to: CGPoint(x: bubbleLeft, y: connector.toY))
            context.stroke(path, with: .color(connector.color.opacity(0.35)), lineWidth: 1)
        }

        if let y = day.nowY {
            drawNow(in: &context, size: size, axisX: axisX, y: y)
        }

        // Only the strip's very top edge cuts curves mid-flight — fade
        // them into the background there. Day boundaries fade nothing;
        // the strip continues.
        if day.showsLiveEdge {
            let fadeHeight: CGFloat = 28
            context.fill(
                Path(CGRect(x: 0, y: 0, width: size.width, height: fadeHeight)),
                with: .linearGradient(
                    Gradient(colors: [Theme.background, Theme.background.opacity(0)]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: fadeHeight),
                ),
            )
        }
    }

    /// The time axis, running the full slice (bubbles can spill past the
    /// mapped span; the axis keeps going so the strip reads as unbroken). The
    /// newest slice carries an arrowhead at the top — the axis runs past "now"
    /// to where the active doses wind down, and the arrow says it keeps going
    /// up from there. Faint up-chevrons along it are the ambient reminder that
    /// time on this strip flows upward.
    private func drawAxis(in context: inout GraphicsContext, size: CGSize, axisX: CGFloat) {
        let axisTop: CGFloat = day.showsLiveEdge ? 16 : 0
        var axisLine = Path()
        axisLine.move(to: CGPoint(x: axisX, y: axisTop))
        axisLine.addLine(to: CGPoint(x: axisX, y: size.height))
        context.stroke(axisLine, with: .color(Color.primary.opacity(day.showsLiveEdge ? 0.22 : 0.12)), lineWidth: day.showsLiveEdge ? 1 : 0.7)
        if day.showsLiveEdge {
            var arrow = Path()
            arrow.move(to: CGPoint(x: axisX - 4.5, y: axisTop + 6))
            arrow.addLine(to: CGPoint(x: axisX, y: axisTop - 2))
            arrow.addLine(to: CGPoint(x: axisX + 4.5, y: axisTop + 6))
            context.stroke(arrow, with: .color(Color.primary.opacity(0.3)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }

        var chevronY = size.height - 60
        while chevronY > 40 {
            let clearOfDots = day.doseDots.allSatisfy { abs($0.y - chevronY) > 14 }
            let clearOfNow = day.nowY.map { abs($0 - chevronY) > 14 } ?? true
            if clearOfDots, clearOfNow {
                var chevron = Path()
                chevron.move(to: CGPoint(x: axisX - 3.5, y: chevronY + 3))
                chevron.addLine(to: CGPoint(x: axisX, y: chevronY - 2.5))
                chevron.addLine(to: CGPoint(x: axisX + 3.5, y: chevronY + 3))
                context.stroke(chevron, with: .color(Color.primary.opacity(0.16)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
            }
            chevronY -= 130
        }
    }

    /// Hour numerals (bare 24 h, tabular) and the sun/moon glyphs standing in
    /// for 06 and 18, each on a small background halo so the gridline and the
    /// curves under it stop at the digits.
    private func drawHourLabels(in context: inout GraphicsContext, size: CGSize) {
        let centerX = TimelineGutter.labelCenterX
        for tick in day.hourTicks {
            guard let label = tick.label, tick.y >= 0, tick.y <= size.height else { continue }
            switch label {
            case let .numeral(text):
                let resolved = context.resolve(
                    Text(verbatim: text)
                        .font(.system(size: 11, design: .rounded).monospacedDigit())
                        .foregroundStyle(Theme.secondaryLabel),
                )
                let measured = resolved.measure(in: CGSize(width: 60, height: 30))
                drawHalo(in: &context, center: CGPoint(x: centerX, y: tick.y), size: measured)
                context.draw(resolved, at: CGPoint(x: centerX, y: tick.y), anchor: .center)
            case let .symbol(name):
                var image = context.resolve(Image(systemName: name))
                image.shading = .style(.quaternary)
                let side: CGFloat = 12
                drawHalo(in: &context, center: CGPoint(x: centerX, y: tick.y), size: CGSize(width: side, height: side))
                context.draw(image, in: CGRect(x: centerX - side / 2, y: tick.y - side / 2, width: side, height: side))
            }
        }
    }

    private func drawNow(in context: inout GraphicsContext, size: CGSize, axisX: CGFloat, y: CGFloat) {
        var nowLine = Path()
        nowLine.move(to: CGPoint(x: axisX, y: y))
        nowLine.addLine(to: CGPoint(x: size.width, y: y))
        context.stroke(nowLine, with: .color(Theme.accent.opacity(0.65)), lineWidth: 2.5)
        context.fill(
            Path(ellipseIn: CGRect(x: axisX - 3.5, y: y - 3.5, width: 7, height: 7)),
            with: .color(Theme.accent),
        )
        let resolved = context.resolve(
            Text("Now")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.accent),
        )
        let center = CGPoint(x: TimelineGutter.labelCenterX, y: y)
        drawHalo(in: &context, center: center, size: resolved.measure(in: CGSize(width: 60, height: 30)))
        context.draw(resolved, at: center, anchor: .center)
    }

    private func drawHalo(in context: inout GraphicsContext, center: CGPoint, size: CGSize) {
        let rect = CGRect(
            x: center.x - size.width / 2 - 2,
            y: center.y - size.height / 2 - 1,
            width: size.width + 4,
            height: size.height + 2,
        )
        context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(Theme.background))
    }
}

// MARK: - Session envelope

/// The tappable frame around a session's bubbles — an outline (the bubbles
/// carry their own glass) with a "Session ›" footer that opens the session.
struct SessionEnvelopeButton: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.02))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
                .overlay(alignment: .bottomTrailing) {
                    // Chevron styled and inset identically to the bubbles'
                    // (bubble inset 8 + bubble padding 10), so the two columns
                    // of chevrons align.
                    HStack(spacing: 8) {
                        Text("Session")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.secondaryLabel)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .padding(.trailing, 18)
                    .padding(.bottom, 6)
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Slice layout

/// One day slice of the continuous strip, all in points. Within the slice —
/// as across the whole strip — larger y = earlier. `mapHeight` is the slice's
/// share of the global time map; `totalHeight` can exceed it when displaced
/// cards spill past the mapped span.
struct TimelineDayLayout: Identifiable {
    let date: Date
    let isToday: Bool
    let style: Style
    /// The strip's newest slice: carries the axis arrowhead, the top fade,
    /// and (usually) the "Now" line.
    let showsLiveEdge: Bool
    let cardGroups: [CardGroup]
    let envelopes: [SessionEnvelope]
    let series: [CurveSeries]
    let doseDots: [DoseDot]
    let connectors: [Connector]
    let hourTicks: [HourTick]
    let nowY: CGFloat?
    let mapHeight: CGFloat
    let totalHeight: CGFloat

    var id: Date {
        date
    }

    /// The display options the slice was laid out for.
    struct Style: Equatable {
        /// Off: no strip, ruler or curves — the bubbles stack as a list.
        let showsAxis: Bool
        let bubbleStyle: TimelineBubbleStyle
        /// Body-load mode: half-life PK decay instead of effect curves, and
        /// elimination percentages on the bubbles.
        let pkMode: Bool
        /// Weight each dose's curve by its strength (effect intensity, or
        /// amount in PK mode). Off, every dose draws at unit weight — a medium
        /// dose gets the full lane instead of a sliver of it.
        let strengthScaling: Bool
    }

    static let cardSpacing: CGFloat = 4
    static let groupGap: CGFloat = 14
    static let envelopePad: CGFloat = 6
    static let envelopeFooterHeight: CGFloat = 22
    /// Base vertical resolution at zoom 1 — uniform across the whole strip.
    static let basePointsPerMinute: CGFloat = 1.4

    struct CardGroup: Identifiable {
        let id: PersistentIdentifier
        /// Newest first — matching the axis direction.
        let items: [CardItem]
        let representativeTime: Date
        let sessionID: UUID?
        /// Each bubble's height, per the bubble style.
        let cardHeight: CGFloat
        /// Resolved top of the card stack (after collision push-down).
        var topY: CGFloat = 0
        var inSession = false
        /// `false` when the group's time capsule would overprint the "Now"
        /// tag in the gutter — Now wins (``TimelineGutterLabels``).
        var showsTimeLabel = true

        var height: CGFloat {
            CGFloat(items.count) * cardHeight
                + CGFloat(items.count - 1) * TimelineDayLayout.cardSpacing
        }

        var centerY: CGFloat {
            topY + height / 2
        }
        var bottomY: CGFloat {
            topY + height
        }
    }

    struct CardItem: Identifiable {
        let entry: DoseEntry
        let color: Color
        let remainingFraction: Double?
        /// The dose's acute-effect state while its effects are still running
        /// at build time — the bubble's phase progress reads from it. `nil`
        /// for ended doses and doses without duration data.
        let state: ActiveSubstanceState?

        var id: PersistentIdentifier {
            entry.persistentModelID
        }
    }

    struct SessionEnvelope: Identifiable {
        let id: UUID
        let yStart: CGFloat
        let yEnd: CGFloat
    }

    /// One substance's effect curve as (y, 0…1) points, y ascending (newest
    /// first), normalized to the substance's own all-time effect peak so day
    /// slices join seamlessly.
    struct CurveSeries {
        let color: Color
        let points: [(y: CGFloat, v: Double)]
    }

    struct DoseDot {
        let y: CGFloat
        let color: Color
    }

    /// A thin line from a dose's true position on the time axis to the
    /// vertical center of its card — the card can sit away from its moment
    /// when several land in one stretch, and with many entries in one hour
    /// the connectors are what say which dot belongs to which card.
    struct Connector {
        let fromY: CGFloat
        let toY: CGFloat
        let color: Color
    }

    struct HourTick {
        let y: CGFloat
        /// `nil` when the gridline stands alone — its label would collide
        /// with a dose capsule, the "Now" tag, or a neighboring hour label.
        let label: Label?

        enum Label {
            /// The bare two-digit 24 h hour.
            case numeral(String)
            /// An SF Symbol standing in for the hour: `sun.max` at 06,
            /// `moon` at 18.
            case symbol(String)
        }
    }
}

// MARK: - Strip builder

/// Builds the global time map once, then lays out day slices on demand
/// (newest first) so the model can publish them progressively.
@MainActor
struct TimelineStripBuilder {
    private let colorMap: [String: Color]
    private let remainingFractions: [PersistentIdentifier: Double]
    private let style: TimelineDayLayout.Style
    private var pkCurves: Bool {
        style.pkMode
    }

    private var strengthScaling: Bool {
        style.strengthScaling
    }

    /// Effect states per substance (lowercased canonical name) — the same
    /// acute-effect curves every other timeline surface draws. Doses without
    /// duration data have no state and appear as dots/cards only, exactly as
    /// they render as markers elsewhere.
    private let statesBySubstance: [String: [ActiveSubstanceState]]
    /// Raw entries per substance (lowercased name, ascending) — the PK mode's
    /// input.
    private let entriesBySubstance: [String: [DoseEntry]]

    /// Per-day slices, newest first: the day, its groups (newest first), and
    /// its time range [bottomTime, topTime) on the strip.
    private let slices: [(date: Date, isToday: Bool, topTime: Date, bottomTime: Date, groups: [TimelineDayLayout.CardGroup])]
    /// Global forward map: ascending times with cumulative heights.
    private let mapTimes: [Date]
    private let mapYs: [CGFloat]
    private let stripHeight: CGFloat
    private let now = Date.now

    /// Per-substance all-time peak (effect intensity or PK concentration,
    /// depending on mode) — the normalization scale that keeps a substance's
    /// curve continuous across slice boundaries.
    private var peakCache: [String: Double] = [:]
    /// PK mode: per-substance resolved rate constants, cached across slices.
    private var pkConstantsCache: [String: (halfLife: Double, ke: Double, ka: Double)?] = [:]

    var sliceCount: Int {
        slices.count
    }

    init?(entries: [DoseEntry], colors: [SubstanceColor], colorMap: [String: Color], zoom: Double, compressGaps: Bool, style: TimelineDayLayout.Style) {
        guard !entries.isEmpty else { return nil }
        self.colorMap = colorMap
        self.style = style
        remainingFractions = Self.computeRemainingFractions(entries: entries)

        // One state per dose that resolves duration data — the curves' input
        // and, per entry, the bubble's phase progress.
        let hexMap = colors.hexColorMap
        var states: [ActiveSubstanceState] = []
        var statesByEntry: [PersistentIdentifier: ActiveSubstanceState] = [:]
        for entry in entries {
            let hex = SubstancePalette.hex(for: entry.substance, hexMap: hexMap)
            guard let state = ActiveSubstanceState.from(entry: entry, colorHex: hex) else { continue }
            states.append(state)
            statesByEntry[entry.persistentModelID] = state
        }
        statesBySubstance = Dictionary(grouping: states) { $0.substanceName.lowercased() }
        var bySubstance = Dictionary(grouping: entries) { $0.substance.lowercased() }
        for k in bySubstance.keys {
            bySubstance[k]?.sort { $0.timestamp < $1.timestamp }
        }
        entriesBySubstance = bySubstance

        let calendar = Calendar.current
        let byDay = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.timestamp) }
        let dayDates = byDay.keys.sorted(by: >)
        guard let oldestDay = dayDates.last else { return nil }

        // Strip bounds: from just before the oldest dose up past "now" to
        // where the longest still-running curve ends plus a margin, capped at
        // a day so a multi-day half-life can't make the future a screen-tall
        // empty run. The curve mode decides what "running" means: effect
        // windows, or six half-lives in body-load mode.
        let globalStart = byDay[oldestDay]!.map(\.timestamp).min()!.addingTimeInterval(-5 * 60)
        let currentTime = now
        let modeledEnds: [Date] = style.pkMode
            ? Self.pkActivityEnds(entries: entries)
            : states.map { $0.doseTimestamp.addingTimeInterval($0.totalMinutes * 60) }
        let curvesEnd = modeledEnds.filter { $0 > currentTime }.max()
        let globalEnd = max(
            currentTime.addingTimeInterval(Self.minimumFutureSeconds),
            min(
                (curvesEnd ?? .distantPast).addingTimeInterval(Self.futureMarginSeconds),
                currentTime.addingTimeInterval(Self.maximumFutureSeconds),
            ),
        )

        // Slices, newest first. A slice runs from its day's start up to the
        // next newer dosed day's start (absorbing any empty days between), and
        // the newest slice runs to the strip's live edge.
        var sliceInfos: [(date: Date, isToday: Bool, topTime: Date, bottomTime: Date, groups: [TimelineDayLayout.CardGroup])] = []
        let cardHeight = TimelineDoseBubble.height(for: style.bubbleStyle)
        for (index, day) in dayDates.enumerated() {
            let topTime = index == 0 ? globalEnd : calendar.startOfDay(for: dayDates[index - 1])
            let bottomTime = index == dayDates.count - 1 ? globalStart : day
            let groups = Self.makeGroups(
                dayEntries: byDay[day]!,
                colorMap: colorMap,
                remainingFractions: remainingFractions,
                statesByEntry: statesByEntry,
                cardHeight: cardHeight,
                now: currentTime,
            )
            sliceInfos.append((day, calendar.isDateInToday(day), topTime, bottomTime, groups))
        }
        slices = sliceInfos

        // Global map: uniform points-per-minute, with doseless gaps capped
        // (unless compression is off). Every slice boundary, group anchor,
        // and "now" is a breakpoint. The segment past now carries the active
        // curves' tails, so it gets its own, far roomier cap — the tail's end
        // stays on the strip, with the hour ticks bunching to say how far it
        // reaches. Per slice, if the cards need more room than its span
        // provides, the deficit stretches the slice's largest gap — the dense
        // stretches keep their uniform scale.
        let ppm = TimelineDayLayout.basePointsPerMinute * CGFloat(zoom)
        let gapCap: CGFloat = compressGaps ? max(90, 45 * ppm) : .infinity
        let futureCap: CGFloat = compressGaps ? max(240, 240 * ppm) : .infinity

        var eventTimes: Set<Date> = [globalStart, globalEnd, currentTime]
        for slice in sliceInfos {
            eventTimes.insert(slice.bottomTime)
            for group in slice.groups {
                eventTimes.insert(group.representativeTime)
            }
        }
        let times = eventTimes.sorted().filter { $0 >= globalStart && $0 <= globalEnd }

        var heights: [CGFloat] = []
        heights.reserveCapacity(times.count - 1)
        for i in 0 ..< (times.count - 1) {
            let minutes = CGFloat(times[i + 1].timeIntervalSince(times[i]) / 60)
            let isFuture = times[i] >= currentTime
            let cap = isFuture ? futureCap : gapCap
            let floor = isFuture ? Self.liveEdgeMinimumHeight : 2
            heights.append(max(min(minutes * ppm, cap), floor))
        }

        // Slice floors: stretch the largest segment inside an undersized
        // slice so its cards fit without spilling into the next day.
        for slice in sliceInfos {
            guard let lo = times.firstIndex(where: { $0 >= slice.bottomTime }),
                  let hi = times.lastIndex(where: { $0 <= slice.topTime }),
                  hi > lo else { continue }
            let sliceHeight = heights[lo ..< hi].reduce(0, +)
            let groups = slice.groups
            let need = groups.map(\.height).reduce(0, +)
                + CGFloat(max(0, groups.count - 1)) * TimelineDayLayout.groupGap
                + CGFloat(groups.count) * TimelineDayLayout.envelopePad * 2
                + TimelineDayLayout.envelopeFooterHeight + 40
            if sliceHeight < need,
               let biggest = (lo ..< hi).max(by: { heights[$0] < heights[$1] }) {
                heights[biggest] += need - sliceHeight
            }
        }

        var ys: [CGFloat] = [0]
        ys.reserveCapacity(times.count)
        for h in heights {
            ys.append(ys[ys.count - 1] + h)
        }
        mapTimes = times
        mapYs = ys
        stripHeight = ys[ys.count - 1]
    }

    /// The strip always runs at least this far past now, so the live edge
    /// has room for its arrowhead and fade even when nothing is active.
    private static let minimumFutureSeconds: TimeInterval = 10 * 60
    /// Breathing room past the last curve's modeled end.
    private static let futureMarginSeconds: TimeInterval = 30 * 60
    /// Ceiling on the future extent, whatever is still active.
    private static let maximumFutureSeconds: TimeInterval = 24 * 3_600
    /// Point floor for the segment past now, at any zoom: keeps the "Now"
    /// tag below the day tag in the gutter and clear of the axis arrowhead.
    private static let liveEdgeMinimumHeight: CGFloat = 52

    /// Body-load mode's activity end per dose: six half-lives, the same cutoff
    /// ``computeRemainingFractions(entries:)`` treats as cleared. Doses that
    /// draw no body-load curve (supplements, no half-life) contribute nothing.
    private static func pkActivityEnds(entries: [DoseEntry]) -> [Date] {
        var substanceCache: [String: Substance?] = [:]
        var ends: [Date] = []
        for entry in entries {
            let key = entry.substance.lowercased()
            let substance: Substance?
            if let cached = substanceCache[key] {
                substance = cached
            } else {
                substance = SubstanceLibrary.lookup(entry.substance)
                substanceCache[key] = substance
            }
            if substance?.category == .supplement { continue }
            guard let halfLife = PKResolver.halfLifeMinutes(substance: substance, entryName: entry.substance) else { continue }
            ends.append(entry.timestamp.addingTimeInterval(halfLife * 6 * 60))
        }
        return ends
    }

    /// Global reversed lookup: later time → smaller y (from the strip's top).
    private static func reversedY(_ t: Date, times: [Date], ys: [CGFloat], total: CGFloat) -> CGFloat {
        if t <= times[0] { return total }
        if t >= times[times.count - 1] { return 0 }
        var lo = 0
        var hi = times.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if times[mid] <= t { lo = mid } else { hi = mid }
        }
        let span = times[hi].timeIntervalSince(times[lo])
        let f = span > 0 ? t.timeIntervalSince(times[lo]) / span : 0
        return total - (ys[lo] + (ys[hi] - ys[lo]) * CGFloat(f))
    }

    private func globalY(_ t: Date) -> CGFloat {
        Self.reversedY(t, times: mapTimes, ys: mapYs, total: stripHeight)
    }

    // MARK: Slice layout

    mutating func layout(sliceAt index: Int) -> TimelineDayLayout {
        let slice = slices[index]
        let sliceTopY = globalY(slice.topTime)
        let mapHeight = globalY(slice.bottomTime) - sliceTopY
        // Captures value copies, not `self` — `curveSeries` below mutates
        // self and takes this closure at the same time.
        let (times, ys, total) = (mapTimes, mapYs, stripHeight)
        let localY: (Date) -> CGFloat = { t in
            Self.reversedY(t, times: times, ys: ys, total: total) - sliceTopY
        }

        var groups = slice.groups

        // Session runs — consecutive groups sharing a session, with at least
        // two doses total, earn an envelope (single-dose sessions would just
        // duplicate the card's own tap target; the dose screen links onward).
        var runs: [(sessionID: UUID, range: ClosedRange<Int>)] = []
        var i = 0
        while i < groups.count {
            guard let sid = groups[i].sessionID else { i += 1; continue }
            var j = i
            while j + 1 < groups.count, groups[j + 1].sessionID == sid {
                j += 1
            }
            let doseCount = groups[i ... j].reduce(0) { $0 + $1.items.count }
            if doseCount >= 2 {
                runs.append((sid, i ... j))
                for k in i ... j {
                    groups[k].inSession = true
                }
            }
            i = j + 1
        }
        // Envelope padding, in axis direction: above the run's newest group
        // and pad+footer below its oldest. Groups are newest-first.
        var padAbove = [CGFloat](repeating: 0, count: groups.count)
        var padBelow = [CGFloat](repeating: 0, count: groups.count)
        for run in runs {
            padAbove[run.range.lowerBound] = TimelineDayLayout.envelopePad
            padBelow[run.range.upperBound] = TimelineDayLayout.envelopePad + TimelineDayLayout.envelopeFooterHeight
        }

        // Anchor each group's center at its time, then push down (into the
        // past) whatever collides — the connectors keep the true position
        // legible.
        for k in groups.indices {
            var top = localY(groups[k].representativeTime) - groups[k].height / 2
            if k == 0 {
                top = max(top, padAbove[0] + 24)
            } else {
                top = max(
                    top,
                    groups[k - 1].topY + groups[k - 1].height
                        + padBelow[k - 1] + TimelineDayLayout.groupGap + padAbove[k],
                )
            }
            groups[k].topY = top
        }

        let envelopes = runs.map { run in
            let newest = groups[run.range.lowerBound]
            let oldest = groups[run.range.upperBound]
            return TimelineDayLayout.SessionEnvelope(
                id: run.sessionID,
                yStart: newest.topY - TimelineDayLayout.envelopePad,
                yEnd: oldest.bottomY + TimelineDayLayout.envelopePad + TimelineDayLayout.envelopeFooterHeight,
            )
        }

        let deepestBottom = groups.indices.map { groups[$0].bottomY + padBelow[$0] }.max() ?? 0
        let totalHeight = max(mapHeight, deepestBottom + 12)

        var doseDots: [TimelineDayLayout.DoseDot] = []
        var connectors: [TimelineDayLayout.Connector] = []
        for group in groups {
            for (itemIndex, item) in group.items.enumerated() {
                let dotY = localY(item.entry.timestamp)
                doseDots.append(TimelineDayLayout.DoseDot(y: dotY, color: item.color))
                let cardCenterY = group.topY
                    + CGFloat(itemIndex) * (group.cardHeight + TimelineDayLayout.cardSpacing)
                    + group.cardHeight / 2
                connectors.append(TimelineDayLayout.Connector(fromY: dotY, toY: cardCenterY, color: item.color))
            }
        }

        let showsLiveEdge = index == 0
        let nowY: CGFloat? = if now >= slice.bottomTime, now <= slice.topTime {
            localY(now)
        } else {
            nil
        }

        let visibleLabels = TimelineGutterLabels.doseLabelsVisible(doseYs: groups.map(\.centerY), nowY: nowY)
        for k in groups.indices {
            groups[k].showsTimeLabel = visibleLabels[k]
        }

        let hourTicks = hourTicks(
            slice: slice,
            localY: localY,
            mapHeight: mapHeight,
            groups: groups,
            nowY: nowY,
        )

        // With the axis off nothing draws the curves, so skip sampling them.
        let series = style.showsAxis ? curveSeries(slice: slice, localY: localY) : []

        return TimelineDayLayout(
            date: slice.date,
            isToday: slice.isToday,
            style: style,
            showsLiveEdge: showsLiveEdge,
            cardGroups: groups,
            envelopes: envelopes,
            series: series,
            doseDots: doseDots,
            connectors: connectors,
            hourTicks: hourTicks,
            nowY: nowY,
            mapHeight: mapHeight,
            totalHeight: totalHeight,
        )
    }

    // MARK: Hour ruler

    /// A gridline for every hour that fits (≥8 pt apart — in a compressed
    /// gap they bunch, which is the compression cue); labels additionally
    /// thin out around dose capsules, the "Now" tag, each other, and any
    /// label a displaced card has pushed out of time order. Sun and moon
    /// glyphs stand in for the 06 and 18 numerals.
    private func hourTicks(
        slice: (date: Date, isToday: Bool, topTime: Date, bottomTime: Date, groups: [TimelineDayLayout.CardGroup]),
        localY: (Date) -> CGFloat,
        mapHeight: CGFloat,
        groups: [TimelineDayLayout.CardGroup],
        nowY: CGFloat?,
    ) -> [TimelineDayLayout.HourTick] {
        let calendar = Calendar.current
        guard var t = calendar.dateInterval(of: .hour, for: slice.bottomTime)?.end else { return [] }

        let labels = groups.map { (time: $0.representativeTime, y: $0.centerY) }
        let visibleDoseYs = groups.filter(\.showsTimeLabel).map(\.centerY)
        var ticks: [TimelineDayLayout.HourTick] = []
        var lastTickY: CGFloat = .infinity
        var lastLabelY: CGFloat = .infinity
        while t <= slice.topTime {
            let y = localY(t)
            defer { t = t.addingTimeInterval(3_600) }
            guard y >= 6, y <= mapHeight - 6, lastTickY - y >= 8 else { continue }
            lastTickY = y
            let ordered = labels.allSatisfy { label in
                label.time < t ? label.y > y - 4 : label.y < y + 4
            }
            let labelFits = y >= 12 && y <= mapHeight - 12
                && ordered
                && TimelineGutterLabels.hourLabelFits(y: y, doseYs: visibleDoseYs, nowY: nowY)
                && lastLabelY - y >= 24
            if labelFits {
                let label: TimelineDayLayout.HourTick.Label = switch calendar.component(.hour, from: t) {
                case 6: .symbol("sun.max")
                case 18: .symbol("moon")
                default: .numeral(TimelineGutter.hourNumeral(t))
                }
                ticks.append(TimelineDayLayout.HourTick(y: y, label: label))
                lastLabelY = y
            } else {
                ticks.append(TimelineDayLayout.HourTick(y: y, label: nil))
            }
        }
        return ticks
    }

    // MARK: Effect curves

    /// Samples every substance's **acute effect intensity** on a y-grid
    /// derived from the global map — the same phase-based curves the journal
    /// cards and session detail draw, so a dose's spine curve ends when its
    /// effects end, not when the last molecule clears (that's the %-badge's
    /// and In Your System's job). Normalized to the substance's all-time
    /// effect peak, so widths mean the same thing on every day and the curve
    /// crosses slice boundaries without a jump.
    private mutating func curveSeries(
        slice: (date: Date, isToday: Bool, topTime: Date, bottomTime: Date, groups: [TimelineDayLayout.CardGroup]),
        localY: (Date) -> CGFloat,
    ) -> [TimelineDayLayout.CurveSeries] {
        // Sample grid over the slice's time range, denser where the map is
        // stretched: walk global segments clipped to the slice.
        var grid: [(t: Date, y: CGFloat)] = []
        var segStart = slice.bottomTime
        while segStart < slice.topTime {
            var lo = 0
            var hi = mapTimes.count - 1
            while hi - lo > 1 {
                let mid = (lo + hi) / 2
                if mapTimes[mid] <= segStart { lo = mid } else { hi = mid }
            }
            let segEnd = min(mapTimes[hi], slice.topTime)
            let h = localY(segStart) - localY(segEnd)
            let steps = max(2, Int(h / 3))
            let span = segEnd.timeIntervalSince(segStart)
            for s in 0 ..< steps {
                let t = segStart.addingTimeInterval(span * Double(s) / Double(steps))
                grid.append((t: t, y: localY(t)))
            }
            segStart = segEnd
        }
        grid.append((t: slice.topTime, y: localY(slice.topTime)))
        grid.sort { $0.y < $1.y }

        var result: [TimelineDayLayout.CurveSeries] = if pkCurves {
            pkSeries(slice: slice, grid: grid)
        } else {
            effectSeries(slice: slice, grid: grid)
        }

        // Widest fills draw first so a slim spike is never buried under a
        // broad neighbor.
        result.sort { a, b in
            a.points.reduce(0) { $0 + $1.v } > b.points.reduce(0) { $0 + $1.v }
        }
        return result
    }

    private mutating func effectSeries(
        slice: (date: Date, isToday: Bool, topTime: Date, bottomTime: Date, groups: [TimelineDayLayout.CardGroup]),
        grid: [(t: Date, y: CGFloat)],
    ) -> [TimelineDayLayout.CurveSeries] {
        var result: [TimelineDayLayout.CurveSeries] = []
        for (key, states) in statesBySubstance {
            // Only states whose effect window overlaps this slice contribute.
            let relevant = states.filter { state in
                let end = state.doseTimestamp.addingTimeInterval(state.totalMinutes * 60)
                return state.doseTimestamp <= slice.topTime && end >= slice.bottomTime
            }
            guard !relevant.isEmpty else { continue }

            var values: [Double] = []
            values.reserveCapacity(grid.count)
            var sliceMax = 0.0
            for sample in grid {
                let v = Self.effectValue(at: sample.t, states: relevant, strengthScaling: strengthScaling)
                values.append(v)
                sliceMax = max(sliceMax, v)
            }

            let scale = globalEffectPeak(key: key, states: states)
            guard scale > 0, sliceMax > scale * 0.02 else { continue }

            let color = SubstancePalette.color(for: relevant[0].substanceName, colorMap: colorMap)
            let points = zip(grid, values).map { (y: $0.y, v: min($1 / scale, 1)) }
            result.append(TimelineDayLayout.CurveSeries(color: color, points: points))
        }
        return result
    }

    /// Body-load mode: half-life decay per substance, normalized to the
    /// substance's all-time stacked peak concentration. Long tails draw as
    /// long as they honestly persist — that's what this mode is for.
    private mutating func pkSeries(
        slice: (date: Date, isToday: Bool, topTime: Date, bottomTime: Date, groups: [TimelineDayLayout.CardGroup]),
        grid: [(t: Date, y: CGFloat)],
    ) -> [TimelineDayLayout.CurveSeries] {
        var result: [TimelineDayLayout.CurveSeries] = []
        for (key, substanceEntries) in entriesBySubstance {
            guard let name = substanceEntries.first?.substance,
                  let pk = resolvePKConstants(key: key, name: name) else { continue }

            let lookback = slice.bottomTime.addingTimeInterval(-pk.halfLife * 60 * 6)
            let relevant = substanceEntries.filter {
                $0.timestamp >= lookback && $0.timestamp <= slice.topTime
            }
            guard !relevant.isEmpty else { continue }

            var values: [Double] = []
            values.reserveCapacity(grid.count)
            var sliceMax = 0.0
            for sample in grid {
                var conc = 0.0
                for entry in relevant {
                    let elapsed = sample.t.timeIntervalSince(entry.timestamp) / 60
                    if elapsed >= 0 {
                        conc += doseWeight(entry) * PKModel.concentration(at: elapsed, ke: pk.ke, ka: pk.ka)
                    }
                }
                values.append(conc)
                sliceMax = max(sliceMax, conc)
            }

            let scale = globalPKPeak(key: key, pk: pk)
            guard scale > 0, sliceMax > scale * 0.03 else { continue }

            let color = SubstancePalette.color(for: name, colorMap: colorMap)
            let points = zip(grid, values).map { (y: $0.y, v: min($1 / scale, 1)) }
            result.append(TimelineDayLayout.CurveSeries(color: color, points: points))
        }
        return result
    }

    /// PK mode: resolve (and cache) a substance's rate constants; `nil` for
    /// substances that draw no body-load curve (no half-life, supplements).
    private mutating func resolvePKConstants(key: String, name: String) -> (halfLife: Double, ke: Double, ka: Double)? {
        if let cached = pkConstantsCache[key] { return cached }
        var resolved: (halfLife: Double, ke: Double, ka: Double)?
        if let substance = SubstanceLibrary.lookup(key),
           substance.category != .supplement,
           let halfLife = PKResolver.halfLifeMinutes(substance: substance, entryName: name),
           halfLife > 0 {
            let (ke, ka) = PKResolver.rateConstants(
                halfLifeMinutes: halfLife,
                duration: substance.resolveDuration(for: .oral),
            )
            if PKModel.cmax(ke: ke, ka: ka) > 0 {
                resolved = (halfLife, ke, ka)
            }
        }
        pkConstantsCache[key] = resolved
        return resolved
    }

    /// PK mode: the substance's all-time stacked peak concentration,
    /// evaluated at each dose's own peak moment. Cached — the normalization
    /// scale for every slice.
    private mutating func globalPKPeak(key: String, pk: (halfLife: Double, ke: Double, ka: Double)) -> Double {
        if let cached = peakCache["pk|\(key)"] { return cached }
        let substanceEntries = entriesBySubstance[key] ?? []
        let tmax = pk.ka > pk.ke ? log(pk.ka / pk.ke) / (pk.ka - pk.ke) : pk.halfLife
        var peak = 0.0
        for anchor in substanceEntries {
            let t = anchor.timestamp.addingTimeInterval(tmax * 60)
            var conc = 0.0
            for entry in substanceEntries {
                let elapsed = t.timeIntervalSince(entry.timestamp) / 60
                if elapsed >= 0 {
                    conc += doseWeight(entry) * PKModel.concentration(at: elapsed, ke: pk.ke, ka: pk.ka)
                }
            }
            peak = max(peak, conc)
        }
        peakCache["pk|\(key)"] = peak
        return peak
    }

    /// PK mode's per-dose weight: the logged amount, or unit weight with
    /// strength scaling off.
    private func doseWeight(_ entry: DoseEntry) -> Double {
        strengthScaling ? entry.amount : 1
    }

    /// Stacked effect intensity for one substance at `t` — each dose's
    /// phase-curve shape scaled by its dose intensity (unit weight with
    /// strength scaling off), summed.
    private static func effectValue(at t: Date, states: [ActiveSubstanceState], strengthScaling: Bool) -> Double {
        var total = 0.0
        for state in states {
            let minutes = t.timeIntervalSince(state.doseTimestamp) / 60
            guard minutes >= 0, minutes <= state.totalMinutes else { continue }
            let weight = strengthScaling ? state.doseIntensity : 1
            total += weight * TimelineCurveModel.intensity(at: minutes, for: state)
        }
        return total
    }

    /// The substance's all-time stacked effect peak: its summed intensity
    /// evaluated around each dose's own crest. Cached — this is the
    /// normalization scale for every slice.
    private mutating func globalEffectPeak(key: String, states: [ActiveSubstanceState]) -> Double {
        if let cached = peakCache[key] { return cached }
        var peak = 0.0
        for state in states {
            let crest = state.doseTimestamp.addingTimeInterval(
                (state.comeupEndMinutes + state.peakEndMinutes) / 2 * 60,
            )
            peak = max(peak, Self.effectValue(at: crest, states: states, strengthScaling: strengthScaling))
        }
        peakCache[key] = peak
        return peak
    }

    // MARK: Static helpers

    private static func makeGroups(
        dayEntries: [DoseEntry],
        colorMap: [String: Color],
        remainingFractions: [PersistentIdentifier: Double],
        statesByEntry: [PersistentIdentifier: ActiveSubstanceState],
        cardHeight: CGFloat,
        now: Date,
    ) -> [TimelineDayLayout.CardGroup] {
        let sorted = dayEntries.sorted { $0.timestamp < $1.timestamp }
        var groups: [TimelineDayLayout.CardGroup] = []
        var currentBatch: [DoseEntry] = []
        func flushBatch() {
            guard !currentBatch.isEmpty else { return }
            let repTime = currentBatch[currentBatch.count / 2].timestamp
            groups.append(TimelineDayLayout.CardGroup(
                id: currentBatch[0].persistentModelID,
                items: currentBatch.reversed().map { entry in
                    let state = statesByEntry[entry.persistentModelID]
                    let running = state.map { $0.doseTimestamp.addingTimeInterval($0.totalMinutes * 60) > now } ?? false
                    return TimelineDayLayout.CardItem(
                        entry: entry,
                        color: SubstancePalette.color(for: entry.substance, colorMap: colorMap),
                        remainingFraction: remainingFractions[entry.persistentModelID],
                        state: running ? state : nil,
                    )
                },
                representativeTime: repTime,
                sessionID: currentBatch[0].session?.id,
                cardHeight: cardHeight,
            ))
            currentBatch = []
        }
        for entry in sorted {
            if let prev = currentBatch.last,
               entry.timestamp.timeIntervalSince(prev.timestamp) > 5 * 60 {
                flushBatch()
            }
            currentBatch.append(entry)
        }
        flushBatch()
        return groups.reversed()
    }

    /// Fraction of each dose still in the body, keyed by entry identity.
    /// Mirrors ``ActiveSubstanceCalculator``'s gates (supplements and unmodeled
    /// forms contribute nothing; ≤3% counts as cleared) so the card badge and
    /// the In Your System readout can never disagree about what is active.
    private static func computeRemainingFractions(entries: [DoseEntry]) -> [PersistentIdentifier: Double] {
        var result: [PersistentIdentifier: Double] = [:]
        var substanceCache: [String: Substance?] = [:]
        let now = Date.now

        for entry in entries {
            let key = entry.substance.lowercased()
            let substance: Substance?
            if let cached = substanceCache[key] {
                substance = cached
            } else {
                substance = SubstanceLibrary.lookup(entry.substance)
                substanceCache[key] = substance
            }

            if substance?.category == .supplement { continue }
            let productDuration = entry.productDuration
            if productDuration == nil, entry.namesUnmodeledForm { continue }
            guard let halfLife = PKResolver.halfLifeMinutes(substance: substance, entryName: entry.substance) else { continue }

            let elapsed = now.timeIntervalSince(entry.timestamp) / 60
            guard elapsed >= 0, elapsed < halfLife * 6 else { continue }

            let (ke, ka) = PKResolver.rateConstants(
                halfLifeMinutes: halfLife,
                duration: productDuration ?? substance?.resolveDuration(
                    for: entry.route, saltForm: entry.saltForm, isomer: entry.isomer,
                ),
            )
            let fraction = PKModel.fractionRemainingInBody(at: elapsed, ke: ke, ka: ka)
            if fraction > 0.03 {
                result[entry.persistentModelID] = fraction
            }
        }
        return result
    }
}
