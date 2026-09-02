import ActivityKit
import SwiftData
import SwiftUI
import TipKit

struct SessionDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.sessionEditingService) private var editing
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appNavigator) private var navigator
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

    /// Everything the sections read, resolved once per content change — see
    /// ``SessionResolveModel``.
    private var resolvedDay: ResolvedDay {
        SessionResolveModel.resolvedDay(
            entries: entries,
            colors: Array(substanceColors),
            startDate: session.startDate,
            signature: SessionResolveModel.timelineSignature(entries: entries, colorCount: substanceColors.count),
        )
    }

    // MARK: - Mechanistic effect model

    /// Hours from session start to now, for the "now" indicator.
    private var nowHours: Double {
        max(0, Date.now.timeIntervalSince(session.startDate) / 3_600)
    }

    /// Dose ticks for the mechanistic charts: every logged dose — the curve-backed
    /// ones (one per dose) plus the duration-less markers. Built at the render site
    /// so a recolor updates the tick colors without invalidating the simulation cache.
    private func mechanisticDoseMarks(_ day: ResolvedDay) -> [MechanisticSessionModel.DoseMark] {
        let curveDoses = day.states.map { (timestamp: $0.doseTimestamp, colorHex: $0.colorHex) }
        let markerDoses = day.markers.map { (timestamp: $0.timestamp, colorHex: $0.colorHex) }
        return (curveDoses + markerDoses).map {
            MechanisticSessionModel.DoseMark(
                hours: $0.timestamp.timeIntervalSince(session.startDate) / 3_600,
                colorHex: $0.colorHex,
            )
        }
    }

    /// The substance→color map for child sections: the warm cached map, or a
    /// direct build on the first frame before `.task(id: colorSignature)` lands
    /// (same warm-up story as ``resolvedColor``).
    private var activeColorMap: [String: Color] {
        model.colorMapReady || !model.colorMap.isEmpty ? model.colorMap : Array(substanceColors).colorMap
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
    private func vitalsWindowEnd(_ states: [ActiveSubstanceState]) -> Date {
        let effectEnd = states
            .map { $0.doseTimestamp.addingTimeInterval($0.totalMinutes * 60) }
            .max() ?? session.startDate.addingTimeInterval(6 * 3_600)
        return isToday ? max(effectEnd, .now) : effectEnd
    }

    /// Show the one-time Apple Health promo only when it can actually pay off: the
    /// device has Health, the overlay isn't already on, there's a timeline to lay
    /// vitals over, and we haven't already offered (turned on or dismissed).
    private func shouldOfferVitals(_ states: [ActiveSubstanceState]) -> Bool {
        HealthKitVitals.shared.isAvailable
            && !showSessionVitals
            && !didOfferSessionVitals
            && !states.isEmpty
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
    private func hasOngoingDose(_ states: [ActiveSubstanceState]) -> Bool {
        let now = Date.now
        return states.contains { now < $0.doseTimestamp.addingTimeInterval($0.totalMinutes * 60) }
    }

    var body: some View {
        @Bindable var editing = editing
        let day = resolvedDay
        let ongoing = hasOngoingDose(day.states)
        let mechanisticSignature = SessionResolveModel.mechanisticSignature(doses: day.mechanisticDoses)
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
                    if !day.states.isEmpty {
                        SessionTimelineSection(
                            states: day.states,
                            markers: day.markers,
                            curveLaneCount: day.curveLaneCount,
                            markerLaneCount: day.markerLaneCount,
                            timelineEnlarged: $timelineEnlarged,
                            hasOngoingDose: ongoing,
                            vitals: model.sessionVitals,
                            noteMarkers: SessionResolveModel.noteMarkers(notes: session.orderedNotes),
                            onNoteTap: { id in navigator.present(.sessionNoteEditor(sessionID: session.id, noteID: id)) },
                        )
                    }

                    // Where the curve is withheld: a Concerta-only day drops the
                    // timeline entirely, and a mixed day shows one only for the
                    // doses it can model. Either way, say why the unmodeled dose is
                    // just a dot rather than leaving a conspicuous gap.
                    if let note = SessionResolveModel.unmodeledFormNote(entries: entries) {
                        UnmodeledFormNote(content: note)
                    }

                    // Effect Estimates — the mechanistic model as its own graph
                    // section between the timeline and the doses. A gateway card
                    // (preview + caveat) pushing to the dedicated multi-lens
                    // screen, shown only once the engine has modeled the session.
                    if day.mechanisticSupported, let mechanisticResult = model.mechanisticResult {
                        let partition = SessionResolveModel.mechanisticPartition(
                            entries: entries, pharmacology: day.mechanisticPharmacology,
                        )
                        EffectEstimatesCard(
                            result: mechanisticResult,
                            startDate: session.startDate,
                            nowHours: nowHours,
                            doseMarks: mechanisticDoseMarks(day),
                            vitals: model.sessionVitals,
                            modeled: partition.modeled,
                            ignored: partition.ignored,
                        )
                    }

                    if shouldOfferVitals(day.states) {
                        VitalsOfferBanner()
                    }

                    if CheckInScheduler.shouldOffer(session: session, hasOngoingDose: ongoing) {
                        CheckInOfferBanner(session: session)
                    }

                    let notes = session.orderedNotes
                    SessionEntryListSection(
                        entries: entries, displays: entryDisplays(day),
                        notes: notes, noteDisplays: SessionNoteDisplay.make(from: notes),
                        sessionID: session.id, isRecentDay: isRecentDay,
                    )

                    // In Your Body — per-substance session totals merged with the
                    // live elimination model (what's still circulating, clearance
                    // projections, the curve on tap). Replaces the bare cumulative
                    // totals: a total is just the "dosed" side of body load.
                    SessionBodyLoadSection(entries: entries, colorMap: activeColorMap)

                    // Safety — interaction warnings shown in full plus a heart-rate
                    // summary. Headerless; the severity-tinted interaction rows
                    // already name it.
                    SessionSafetySection(
                        interactions: day.interactions,
                        pkFindings: day.pkFindings,
                        hrSummary: model.hrSummary,
                    )

                    // Recovery — per-category comedown guidance for what this
                    // session actually contained, plus a link into the full guide.
                    SessionRecoverySection(categories: SessionResolveModel.recoveryCategories(entries: entries))
                }
            }
            .listRowBackground(CardBackground())
        }
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 0, for: .scrollContent)
        .contentMargins(.horizontal, Spacing.xxl, for: .scrollContent)
        .listSectionSpacing(Spacing.xxl)
        .background(Theme.background)
        .task(id: colorSignature) {
            model.loadColorMap(colors: substanceColors)
        }
        .task(id: vitalsTaskKey) {
            await model.loadVitals(
                session: session, entries: entries,
                windowEnd: vitalsWindowEnd(resolvedDay.states), showSessionVitals: showSessionVitals,
            )
        }
        .task(id: mechanisticSignature) {
            await SubstanceStore.shared.ensureAllLoaded()
            let resolved = resolvedDay
            await model.computeMechanistic(
                supported: resolved.mechanisticSupported,
                doses: resolved.mechanisticDoses,
                pharmacology: resolved.mechanisticPharmacology,
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
                    hasCurves: !day.states.isEmpty,
                    isToday: isToday,
                    hasOngoingDose: ongoing,
                    longestBreakPivot: SessionMenu.longestBreakPivot(in: entries),
                    onRename: {
                        titleDraft = session.title ?? ""
                        showRename = true
                    },
                    onAddNote: { navigator.present(.sessionNoteEditor(sessionID: session.id)) },
                    onEditSummary: editSummary,
                    onToggleLiveActivity: toggleLiveActivity,
                )
                .popoverTip(SessionMenuTip(), arrowEdge: .top)
            }
        }
        .task { await OnboardingTips.retireDataTipAfterSessionMenuTip() }
        // The primary "Log a dose" action lives in the tab bar's bottom accessory
        // (always on screen beneath this detail), so the day view no longer
        // floats its own add button.
        .alert("Rename Session", isPresented: $showRename) {
            TextField("Session title", text: $titleDraft)
            Button("Cancel", role: .cancel) {}
            Button("Save") { SessionService.setTitle(titleDraft, for: session) }
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
                session: session,
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

    /// Each dose row's render-ready facts: the resolved substance core (memoized
    /// with the day) plus the two things that change without the content — the
    /// row tint and the heart-rate response.
    private func entryDisplays(_ day: ResolvedDay) -> [DayEntryDisplay] {
        entries.enumerated().map { index, entry in
            let hr = model.doseHR[entry.id]
            return DayEntryDisplay(
                core: day.entryCores[index], color: resolvedColor(entry.substance), hr: hr,
                confounderColors: (hr?.confounders ?? []).map { resolvedColor($0) },
            )
        }
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

    /// Open the summary in the note sheet: the existing `.summary` note, or a
    /// fresh one of that kind (which the shim also creates from a pre-notes
    /// `Session.note`).
    private func editSummary() {
        let summary = SessionNoteService.ensureSummaryNote(for: session)
        navigator.present(.sessionNoteEditor(sessionID: session.id, noteID: summary?.id, summary: summary == nil))
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
