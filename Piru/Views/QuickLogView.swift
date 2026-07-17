import OSLog
import SwiftData
import SwiftUI
import UIKit
import WidgetKit

private let quickLogLogger = Logger(subsystem: "dev.yumeji.piru", category: "QuickLog")

/// Thin wrapper that pins the recent-history window before building the screen.
///
/// ``QuickLogView`` holds a `@Query` over `DoseEntry` for its recency-derived
/// surfaces (today's active-percent badges, recent tags/locations). That query
/// must be **bounded** — the full dose table is years of rows the quick-log
/// screen never needs, yet loading it on every open kept the whole history
/// resident and made three consumers pay O(history). A `@Query` predicate can't
/// call `Date.now`/`addingTimeInterval`, so the cutoff is computed here as plain
/// `@State` and handed to the screen, which builds its `@Query` from it in
/// `init`. (Re-initializing the screen with a new cutoff preserves its `@State`
/// — view identity is stable — so even a refreshed cutoff never drops a staged
/// tray; but a sheet is short-lived, so one capture at present is enough.)
struct QuickLogSheet: View {
    var prestagedRoutine: String?

    /// Days of dose history the quick-log surfaces treat as "recent". Must
    /// exceed the longest plausible "still-active PK badge" horizon: a dose
    /// older than this shows no active-percent badge, which is correct — its
    /// body load has long since decayed below the badge's 5% floor. 120 days
    /// clears even long-half-life substances (fluoxetine ≈ 70 days to a 5% load)
    /// with margin, while keeping the resident array small.
    private static let recentWindowDays: TimeInterval = 120

    /// Captured once when the sheet's state first initializes (a fresh sheet per
    /// present), so the window doesn't drift mid-session. A few hours of drift
    /// across a 120-day window is irrelevant, so it never needs refreshing.
    @State private var cutoff = Date.now.addingTimeInterval(-recentWindowDays * 86_400)

    var body: some View {
        QuickLogView(prestagedRoutine: prestagedRoutine, historyCutoff: cutoff)
    }
}

struct QuickLogView: View {
    /// Stage this routine's items into the tray on open — the landing state
    /// for a routine-reminder notification tap (`piru://quicklog?routine=`).
    var prestagedRoutine: String?

    /// Lower bound for ``allEntries`` — see ``QuickLogSheet``. Stored so the
    /// explicit `init` can build the windowed `@Query` from it.
    let historyCutoff: Date

    @Environment(\.modelContext) private var modelContext
    @Environment(\.appNavigator) private var navigator

    /// Recent dose history only (since ``historyCutoff``), newest-first — every
    /// consumer (`rebuildEntryDerived`, the notification check) relies on the
    /// reverse-chronological order and needs no more than this window. Built in
    /// `init` because a `#Predicate` can't compute the cutoff itself.
    @Query private var allEntries: [DoseEntry]

    @Query private var substanceColors: [SubstanceColor]
    @Query(sort: \DailyDoseItem.sortOrder) private var dailyDoseItems: [DailyDoseItem]
    @Query(sort: \DoseRoutine.sortOrder) private var routines: [DoseRoutine]
    @Query(sort: [SortDescriptor(\FavoriteSubstance.sortOrder), SortDescriptor(\FavoriteSubstance.createdAt, order: .reverse)]) private var favorites: [FavoriteSubstance]
    @Query private var quickLogDoses: [QuickLogDose]

    @AppStorage(QuickLogManager.fixedOrderDefaultsKey) private var quickLogFixedOrder = false

    @State private var searchText = ""
    @State private var showCustomForm = false
    @State private var showEditSheet = false

    /// Staged-but-uncommitted doses. Tapping a chip stages it here; the dock
    /// (the screen's single bottom surface) is the commit surface for one dose
    /// or a whole stack.
    @State private var tray = DoseTrayModel()

    /// The dock is in search mode: field focused, results render inside the
    /// dock sheet. Entered by focusing the dock's pinned field or the tray's
    /// "Add another…"; exits on cancel, on staging a result, or when the dock
    /// is dragged below its tallest detent. Shared with ``QuickLogDock``,
    /// which owns the keyboard focus that drives it.
    @State private var searchActive = false

    /// The dock sheet is mounted for the lifetime of the cover. Requested
    /// from the first body evaluation so it presents *with* the cover's own
    /// transition rather than popping in afterwards.
    @State private var dockPresented = true

    /// Measured height of the cover — bounds the dock's compact detent.
    @State private var containerHeight: CGFloat = 0

    /// Every derived dataset the screen renders lives on this `@Observable`
    /// model, not inline on the view struct. Storing the (array-of-`Substance`)
    /// caches on the value-type view made every `body` pass deep-copy the whole
    /// dataset — `initializeWithCopy` dominated a 784 ms first-render trace; the
    /// reference-typed model drops the view's stored surface to a few flags.
    @State private var content = QuickLogContentModel()

