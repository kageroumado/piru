import ActivityKit
import SwiftData
import SwiftUI
import TipKit

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
    /// Presents the consolidated "Share Session" sheet (image / PDF / Markdown).
    @State private var showShareSession = false

    /// Selected lens for the session graph. `.timeline` is the classic
    /// per-substance duration view; the mechanistic lenses (Feeling/Energy/Urge/
    /// Safety) appear only when the engine can model the session.
    @State private var effectLens: EffectLens = .timeline
    /// The simulated mechanistic timeline — nil until computed or when the
    /// session contains nothing the engine models.
    @State private var mechanisticResult: MechanisticSessionModel.Result?

    /// Opt-in: overlay Apple Health heart rate / blood pressure on the session.
    /// Stored in the app-group suite so it's consistent app-wide. When off (the
    /// default), no vitals are fetched and nothing about them appears.
    @AppStorage("showSessionVitals", store: UserDefaults(suiteName: "group.dev.yumeji.piru"))
    private var showSessionVitals = false
    /// Apple Health vitals for this session's window (nil until fetched / when empty).
    @State private var sessionVitals: SessionVitals?
    /// Per-dose heart-rate response, keyed by `DoseEntry.id`, for the row chips.
    @State private var doseHR: [UUID: DoseHRResponse] = [:]
    /// Session-wide heart-rate summary for the Summary card.
    @State private var hrSummary: HRSummary?

    /// One-time discovery: users who never enabled the vitals overlay (existing
    /// users who skipped the onboarding Health step, or opted out) get a small
    /// dismissible banner promoting it. Set true once they either turn it on OR
    /// dismiss the banner — after which it never reappears. Main-app UI state, so
    /// the default suite (not the app group) is fine.
    @AppStorage("didOfferSessionVitals") private var didOfferSessionVitals = false
    /// Drives the banner's connect button while its Health sheet is up.
    @State private var isConnectingVitals = false

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

    /// Distinct substances drawn on the timeline — the lane count once the graph
    /// switches to small multiples. Precomputed in ``resolvedDay``; passed to
    /// ``SessionTimelineSection`` for its height calc.
    private var laneCount: Int {
        resolvedDay.laneCount
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
            let mechanisticDoses = Self.computeMechanisticDoses(entries, startDate: session.startDate)
            return ResolvedDay(
                states: t.states,
                markers: t.markers,
                interactions: interactions,
                cumulativeDoses: Self.computeCumulativeDoses(entries),
                laneCount: laneNames.count,
                entryCores: Self.computeEntryCores(entries),
                mechanisticDoses: mechanisticDoses,
                mechanisticSupported: MechanisticSessionModel.supportsMechanisticView(mechanisticDoses),
            )
        }
    }

    /// Each dose reduced to the effect engine's inputs, resolved **once** per
    /// content change alongside the rest of ``ResolvedDay`` — reading it in
    /// `body` (support gate, task signature) must never pay a store lookup.
    /// Doses whose substance isn't in the library are dropped — they can't be
    /// modeled anyway.
    private static func computeMechanisticDoses(_ entries: [DoseEntry], startDate: Date) -> [MechanisticSessionModel.DoseInput] {
        var categoryCache: [String: SubstanceCategory?] = [:]
        func category(_ name: String) -> SubstanceCategory? {
            let key = name.lowercased()
            if let cached = categoryCache[key] { return cached }
            let resolved = SubstanceLibrary.lookupByNameOrAlias(name)?.category
            categoryCache[key] = resolved
            return resolved
        }
        return entries.compactMap { entry in
            guard let category = category(entry.substance) else { return nil }
            return MechanisticSessionModel.DoseInput(
                name: entry.substance,
                category: category,
                amount: entry.amount,
                route: entry.route,
                hours: entry.timestamp.timeIntervalSince(startDate) / 3_600,
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
                // Acute effect window (same source as the timeline curve), so the
                // rail matches the graph — not the long elimination tail.
                totalMinutes: ActiveSubstanceState.from(entry: entry, colorHex: "000000")?.totalMinutes,
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

    // MARK: Mechanistic effect model

    /// Hours from session start to now, for the "now" indicator.
    private var nowHours: Double {
        max(0, Date.now.timeIntervalSince(session.startDate) / 3_600)
    }

    /// Whether the session contains a stimulant/opioid the engine models.
    /// Precomputed with the day resolve — reading it per body costs nothing.
    private var mechanisticSupported: Bool {
        resolvedDay.mechanisticSupported
    }

    /// The lenses to offer in the switcher.
    private var availableLenses: [EffectLens] {
        mechanisticSupported ? [.timeline] + EffectLens.mechanistic : [.timeline]
    }

    /// Cheap: hashes the small, already-memoized dose inputs (which carry no
    /// colour — a recolour must not re-trigger the simulation task).
    private var mechanisticSignature: Int {
        var hasher = Hasher()
        hasher.combine(resolvedDay.mechanisticDoses)
        return hasher.finalize()
    }

    /// Resolve + simulate the session off the main actor, memoized. Runs on any
    /// change to the dose signature.
    private func computeMechanistic() async {
        guard mechanisticSupported else {
            mechanisticResult = nil
            if effectLens != .timeline { effectLens = .timeline }
            return
        }
        let doses = resolvedDay.mechanisticDoses
        let key = mechanisticSignature
        if let cached = MechanisticModelCache.shared.cached(key) {
            mechanisticResult = cached
            return
        }
        let last = doses.map(\.hours).max() ?? 0
        let tMax = min(48, max(12, last + 12))
        let result = await Task.detached { MechanisticSessionModel.compute(doses: doses, tMax: tMax) }.value
        // `.task(id:)` cancels this on a signature change — don't let a stale
        // simulation land after the newer task has already assigned its result.
        guard !Task.isCancelled else { return }
        if let result { MechanisticModelCache.shared.insert(key, result) }
        mechanisticResult = result
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
        !cumulativeDoses.isEmpty || !dayInteractions.isEmpty || hrSummary != nil
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
            Text(CustomSubstanceStore.shared.displayName(for: item.substance))
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

    /// Session-wide heart-rate summary — average / peak, and how it compares to
    /// the user's resting rate when known.
    private func hrSummaryRow(_ summary: HRSummary) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "heart.fill")
                .font(.title3)
                .foregroundStyle(VitalsPalette.heart)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Heart rate")
                        .font(.subheadline.weight(.semibold))
                    Text("avg \(summary.average) · peak \(summary.peak) bpm")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(Theme.secondaryLabel)
                }
                if let resting = summary.resting {
                    Text(
                        summary.average > resting + 3
                            ? "Elevated vs your resting \(resting) bpm"
                            : "In line with your resting \(resting) bpm",
                    )
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
                }
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
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

    // MARK: - Apple Health vitals

    /// Re-runs the vitals fetch when the session changes or the setting is toggled.
    private var vitalsTaskKey: String {
        "\(session.id.uuidString)-\(showSessionVitals)"
    }

    /// End of the window to read vitals over: the latest effect end, extended to
    /// now for a session still in progress today.
    private var vitalsWindowEnd: Date {
        let effectEnd = substanceStates
            .map { $0.doseTimestamp.addingTimeInterval($0.totalMinutes * 60) }
            .max() ?? session.startDate.addingTimeInterval(6 * 3_600)
        return isToday ? max(effectEnd, .now) : effectEnd
    }

    /// Fetch Health vitals for this session and derive the chart overlay, the
    /// per-dose row chips, and the summary — or clear them when disabled. Attempts
    /// the read unconditionally (iOS never reports read access); an empty result
    /// simply leaves everything nil, so nothing about vitals shows.
    private func loadVitals() async {
        let start = session.startDate.addingTimeInterval(-VitalsAnalysis.baselineLookback)
        let end = vitalsWindowEnd
        let fetched = await fetchVitals(from: start, to: end)
        guard !Task.isCancelled else { return }

        sessionVitals = fetched.isEmpty ? nil : fetched
        var responses: [UUID: DoseHRResponse] = [:]
        for entry in entries {
            if let response = VitalsAnalysis.doseResponse(doseAt: entry.timestamp, in: fetched.heartRate) {
                responses[entry.id] = response
            }
        }
        doseHR = responses
        hrSummary = VitalsAnalysis.summary(
            from: session.startDate, to: end,
            heartRate: fetched.heartRate, restingHeartRate: fetched.restingHeartRate,
        )
    }

    private func fetchVitals(from start: Date, to end: Date) async -> SessionVitals {
        #if DEBUG
            // On-simulator visual verification without Health data. Never ships.
            if ProcessInfo.processInfo.arguments.contains("-piruFakeVitals") {
                return DebugVitals.synthetic(doses: entries.map(\.timestamp), start: session.startDate, end: end)
            }
        #endif
        guard showSessionVitals, HealthKitVitals.shared.isAvailable else { return .empty }
        // Pure read — authorization is requested only at the opt-in points (the
        // Apple Health onboarding step, the Apple Health settings screen, and the
        // discovery banner below), never here. Presenting the HealthKit system
        // sheet from inside this already-presented session sheet is a
        // double-presentation conflict: the prompt flashes up and is instantly
        // dismissed, so the request never completes and re-fires on every open.
        // Reading with no access simply returns empty (iOS never reports read
        // status), which renders as nothing on the timeline.
        return await HealthKitVitals.shared.vitals(from: start, to: end)
    }

    // MARK: - Vitals discovery banner

    /// Show the one-time Apple Health promo only when it can actually pay off: the
    /// device has Health, the overlay isn't already on, there's a timeline to lay
    /// vitals over, and we haven't already offered (turned on or dismissed).
    private var shouldOfferVitals: Bool {
        HealthKitVitals.shared.isAvailable
            && !showSessionVitals
            && !didOfferSessionVitals
            && !substanceStates.isEmpty
    }

    /// A dismissible info card (styled like the note row) that introduces the
    /// vitals overlay to users who never opted in — its "Turn On" surfaces the same
    /// single combined Health sheet as everywhere else.
    private var vitalsOfferBanner: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "heart.text.square")
                        .font(.title2)
                        .foregroundStyle(VitalsPalette.heart)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("See your heart rate here")
                            .font(.subheadline.weight(.semibold))
                        Text("Connect Apple Health to overlay how your body responded to each dose — read-only.")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Button(action: dismissVitalsOffer) {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.secondaryLabel)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Dismiss"))
                }
                Button {
                    Task { await enableVitalsFromOffer() }
                } label: {
                    HStack(spacing: 8) {
                        if isConnectingVitals { ProgressView().controlSize(.mini) }
                        Text(isConnectingVitals ? "Connecting…" : "Turn On Apple Health")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.regular)
                .tint(Theme.accent)
                .disabled(isConnectingVitals)
            }
            .padding(.vertical, 4)
        }
    }

    /// Turn the overlay on from the banner: the same single combined Health sheet
    /// (weight + heart rate + blood pressure), then flip the overlay on and record
    /// that we've offered so the banner never returns. Flipping `showSessionVitals`
    /// changes `vitalsTaskKey`, so `loadVitals()` re-runs and the band fills in.
    private func enableVitalsFromOffer() async {
        guard !isConnectingVitals else { return }
        isConnectingVitals = true
        // Skip the request (and its empty-sheet flash) if access is already decided.
        if await HealthKitVitals.shared.connectWouldPrompt() {
            await HealthKitVitals.shared.requestFullAccess()
        }
        _ = await HealthKitBodyMass.shared.syncLatest()
        isConnectingVitals = false
        didOfferSessionVitals = true
        showSessionVitals = true
    }

    /// Dismiss the banner for good — showing it counts as having offered, whether
    /// or not they turned it on.
    private func dismissVitalsOffer() {
        withAnimation(.smooth(duration: 0.25)) { didOfferSessionVitals = true }
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

    /// The lens switcher, pinned above the List (not a grouped-list row) so the
    /// pills run edge-to-edge and clip flat at the screen edges — matching the
    /// Journal tag bar. Only for sessions that offer the mechanistic lenses.
    @ViewBuilder private var lensBar: some View {
        if mechanisticSupported, availableLenses.count > 1 {
            LensBar(lens: $effectLens, lenses: availableLenses, result: mechanisticResult, nowHours: nowHours)
                .background(Theme.background)
        }
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
                        if mechanisticSupported {
                            SessionGraphSection(
                                lens: $effectLens,
                                mechanistic: mechanisticResult,
                                states: substanceStates,
                                markers: doseMarkers,
                                laneCount: laneCount,
                                timelineEnlarged: $timelineEnlarged,
                                isToday: isToday,
                                hasOngoingDose: hasOngoingDose,
                                vitals: sessionVitals,
                                startDate: session.startDate,
                                nowHours: nowHours,
                                onToggleLiveActivity: toggleLiveActivity,
                            )
                        } else {
                            SessionTimelineSection(
                                states: substanceStates,
                                markers: doseMarkers,
                                laneCount: laneCount,
                                graphExpanded: $graphExpanded,
                                timelineEnlarged: $timelineEnlarged,
                                isToday: isToday,
                                hasOngoingDose: hasOngoingDose,
                                vitals: sessionVitals,
                                onToggleLiveActivity: toggleLiveActivity,
                            )
                        }
                    }

                    if shouldOfferVitals {
                        vitalsOfferBanner
                    }

                    if let note = session.note, !note.isEmpty {
                        Section("Note") {
                            Text(note)
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondaryLabel)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(.rect)
                                .onTapGesture { editNote() }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) { deleteNote() } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    Button { editNote() } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(.orange)
                                }
                                .contextMenu {
                                    Button { editNote() } label: {
                                        Label("Edit Note", systemImage: "pencil")
                                    }
                                    Divider()
                                    Button(role: .destructive) { deleteNote() } label: {
                                        Label("Delete Note", systemImage: "trash")
                                    }
                                }
                        }
                    }

                    // Entries
                    let cores = resolvedDay.entryCores
                    let displays = entries.enumerated().map { index, entry in
                        DayEntryDisplay(core: cores[index], color: colorFor(entry), hr: doseHR[entry.id])
                    }
                    SessionEntryListSection(entries: entries, displays: displays, isRecentDay: isRecentDay)

                    // A single "Summary" section folds together the day's derived
                    // signals — interaction warnings (expand in place), cumulative
                    // re-dose totals, and a link to recovery guidance — instead of
                    // three separate stacked sections competing below the log.
                    if hasSummary {
                        Section("Summary") {
                            if !dayInteractions.isEmpty {
                                interactionsDisclosure
                            }

                            if let hrSummary {
                                hrSummaryRow(hrSummary)
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
            .listRowBackground(CardBackground())
        }
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 0, for: .scrollContent)
        .listSectionSpacing(16)
        .safeAreaInset(edge: .top, spacing: 0) { lensBar }
        .background(Theme.background)
        .task(id: colorSignature) {
            colorMap = Array(substanceColors).colorMap
            colorMapReady = true
        }
        .task(id: vitalsTaskKey) { await loadVitals() }
        .task(id: mechanisticSignature) { await computeMechanistic() }
        .navigationTitle(session.title ?? "\(dayOfWeek), \(dateTitle)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !entries.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showShareSession = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel(Text("Share session"))
                }
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
            SessionNoteEditor(text: $noteDraft) { SessionService.setNote($0, for: session) }
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
        .sheet(isPresented: $showShareSession) {
            SessionShareSheet(
                title: session.title ?? "",
                dateText: "\(dayOfWeek), \(dateTitle)",
                entries: entries,
                colors: Array(substanceColors),
                stackRedoses: stackRedoses,
            )
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
                editNote()
            } label: {
                Label(session.note == nil ? "Add Note" : "Edit Note", systemImage: "note.text")
            }
            if !substanceStates.isEmpty {
                Divider()
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.84)) { timelineEnlarged.toggle() }
                } label: {
                    Label(
                        timelineEnlarged ? "Shrink Graph" : "Expand Graph",
                        systemImage: timelineEnlarged ? "arrow.down.right.and.arrow.up.left" : "arrow.up.backward.and.arrow.down.forward",
                    )
                }
                if isToday, hasOngoingDose {
                    let isRunning = LiveActivityManager.shared.isLiveActivityRunning
                    Button {
                        toggleLiveActivity()
                    } label: {
                        Label(
                            isRunning ? "Stop Live Activity" : "Start Live Activity",
                            systemImage: isRunning ? "stop.fill" : "dot.radiowaves.up.forward",
                        )
                    }
                }
            }
            if let pivot = longestBreakPivot {
                Divider()
                Button {
                    withAnimation { editing.split(at: pivot.dose, in: modelContext) }
                } label: {
                    Label(
                        "Split at Longest Break (\(pivot.gapText))",
                        systemImage: "scissors",
                    )
                }
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

    /// The dose immediately after the session's widest interior gap — the pivot a
    /// one-tap "Split at Longest Break" cuts at, mirroring where the clustering
    /// heuristic would break. `nil` when the session has fewer than two doses or
    /// no gap wide enough to be worth splitting (below the always-join floor).
    private var longestBreakPivot: (dose: DoseEntry, gapText: String)? {
        let doses = entries
        guard doses.count > 1 else { return nil }
        var widest: TimeInterval = 0
        var pivotIndex = 0
        for index in 1 ..< doses.count {
            let gap = doses[index].timestamp.timeIntervalSince(doses[index - 1].timestamp)
            if gap > widest {
                widest = gap
                pivotIndex = index
            }
        }
        guard pivotIndex > 0, widest > SessionClustering.Constants.floor else { return nil }
        return (doses[pivotIndex], Self.gapFormatter.string(from: widest) ?? "")
    }

    /// Compact "3h 10m" style formatter for the longest-break label.
    private static let gapFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

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

    /// Open the note editor, seeding the draft from the session's current note.
    /// Shared by the ⋯ menu and the Note row's inline tap / swipe / context edit.
    private func editNote() {
        noteDraft = session.note ?? ""
        showNoteEditor = true
    }

    /// Clear the session's note (row swipe-to-delete / context "Delete Note").
    private func deleteNote() {
        withAnimation { SessionService.setNote("", for: session) }
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
    /// Engine inputs + support gate for the mechanistic lenses, resolved with
    /// the rest of the day so per-body reads never hit the substance store.
    var mechanisticDoses: [MechanisticSessionModel.DoseInput] = []
    var mechanisticSupported: Bool = false
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

// MARK: - Session Detail Sections

/// The day-detail's timeline graph section. Its expand/enlarge state lives on the
/// parent (so the accessory and title stay in sync) and is threaded in as
/// bindings; the live-activity toggle is a parent action.
private struct SessionTimelineSection: View {
    let states: [ActiveSubstanceState]
    let markers: [DoseMarker]
    let laneCount: Int
    @Binding var graphExpanded: Bool
    @Binding var timelineEnlarged: Bool
    let isToday: Bool
    let hasOngoingDose: Bool
    let vitals: SessionVitals?
    let onToggleLiveActivity: () -> Void

    @AppStorage("stackRedoses", store: UserDefaults(suiteName: "group.dev.yumeji.piru")) private var stackRedoses = true
    @AppStorage(LaneModeDefaults.enabledKey, store: UserDefaults(suiteName: LaneModeDefaults.suite)) private var laneModeEnabled = LaneModeDefaults.enabledDefault
    @AppStorage(LaneModeDefaults.thresholdKey, store: UserDefaults(suiteName: LaneModeDefaults.suite)) private var laneModeThreshold = LaneModeDefaults.thresholdDefault

    var body: some View {
        Section {
            if graphExpanded {
                let bandExtra = (vitals?.hasHeartRate == true) ? GraphMetrics.vitalsBandTotal(enlarged: timelineEnlarged) : 0
                AnimatableHeight(height: GraphMetrics.graphHeight(enlarged: timelineEnlarged, laneCount: laneCount, laneModeEnabled: laneModeEnabled, laneModeThreshold: laneModeThreshold) + bandExtra) {
                    TimelineGraphView(
                        substances: states,
                        currentTime: .now,
                        compact: false,
                        markers: markers,
                        stackRedoses: stackRedoses,
                        dayBounded: true,
                        vitals: vitals,
                        vitalsBandEnlarged: timelineEnlarged,
                        focusAroundNow: hasOngoingDose,
                        synchronous: true,
                    )
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.84), value: timelineEnlarged)
                // Tight insets scoped to the graph row alone so it spans nearly
                // edge-to-edge; the header/footer keep the List's default inset.
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
                        onToggleLiveActivity()
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
                    .popoverTip(isRunning ? nil : LiveActivityTip())
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
                Text("Slide to move, pinch to zoom, hold to inspect")
            }
        }
    }
}

/// The modeled-session graph section: one lens at a time (classic Timeline or a
/// mechanistic effect curve) in the app's grouped style, with the lens pills
/// *below* the graph, a shared enlarge control, and the drag hint as the footer.
/// Both graphs are sized from ``GraphMetrics`` so switching lenses never resizes.
private struct SessionGraphSection: View {
    @Binding var lens: EffectLens
    let mechanistic: MechanisticSessionModel.Result?
    let states: [ActiveSubstanceState]
    let markers: [DoseMarker]
    let laneCount: Int
    @Binding var timelineEnlarged: Bool
    let isToday: Bool
    let hasOngoingDose: Bool
    let vitals: SessionVitals?
    let startDate: Date
    let nowHours: Double
    let onToggleLiveActivity: () -> Void

    @AppStorage("stackRedoses", store: UserDefaults(suiteName: "group.dev.yumeji.piru")) private var stackRedoses = true
    @AppStorage(LaneModeDefaults.enabledKey, store: UserDefaults(suiteName: LaneModeDefaults.suite)) private var laneModeEnabled = LaneModeDefaults.enabledDefault
    @AppStorage(LaneModeDefaults.thresholdKey, store: UserDefaults(suiteName: LaneModeDefaults.suite)) private var laneModeThreshold = LaneModeDefaults.thresholdDefault

    private var height: CGFloat {
        GraphMetrics.graphHeight(enlarged: timelineEnlarged, laneCount: laneCount, laneModeEnabled: laneModeEnabled, laneModeThreshold: laneModeThreshold)
    }

    var body: some View {
        // The lens pills are lifted out of the List into a pinned top bar (see the
        // host's `.safeAreaInset`), so they can run edge-to-edge without the
        // grouped-list inset + rounded-corner clip.

        // Graph card — fills the card vertically; only the L/R edges are inset.
        // Expand & Live Activity moved to the toolbar menu so they don't sit on
        // top of the (small) graph.
        Section {
            AnimatableHeight(height: height) { graph }
                .animation(.spring(response: 0.4, dampingFraction: 0.84), value: timelineEnlarged)
                // Full-bleed the canvas to the card edge so continuous curves run
                // edge to edge. A grouped List ignores `leading: 0` (it falls back
                // to the ~20pt content margin), so a 0.5pt epsilon is the reliable
                // way to reach the card edge.
                .listRowInsets(EdgeInsets(top: 0, leading: 0.5, bottom: 0, trailing: 0.5))
                .listRowSeparator(.hidden)
        } footer: {
            // The classic timeline supports hold-to-inspect; the mechanistic
            // lenses don't, so only mention it for the timeline graph.
            if lens == .timeline || mechanistic == nil {
                Text("Slide to move, pinch to zoom, hold to inspect")
            } else {
                Text("Slide to move, pinch to zoom")
            }
        }

        if lens.pairsVitals, let vitals, !vitals.isEmpty {
            Section {
                MechanisticVitalsCards(vitals: vitals, startDate: startDate, nowHours: nowHours)
                    .listRowInsets(EdgeInsets(top: 0, leading: GraphMetrics.cardInset, bottom: 2, trailing: GraphMetrics.cardInset))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
    }

    @ViewBuilder private var graph: some View {
        if lens == .timeline || mechanistic == nil {
            TimelineGraphView(
                substances: states,
                currentTime: .now,
                compact: false,
                markers: markers,
                stackRedoses: stackRedoses,
                dayBounded: true,
                vitals: nil,
                vitalsBandEnlarged: timelineEnlarged,
                focusAroundNow: hasOngoingDose,
                synchronous: true,
            )
        } else if let result = mechanistic {
            MechanisticChartView(result: result, lens: lens, startDate: startDate, nowHours: nowHours, doseMarks: doseMarks, vitals: vitals)
        }
    }

    /// Dose ticks for the mechanistic chart: every logged dose — the curve-backed
    /// ones (`states`, one per dose) plus the duration-less ones (`markers`, which
    /// hold ONLY doses without curves). Built at the render site so a recolour
    /// updates the tick colours without invalidating the simulation cache. The
    /// earliest mark also anchors the chart's scrollable extent.
    private var doseMarks: [MechanisticSessionModel.DoseMark] {
        let curveDoses = states.map { (timestamp: $0.doseTimestamp, colorHex: $0.colorHex) }
        let markerDoses = markers.map { (timestamp: $0.timestamp, colorHex: $0.colorHex) }
        return (curveDoses + markerDoses).map {
            MechanisticSessionModel.DoseMark(
                hours: $0.timestamp.timeIntervalSince(startDate) / 3_600,
                colorHex: $0.colorHex,
            )
        }
    }
}

/// The day-detail's dose-row list. Takes value inputs only — `entries` for the
/// row actions, prebuilt `displays` for rendering — so it skips re-evaluation
/// when the parent re-runs for graph-state toggles.
private struct SessionEntryListSection: View {
    let entries: [DoseEntry]
    let displays: [DayEntryDisplay]
    let isRecentDay: Bool

    var body: some View {
        Section {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                DayEntryRow(
                    entry: entry,
                    display: displays[index],
                    showRelativeTime: isRecentDay,
                    canSplit: index != 0,
                )
                .equatable()
            }
        }
    }
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
        // A plain Button (not a NavigationLink) so the disclosure chevron lives
        // inside the row, aligned with the dose, rather than system-centred on the
        // full row height. Tighter vertical insets than the grouped default.
        Button {
            navigator.push(.entry(timestamp: display.core.timestamp, id: display.core.entryID))
        } label: {
            EntryRowView(display: display, showRelativeTime: showRelativeTime)
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
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
    /// Bound to the caller's scratch draft (seeded from `session.note` before the
    /// sheet opens). Binding — not a re-seeded `@State` — so the existing note is
    /// always present on re-open; Cancel simply discards the unsaved draft.
    @Binding var text: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    /// The rounded, padded editor ground — concentric with the sheet, matching
    /// the share sheet's card language.
    private var editorShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .focused($focused)
                .scrollContentBackground(.hidden)
                .padding(12)
                .background { editorShape.fill(.thickMaterial) }
                .overlay(editorShape.stroke(Color.primary.opacity(0.08), lineWidth: 1))
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background)
                .navigationTitle("Session Note")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark").font(.body.weight(.semibold))
                        }
                        .accessibilityLabel(Text("Cancel"))
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            onSave(text)
                            dismiss()
                        } label: {
                            Image(systemName: "checkmark").font(.body.weight(.semibold))
                        }
                        .buttonStyle(.glassProminent)
                        .tint(Theme.accent)
                        .accessibilityLabel(Text("Save"))
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { focused = true }
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
                                Text(CustomSubstanceStore.shared.displayName(for: dose.substance))
                                    .font(.headline)
                                Spacer()
                                Text("\(dose.amount.doseFormatted) \(dose.unit)")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.secondaryLabel)
                            }
                            .listRowBackground(CardBackground())
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
                                .listRowBackground(CardBackground())
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
                                    .listRowBackground(CardBackground())
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
                Text("\(CustomSubstanceStore.shared.displayName(for: dose.substance)) is logged on a different day. Pick a time within this session's day so the session stays a single day.")
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

