import ActivityKit
import SwiftData
import SwiftUI

struct SessionDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appNavigator) private var navigator
    let session: Session
    @Query private var substanceColors: [SubstanceColor]
    @Environment(\.sessionEditingService) private var editing

    /// The session's doses in time order — the view's working set, replacing the
    /// former calendar-day `@Query` window.
    private var entries: [DoseEntry] {
        session.orderedDoses
    }

    /// Alias so the existing day-derived title/recency helpers read the session's
    /// start instead of a passed-in date.
    private var date: Date {
        session.startDate
    }
    @AppStorage("stackRedoses", store: UserDefaults(suiteName: "group.dev.yumeji.piru")) private var stackRedoses = true
    @AppStorage(LaneModeDefaults.enabledKey, store: UserDefaults(suiteName: LaneModeDefaults.suite)) private var laneModeEnabled = LaneModeDefaults.enabledDefault
    @AppStorage(LaneModeDefaults.thresholdKey, store: UserDefaults(suiteName: LaneModeDefaults.suite)) private var laneModeThreshold = LaneModeDefaults.thresholdDefault

    /// The session immediately before this one in time — the target for
    /// "Merge with previous". A bounded one-row fetch resolved when the menu
    /// opens, replacing a whole-table `@Query` that re-ran this view's body on
    /// every change to any session. `startDate < session.startDate` already
    /// excludes self, so no id guard is needed.
    private func fetchPreviousSession() -> Session? {
        let cutoff = session.startDate
        var descriptor = FetchDescriptor<Session>(
            predicate: #Predicate { $0.startDate < cutoff },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)],
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    @State private var showRename = false
    @State private var titleDraft = ""
    @State private var showNoteEditor = false
    @State private var noteDraft = ""
    @State private var graphExpanded = true
    /// Expansion of the interaction warnings inside the Summary section. Collapsed
    /// by default — the severity-tinted count already signals their presence.
    @State private var interactionsExpanded = false
    /// Grows the inline timeline in place: the graph's frame steps up to a taller
    /// height and the List reflows the entries below it — no separate fullscreen
    /// sheet, no overlay. Every gesture stays the same; the curves just get room.
    @State private var timelineEnlarged = false
    @State private var exportedImage: UIImage?
    @State private var showShareSheet = false
    @State private var isExporting = false

    /// Substance → colour, rebuilt only when the colour assignments change.
    /// `colorFor`/`colorForName` are called once per entry row, and each used to
    /// allocate a fresh `Array(substanceColors)` *and* rebuild the whole colour
    /// map — O(rows × colours) per body pass.
    @State private var colorMap: [String: Color] = [:]
    /// Flips true once `colorMap` is first populated, so `resolvedColor` stops
    /// falling back to the per-call map build after the warm-up frame.
    @State private var colorMapReady = false

    private var colorSignature: Int {
        var hasher = Hasher()
        for color in substanceColors {
            hasher.combine(color.substance)
            hasher.combine(color.hexColor)
        }
        return hasher.finalize()
    }

    /// Height of the grown-in-place timeline — a modest step up from the embedded
    /// 168pt, enough to read without the distorted full-screen stretch.
    private static let enlargedGraphHeight: CGFloat = 320

    /// Distinct substances drawn on the timeline — the lane count once the graph
    /// switches to small multiples. Precomputed in ``resolvedDay``.
    private var laneCount: Int {
        resolvedDay.laneCount
    }

    /// Timeline height. Overlapping-curve days use the fixed embedded/enlarged
    /// heights; lane-mode days grow with the lane count so each horizon strip
    /// keeps a readable minimum instead of being crushed to a sliver. Clamped so
    /// a very busy day still fits a scrollable card.
    private func graphHeight(enlarged: Bool) -> CGFloat {
        let base = enlarged ? Self.enlargedGraphHeight : GraphMetrics.embedded
        guard laneModeEnabled, laneCount >= laneModeThreshold else { return base }
        let perLane: CGFloat = enlarged ? 46 : 32
        let axisOverhead: CGFloat = 40
        let ideal = CGFloat(laneCount) * perLane + axisOverhead
        return max(base, min(ideal, enlarged ? 560 : 380))
    }

    /// The day's resolved timeline + interaction warnings, derived **synchronously
    /// and memoized** (see ``DayResolveCache``) per change to the day's
    /// entries/colours. Resolving a single day is cheap — a handful of
    /// `SubstanceLibrary` lookups plus one batch interaction check — so the prior
    /// async `.task` resolve bought nothing but a structural cost: `substanceStates`
    /// and `dayInteractions` started empty, so the `if !…isEmpty` Sections *flipped
    /// in* after the first frame, rebuilding the List content (`_ConditionalContent`
    /// → `makeViewList` → generic-metadata instantiation) on every open. Computing
    /// up front keeps the view tree's shape fixed from frame 1 — no flip, no hang.
    private var resolvedDay: ResolvedDay {
        DayResolveCache.shared.resolve(signature: timelineSignature) {
            let t = ActiveSubstanceState.timeline(for: entries, colors: Array(substanceColors))
            let names = Array(Set(entries.map(\.substance)))
            let interactions = names.count >= 2 ? InteractionChecker.checkBatch(names, against: []) : []
            let laneNames = Set(t.states.map { $0.substanceName.lowercased() })
                .union(t.markers.map { $0.substanceName.lowercased() })
            return ResolvedDay(
                states: t.states,
                markers: t.markers,
                interactions: interactions,
                cumulativeDoses: Self.computeCumulativeDoses(entries),
                laneCount: laneNames.count,
                entryCores: Self.computeEntryCores(entries),
            )
        }
    }

    /// Resolve each dose row's substance facts once. Caches the per-substance
    /// `SubstanceLibrary` lookup so repeated substances in a session don't
    /// re-resolve, and applies the `CustomSubstanceStore` display-name override.
    private static func computeEntryCores(_ entries: [DoseEntry]) -> [DayEntryCore] {
        var substanceCache: [String: Substance?] = [:]
        func substance(_ name: String) -> Substance? {
            let key = name.lowercased()
            if let cached = substanceCache[key] { return cached }
            let resolved = SubstanceLibrary.lookupByNameOrAlias(name)
            substanceCache[key] = resolved
            return resolved
        }
        return entries.map { entry in
            let doseLevel = substance(entry.substance)?.doseRange(for: entry.route)?.level(for: entry.amount)
            return DayEntryCore(
                entryID: entry.id,
                timestamp: entry.timestamp,
                displayName: CustomSubstanceStore.shared.displayName(for: entry.substance),
                amount: entry.amount,
                unit: entry.unit,
                route: entry.route,
                doseLevel: doseLevel,
                tags: entry.tags,
            )
        }
    }

    /// Aggregate re-doses (substances logged more than once this session).
    /// Keeps each substance's first-seen casing (e.g. "3-Me-PCPy").
    private static func computeCumulativeDoses(_ entries: [DoseEntry]) -> [(substance: String, total: Double, unit: String, count: Int)] {
        var grouped: [String: (name: String, total: Double, unit: String, count: Int)] = [:]
        for entry in entries {
            let key = entry.substance.lowercased()
            if let existing = grouped[key] {
                grouped[key] = (name: existing.name, total: existing.total + entry.amount, unit: existing.unit, count: existing.count + 1)
            } else {
                grouped[key] = (name: entry.substance, total: entry.amount, unit: entry.unit, count: 1)
            }
        }
        return grouped.values
            .filter { $0.count > 1 }
            .map { (substance: $0.name, total: $0.total, unit: $0.unit, count: $0.count) }
            .sorted { $0.substance < $1.substance }
    }

    private var substanceStates: [ActiveSubstanceState] {
        resolvedDay.states
    }
    private var doseMarkers: [DoseMarker] {
        resolvedDay.markers
    }
    private var dayInteractions: [InteractionResult] {
        resolvedDay.interactions
    }

    /// Content fingerprint of the day's doses + colour count — the memo key, so
    /// the resolve re-runs on an edit but not on every body re-evaluation.
    private var timelineSignature: Int {
        var hasher = Hasher()
        for entry in entries {
            hasher.combine(entry.persistentModelID)
            hasher.combine(entry.timestamp)
            hasher.combine(entry.amount)
            hasher.combine(entry.substance)
            hasher.combine(entry.route)
        }
        hasher.combine(substanceColors.count)
        return hasher.finalize()
    }

    /// Re-dose totals, precomputed in ``resolvedDay``.
    private var cumulativeDoses: [(substance: String, total: Double, unit: String, count: Int)] {
        resolvedDay.cumulativeDoses
    }

    /// The Summary section appears whenever there is at least one derived signal
    /// to show — re-dose totals or interaction warnings. (Recovery tips ride along
    /// inside it rather than standing alone.)
    private var hasSummary: Bool {
        !cumulativeDoses.isEmpty || !dayInteractions.isEmpty
    }

    /// Highest severity among the day's interactions — drives the disclosure's
    /// tint and icon so a dangerous combo reads red even while collapsed.
    private var maxInteractionSeverity: InteractionSeverity {
        dayInteractions.map(\.severity).max() ?? .caution
    }

    @ViewBuilder
    private var interactionsDisclosure: some View {
        let severity = maxInteractionSeverity
        DisclosureGroup(isExpanded: $interactionsExpanded) {
            ForEach(dayInteractions.enumerated(), id: \.offset) { _, warning in
                InteractionWarningRow(warning: warning)
            }
        } label: {
            Label {
                Text(dayInteractions.count == 1 ? "1 interaction" : "\(dayInteractions.count) interactions")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(severity.labelColor)
            } icon: {
                Image(systemName: severity == .dangerous ? "exclamationmark.triangle.fill" : "exclamationmark.triangle")
                    .foregroundStyle(severity.labelColor)
            }
        }
        .tint(severity.labelColor)
    }

    private func cumulativeRow(_ item: (substance: String, total: Double, unit: String, count: Int)) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(colorForName(item.substance))
                .frame(width: 10, height: 10)
            Text(item.substance)
                .font(.headline)
            Spacer()
            Text("\(item.total.doseFormatted) \(item.unit)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
            Text("(\(item.count)x)")
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
        }
    }

    private var dateTitle: String {
        // The current year is implicit — only show it for past/future years.
        let base = Date.FormatStyle.dateTime.day().month(.wide)
        let sameYear = Calendar.current.isDate(date, equalTo: .now, toGranularity: .year)
        return date.formatted(sameYear ? base : base.year())
    }

    private var dayOfWeek: String {
        date.formatted(.dateTime.weekday(.wide))
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    /// Today or yesterday — recent enough that an elapsed-time line ("13h ago",
    /// "1d ago") is meaningful on every row. Older days show clock time alone so
    /// the column stays symmetric.
    private var isRecentDay: Bool {
        Calendar.current.isDateInToday(date) || Calendar.current.isDateInYesterday(date)
    }

    /// Any dose on this day whose effect window still includes now. Gates the
    /// "Live Activity" action so it only appears while a session is actually
    /// live, not once every dose has fully worn off.
    private var hasOngoingDose: Bool {
        let now = Date.now
        return substanceStates.contains { now < $0.doseTimestamp.addingTimeInterval($0.totalMinutes * 60) }
    }

    var body: some View {
        @Bindable var editing = editing
        return List {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "No Entries",
                        systemImage: "pill",
                        description: Text("No substances logged in this session."),
                    )
                } else {
                    // Timeline graph — only when at least one dose draws a curve.
                    // A day of nothing but markers (long-acting meds, duration-less
                    // doses) would render an empty axis, so we drop the whole
                    // section and let the entry list speak for itself.
                    if !substanceStates.isEmpty {
                        Section {
                            if graphExpanded {
                                AnimatableHeight(height: graphHeight(enlarged: timelineEnlarged)) {
                                    TimelineGraphView(
                                        substances: substanceStates,
                                        currentTime: .now,
                                        compact: false,
                                        markers: doseMarkers,
                                        stackRedoses: stackRedoses,
                                        dayBounded: true,
                                        synchronous: true,
                                    )
                                }
                                .animation(.spring(response: 0.4, dampingFraction: 0.84), value: timelineEnlarged)
                                // Tight insets are scoped to the graph row alone so it
                                // spans nearly edge-to-edge; the header/footer keep the
                                // List's default inset and so line up with the "N
                                // entries" header below.
                                .listRowInsets(EdgeInsets(
                                    top: GraphMetrics.section / 2,
                                    leading: GraphMetrics.cardInset / 2,
                                    bottom: GraphMetrics.section / 2,
                                    trailing: GraphMetrics.cardInset / 2,
                                ))
                            }
                        } header: {
                            HStack(spacing: GraphMetrics.section) {
                                Button {
                                    withAnimation { graphExpanded.toggle() }
                                } label: {
                                    HStack {
                                        Text("Timeline")
                                        Image(systemName: "chevron.right")
                                            .font(.caption2.weight(.semibold))
                                            .rotationEffect(.degrees(graphExpanded ? 90 : 0))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)

                                Spacer()

                                if isToday, hasOngoingDose {
                                    let isRunning = LiveActivityManager.shared.isLiveActivityRunning
                                    Button {
                                        toggleLiveActivity()
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: isRunning ? "stop.fill" : "dot.radiowaves.up.forward")
                                            Text(isRunning ? "Stop Live Activity" : "Start Live Activity")
                                        }
                                        .font(.caption2.weight(.semibold))
                                    }
                                    .buttonStyle(.bordered)
                                    .buttonBorderShape(.capsule)
                                    .controlSize(.mini)
                                    .tint(Theme.accent)
                                    .textCase(nil)
                                }

                                if graphExpanded {
                                    Button {
                                        timelineEnlarged.toggle()
                                    } label: {
                                        Image(
                                            systemName: timelineEnlarged
                                                ? "arrow.down.right.and.arrow.up.left"
                                                : "arrow.up.backward.and.arrow.down.forward",
                                        )
                                        .font(.caption.weight(.semibold))
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(Theme.accent)
                                    .accessibilityLabel(Text(timelineEnlarged ? "Shrink timeline" : "Expand timeline"))
                                }
                            }
                        } footer: {
                            if graphExpanded {
                                Text("Drag to pan, pinch to zoom, hold to inspect")
                            }
                        }
                    }

                    if let note = session.note, !note.isEmpty {
                        Section("Note") {
                            Text(note)
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondaryLabel)
                        }
                    }

                    // Entries
                    Section {
                        let cores = resolvedDay.entryCores
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            DayEntryRow(
                                entry: entry,
                                display: DayEntryDisplay(
                                    core: cores[index],
                                    color: colorFor(entry),
                                ),
                                showRelativeTime: isRecentDay,
                                canSplit: index != 0,
                            )
                            .equatable()
                        }
                    } header: {
                        Text("^[\(entries.count) entry](inflect: true)")
                    }

                    // A single "Summary" section folds together the day's derived
                    // signals — interaction warnings (expand in place), cumulative
                    // re-dose totals, and a link to recovery guidance — instead of
                    // three separate stacked sections competing below the log.
                    if hasSummary {
                        Section("Summary") {
                            if !dayInteractions.isEmpty {
                                interactionsDisclosure
                            }

                            ForEach(cumulativeDoses, id: \.substance) { item in
                                cumulativeRow(item)
                            }

                            NavigationLink(value: PushRoute.comedownGuide) {
                                Label("Recovery tips", systemImage: "heart.text.clipboard")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                    }
                }
            }
            .listRowBackground(Theme.cardBackground)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .task(id: colorSignature) {
            colorMap = Array(substanceColors).colorMap
            colorMapReady = true
        }
        .navigationTitle(session.title ?? "\(dayOfWeek), \(dateTitle)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !entries.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        exportDayLog()
                    } label: {
                        if isExporting {
                            ProgressView()
                                .tint(Theme.accent)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    .disabled(isExporting)
                    .accessibilityLabel(Text("Share session log"))
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }
            ToolbarItem(placement: .topBarTrailing) {
                sessionMenu
            }
        }
        // The primary "Log a dose" action lives in the tab bar's bottom accessory
        // (always on screen beneath this detail), so the day view no longer
        // floats its own add button.
        .alert("Rename Session", isPresented: $showRename) {
            TextField("Session title", text: $titleDraft)
            Button("Cancel", role: .cancel) {}
            Button("Save") { SessionService.setTitle(titleDraft, for: session) }
        }
        .sheet(isPresented: $showNoteEditor) {
            SessionNoteEditor(note: noteDraft) { SessionService.setNote($0, for: session) }
        }
        .sheet(item: $editing.entryToAdjustTime) { entry in
            NavigationStack {
                TimeAdjustSheet(entry: entry)
            }
            .presentationDetents([.medium])
        }
        .sheet(item: $editing.entryToMove) { entry in
            MoveToSessionView(dose: entry)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showShareSheet) {
            if let image = exportedImage {
                DayLogShareSheet(image: image)
                    .presentationDetents([.medium, .large])
            }
        }
        .sheet(item: $editing.recolorRequest) { request in
            SubstanceColorPickerView(
                substanceName: request.substanceName,
                takenColors: Array(substanceColors).takenColorMap,
            ) { hex in
                if let existing = substanceColors.first(where: { $0.substance.lowercased() == request.substanceName.lowercased() }) {
                    existing.hexColor = hex
                } else {
                    modelContext.insert(SubstanceColor(substance: request.substanceName, hexColor: hex))
                }
                editing.recolorRequest = nil
            }
            .presentationDetents([.large])
        }
    }

    /// Title/note editing + "merge with previous" — the session-level overrides.
    private var sessionMenu: some View {
        Menu {
            Button {
                titleDraft = session.title ?? ""
                showRename = true
            } label: {
                Label(session.title == nil ? "Add Title" : "Rename", systemImage: "pencil")
            }
            Button {
                noteDraft = session.note ?? ""
                showNoteEditor = true
            } label: {
                Label(session.note == nil ? "Add Note" : "Edit Note", systemImage: "note.text")
            }
            if let previous = fetchPreviousSession() {
                Divider()
                Button {
                    withAnimation { SessionService.merge(previous, into: session, in: modelContext) }
                } label: {
                    Label("Merge with Previous", systemImage: "arrow.triangle.merge")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
    }

    private func colorFor(_ entry: DoseEntry) -> Color {
        resolvedColor(entry.substance)
    }

    private func colorForName(_ name: String) -> Color {
        resolvedColor(name)
    }

    /// Row tint for a substance. Reads the cached `colorMap` once it's warm; on
    /// the very first frame — before `.task(id: colorSignature)` populates it —
    /// falls back to a direct resolve so the dots don't flash from the accent
    /// tint to their real colour. The fallback pays the full map build for that
    /// one frame only; once `colorMapReady` flips, a miss means the substance
    /// genuinely has no assigned colour, so it returns the accent without
    /// rebuilding the map every body pass.
    private func resolvedColor(_ name: String) -> Color {
        let key = name.lowercased()
        if let color = colorMap[key] { return color }
        guard !colorMapReady else { return Theme.accent }
        return Array(substanceColors).colorMap[key] ?? Theme.accent
    }

    private func exportDayLog() {
        isExporting = true
        let hexMap = Array(substanceColors).hexColorMap
        // Resolve each distinct substance once, not twice per dose.
        var substanceCache: [String: Substance?] = [:]
        func substance(_ name: String) -> Substance? {
            let key = name.lowercased()
            if let cached = substanceCache[key] { return cached }
            let resolved = SubstanceLibrary.lookupByNameOrAlias(name)
            substanceCache[key] = resolved
            return resolved
        }
        let entriesCopy = entries.map { entry in
            let sub = substance(entry.substance)
            return DayLogImageExporter.EntryData(
                substance: entry.substance,
                amount: entry.amount,
                unit: entry.unit,
                route: entry.route,
                timestamp: entry.timestamp,
                notes: entry.notes,
                tags: entry.tags,
                category: sub?.category,
                doseLevel: sub?.doseRange(for: entry.route)?.level(for: entry.amount),
                colorHex: hexMap[entry.substance.lowercased()],
            )
        }
        let exportDate = date
        // Capture the timeline only when it's actually on screen — a collapsed
        // graph exports the entry list alone, matching what the user sees.
        let timelineImage = renderTimelineImage()
        Task {
            let image = DayLogImageExporter.generateImage(
                date: exportDate,
                entries: entriesCopy,
                timeline: timelineImage,
            )
            isExporting = false
            if let image {
                exportedImage = image
                showShareSheet = true
            }
        }
    }

    /// Render the timeline graph to a standalone image for the day-log export.
    /// Mirrors the on-screen graph (same resolved curves/markers, synchronous so
    /// it's drawn in one pass) on a dark card, sized to the exporter's column.
    /// Returns nil when the graph is collapsed or has no curve to draw.
    @MainActor
    private func renderTimelineImage() -> UIImage? {
        guard graphExpanded, !substanceStates.isEmpty else { return nil }
        let graph = TimelineGraphView(
            substances: substanceStates,
            currentTime: .now,
            compact: false,
            markers: doseMarkers,
            stackRedoses: stackRedoses,
            dayBounded: true,
            synchronous: true,
        )
        .frame(width: DayLogImageExporter.timelineWidth, height: graphHeight(enlarged: false))
        .background(Color(white: 0.09))
        .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: graph)
        renderer.scale = 3 // @3x — crisp in the shareable export regardless of device
        return renderer.uiImage
    }

    private func toggleLiveActivity() {
        if LiveActivityManager.shared.isLiveActivityRunning {
            LiveActivityManager.shared.hideLiveActivity()
        } else {
            ActiveSessionManager.shared.restartFromEntries(
                entries,
                allColors: Array(substanceColors),
            )
            LiveActivityManager.shared.startLiveActivity()
        }
    }
}

/// A day's resolved curves, markers, and interaction warnings.
private struct ResolvedDay {
    var states: [ActiveSubstanceState] = []
    var markers: [DoseMarker] = []
    var interactions: [InteractionResult] = []
    /// Re-dose totals (substances logged more than once), precomputed with the
    /// rest so the Summary section and `hasSummary` don't re-aggregate per body.
    var cumulativeDoses: [(substance: String, total: Double, unit: String, count: Int)] = []
    /// Distinct timeline lanes, precomputed so `graphHeight` doesn't rebuild two
    /// name Sets on every height-animation frame.
    var laneCount: Int = 0
    /// Render-ready, substance-resolved facts for each dose row, in `entries`
    /// order. Built here (once per content change) so the heavy per-row resolve
    /// — `SubstanceLibrary` lookup + dose-level classification + display-name
    /// override — never runs in a row `body`.
    var entryCores: [DayEntryCore] = []
}

/// Hosts a fixed-height child whose height is itself the animation driver.
///
/// Animating `.frame(height:)` on a `Canvas` directly makes SwiftUI rasterise the
/// drawing and scale the bitmap from its centre — the curves blink out for a frame
/// and the whole graph "pops" from the middle instead of growing down. Conforming
/// the host to `Animatable` on the height forces `body` to re-evaluate on **every**
/// interpolation step, so the `Canvas` re-runs its draw closure at each in-between
/// height and the timeline genuinely grows in place. The child keeps its identity
/// (and so its `@State`-memoised geometry) across the steps — only the proposed
/// height changes.
private struct AnimatableHeight<Content: View>: View, Animatable {
    var height: CGFloat
    var animatableData: CGFloat {
        get { height }
        set { height = newValue }
    }

    @ViewBuilder var content: Content

    var body: some View {
        content.frame(height: height)
    }
}

/// Single-slot process-wide memo for the visible day's ``ResolvedDay``, keyed by
/// the day's content signature. Only one day detail is on screen at a time, so a
/// single slot suffices; a stacked second detail simply recomputes (still
/// correct). This is the "`@State` as a cache" pattern — store an
/// expensive-to-recompute value without change-tracking it — and is what lets the
/// view resolve synchronously up front instead of flipping Sections in from an
/// async `.task`.
@MainActor
private final class DayResolveCache {
    static let shared = DayResolveCache()
    private var signature: Int?
    private var value = ResolvedDay()

    func resolve(signature: Int, _ compute: () -> ResolvedDay) -> ResolvedDay {
        if self.signature == signature { return value }
        let resolved = compute()
        self.signature = signature
        value = resolved
        return resolved
    }
}

private struct DayLogShareSheet: UIViewControllerRepresentable {
    let image: UIImage

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}

private struct TimeAdjustSheet: View {
    @Bindable var entry: DoseEntry
    @Environment(\.dismiss) private var dismiss
    @Query private var substanceColors: [SubstanceColor]
    @State private var originalTimestamp: Date?

    var body: some View {
        Form {
            DatePicker("Date & Time", selection: $entry.timestamp)
        }
        .navigationTitle("Adjust Time")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: { Image(systemName: "xmark") }
            }
        }
        .onAppear { if originalTimestamp == nil { originalTimestamp = entry.timestamp } }
        .onDisappear {
            // Keep the session accessory + Live Activity in sync with the edited
            // time (they read ActiveSessionManager's snapshot, not SwiftData).
            guard let original = originalTimestamp, original != entry.timestamp else { return }
            ActiveSessionManager.shared.refreshEditedEntry(
                previousTimestamp: original,
                entry: entry,
                allColors: Array(substanceColors),
            )
            // Pending reminders are keyed to the old timestamp — a moved dose
            // must drop them and reschedule from its new time.
            DoseNotificationManager.doseRescheduled(entry: entry, previousTimestamp: original)
        }
    }
}