    init(prestagedRoutine: String? = nil, historyCutoff: Date) {
        self.prestagedRoutine = prestagedRoutine
        self.historyCutoff = historyCutoff
        _allEntries = Query(
            FetchDescriptor(
                predicate: #Predicate<DoseEntry> { $0.timestamp >= historyCutoff },
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)],
            ),
            transaction: Transaction(animation: nil),
        )
    }

    // MARK: - Favorites

    /// Pre-`sortOrder` favorites are all 0 — stamp them with their current
    /// display order (newest first, matching the old query) exactly once, so
    /// reordering has distinct positions to work with.
    private func seedFavoriteOrderIfNeeded() {
        guard favorites.count > 1, favorites.allSatisfy({ $0.sortOrder == 0 }) else { return }
        for (index, favorite) in favorites.sorted(by: { $0.createdAt > $1.createdAt }).enumerated() {
            favorite.sortOrder = index
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                // The scroll content (routines, favorites, recent cards) is a
                // closure-free child: it takes only the two stable references it
                // needs (`content`, `tray`) and owns its own `@Query`s/actions,
                // so a search keystroke — which re-runs *this* body through
                // `searchText`/`dockResults` — no longer cascades into every
                // card. With no parent closures to defeat SwiftUI's view-value
                // comparison, the framework skips this subtree when the parent
                // re-renders for reasons it doesn't depend on. See
                // ``QuickLogCardList``.
                QuickLogCardList(content: content, tray: tray)
                    .padding(.horizontal)
                    .padding(.top, 4)
                    // Clear the dock sheet's peek detent so the last cards can
                    // scroll above it.
                    .padding(.bottom, QuickLogDockMetrics.peekHeight + 20)
                    // With a dose editor open in the dock, hide the cards behind it
                    // from assistive tech so VoiceOver/Voice Control focus the
                    // editor's controls instead of interleaving the dimmed list.
                    .accessibilityHidden(!tray.expandedItemIDs.isEmpty)
            }
            // Staging haptics live in a leaf, not this body: reading the tick
            // counters here would re-run the whole `QuickLogView.body` on
            // every stage/increment.
            .background(StagingHaptics(tray: tray))
            .background(CoverAccessibilityUnmasker())
            // With the cover's modal flag cleared (see the unmasker), nothing
            // at the window level masks this content while a sheet is stacked
            // on the dock — VoiceOver could wander into elements the sheet
            // blocks from touch. Hide the cover content whenever a nested
            // sheet is up. (Sheets presented from deep inside the dock — the
            // drink preset manager, find-a-place — are the dock's own overlay
            // problem and don't expose this layer.)
            .accessibilityHidden(showEditSheet || showCustomForm || navigator.sheetStack.count > 1)
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .navigationTitle("Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // With staged doses, close is a Menu — it gets the glass
                    // morph out of the button, unlike a confirmationDialog,
                    // which anchors to the toolbar as a stray popover.
                    if tray.isEmpty {
                        Button {
                            navigator.dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                    } else {
                        Menu {
                            Button(role: .destructive) {
                                navigator.dismiss()
                            } label: {
                                Label("Discard Doses", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "xmark")
                        }
                    }
                }
                // One standard Edit action, text-labeled per the HIG ("Edit"
                // is the canonical hard-to-symbolize action) — one sheet for
                // everything editable here: routines & prescriptions and the
                // favorites order. The "Fixed Order" toggle lives in
                // Settings ▸ Journal ("Keep Quick-Log Order").
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") {
                        showEditSheet = true
                    }
                    .accessibilityLabel("Edit routines and favorites")
                }
            }
            .task {
                // Wait for the launch prewarm so the card lookups below land on
                // the warm batch cache instead of cold per-substance SQL (returns
                // immediately if already loaded; the rebuild is then cheap enough
                // not to block the present animation).
                await SubstanceStore.shared.ensureAllLoaded()
                QuickLogManager.seedIfNeeded(history: allEntries, context: modelContext)
                RoutineMigrator.seedIfNeeded(context: modelContext)
                seedFavoriteOrderIfNeeded()
                content.rebuildColorLookup(substanceColors: substanceColors)
                // Cards first: `rebuildEntryDerived` scopes its per-substance PK
                // badge work to the *displayed* set (favorites + the 10 recents),
                // so the card caches must exist before it runs.
                content.rebuildCards(quickLogDoses: quickLogDoses, favorites: favorites)
                content.rebuildEntryDerived(allEntries: allEntries, dailyDoseItems: dailyDoseItems, routines: routines)
                content.markLoaded()
                if let prestagedRoutine {
                    stageRoutine(named: prestagedRoutine)
                }
            }
            .task(id: quickLogDoses.count) {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                content.rebuildCards(quickLogDoses: quickLogDoses, favorites: favorites)
            }
            // A logged dose (here or elsewhere) changes the history-derived
            // caches — refresh them off the body, keyed on a content signature
            // so in-place edits invalidate too.
            .onChange(of: QuickLogContentModel.entriesSignature(allEntries)) {
                content.rebuildEntryDerived(allEntries: allEntries, dailyDoseItems: dailyDoseItems, routines: routines)
            }
            .onChange(of: substanceColors.count) {
                content.rebuildColorLookup(substanceColors: substanceColors)
                content.rebuildCards(quickLogDoses: quickLogDoses, favorites: favorites)
            }
            // Keyed on names, not count — a reorder changes order only.
            .onChange(of: favorites.map(\.substance)) { content.rebuildFavorites(favorites: favorites) }
            // Routine pills depend on the routine rows + daily items; refresh
            // the cache when either is edited (the Manage Routines sheet).
            .onChange(of: routineSignature) { content.rebuildDailyGroups(dailyDoseItems: dailyDoseItems, routines: routines) }
            .task(id: searchText) {
                guard !searchText.isEmpty else {
                    content.setLibraryResults([])
                    return
                }
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                content.setLibraryResults(
                    SubstanceLibrary.searchMatches(searchText)
                        .filter { !content.cachedHistoryNames.contains($0.substance.name.lowercased()) },
                )
            }
        }
        // The staging dock: a native detented sheet over this cover, mounted
        // for the cover's whole lifetime (never dismissible — it's the
        // staging basket). Sheets launched from quick log (custom-substance
        // form, favorites editor) stack *on the dock*, not on the cover: the
        // dock permanently occupies the cover's presentation slot, so a
        // sibling sheet here would never present.
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { newValue in
            containerHeight = newValue
        }
        .sheet(isPresented: $dockPresented) {
            DockSheetHost(
                tray: tray,
                content: content,
                containerHeight: containerHeight,
                searchText: $searchText,
                searchActive: $searchActive,
                showCustomForm: $showCustomForm,
                showEditSheet: $showEditSheet,
                onCommit: commitTray,
            )
        }
    }

    // MARK: - Daily routine

    /// Cheap change-signature for the routine pills' inputs (tiny N), used to
    /// invalidate `cachedDailyGroups` on an in-place edit from the settings
    /// sheet. Covers both the routine rows and the daily items in one key so
    /// the body adds a single `onChange` rather than two.
    private var routineSignature: [String] {
        var parts: [String] = []
        for routine in routines {
            let minutes = routine.timeMinutes ?? -1
            parts.append("r:\(routine.name)|\(minutes)|\(routine.sortOrder)")
        }
        for item in dailyDoseItems {
            parts.append("i:\(item.substance)|\(item.category)|\(item.sortOrder)")
        }
        return parts
    }

    private func stagedQuantity(_ item: DailyDoseItem) -> Int {
        tray.quantity(substance: item.substance, route: item.route, amount: item.amount, unit: item.unit)
    }

    /// Stage every item of the named routine, exactly as if its pill were
    /// tapped (idempotent) — the landing state for a reminder-notification tap.
    private func stageRoutine(named name: String) {
        let items = dailyDoseItems.filter { $0.category == name }
        guard !items.isEmpty else { return }
        withAnimation(.snappy) {
            for item in items where stagedQuantity(item) == 0 {
                stageDailyItem(item)
            }
        }
    }

    private func stageDailyItem(_ item: DailyDoseItem) {
        tray.stage(
            substance: item.substance,
            route: item.route,
            amount: item.amount,
            unit: item.unit,
            colorHex: content.cachedColorLookup[item.substance.lowercased()],
            librarySubstance: SubstanceLibrary.timelineLookup(item.substance.lowercased()),
            // Carry the daily item's product so a Concerta med logs as Concerta —
            // the tray derives the release form/isomer from it, same as search.
            productName: item.productName,
            isFromDailySet: true,
            isBackgroundMed: item.isBackgroundMed,
        )
    }

    // MARK: - Actions

    /// Commit every staged dose at the tray's shared time, stamping the
    /// tray-wide tags and location. One entry per staged item — a count of
    /// 2 × 150 mg commits as a single 300 mg entry, which is PK-equivalent
    /// under linear superposition.
    private func commitTray() {
        guard tray.isCommittable else { return }

        // Snapshot everything the writes need *before* dismissing. The view's
        // `@State` tray and `@Query` results start tearing down the instant we
        // dismiss, so reading them inside the deferred block would be racy.
        let stagedItems = tray.staged
        let sharedTime = tray.time.resolved
        let tags = Array(tray.tags)
        let location = tray.location
        let fixedOrder = quickLogFixedOrder
        let context = modelContext
        let recentEntries = Array(allEntries)
        var colors = Array(substanceColors)

        // The success haptic + dismiss fire *first*, on this runloop, so the
        // sheet starts sliding away immediately. (Haptic played directly
        // because the sheet tears down before a `sensoryFeedback` trigger
        // would fire.) Quick-log completes a flow, so clear the whole chain.
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        navigator.dismissAll()

        // Tier 1 — next runloop tick: the work that makes the dose *appear*
        // and persist (inserts, session assignment, color, active-session
        // update, one save). Deferred a tick so it doesn't block the
        // dismissal's first frame, but kept prompt so the journal behind the
        // sheet shows the dose as the sheet slides away — no pop-in.
        DispatchQueue.main.async {
            var createdEntries: [DoseEntry] = []
            var curation: [QuickLogManager.LoggedDose] = []

            for item in stagedItems {
                let entry = DoseEntry(
                    substance: item.substanceName,
                    amount: item.totalAmount,
                    unit: item.unit,
                    route: item.route,
                    saltForm: item.saltForm,
                    isomer: item.isomer,
                    releaseForm: item.releaseForm,
                    productName: item.productName,
                    substanceUID: item.substanceUID,
                    displayNameSnapshot: item.displayNameSnapshot,
                    timestamp: sharedTime,
                    notes: item.note.isEmpty ? nil : item.note,
                    tags: tags,
                    isBackgroundMed: item.isBackgroundMed,
                    locationName: location?.name,
                    latitude: location?.latitude,
                    longitude: location?.longitude,
                    hadGrapefruit: item.hadGrapefruit ? true : nil,
                    volumeML: item.volumeML,
                    abv: item.abv,
                    drinkName: item.drinkName,
                )
                context.insert(entry)
                SessionService.assignSession(for: entry, in: context)
                createdEntries.append(entry)

                // Record each component's chip amount (not the merged total) so
                // the curated list floats the chips the user actually tapped,
                // without minting a chip for every sum. Daily routine items keep
                // their own surface and don't mint quick-log chips.
                if !item.isFromDailySet {
                    for component in item.components {
                        curation.append(QuickLogManager.LoggedDose(
                            substance: item.substanceName, route: item.route, amount: component.amount, unit: item.unit,
                            volumeML: item.volumeML, abv: item.abv, drinkName: item.drinkName, emoji: item.emoji,
                            substanceUID: item.substanceUID, isomer: item.isomer,
                            releaseForm: item.releaseForm, saltForm: item.saltForm, productName: item.productName,
                        ))
                    }
                }

                // Auto-assign a stable palette color for a brand-new substance
                // up front (deterministic hash, the same color the graph uses),
                // tracking it in the local `colors` snapshot so the session
                // picks it up immediately without a store round-trip.
                if !colors.hasColor(for: item.substanceName) {
                    let newColor = SubstanceColor(substance: item.substanceName, hexColor: PresetColor.deterministic(for: item.substanceName).hex)
                    context.insert(newColor)
                    colors.append(newColor)
                }

                ActiveSessionManager.shared.addDose(
                    entry: entry,
                    substance: item.librarySubstance,
                    colorHex: SubstancePalette.hex(for: item.substanceName, hexMap: colors.hexColorMap),
                    allColors: colors,
                )
            }
            do {
                try context.save()
            } catch {
                // The success haptic + dismissal already fired (deliberately —
                // the sheet must slide immediately), so a failure here leaves
                // the live session showing doses the store doesn't have. The
                // inserts stay pending on the context, so the next save — the
                // curation write below or SwiftData's autosave — retries them;
                // record it loudly instead of vanishing the evidence.
                quickLogLogger.fault("Quick-log commit save failed for \(stagedItems.count) dose(s): \(error)")
            }
            // Curated-list maintenance is a site-specific immediate bit (it
            // records the chips the user actually tapped), kept prompt so a
            // reopened tray reflects them right away.
            QuickLogManager.record(curation, fixedOrder: fixedOrder, context: context)
            DoseLogService.shared.changed()

            // Tier 2 — after the dismissal animation: the bookkeeping that isn't
            // on screen (wellness notifications, scoped inventory recompute, one
            // widget reload). Routed through the same deferred funnel the entry
            // form uses; running it now would drop frames *during* the slide-down,
            // and none of it is visible until the next quick-log open or a widget
            // refresh.
            let affected = Set(stagedItems.map(\.substanceName))
            DoseLogService.shared.scheduleDeferredBookkeeping(forSubstances: affected, in: context) {
                for entry in createdEntries {
                    DoseNotificationManager.doseLogged(entry: entry, recentEntries: recentEntries)
                }
            }
        }
    }
}

