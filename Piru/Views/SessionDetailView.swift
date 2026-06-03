import ActivityKit
import SwiftData
import SwiftUI

struct SessionDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appNavigator) private var navigator
    let session: Session
    @Query private var substanceColors: [SubstanceColor]
    @Query(sort: \Session.startDate, order: .reverse) private var allSessions: [Session]

    /// The session's doses in time order — the view's working set, replacing the
    /// former calendar-day `@Query` window.
    private var entries: [DoseEntry] { session.orderedDoses }

    /// Alias so the existing day-derived title/recency helpers read the session's
    /// start instead of a passed-in date.
    private var date: Date { session.startDate }
    @AppStorage("stackRedoses", store: UserDefaults(suiteName: "group.dev.yumeji.piru")) private var stackRedoses = true

    /// The session immediately before this one in time — the target for
    /// "Merge with previous".
    private var previousSession: Session? {
        allSessions.first {
            $0.startDate < session.startDate && $0.persistentModelID != session.persistentModelID
        }
    }

    @State private var entryToAdjustTime: DoseEntry?
    @State private var showRename = false
    @State private var titleDraft = ""
    @State private var showNoteEditor = false
    @State private var noteDraft = ""
    @State private var showColorPicker = false
    @State private var colorPickerSubstance = ""
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

    /// Height of the grown-in-place timeline — a modest step up from the embedded
    /// 168pt, enough to read without the distorted full-screen stretch.
    private static let enlargedGraphHeight: CGFloat = 320

    /// Distinct substances drawn on the timeline — the lane count once the graph
    /// switches to small multiples.
    private var laneCount: Int {
        let curve = substanceStates.map { $0.substanceName.lowercased() }
        let marker = doseMarkers.map { $0.substanceName.lowercased() }
        return Set(curve + marker).count
    }

    /// Timeline height. Overlapping-curve days use the fixed embedded/enlarged
    /// heights; lane-mode days grow with the lane count so each horizon strip
    /// keeps a readable minimum instead of being crushed to a sliver. Clamped so
    /// a very busy day still fits a scrollable card.
    private func graphHeight(enlarged: Bool) -> CGFloat {
        let base = enlarged ? Self.enlargedGraphHeight : GraphMetrics.embedded
        guard laneCount >= TimelineGraphView.laneModeThreshold else { return base }
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
            return ResolvedDay(states: t.states, markers: t.markers, interactions: interactions)
        }
    }

    private var substanceStates: [ActiveSubstanceState] { resolvedDay.states }
    private var doseMarkers: [DoseMarker] { resolvedDay.markers }
    private var dayInteractions: [InteractionResult] { resolvedDay.interactions }

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

    private var cumulativeDoses: [(substance: String, total: Double, unit: String, count: Int)] {
        // Keep the substance's original casing (e.g. "3-Me-PCPy") by remembering
        // the first-seen name per lowercased key — `.capitalized` would mangle it.
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
            ForEach(Array(dayInteractions.enumerated()), id: \.offset) { _, warning in
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

    @ViewBuilder
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
        List {
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
                                        Image(systemName: timelineEnlarged
                                            ? "arrow.down.right.and.arrow.up.left"
                                            : "arrow.up.backward.and.arrow.down.forward")
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
                    Section("\(entries.count) entr\(entries.count == 1 ? "y" : "ies")") {
                        ForEach(entries) { entry in
                            DayEntryRow(
                                entry: entry,
                                color: colorFor(entry),
                                showRelativeTime: isRecentDay,
                                canSplit: entry !== entries.first,
                                onDelete: { deleteEntry(entry) },
                                onAdjustTime: { entryToAdjustTime = entry },
                                onChangeColor: {
                                    colorPickerSubstance = entry.substance
                                    showColorPicker = true
                                },
                                onSplit: { splitSession(at: entry) },
                            )
                        }
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

                            NavigationLink {
                                ComedownGuideView()
                            } label: {
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
                            Image(systemName: "camera")
                        }
                    }
                    .disabled(isExporting)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                sessionMenu
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    navigator.present(.quickLog)
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("Rename Session", isPresented: $showRename) {
            TextField("Session title", text: $titleDraft)
            Button("Cancel", role: .cancel) {}
            Button("Save") { SessionService.setTitle(titleDraft, for: session) }
        }
        .sheet(isPresented: $showNoteEditor) {
            SessionNoteEditor(note: noteDraft) { SessionService.setNote($0, for: session) }
        }
        .sheet(item: $entryToAdjustTime) { entry in
            NavigationStack {
                TimeAdjustSheet(entry: entry)
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showShareSheet) {
            if let image = exportedImage {
                DayLogShareSheet(image: image)
                    .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: $showColorPicker) {
            SubstanceColorPickerView(
                substanceName: colorPickerSubstance,
                takenColors: Array(substanceColors).takenColorMap,
            ) { hex in
                if let existing = substanceColors.first(where: { $0.substance.lowercased() == colorPickerSubstance.lowercased() }) {
                    existing.hexColor = hex
                } else {
                    modelContext.insert(SubstanceColor(substance: colorPickerSubstance, hexColor: hex))
                }
                showColorPicker = false
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
            if let previous = previousSession {
                Divider()
                Button {
                    withAnimation { SessionService.merge(previous, into: session, in: modelContext) }
                } label: {
                    Label("Merge with Previous", systemImage: "arrow.triangle.merge")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    /// Split the session so `entry` and every later dose become a new session.
    private func splitSession(at entry: DoseEntry) {
        withAnimation { SessionService.split(session, at: entry, in: modelContext) }
    }

    private func deleteEntry(_ entry: DoseEntry) {
        let name = entry.substance
        let timestamp = entry.timestamp

        withAnimation {
            modelContext.delete(entry)
        }

        // Also remove from live activity if active
        ActiveSessionManager.shared.removeDose(
            substanceName: name,
            timestamp: timestamp,
            allColors: Array(substanceColors),
        )
    }

    private func colorFor(_ entry: DoseEntry) -> Color {
        Array(substanceColors).colorMap[entry.substance.lowercased()] ?? Theme.accent
    }

    private func colorForName(_ name: String) -> Color {
        Array(substanceColors).colorMap[name.lowercased()] ?? Theme.accent
    }

    private func exportDayLog() {
        isExporting = true
        let entriesCopy = entries.map { entry in
            DayLogImageExporter.EntryData(
                substance: entry.substance,
                amount: entry.amount,
                unit: entry.unit,
                route: entry.route,
                timestamp: entry.timestamp,
                notes: entry.notes,
                tags: entry.tags,
                category: SubstanceLibrary.lookupByNameOrAlias(entry.substance)?.category,
                doseLevel: SubstanceLibrary.lookupByNameOrAlias(entry.substance)?.doseRange(for: entry.route)?.level(for: entry.amount),
                colorHex: Array(substanceColors).hexColorMap[entry.substance.lowercased()],
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
        }
    }
}

/// One dose row in the day detail. Extracted from the inline `ForEach` body so
/// SwiftUI builds (and caches the generic metadata for) a single named row type
/// instead of re-instantiating the deep `NavigationLink`+swipe+contextMenu
/// modifier chain per entry on every list rebuild — which dominated day-view
/// entry as `makeViewList` + `swift_conformsToProtocol` churn.
private struct DayEntryRow: View {
    let entry: DoseEntry
    let color: Color
    let showRelativeTime: Bool
    /// `true` for any dose after the first — splitting "here" leaves doses behind.
    let canSplit: Bool
    let onDelete: () -> Void
    let onAdjustTime: () -> Void
    let onChangeColor: () -> Void
    let onSplit: () -> Void

    @Environment(\.appNavigator) private var navigator

    var body: some View {
        NavigationLink(value: PushRoute.entry(timestamp: entry.timestamp)) {
            EntryRowView(entry: entry, color: color, showRelativeTime: showRelativeTime)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                navigator.present(.entryEdit(timestamp: entry.timestamp))
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.orange)
        }
        .contextMenu {
            Button(action: onAdjustTime) {
                Label("Adjust Time", systemImage: "clock")
            }
            Button(action: onChangeColor) {
                Label("Change Color", systemImage: "paintbrush")
            }
            Button {
                navigator.present(.entryEdit(timestamp: entry.timestamp))
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            if canSplit {
                Button(action: onSplit) {
                    Label("Split Session Here", systemImage: "scissors")
                }
            }
            Divider()
            Button(role: .destructive, action: onDelete) {
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