/// One dose row in the day detail. Extracted from the inline `ForEach` body so
/// SwiftUI builds (and caches the generic metadata for) a single named row type
/// instead of re-instantiating the deep `NavigationLink`+swipe+contextMenu
/// modifier chain per entry on every list rebuild — which dominated day-view
/// entry as `makeViewList` + `swift_conformsToProtocol` churn.
private struct DayEntryRow: View, Equatable {
    /// The dose model — used only by the swipe/menu *actions* (never read in
    /// `body`), so it never makes the row observe the entry. Kept out of `==`:
    /// all displayed content is compared via `display`, which is rebuilt from
    /// the entry upstream whenever it changes.
    let entry: DoseEntry
    let display: DayEntryDisplay
    let showRelativeTime: Bool
    /// `true` for any dose after the first — splitting "here" leaves doses behind.
    let canSplit: Bool

    @Environment(\.appNavigator) private var navigator
    @Environment(\.sessionEditingService) private var editing
    @Environment(\.modelContext) private var modelContext

    /// Compare on the render-ready `display` (a value type) + the two flags
    /// only — never on the `entry` reference (a SwiftData `@Model`; two refs to
    /// the same object always compare equal, which would freeze content updates).
    /// So a detail-screen toggle that leaves this row's data unchanged skips its
    /// body entirely.
    static func == (lhs: DayEntryRow, rhs: DayEntryRow) -> Bool {
        lhs.display == rhs.display
            && lhs.showRelativeTime == rhs.showRelativeTime
            && lhs.canSplit == rhs.canSplit
    }

