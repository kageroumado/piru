import SwiftData
import SwiftUI
import UIKit
import VisionKit
import WidgetKit

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
    /// Canonical name of a substance to stage (with its editor open) on present.
    var prefillSubstance: String?

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
        QuickLogView(prestagedRoutine: prestagedRoutine, prefillSubstance: prefillSubstance, historyCutoff: cutoff)
    }
}

struct QuickLogView: View {
    /// Stage this routine's items into the tray on open — the landing state
    /// for a routine-reminder notification tap (`piru://quicklog?routine=`).
    var prestagedRoutine: String?

    /// Stage this substance (canonical name) as a draft on open, with its dose
    /// editor expanded on the library's reference dose — the landing state for
    /// the "Log" button on a substance's detail screen
    /// (`piru://quicklog?substance=`).
    var prefillSubstance: String?

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
    @State private var showScanner = false

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

    /// Set the instant the tray commits: the sheet is dismissing, so the
    /// revision-keyed derived-cache rebuild — which the commit itself triggers —
    /// would be pure wasted main-thread time during the slide-down.
    @State private var isCommitted = false

    /// Measured height of the cover — bounds the dock's compact detent.
    @State private var containerHeight: CGFloat = 0

    /// Every derived dataset the screen renders lives on this `@Observable`
    /// model, not inline on the view struct. Storing the (array-of-`Substance`)
    /// caches on the value-type view made every `body` pass deep-copy the whole
    /// dataset — `initializeWithCopy` dominated a 784 ms first-render trace; the
    /// reference-typed model drops the view's stored surface to a few flags.
    @State private var content = QuickLogContentModel()