// MARK: - Dock Sheet Host

/// The dock sheet's content root: owns the detent state and applies the
/// presentation configuration.
///
/// Split out of `QuickLogView` so the dock's detent churn stays local: the
/// detent selection and set are rewritten several times per transition (every
/// stage, search enter/exit, drag settle), and while they were `@State` on
/// `QuickLogView` each write re-ran the *whole screen's* body — toolbar,
/// scroll chrome, and this sheet closure — just to re-apply an unchanged
/// presentation. Owned here, a detent write invalidates only this wrapper.
/// Localizing the re-application also narrows the window where a SwiftUI
/// presentation update can rewrite the sheet's detents mid-ramp (the
/// self-heal in `QuickLogDock.animateHeightDetent` exists for exactly that).
///
/// Presentation configuration lives at this view's root so it reliably
/// reaches the presentation (not shadowed by the nested sheet wrappers
/// above it). The background *style* is clear: that swaps the default
/// full-width sheet backing for the system's inset floating glass platter,
/// which is the dock's one surface in every detent (Maps' collapsed-bar
/// look at peek).
private struct DockSheetHost: View {
    var tray: DoseTrayModel
    var content: QuickLogContentModel
    var containerHeight: CGFloat
    @Binding var searchText: String
    @Binding var searchActive: Bool
    /// Owned by `QuickLogView` (its body hides the cover content from
    /// assistive tech while either sheet is up); presented from here because
    /// the dock occupies the cover's only presentation slot, so these must
    /// stack on the dock.
    @Binding var showCustomForm: Bool
    @Binding var showEditSheet: Bool
    let onCommit: () -> Void