    var body: some View {
        NavigationLink(value: PushRoute.entry(timestamp: display.core.timestamp, id: display.core.entryID)) {
            EntryRowView(display: display, showRelativeTime: showRelativeTime)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { editing.delete(entry, in: modelContext) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                navigator.present(.entryEdit(timestamp: entry.timestamp, id: entry.id))
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.orange)
        }
        .contextMenu {
            Button { editing.requestAdjustTime(entry) } label: {
                Label("Adjust Time", systemImage: "clock")
            }
            Button { editing.requestRecolor(entry.substance) } label: {
                Label("Change Color", systemImage: "paintbrush")
            }
            Button {
                navigator.present(.entryEdit(timestamp: entry.timestamp, id: entry.id))
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            if canSplit {
                Button { editing.split(at: entry, in: modelContext) } label: {
                    Label("Split Session Here", systemImage: "scissors")
                }
            }
            Button { editing.requestMove(entry) } label: {
                Label("Move to Session…", systemImage: "arrow.right.arrow.left")
            }
            Divider()
            Button(role: .destructive) { editing.delete(entry, in: modelContext) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

/// A small sheet for editing a session's free-form note.
private struct SessionNoteEditor: View {
    @State private var text: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    init(note: String, onSave: @escaping (String) -> Void) {
        _text = State(initialValue: note)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .padding()
                .navigationTitle("Session Note")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            onSave(text)
                            dismiss()
                        }
                    }
                }
        }
        .presentationDetents([.medium])
    }
}

/// Relocates a single dose into any other session — or a brand-new one. The
/// per-dose counterpart to *split* (which carves off a tail) and *merge* (which
/// folds whole sessions together): this picks up exactly one dose and sets it
/// down wherever the user says, including a fresh session of its own, which is
/// the one regrouping the other two can't express. Tapping a target performs
/// the move immediately and dismisses — light and reversible (just move back).
private struct MoveToSessionView: View {
    let dose: DoseEntry
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Session.startDate, order: .reverse) private var sessions: [Session]
    @Query private var substanceColors: [SubstanceColor]
    @State private var retimeTarget: Session?

