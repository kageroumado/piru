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
/// bounded strip — and each compressed stretch breaks the axis, its hours
/// left unlabeled. Compression can be turned off entirely for a
/// stable 1:1 scale.
///
/// The strip shows absolute time labels on the left (hour ruler + per-dose
/// times), a per-substance PK spine, and dose cards connected to their true
/// position on the axis. Doses belonging to one ``Session`` are wrapped in a
/// tappable envelope that opens the session detail — the timeline → session
/// → dose hierarchy. A session with a single dose in a day draws no
/// envelope, so that bubble opens the session itself
/// (``TimelineDayLayout/CardGroup/sessionOpenedByBubble``).
struct UnifiedTimelineView: View {
    @Environment(\.modelContext) private var modelContext
    /// Every dose, newest first, current for the dose log's revision
    /// (``DoseLogEntries``), shared with the Journal.
    private var entries: [DoseEntry] {
        DoseLogEntries.shared.entries(in: modelContext)
    }

    @Query private var substanceColors: [SubstanceColor]
    @State private var model = UnifiedTimelineModel()
    /// Bubble heights grow with the text size, so a change re-lays the strip.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showingCalendar = false
    /// Advanced by ``TimelineClockTick`` so the strip's "now" follows the clock.
    @State private var clockTick = 0
    /// Set once the first built strip has been scrolled to Now, so later
    /// rebuilds leave the reader where they scrolled.
    @State private var hasOpenedAtNow = false
    @State private var viewportHeight = TimelineViewportHeight()
    @GestureState private var pinchScale: CGFloat = 1
    @AppStorage("timelineZoom", store: UserDefaults(suiteName: AppIdentity.appGroup)) private var zoom = 1.0
    @AppStorage("timelineCompression", store: UserDefaults(suiteName: AppIdentity.appGroup)) private var compressGaps = true
    @AppStorage("timelinePKCurves", store: UserDefaults(suiteName: AppIdentity.appGroup)) private var pkCurves = false
    @AppStorage("timelineCurveScale", store: UserDefaults(suiteName: AppIdentity.appGroup)) private var curveScale = TimelineCurveScale.doseStrength
    @AppStorage("timelineShowsAxis", store: UserDefaults(suiteName: AppIdentity.appGroup)) private var showsAxis = true
    @AppStorage("timelineBubbleStyle", store: UserDefaults(suiteName: AppIdentity.appGroup)) private var bubbleStyle = TimelineBubbleStyle.full
    @AppStorage(HealthKitVitals.overlayKey, store: HealthKitVitals.settingsStore) private var showsVitals = false

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
                            TimelineDayContent(day: day)
                                .equatable()
                                .id(day.date)
                        }
                    }
                }
                .padding(.bottom, 40)
                .scaleEffect(x: 1, y: pinchScale, anchor: .top)
            }
            .onGeometryChange(for: CGFloat.self) { TimelineViewportHeight.visible(in: $0) } action: { viewportHeight.value = $0 }
            .skinBackdrop()
            .simultaneousGesture(magnification)
            .toolbar {
                ToolbarItem(placement: .platformTopBarTrailing) {
                    TimelineOptionsMenu(
                        zoom: $zoom,
                        compressGaps: $compressGaps,
                        pkCurves: $pkCurves,
                        curveScale: $curveScale,
                        showsAxis: $showsAxis,
                        bubbleStyle: $bubbleStyle,
                    ) {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
                ToolbarItem(placement: .platformTopBarTrailing) {
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
            .timelineClockTick($clockTick)
            .onChange(of: model.days.isEmpty) { _, isEmpty in
                guard !isEmpty, !hasOpenedAtNow else { return }
                hasOpenedAtNow = true
                if let target = TimelineOpeningTarget.resolve(model.days, viewportHeight: viewportHeight.value) {
                    proxy.scrollTo(target.id, anchor: target.anchor)
                }
            }
            .onChange(of: model.builtPreferences) { old, _ in
                guard old != nil, hasOpenedAtNow,
                      let target = TimelineOpeningTarget.resolve(model.days, viewportHeight: viewportHeight.value)
                else { return }
                proxy.scrollTo(target.id, anchor: target.anchor)
            }
            .task(id: rebuildKey) {
                // The launch cache first, as the Journal's strip does: a hit
                // paints without building the strip on the main actor.
                if model.days.isEmpty,
                   await model.restoreCached(
                       container: modelContext.container,
                       revision: rebuildKey.hashValue,
                       zoom: zoom,
                       compressGaps: compressGaps,
                       pkCurves: pkCurves,
                       curveScale: curveScale,
                       showsAxis: showsAxis,
                       bubbleStyle: bubbleStyle,
                       showsVitals: showsVitals,
                   ) {
                    return
                }
                await model.rebuild(
                    entries: entries,
                    colors: substanceColors,
                    colorMap: substanceColors.colorMap,
                    revision: rebuildKey.hashValue,
                    zoom: zoom,
                    compressGaps: compressGaps,
                    pkCurves: pkCurves,
                    curveScale: curveScale,
                    showsAxis: showsAxis,
                    bubbleStyle: bubbleStyle,
                    showsVitals: showsVitals,
                )
            }
        }
    }

    private var rebuildKey: String {
        "\(DoseLogService.shared.revision)|\(zoom)|\(compressGaps)|\(pkCurves)|\(curveScale.rawValue)|\(showsAxis)|\(bubbleStyle.rawValue)|\(showsVitals)|\(dynamicTypeSize)|\(clockTick)"
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
            .inlineNavigationTitle()
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
            description: Text("Your timeline will appear here after your first entry."),
        )
        .padding(.top, 60)
    }
}

// MARK: - Day slice

/// One day slice of the strip. Axis on: the strip layout
/// (``TimelineStripDayContent``); axis off: the bubbles as a plain list
/// (``TimelineListDayContent``).
///
/// `Equatable` on the layout alone: the strip has hundreds of these, and every
/// evaluation of the list around them (a navigation push, a tab switch) would
/// re-run all of their bodies if they took tap closures, which are fresh
/// identities each pass. The taps push through the navigator here, so the
/// only input is the value the day was laid out from.
struct TimelineDayContent: View, Equatable {
    let day: TimelineDayLayout
    @Environment(\.appNavigator) private var navigator
    @Environment(\.opensRecordsBesideList) private var opensRecordsBesideList

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.day == rhs.day
    }

    var body: some View {
        let onEntryTap: (TimelineDayLayout.CardItem) -> Void = { item in
            navigator.openRecord(.entry(timestamp: item.timestamp, id: item.id), besideList: opensRecordsBesideList)
        }
        let onSessionTap: (UUID) -> Void = { sessionID in
            navigator.openRecord(.session(id: sessionID), besideList: opensRecordsBesideList)
        }
        if day.style.showsAxis {
            TimelineStripDayContent(day: day, onEntryTap: onEntryTap, onSessionTap: onSessionTap)
        } else {
            TimelineListDayContent(day: day, onEntryTap: onEntryTap, onSessionTap: onSessionTap)
        }
    }
}
