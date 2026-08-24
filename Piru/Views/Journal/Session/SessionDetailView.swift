import ActivityKit
import SwiftData
import SwiftUI
import TipKit

struct SessionDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.sessionEditingService) private var editing
    @Environment(\.scenePhase) private var scenePhase
    let session: Session
    @Query private var substanceColors: [SubstanceColor]

    /// Async-loaded data (color map, vitals, mechanistic simulation) — see
    /// ``SessionDetailModel``. Filled from the `.task`s below so a load lands only
    /// on the sections that read it, and this view's own `@State` stays limited to
    /// edit/UI concerns.
    @State private var model = SessionDetailModel()

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

    @State private var showRename = false
    @State private var titleDraft = ""
    @State private var showNoteEditor = false
    @State private var noteDraft = ""
    /// Grows the inline timeline in place: the graph's frame steps up to a taller
    /// height and the List reflows the entries below it — no separate fullscreen
    /// sheet, no overlay. Every gesture stays the same; the curves just get room.
    ///
    /// Persisted so a user who prefers the enlarged graph keeps it across every
    /// session and app launch. Mirrored by the "Expand Session Graph" toggle in
    /// Journal settings.
    @AppStorage(SessionGraphDefaults.enlargedKey, store: UserDefaults(suiteName: SessionGraphDefaults.suite))
    private var timelineEnlarged = SessionGraphDefaults.enlargedDefault
    /// Presents the consolidated "Share Session" sheet (image / PDF / Markdown).
    @State private var showShareSession = false

    /// Opt-in: overlay Apple Health heart rate / blood pressure on the session.
    /// Stored in the app-group suite so it's consistent app-wide. Drives the vitals
    /// task and the discovery-banner gate.
    @AppStorage("showSessionVitals", store: UserDefaults(suiteName: "group.dev.yumeji.piru"))
    private var showSessionVitals = false
    /// One-time discovery: whether the vitals overlay has already been offered
    /// (turned on or dismissed). Gates the discovery banner.
    @AppStorage("didOfferSessionVitals") private var didOfferSessionVitals = false

    private var colorSignature: Int {
        var hasher = Hasher()
        for color in substanceColors {
            hasher.combine(color.substance)
            hasher.combine(color.hexColor)
        }
        return hasher.finalize()
    }

    /// Distinct substances drawn on the timeline once the graph switches to
    /// small multiples, split by lane kind: curve lanes need room for a hump,
    /// pin-only lanes need a strip. Precomputed in ``resolvedDay``; passed to
    /// ``SessionTimelineSection`` for its height calc, which must reach the same
    /// answer the renderer does.
    private var curveLaneCount: Int {
        resolvedDay.curveLaneCount
    }

    private var markerLaneCount: Int {
        resolvedDay.markerLaneCount
    }

    /// The day's resolved timeline + interaction warnings, derived **synchronously
    /// and memoized** (see ``DayResolveCache``) per change to the day's
    /// entries/colors. Resolving a single day is cheap — a handful of
    /// `SubstanceLibrary` lookups plus one batch interaction check — so the prior
    /// async `.task` resolve bought nothing but a structural cost: `substanceStates`
    /// and `dayInteractions` started empty, so the `if !…isEmpty` Sections *flipped
    /// in* after the first frame, rebuilding the List content on every open.
    /// Computing up front keeps the view tree's shape fixed from frame 1 — no flip.
    private var resolvedDay: ResolvedDay {
        DayResolveCache.shared.resolve(signature: timelineSignature) {
            let t = ActiveSubstanceState.timeline(for: entries, colors: Array(substanceColors))
            let names = Array(Set(entries.map(\.substance)))
            let interactions = names.count >= 2 ? InteractionChecker.checkBatch(names, against: []) : []
            // The measured layer. Every row here cites a study; matching is
            // canonical-name only, so a row naming a class ("CYP3A4 inhibitors")
            // stays on its own substance page rather than being inferred onto a
            // logged drug.
            let active = InteractionChecker.activeEntries(from: entries)
            var pkFindings: [PKInteractionFinding] = []
            var seenPK: Set<Int64> = []
            for name in names {
                for finding in InteractionChecker.pharmacokineticInteractions(name, against: active)
                    where seenPK.insert(finding.id).inserted {
                    pkFindings.append(finding)
                }
            }
            // Mirrors the renderer's own split: a marker lane exists only for a
            // substance with no curve lane (``markerOnlyLanes(excluding:)``).
            let curveNames = Set(t.states.map { $0.substanceName.lowercased() })
            let markerNames = Set(t.markers.map { $0.substanceName.lowercased() })
                .subtracting(curveNames)
            let mechanisticDoses = Self.computeMechanisticDoses(entries, startDate: session.startDate)
            let mechanisticPharmacology = Self.resolveMechanisticPharmacology(mechanisticDoses)
            return ResolvedDay(
                states: t.states,
                markers: t.markers,
                interactions: interactions,
                pkFindings: pkFindings,
                curveLaneCount: curveNames.count,
                markerLaneCount: markerNames.count,
                entryCores: Self.computeEntryCores(entries),
                mechanisticDoses: mechanisticDoses,
                mechanisticSupported: MechanisticSessionModel.supportsMechanisticView(mechanisticDoses, pharmacology: mechanisticPharmacology),
                mechanisticPharmacology: mechanisticPharmacology,
            )
        }
    }

    /// Each dose reduced to the effect engine's inputs, resolved **once** per
    /// content change alongside the rest of ``ResolvedDay`` — reading it in
    /// `body` (support gate, task signature) must never pay a store lookup.
    /// Doses whose substance isn't in the library are dropped — they can't be
    /// modeled anyway.
    private static func computeMechanisticDoses(_ entries: [DoseEntry], startDate: Date) -> [MechanisticSessionModel.DoseInput] {
        var inLibraryCache: [String: Bool] = [:]
        func inLibrary(_ name: String) -> Bool {
            let key = name.lowercased()
            if let cached = inLibraryCache[key] { return cached }
            let resolved = SubstanceLibrary.timelineLookup(name) != nil
            inLibraryCache[key] = resolved
            return resolved
        }
        return entries.compactMap { entry in
            guard inLibrary(entry.substance) else { return nil }
            // The effect engine models absorption from the route's profile, which
            // is the immediate-release one — so an extended-release dose would be
            // simulated as if it landed all at once, and the whole session's
            // estimate would inherit that. A dose whose form we decline to model
            // is left out rather than modelled wrong.
            guard !entry.namesUnmodeledForm else { return nil }
            return MechanisticSessionModel.DoseInput(
                name: entry.substance,
                amount: entry.amount,
                route: entry.route,
                hours: entry.timestamp.timeIntervalSince(startDate) / 3_600,
            )
        }
    }

    /// Resolve each distinct substance's PK + binding from the bundled pharmacology
    /// DB, keyed by normalized name. Runs with the rest of the day resolve (main
    /// actor, memoized), so the engine's per-substance params are data-driven
    /// without a store lookup in `body` or in the off-main simulation.
    private static func resolveMechanisticPharmacology(_ doses: [MechanisticSessionModel.DoseInput]) -> [String: PharmacologyParameters] {
        var result: [String: PharmacologyParameters] = [:]
        for dose in doses {
            let key = SubstanceModelDatabase.normalize(dose.name)
            if result[key] == nil {
                result[key] = SubstanceStore.shared.pharmacologyParameters(forSubstanceName: dose.name)
            }
        }
        return result
    }

    /// Resolve each dose row's substance facts once — see ``DayEntryCore/make(from:)``,
    /// which the journal's rows share.
    private static func computeEntryCores(_ entries: [DoseEntry]) -> [DayEntryCore] {
        DayEntryCore.make(from: entries)
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

    /// The line to show where the timeline would be when the session names a form
    /// the app declines to model (``DoseEntry/namesUnmodeledForm``) — a Concerta, a
    /// depot injection. `nil` when nothing here needs explaining. Runs only over
    /// the (rare, few) unmodeled doses, so it costs nothing on an ordinary session.
    private var unmodeledFormNote: UnmodeledFormNote.Content? {
        // Only doses that truly draw nothing — a named ER product with an authored
        // envelope (Concerta) now draws a real curve, so it isn't "unmodeled" here.
        let unmodeled = entries.filter(\.drawsNoAcuteCurve)
        guard !unmodeled.isEmpty else { return nil }
        var seen = Set<String>()
        var pairs: [(product: String, base: String)] = []
        for entry in unmodeled {
            let base = SubstanceLibrary.timelineLookup(entry.substance)?.name ?? entry.substance
            let product = DoseTitle.resolve(for: entry)
            if seen.insert(product.lowercased() + "\u{1}" + base.lowercased()).inserted {
                pairs.append((product, base))
            }
        }
        // Name the form only when there's exactly one and its title isn't just the
        // base with a suffix — "the Methylphenidate XR form of Methylphenidate"
        // reads badly, so that (and any multi-form session) gets the neutral line.
        if pairs.count == 1, !pairs[0].product.localizedCaseInsensitiveContains(pairs[0].base) {
            return .named(product: pairs[0].product, base: pairs[0].base)
        }
        return .generic
    }

    // MARK: - Mechanistic effect model

    /// Hours from session start to now, for the "now" indicator.
    private var nowHours: Double {
        max(0, Date.now.timeIntervalSince(session.startDate) / 3_600)
    }

    /// Whether the session contains a stimulant/opioid the engine models.
    /// Precomputed with the day resolve — reading it per body costs nothing.
    private var mechanisticSupported: Bool {
        resolvedDay.mechanisticSupported
    }

    /// Dose ticks for the mechanistic charts: every logged dose — the curve-backed
    /// ones (`substanceStates`, one per dose) plus the duration-less ones
    /// (`doseMarkers`). Built at the render site so a recolor updates the tick
    /// colors without invalidating the simulation cache.
    private var mechanisticDoseMarks: [MechanisticSessionModel.DoseMark] {
        let curveDoses = substanceStates.map { (timestamp: $0.doseTimestamp, colorHex: $0.colorHex) }
        let markerDoses = doseMarkers.map { (timestamp: $0.timestamp, colorHex: $0.colorHex) }
        return (curveDoses + markerDoses).map {
            MechanisticSessionModel.DoseMark(
                hours: $0.timestamp.timeIntervalSince(session.startDate) / 3_600,
                colorHex: $0.colorHex,
            )
        }
    }

    /// Split the session's distinct substances into those the engine models
    /// (they shape the curves) and those it can't (silently dropped) — the
    /// coverage disclaimer's data. Display names, in first-seen order.
    private var mechanisticPartition: (modeled: [String], ignored: [String]) {
        var seen = Set<String>()
        var modeled: [String] = []
        var ignored: [String] = []
        for entry in entries {
            guard seen.insert(entry.substance.lowercased()).inserted else { continue }
            let display = CustomSubstanceStore.shared.displayName(for: entry.substance)
            let key = SubstanceModelDatabase.normalize(entry.substance)
            // "Modeled" == what `compute` actually simulates: any substance whose params
            // resolve (DB-derived or curated-override-only, e.g. PPAP/BPAP), not just those
            // with a DB pharmacology row.
            if SubstanceModelDatabase.params(name: entry.substance, pharmacology: resolvedDay.mechanisticPharmacology[key]) != nil {
                modeled.append(display)
            } else {
                ignored.append(display)
            }
        }
        return (modeled, ignored)
    }

    /// Cheap: hashes the small, already-memoized dose inputs (which carry no
    /// color — a recolor must not re-trigger the simulation task).
    private var mechanisticSignature: Int {
        var hasher = Hasher()
        hasher.combine(resolvedDay.mechanisticDoses)
        return hasher.finalize()
    }

    /// Content fingerprint of the day's doses + color count — the memo key, so
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

    /// The substance→color map for child sections: the warm cached map, or a
    /// direct build on the first frame before `.task(id: colorSignature)` lands
    /// (same warm-up story as ``resolvedColor``).
    private var activeColorMap: [String: Color] {
        model.colorMapReady || !model.colorMap.isEmpty ? model.colorMap : Array(substanceColors).colorMap
    }

    /// The guided comedown categories present in this session, first-seen order —
    /// the Recovery section's rows. Empty when nothing logged maps to a category
    /// with dedicated guidance (then the section falls back to a plain link).
    private var sessionRecoveryCategories: [SubstanceCategory] {
        var seen = Set<SubstanceCategory>()
        var result: [SubstanceCategory] = []
        for entry in entries {
            guard let category = SubstanceLibrary.timelineLookup(entry.substance)?.category,
                  ComedownGuideView.guidedCategories.contains(category),
                  seen.insert(category).inserted else { continue }
            result.append(category)
        }
        return result
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

    /// Re-runs the vitals fetch when the session changes, the setting is toggled,
    /// or the app comes back to the foreground.
    ///
    /// The scene phase is part of the key rather than a separate `onChange`
    /// because a `.task(id:)` already owns this fetch: returning to the app is
    /// just another reason the answer went stale. There is no HealthKit observer
    /// query anywhere in the app, so a reading taken on the Watch while Piru was
    /// backgrounded has no other way in — before this, the only cure was leaving
    /// the screen and coming back.
    private var vitalsTaskKey: String {
        "\(session.id.uuidString)-\(showSessionVitals)-\(scenePhase == .active)"
    }

    /// End of the window to read vitals over: the latest effect end, extended to
    /// now for a session still in progress today.
    private var vitalsWindowEnd: Date {
        let effectEnd = substanceStates
            .map { $0.doseTimestamp.addingTimeInterval($0.totalMinutes * 60) }
            .max() ?? session.startDate.addingTimeInterval(6 * 3_600)
        return isToday ? max(effectEnd, .now) : effectEnd
    }

    /// Show the one-time Apple Health promo only when it can actually pay off: the
    /// device has Health, the overlay isn't already on, there's a timeline to lay
    /// vitals over, and we haven't already offered (turned on or dismissed).
    private var shouldOfferVitals: Bool {
        HealthKitVitals.shared.isAvailable
            && !showSessionVitals
            && !didOfferSessionVitals
            && !substanceStates.isEmpty
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
                        SessionTimelineSection(
                            states: substanceStates,
                            markers: doseMarkers,
                            curveLaneCount: curveLaneCount,
                            markerLaneCount: markerLaneCount,
                            timelineEnlarged: $timelineEnlarged,
                            hasOngoingDose: hasOngoingDose,
                            vitals: model.sessionVitals,
                        )
                    }

                    // Where the curve is withheld: a Concerta-only day drops the
                    // timeline entirely, and a mixed day shows one only for the
                    // doses it can model. Either way, say why the unmodeled dose is
                    // just a dot rather than leaving a conspicuous gap.
                    if let unmodeledFormNote {
                        UnmodeledFormNote(content: unmodeledFormNote)
                    }

                    // Effect Estimates — the mechanistic model as its own graph
                    // section between the timeline and the doses. A gateway card
                    // (preview + caveat) pushing to the dedicated multi-lens
                    // screen, shown only once the engine has modeled the session.
                    if mechanisticSupported, let mechanisticResult = model.mechanisticResult {
                        let partition = mechanisticPartition
                        EffectEstimatesCard(
                            result: mechanisticResult,
                            startDate: session.startDate,
                            nowHours: nowHours,
                            doseMarks: mechanisticDoseMarks,
                            vitals: model.sessionVitals,
                            modeled: partition.modeled,
                            ignored: partition.ignored,
                        )
                    }

                    if shouldOfferVitals {
                        VitalsOfferBanner()
                    }

                    if let note = session.note, !note.isEmpty {
                        Section("Note") {
                            Text(note)
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondaryLabel)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(.rect)
                                .onTapGesture { editNote() }
                                .accessibilityAddTraits(.isButton)
                                .accessibilityHint(Text("Edits the note"))
                                .accessibilityAction(named: Text("Edit Note")) { editNote() }
                                .accessibilityAction(named: Text("Delete Note")) { deleteNote() }
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

                    let cores = resolvedDay.entryCores
                    let displays = entries.enumerated().map { index, entry -> DayEntryDisplay in
                        let hr = model.doseHR[entry.id]
                        return DayEntryDisplay(
                            core: cores[index], color: colorFor(entry), hr: hr,
                            confounderColors: (hr?.confounders ?? []).map { resolvedColor($0) },
                        )
                    }
                    SessionEntryListSection(entries: entries, displays: displays, isRecentDay: isRecentDay)

                    // In Your Body — per-substance session totals merged with the
                    // live elimination model (what's still circulating, clearance
                    // projections, the curve on tap). Replaces the bare cumulative
                    // totals: a total is just the "dosed" side of body load.
                    SessionBodyLoadSection(entries: entries, colorMap: activeColorMap)

                    // Safety — interaction warnings shown in full plus a heart-rate
                    // summary. Headerless; the severity-tinted interaction rows
                    // already name it.
                    SessionSafetySection(
                        interactions: dayInteractions,
                        pkFindings: resolvedDay.pkFindings,
                        hrSummary: model.hrSummary,
                    )

                    // Recovery — per-category comedown guidance for what this
                    // session actually contained, plus a link into the full guide.
                    SessionRecoverySection(categories: sessionRecoveryCategories)
                }
            }
            .listRowBackground(CardBackground())
        }
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 0, for: .scrollContent)
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .listSectionSpacing(16)
        .background(Theme.background)
        .task(id: colorSignature) {
            model.loadColorMap(colors: substanceColors)
        }
        .task(id: vitalsTaskKey) {
            await model.loadVitals(session: session, entries: entries, windowEnd: vitalsWindowEnd, showSessionVitals: showSessionVitals)
        }
        .task(id: mechanisticSignature) {
            await SubstanceStore.shared.ensureAllLoaded()
            await model.computeMechanistic(
                supported: mechanisticSupported,
                doses: resolvedDay.mechanisticDoses,
                pharmacology: resolvedDay.mechanisticPharmacology,
                signature: mechanisticSignature,
            )
        }
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
                    .popoverTip(ShareSessionTip())
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                SessionMenu(
                    session: session,
                    hasCurves: !substanceStates.isEmpty,
                    isToday: isToday,
                    hasOngoingDose: hasOngoingDose,
                    longestBreakPivot: longestBreakPivot,
                    onRename: {
                        titleDraft = session.title ?? ""
                        showRename = true
                    },
                    onEditNote: editNote,
                    onToggleLiveActivity: toggleLiveActivity,
                )
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
                doseHR: model.doseHR,
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

    /// Row tint for a substance. Reads the cached `colorMap` once it's warm; on
    /// the very first frame — before `.task(id: colorSignature)` populates it —
    /// falls back to a direct resolve so the dots don't flash from the accent
    /// tint to their real color. The fallback pays the full map build for that
    /// one frame only; once `colorMapReady` flips, a miss means the substance
    /// genuinely has no assigned color, so it returns the accent without
    /// rebuilding the map every body pass.
    private func resolvedColor(_ name: String) -> Color {
        let key = name.lowercased()
        if let color = model.colorMap[key] { return color }
        guard !model.colorMapReady else { return Theme.accent }
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
    /// Measured exposure changes between two things actually logged here —
    /// `drug_interactions_pk` rows resolved against the day's entries. Kept
    /// apart from `interactions`: those rank danger, these report a number.
    var pkFindings: [PKInteractionFinding] = []
    /// Distinct timeline lanes by kind, precomputed so `graphHeight` doesn't
    /// rebuild two name Sets on every height-animation frame.
    var curveLaneCount: Int = 0
    var markerLaneCount: Int = 0
    /// Render-ready, substance-resolved facts for each dose row, in `entries`
    /// order. Built here (once per content change) so the heavy per-row resolve
    /// — `SubstanceLibrary` lookup + dose-level classification + display-name
    /// override — never runs in a row `body`.
    var entryCores: [DayEntryCore] = []
    /// Engine inputs + support gate for the mechanistic lenses, resolved with
    /// the rest of the day so per-body reads never hit the substance store.
    var mechanisticDoses: [MechanisticSessionModel.DoseInput] = []
    var mechanisticSupported: Bool = false
    /// Resolved per-substance PK + binding (keyed by normalized name), fetched from
    /// the bundled pharmacology DB once per content change so the engine's per-substance
    /// params (`ke`/`ka`/transporter weights/`releaser`) are data-driven. The off-main
    /// simulation and the support gate both read this.
    var mechanisticPharmacology: [String: PharmacologyParameters] = [:]
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
