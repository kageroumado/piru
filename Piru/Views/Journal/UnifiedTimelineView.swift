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
                    showsAxis: showsAxis,
                    bubbleStyle: bubbleStyle,
                )
            }
        }
    }

    private var rebuildKey: String {
        "\(DoseLogService.shared.revision)|\(zoom)|\(compressGaps)|\(pkCurves)|\(showsAxis)|\(bubbleStyle.rawValue)"
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
        showsAxis: Bool,
        bubbleStyle: TimelineBubbleStyle,
    ) async {
        let key = "\(revision)|\(zoom)|\(compressGaps)|\(pkCurves)|\(showsAxis)|\(bubbleStyle.rawValue)|\(entries.count)"
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
    /// Height of the empty run at the slice's top standing in for skipped
    /// whole days (``TimelineTimeMap/breakHeight``), or 0 when the strip
    /// continues straight from the newer slice.
    let breakAbove: CGFloat
    /// The next older slice starts after a break: the axis fades out toward
    /// this slice's bottom edge.
    let fadesAxisBelow: Bool
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
        /// Where ``representativeTime`` falls on the axis — the time capsule
        /// sits here, beside the dose dot, however far the card stack below is
        /// pushed down by the groups above it.
        var timeY: CGFloat = 0
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
    /// slices join seamlessly. Each point carries the phase of the newest dose
    /// covering it, which the stroke draws as a color shift along the line;
    /// body-load curves model no phases and carry `nil`.
    struct CurveSeries {
        let color: Color
        let points: [CurvePoint]
    }

    struct CurvePoint {
        let y: CGFloat
        let v: Double
        var phase: TimelineCurvePhase?
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
        /// The hour as the locale writes it on its own (``TimelineHourMark``),
        /// or `nil` when the gridline stands alone — its label would collide
        /// with the day tag, a dose capsule, the "Now" tag, or a neighboring
        /// hour label.
        let label: String?
    }
}