    private var currentSessionID: PersistentIdentifier? {
        dose.session?.persistentModelID
    }

    /// Every session except the one the dose already belongs to — the valid
    /// move targets, in the journal's reverse-chronological order.
    private var targets: [Session] {
        sessions.filter { $0.persistentModelID != currentSessionID }
    }

    /// Whether the dose can join `session` keeping its current timestamp without
    /// stretching the session across a long quiescent gap. True when the dose
    /// already falls inside the session's span, or within the clustering sleep
    /// ceiling (8 h) of either edge — the same reach the heuristic would group.
    /// A far session is still selectable, but moving there re-times the dose so
    /// the session doesn't balloon into a multi-day span.
    private func isNear(_ session: Session) -> Bool {
        let doses = session.orderedDoses
        guard let first = doses.first?.timestamp, let last = doses.last?.timestamp else { return true }
        return SessionClustering.canJoinKeepingTime(doseTime: dose.timestamp, sessionFirst: first, sessionLast: last)
    }

    /// Hide "New Session" when the dose is already alone in its session —
    /// pulling it into a fresh one would be a no-op the user can't perceive.
    private var canMakeNewSession: Bool {
        (dose.session?.doses?.count ?? 0) > 1
    }

    private var doseColor: Color {
        Array(substanceColors).colorMap[dose.substance.lowercased()] ?? Theme.accent
    }