    init(prestagedRoutine: String? = nil, prefillSubstance: String? = nil, historyCutoff: Date) {
        self.prestagedRoutine = prestagedRoutine
        self.prefillSubstance = prefillSubstance
        // The windowed @Query closes over the init parameter — see QuickLogSheet
        // for the cutoff's meaning.
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
            .accessibilityHidden(showEditSheet || showCustomForm || showScanner || navigator.sheetStack.count > 1)
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
                        .accessibilityLabel(Text("Close"))
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
                        .accessibilityLabel(Text("Close"))
                    }
                }
                // One standard Edit action, text-labeled per the HIG ("Edit"
                // is the canonical hard-to-symbolize action) — one sheet for
                // everything editable here: routines & prescriptions and the
                // favorites order. The "Fixed Order" toggle lives in
                // Settings ▸ Journal ("Keep Quick-Log Order").
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") {
                        showEditSheet = true
                    }
                    .accessibilityLabel("Edit routines and favorites")
                }
                // The label scanner, split into its own glass group — point the
                // camera at a medication box to stage its substance and strength.
                if DataScannerViewController.isSupported {
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showScanner = true
                        } label: {
                            Image(systemName: "camera")
                        }
                        .accessibilityLabel("Scan a label")
                    }
                }
            }
            .task {
                // Wait for the launch prewarm so the card lookups below land on
                // the warm batch cache instead of cold per-substance SQL (returns
                // immediately if already loaded; the rebuild is then cheap enough
                // not to block the present animation).
                await SubstanceStore.shared.ensureAllLoaded()
                QuickLogManager.seedIfNeeded(history: allEntries, context: modelContext)
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
                if let prefillSubstance {
                    stagePrefill(named: prefillSubstance)
                }
            }
            .task(id: quickLogDoses.count) {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                content.rebuildCards(quickLogDoses: quickLogDoses, favorites: favorites)
            }
            // A logged dose (here or elsewhere) changes the history-derived
            // caches — refresh them off the body, keyed on the dose-log
            // revision (one observed Int; hashing `allEntries` here would
            // subscribe this body to every field of every entry). The initial
            // `.task` above owns the first rebuild, so skip until it has run.
            .task(id: DoseLogService.shared.revision) {
                guard content.hasLoaded, !isCommitted else { return }
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
                // Ranked off-main: the sync form runs the whole ranking pass —
                // fuzzy tail included — on the main actor, per keystroke.
                let matches = await SubstanceLibrary.searchMatchesAsync(searchText)
                guard !Task.isCancelled else { return }
                content.setLibraryResults(
                    matches.filter { !content.cachedHistoryNames.contains($0.substance.name.lowercased()) },
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
                showScanner: $showScanner,
                onCommit: commitTray,
            )
        }
    }

    // MARK: - Daily routine

    /// Cheap change-signature for the group pills' inputs (tiny N), used to
    /// invalidate `cachedDailyGroups` on an in-place edit from the My Meds
    /// hub. Times/quiet/PRN all move a med between groups, so they key it.
    private var routineSignature: [String] {
        dailyDoseItems.map { item in
            let times = item.reminderTimesMinutes.map(String.init).joined(separator: ",")
            return "i:\(item.substance)|\(times)|\(item.isQuiet)|\(item.isAsNeeded)|\(item.sortOrder)"
        }
    }

    private func stagedQuantity(_ item: DailyDoseItem) -> Int {
        tray.quantity(substance: item.substance, productName: item.productName, route: item.route, amount: item.amount, unit: item.unit)
    }

    /// Stage every item of the named routine, exactly as if its pill were
    /// tapped (idempotent) — the landing state for a reminder-notification tap.
    private func stageRoutine(named name: String) {
        // `name` is a MedTimeGroup slug ("morning") from a group pill or a
        // reminder deep link; legacy routine-name links fall back to the
        // dormant category field so old notifications still land somewhere.
        let items: [DailyDoseItem] = if let group = MedTimeGroup(slug: name) {
            dailyDoseItems.filter { MedTimeGroup.belongs($0, to: group) }
        } else {
            dailyDoseItems.filter { $0.category == name }
        }
        guard !items.isEmpty else { return }
        withAnimation(.snappy) {
            for item in items where stagedQuantity(item) == 0 {
                stageDailyItem(item)
            }
        }
    }

    /// Stage one library substance as a draft — the same path a search hit takes
    /// ("Add & edit"): it seeds the reference dose for the substance's default
    /// route and opens the editor, so the sheet lands on the dose the user came
    /// to enter rather than on the card list. No-op for an unknown name.
    private func stagePrefill(named name: String) {
        guard let substance = SubstanceLibrary.resolveFull(name) else { return }
        let route = substance.defaultRoute
        withAnimation(.snappy) {
            tray.stageDraft(
                substance: substance.name,
                route: route,
                unit: substance.defaultUnit,
                colorHex: content.cachedColorLookup[substance.name.lowercased()],
                librarySubstance: substance,
            )
        }
    }

    private func stageDailyItem(_ item: DailyDoseItem) {
        tray.stage(dailyItem: item, colorLookup: content.cachedColorLookup)
    }

    // MARK: - Actions

    /// Commit every staged dose at the tray's shared time, stamping the
    /// tray-wide tags and location. One entry per staged item — a count of
    /// 2 × 150 mg commits as a single 300 mg entry, which is PK-equivalent
    /// under linear superposition.
    private func commitTray() {
        guard tray.isCommittable else { return }
        isCommitted = true

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
        let colors = Array(substanceColors)

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
            var batch: [(entry: DoseEntry, substance: Substance?)] = []
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
                batch.append((entry, item.librarySubstance))

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
            }

            let createdEntries = batch.map(\.entry)
            DoseLogService.shared.logBatch(
                batch,
                colors: colors,
                in: context,
                beforeSave: {
                    // Curated-list maintenance is a site-specific immediate bit
                    // (it records the chips the user actually tapped), kept
                    // prompt so a reopened tray reflects them right away.
                    // Mutations only — the batch's single save commits doses
                    // and chips together, so the per-save `@Query` invalidation
                    // storm fires once, not twice.
                    QuickLogManager.record(curation, fixedOrder: fixedOrder, context: context, save: false)
                },
                // Tier 2 — after the dismissal animation: the wellness
                // notifications; running them now would drop frames during the
                // slide-down, and none of it is visible until the next
                // quick-log open or a widget refresh.
                deferredBookkeeping: {
                    for entry in createdEntries {
                        DoseNotificationManager.doseLogged(entry: entry, recentEntries: recentEntries, in: context)
                    }
                },
            )
        }
    }
}

// MARK: - Dock Sheet Host