    @Environment(\.appNavigator) private var navigator

    /// The dock's current detent. ``QuickLogDock`` drives the transitions.
    @State private var detent: PresentationDetent = QuickLogDockMetrics.peekDetent
    /// The live detent set — dynamic because the dock's smallest detent is
    /// fit-to-content once doses are staged. ``QuickLogDock`` owns the swaps.
    @State private var detents: Set<PresentationDetent> = QuickLogDockMetrics.emptyDetents

    @State private var pendingCustomPrefill: EntryPrefillPayload?

    var body: some View {
        QuickLogDock(
            tray: tray,
            content: content,
            containerHeight: containerHeight,
            searchText: $searchText,
            searchActive: $searchActive,
            detent: $detent,
            detents: $detents,
            onCreateCustom: { showCustomForm = true },
            onCommit: onCommit,
        )
        .sheet(isPresented: $showCustomForm, onDismiss: onCustomFormDismiss) {
            CustomSubstanceFormView(initialName: searchText.trimmingCharacters(in: .whitespaces)) { saved in
                pendingCustomPrefill = EntryPrefillPayload(
                    substance: saved.name,
                    route: saved.defaultRoute,
                    unit: saved.unit,
                )
            }
        }
        .sheet(isPresented: $showEditSheet) {
            QuickLogEditSheet()
        }
        // Navigator sheets launched from quick log (Manage Routines, Edit
        // Routine…) present here, stacked on the dock — the dock occupies
        // the cover's only presentation slot, so they can't present there.
        .hostsNestedNavigatorSheets(navigator)
        .presentationDetents(detents, selection: $detent)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .presentationContentInteraction(.resizes)
        .presentationBackground { Color.clear }
        .interactiveDismissDisabled()
    }