#if DEBUG
    /// Synthetic vitals for on-simulator visual verification, gated behind the
    /// `-piruFakeVitals` launch argument. Never compiled into release builds. HR
    /// rises after each dose (stimulant/alcohol tachycardia) with a little wobble,
    /// plus a couple of blood-pressure spot checks.
    private enum DebugVitals {
        static func synthetic(doses: [Date], start: Date, end: Date) -> SessionVitals {
            let totalMinutes = end.timeIntervalSince(start) / 60
            guard totalMinutes > 0 else { return .empty }

            func smoothstep(_ x: Double) -> Double {
                let c = max(0, min(1, x))
                return c * c * (3 - 2 * c)
            }
            func bump(_ t: Double, at t0: Double, rise: Double, fall: Double) -> Double {
                guard t >= t0 else { return 0 }
                let x = t - t0
                return x < rise ? smoothstep(x / rise) : exp(-(x - rise) / fall)
            }

            let doseMinutes = doses.map { $0.timeIntervalSince(start) / 60 }
            var heartRate: [HeartRateSample] = []
            var minute = -VitalsAnalysis.baselineLookback / 60
            var index = 0
            while minute <= totalMinutes {
                var bpm = 64 - 0.01 * minute
                for (position, dose) in doseMinutes.enumerated() {
                    bpm += Double(9 + position * 4) * bump(minute, at: dose, rise: 30, fall: 160)
                }
                bpm += 2.4 * sin(Double(index) * 1.7) + 1.6 * sin(Double(index) * 0.9)
                heartRate.append(HeartRateSample(date: start.addingTimeInterval(minute * 60), bpm: bpm))
                minute += 5
                index += 1
            }

            var bloodPressure: [BloodPressureReading] = []
            if let first = doseMinutes.first {
                bloodPressure.append(BloodPressureReading(date: start.addingTimeInterval((first + 8) * 60), systolic: 118, diastolic: 76))
            }
            if totalMinutes > 90 {
                bloodPressure.append(BloodPressureReading(date: start.addingTimeInterval(totalMinutes * 0.5 * 60), systolic: 129, diastolic: 83))
            }
            return SessionVitals(heartRate: heartRate, bloodPressure: bloodPressure, restingHeartRate: 62)
        }
    }
#endif