    var body: some View {
        NavigationStack {
            Group {
                if !canMakeNewSession, targets.isEmpty {
                    ContentUnavailableView(
                        "Nowhere to Move",
                        systemImage: "arrow.right.arrow.left",
                        description: Text("This is the only session."),
                    )
                } else {
                    List {
                        Section {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(doseColor)
                                    .frame(width: 12, height: 12)
                                Text(dose.substance)
                                    .font(.headline)
                                Spacer()
                                Text("\(dose.amount.doseFormatted) \(dose.unit)")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.secondaryLabel)
                            }
                            .listRowBackground(Theme.cardBackground)
                        }

                        if canMakeNewSession {
                            Section {
                                Button {
                                    moveToNewSession()
                                } label: {
                                    Label {
                                        Text("New Session").foregroundStyle(.primary)
                                    } icon: {
                                        Image(systemName: "plus.circle.fill")
                                            .foregroundStyle(Theme.accent)
                                    }
                                }
                                .listRowBackground(Theme.cardBackground)
                            } footer: {
                                Text("Pull this dose into its own session.")
                            }
                        }

                        if !targets.isEmpty {
                            Section("Move To") {
                                ForEach(targets) { session in
                                    let near = isNear(session)
                                    Button {
                                        if near {
                                            move(to: session)
                                        } else {
                                            retimeTarget = session
                                        }
                                    } label: {
                                        SessionTargetRow(
                                            session: session,
                                            colors: Array(substanceColors),
                                            requiresRetime: !near,
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .listRowBackground(Theme.cardBackground)
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Theme.background)
            .navigationTitle("Move \(dose.substance)")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $retimeTarget) { session in
                RetimeMoveView(dose: dose, session: session) { newDate in
                    let previousTimestamp = dose.timestamp
                    dose.timestamp = newDate
                    DoseNotificationManager.doseRescheduled(entry: dose, previousTimestamp: previousTimestamp)
                    move(to: session)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
            }
        }
    }

    private func move(to session: Session) {
        withAnimation { SessionService.move(dose, to: session, in: modelContext) }
        dismiss()
    }

    private func moveToNewSession() {
        withAnimation {
            let new = Session(startDate: dose.timestamp)
            modelContext.insert(new)
            SessionService.move(dose, to: new, in: modelContext)
        }
        dismiss()
    }
}

/// A selectable session row in the move picker: a cluster of substance colours,
/// the session's title (or its date), the time span its doses cover, and the
/// dose count.
private struct SessionTargetRow: View {
    let session: Session
    let colors: [SubstanceColor]
    /// The dose's current time is far from this session, so choosing it will ask
    /// for a new time within the session's day rather than moving as-is. Shown as
    /// a small clock cue so the extra step isn't a surprise.
    let requiresRetime: Bool

    private var title: String {
        if let t = session.title, !t.isEmpty { return t }
        return session.startDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    private func timeRange(for doses: [DoseEntry]) -> String {
        guard let first = doses.first?.timestamp else { return "" }
        let last = doses.last?.timestamp ?? first
        let style = Date.FormatStyle.dateTime.hour().minute()
        if Calendar.current.isDate(first, equalTo: last, toGranularity: .minute) {
            return first.formatted(style)
        }
        return "\(first.formatted(style)) – \(last.formatted(style))"
    }

    private func countText(for doses: [DoseEntry]) -> String {
        doses.count == 1 ? String(localized: "1 dose") : String(localized: "\(doses.count) doses")
    }

    /// Up to three distinct substance colours, in first-seen order.
    private func dotColors(for doses: [DoseEntry]) -> [Color] {
        var seen = Set<String>()
        var result: [Color] = []
        for dose in doses {
            let key = dose.substance.lowercased()
            if seen.insert(key).inserted {
                result.append(colors.colorMap[key] ?? Theme.accent)
            }
            if result.count == 3 { break }
        }
        return result
    }

    var body: some View {
        // Sorted once per row render — `orderedDoses` sorts, and three derived
        // values read it.
        let doses = session.orderedDoses
        HStack(spacing: 12) {
            dots(dotColors(for: doses))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(timeRange(for: doses))
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            Spacer()
            if requiresRetime {
                Image(systemName: "clock.badge.questionmark")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            Text(countText(for: doses))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
        }
        .contentShape(Rectangle())
    }

    /// Overlapping color dots, each ringed in the card colour so they read as a
    /// distinct cluster rather than a blur.
    private func dots(_ dotColors: [Color]) -> some View {
        HStack(spacing: -5) {
            ForEach(dotColors.enumerated(), id: \.offset) { _, color in
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Theme.cardBackground, lineWidth: 1.5))
            }
        }
    }
}

/// Re-time step for moving a dose into a session it isn't close to in time.
/// Rather than carrying the dose's original timestamp — which would stretch the
/// target across days — the user picks a new time *within that session's day*, so
/// the session stays a coherent same-day span. The picker is clamped to the day
/// and defaults to just after the session's last dose, the natural "extend it"
/// choice.
private struct RetimeMoveView: View {
    let dose: DoseEntry
    let session: Session
    let onConfirm: (Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Date

    init(dose: DoseEntry, session: Session, onConfirm: @escaping (Date) -> Void) {
        self.dose = dose
        self.session = session
        self.onConfirm = onConfirm
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: session.startDate)
        let dayEnd = cal.date(byAdding: DateComponents(day: 1, second: -1), to: dayStart) ?? dayStart
        let last = session.orderedDoses.last?.timestamp ?? session.startDate
        _draft = State(initialValue: min(max(last, dayStart), dayEnd))
    }

    private var dayRange: ClosedRange<Date> {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: session.startDate)
        let dayEnd = cal.date(byAdding: DateComponents(day: 1, second: -1), to: dayStart) ?? dayStart
        return dayStart ... dayEnd
    }

    private var dayLabel: String {
        session.startDate.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    var body: some View {
        Form {
            Section {
                DatePicker(
                    "Time",
                    selection: $draft,
                    in: dayRange,
                    displayedComponents: [.hourAndMinute],
                )
            } header: {
                Text("New time on \(dayLabel)")
            } footer: {
                Text("\(dose.substance) is logged on a different day. Pick a time within this session's day so the session stays a single day.")
            }
        }
        .navigationTitle("Set Time")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Move") {
                    onConfirm(draft)
                }
            }
        }
    }
}