    private func onCustomFormDismiss() {
        guard let prefill = pendingCustomPrefill else { return }
        pendingCustomPrefill = nil
        withAnimation(.snappy) {
            tray.stageDraft(
                substance: prefill.substance,
                route: prefill.route,
                unit: prefill.unit,
                colorHex: content.cachedColorLookup[prefill.substance.lowercased()],
                librarySubstance: SubstanceLibrary.timelineLookup(prefill.substance.lowercased()),
            )
            searchActive = false
            searchText = ""
        }
    }
}

// MARK: - Staging Haptics

/// A zero-size leaf that fires the staging haptics. It exists so the tick-counter
/// reads (`stageTick` / `incrementTick`) live *here* and not in `QuickLogView.body`
/// — reading the `@Observable` counters in the parent body would re-run the whole
/// quick-log screen on every chip tap. Mounted always-present via `.background`,
/// so it fires regardless of which dock face is showing.
private struct StagingHaptics: View {
    let tray: DoseTrayModel

    var body: some View {
        Color.clear
            .sensoryFeedback(.impact(weight: .light), trigger: tray.stageTick)
            .sensoryFeedback(.increase, trigger: tray.incrementTick)
    }
}

// MARK: - Cover Accessibility Unmasker

/// Restores VoiceOver access to the dock sheet at undimmed detents.
///
/// UIKit marks the quick-log cover's `UITransitionView` `accessibilityViewIsModal`
/// (it's a full-screen modal), and VoiceOver ignores every *sibling* of a modal
/// view — which includes the always-presented dock sheet's own transition view
/// whenever the dock is non-modal (peek/compact/medium, i.e. whenever
/// `presentationBackgroundInteraction` leaves it undimmed). Net effect: at rest
/// the search field, staged doses, and Log Dose are invisible to assistive tech;
/// at `.large` the dock's transition view turns modal itself, wins as topmost,
/// and the situation flips (verified via lldb: both transition views, flag by
/// detent). The full-screen presentation already removes the Journal underneath
/// from the hierarchy, so the cover's modal flag protects nothing — clearing it
/// exposes cover content and dock together, while the dock's *own* modal flag
/// still correctly masks the cover at `.large`.
///
/// Public-API superview walk from a hosted leaf, same pattern as the (retired)
/// `SheetPlatterHider`. Re-asserted from `layoutSubviews` because UIKit can
/// re-apply the flag across presentation transitions.
private struct CoverAccessibilityUnmasker: UIViewRepresentable {
    func makeUIView(context _: Context) -> UnmaskView {
        UnmaskView()
    }
    func updateUIView(_: UnmaskView, context _: Context) {}

    final class UnmaskView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            unmask()
            // The presentation transition can set the flag after this view
            // lands in the window — re-check once the current turn settles.
            DispatchQueue.main.async { [weak self] in self?.unmask() }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            unmask()
        }

        private func unmask() {
            var ancestor = superview
            while let view = ancestor {
                if view.accessibilityViewIsModal {
                    view.accessibilityViewIsModal = false
                    UIAccessibility.post(notification: .layoutChanged, argument: nil)
                    break
                }
                ancestor = view.superview
            }
        }
    }
}

// MARK: - Card List

/// The quick-log scroll content — routines, favorites, and recent cards.
///
/// Extracted from `QuickLogView` as a **closure-free** child: it takes only the
/// two stable references it needs (`content`, `tray`) and owns its own `@Query`s
/// and list-mutating actions, so it passes *no* parent closures. That matters
/// because closures can't be compared — a view holding them is always treated as
/// changed, forcing its body to re-run whenever the parent does. `QuickLogView`'s
/// body re-runs on every search keystroke (it reads `searchText`/`dockResults`),
/// which used to cascade into every `SubstanceCardView`/`OneRowChips` body (a
/// phone SwiftUI trace of the search/dock flow showed ~28k view-body updates
/// dominated by that chain). With only stable references here, SwiftUI's
/// view-value comparison finds this subtree unchanged and skips it when the
/// parent re-renders for state the list doesn't depend on. The cards still update
/// through their own observation (the `content` caches, `tray` staging) — which
/// is exactly the scope we want.
private struct QuickLogCardList: View {
    let content: QuickLogContentModel
    let tray: DoseTrayModel

    @Environment(\.modelContext) private var modelContext
    @Environment(\.appNavigator) private var navigator

    @Query private var quickLogDoses: [QuickLogDose]
    @Query(sort: [SortDescriptor(\FavoriteSubstance.sortOrder), SortDescriptor(\FavoriteSubstance.createdAt, order: .reverse)]) private var favorites: [FavoriteSubstance]

    /// Folds the Routines & Prescriptions section down to its header — for
    /// people who don't use the feature. Persisted across launches.
    @AppStorage("quickLogRoutinesCollapsed") private var routinesCollapsed = false

    var body: some View {
        // Snapshot staged counts once per staging change; each card takes only
        // its own slice, so a card whose staged state is unchanged is skipped by
        // its `.equatable()` rather than re-diffing every chip + context menu.
        let staged = tray.stagedCountsBySubstance()
        return LazyVStack(alignment: .leading, spacing: 12) {
            if !content.hasLoaded {
                // Loading: render nothing (the dock stays put) rather than
                // the empty-state placeholder — the caches fill within a
                // frame or two off the warm batch cache, so this avoids the
                // jarring "No Previous Substances" flash on open.
                EmptyView()
            } else {
                scrollContentInner(staged: staged)
            }
        }
    }

    /// One header style for every section: sentence case, no icon, no caps —
    /// matching how the rest of the app titles things. The extra top padding
    /// separates sections; header → content is the stack's own 12pt.
    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.secondaryLabel)
            .padding(.top, 8)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func scrollContentInner(staged: [String: StagedChipCounts]) -> some View {
        // Routines are always surfaced (discoverability) — with none defined
        // the section is just the New Routine pill, and the whole thing is
        // collapsible for people who don't use it.
        dailySection(staged: staged)

        if content.cachedCards.isEmpty, content.cachedDailyGroups.isEmpty {
            ContentUnavailableView(
                "No Previous Substances",
                systemImage: "magnifyingglass",
                description: Text("Search for a substance to log your first entry."),
            )
        }

        if !content.cachedFavoriteCards.isEmpty || !content.cachedFavoriteLibrarySubstances.isEmpty {
            sectionHeader("Favorites")
            ForEach(content.cachedFavoriteCards) { card in
                cardView(card, isFavorite: true, staged: staged)
                    .id("\(card.id)_fav")
            }
            ForEach(content.cachedFavoriteLibrarySubstances) { substance in
                libraryRow(substance)
            }
        }

        if !content.cachedNonFavoriteCards.isEmpty {
            if !content.cachedFavoriteCards.isEmpty {
                sectionHeader("Recent")
            }
            ForEach(content.cachedNonFavoriteCards) { card in
                cardView(card, isFavorite: false, staged: staged)
                    .id("\(card.id)_recent")
            }
        }
    }

    // MARK: - Daily routine

    @ViewBuilder
    private func dailySection(staged: [String: StagedChipCounts]) -> some View {
        // The collapse toggle is the whole header row — chevron included.
        Button {
            withAnimation(.snappy) { routinesCollapsed.toggle() }
        } label: {
            HStack(spacing: 6) {
                Text("Routines & Prescriptions")
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .rotationEffect(.degrees(routinesCollapsed ? 0 : 90))
                Spacer()
            }
            .foregroundStyle(Theme.secondaryLabel)
            .padding(.top, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Routines & Prescriptions")
        .accessibilityValue(routinesCollapsed ? Text("Collapsed") : Text("Expanded"))

        if !routinesCollapsed {
            FlowLayout(spacing: 8) {
                ForEach(content.cachedDailyGroups) { group in
                    routinePill(group, staged: staged)
                }
                newRoutinePill
            }
        }
    }

    /// Trailing pill of the routines row — creating a routine lives with the
    /// pills it produces.
    private var newRoutinePill: some View {
        Button {
            navigator.present(.dailyDoseSettings)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .imageScale(.small)
                Text("New Routine")
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Color(.secondarySystemFill), in: Capsule())
            .foregroundStyle(Theme.secondaryLabel)
        }
        .buttonStyle(.plain)
    }

    /// A routine is one pill — a *shortcut* that stages its whole set into
    /// the tray in one tap (the eight-supplements use case), idempotent for
    /// anything already staged. The checkmark is informational ("all of these
    /// were logged today"); the pill stays tappable for re-logs. Long-press
    /// to edit the routine itself.
    private func routinePill(_ group: DailyCategoryGroup, staged: [String: StagedChipCounts]) -> some View {
        let done = group.remaining.isEmpty
        let allStaged = group.items.allSatisfy { stagedQuantity($0, staged: staged) > 0 }
        return Button {
            withAnimation(.snappy) {
                for item in group.items where stagedQuantity(item, staged: staged) == 0 {
                    stageDailyItem(item)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: done ? "checkmark" : group.icon)
                    .imageScale(.small)
                Text(group.title)
                Text(verbatim: "· \(group.items.count)")
                    .opacity(0.75)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                allStaged
                    ? Theme.accent
                    : done ? Color.green.opacity(0.12) : Theme.accent.opacity(0.12),
                in: Capsule(),
            )
            .foregroundStyle(
                allStaged
                    ? Color.white
                    : done ? Color.green : Theme.accent,
            )
        }
        .buttonStyle(.plain)
        // Otherwise reads "Daily, middle dot, 2"; speak it as a clean
        // label + item count, with the logged-today state as a value.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(group.title)
        .accessibilityValue(
            done
                ? Text("^[\(group.items.count) item](inflect: true), all logged today")
                : Text("^[\(group.items.count) item](inflect: true)"),
        )
        .accessibilityHint("Stages this routine’s doses")
        .accessibilityAddTraits(.isButton)
        .contextMenu {
            Button {
                navigator.present(.dailyDoseSettings)
            } label: {
                Label("Edit Routine…", systemImage: "pencil")
            }
        }
    }

    private func stagedQuantity(_ item: DailyDoseItem, staged: [String: StagedChipCounts]) -> Int {
        staged[item.substance.lowercased()]?.count(route: item.route, amount: item.amount, unit: item.unit) ?? 0
    }

    private func stageDailyItem(_ item: DailyDoseItem) {
        tray.stage(
            substance: item.substance,
            route: item.route,
            amount: item.amount,
            unit: item.unit,
            colorHex: content.cachedColorLookup[item.substance.lowercased()],
            librarySubstance: SubstanceLibrary.timelineLookup(item.substance.lowercased()),
            // Carry the daily item's product so a Concerta med logs as Concerta —
            // the tray derives the release form/isomer from it, same as search.
            productName: item.productName,
            isFromDailySet: true,
            isBackgroundMed: item.isBackgroundMed,
        )
    }

    // MARK: - Substance Card

    /// Builds the extracted ``SubstanceCardView`` for a recent/favorite card,
    /// wiring the list-owned actions (favorite toggle + curated-list edits)
    /// while the card itself owns its layout and ephemeral expansion state.
    private func cardView(_ card: SubstanceCard, isFavorite: Bool, staged: [String: StagedChipCounts]) -> some View {
        SubstanceCardView(
            card: card,
            isFavorite: isFavorite,
            badge: content.cachedMostRecent[card.id],
            stagedCounts: staged[card.id] ?? .empty,
            tray: tray,
            onToggleFavorite: { withAnimation(.snappy) { toggleFavorite(card) } },
            onMoveChip: { group, chip, toFront in moveChip(group: group, chip: chip, toFront: toFront) },
            onRemoveChip: { group, chip in removeChip(group: group, chip: chip) },
        )
        // Skip rebuilding this card (its chip buttons + context menus) when its
        // content and staged slice are unchanged — the staging-cascade fix.
        .equatable()
    }

    private func toggleFavorite(_ card: SubstanceCard) {
        let nowFavorite = FavoriteService.toggle(
            substance: card.substanceName,
            substanceUID: card.substanceUID,
            isomer: card.isomer,
            releaseForm: card.releaseForm,
            saltForm: card.saltForm,
            productName: card.productName,
            in: modelContext,
        )
        content.setFavorite(identity: card.id, on: nowFavorite)
    }

    // MARK: - Library Row

    private func libraryRow(_ substance: Substance) -> some View {
        Button {
            openLibrarySubstance(substance)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "pill")
                    .foregroundStyle(Theme.secondaryLabel)
                VStack(alignment: .leading, spacing: 2) {
                    Text(substance.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text("\(substance.defaultRoute.displayName) \u{2014} \(substance.defaultUnit)")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            .padding(14)
            .themeCard(cornerRadius: 20)
        }
        .buttonStyle(.plain)
    }

    /// Staging-only counterpart to `QuickLogView.openLibrarySubstance` — a card
    /// in the list isn't a search surface, so it stages a draft without the
    /// search-state reset the dock version performs.
    private func openLibrarySubstance(_ substance: Substance) {
        withAnimation(.snappy) {
            tray.stageDraft(
                substance: substance.name,
                route: substance.defaultRoute,
                unit: substance.defaultUnit,
                colorHex: content.cachedColorLookup[substance.name.lowercased()],
                librarySubstance: substance,
            )
        }
    }

    // MARK: - Quick-log list curation

    /// The curated row backing a chip, matched by substance + route + measurement.
    private func quickLogDose(for group: SubstanceGroup, chip: DoseChip) -> QuickLogDose? {
        let key = QuickLogDose.makeKey(
            substance: group.substanceName,
            route: group.route,
            amount: chip.amount,
            unit: chip.unit,
            substanceUID: group.substanceUID,
            isomer: group.isomer,
            releaseForm: group.releaseForm,
            saltForm: group.saltForm,
            volumeML: chip.volumeML,
            abv: chip.abv,
            drinkName: chip.drinkName,
        )
        return quickLogDoses.first { $0.key == key }
    }

    private func removeChip(group: SubstanceGroup, chip: DoseChip) {
        guard let dose = quickLogDose(for: group, chip: chip) else { return }
        modelContext.delete(dose)
        try? modelContext.save()
        withAnimation(.snappy) { content.rebuildCards(quickLogDoses: quickLogDoses, favorites: favorites) }
    }

    /// Move a chip to the front (or back) of its (substance, route) group by
    /// rewriting its `sortOrder` just past the current min/max.
    private func moveChip(group: SubstanceGroup, chip: DoseChip, toFront: Bool) {
        guard let dose = quickLogDose(for: group, chip: chip) else { return }
        // Reorder within the same (identity, route) group — a Concerta chip floats
        // past its Concerta siblings, not Ritalin's.
        let siblings = quickLogDoses.filter { $0.identityKey == group.cardKey && $0.route == group.route }
        if toFront {
            dose.sortOrder = (siblings.map(\.sortOrder).min() ?? 0) - 1
        } else {
            dose.sortOrder = (siblings.map(\.sortOrder).max() ?? 0) + 1
        }
        try? modelContext.save()
        withAnimation(.snappy) { content.rebuildCards(quickLogDoses: quickLogDoses, favorites: favorites) }
    }
}
