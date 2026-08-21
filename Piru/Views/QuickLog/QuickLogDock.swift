import OSLog
import SwiftUI
import UIKit

// MARK: - Metrics

/// Geometry shared between the dock sheet and the quick-log cover behind it.
///
/// The text-derived members are computed, not stored: they scale with the
/// user's Dynamic Type size (via `UIFontMetrics`, which reads the app-wide
/// content size category — the app never overrides it per-view), so the
/// search field and the detents built from it don't clip at accessibility
/// sizes. Repeated accesses within one size category return identical values,
/// which keeps `PresentationDetent` equality comparisons stable.
enum QuickLogDockMetrics {
    /// The pinned search field's height — one size in every dock state.
    static var fieldHeight: CGFloat {
        UIFontMetrics(forTextStyle: .body).scaledValue(for: 48).rounded()
    }
    /// How far the compact search bar floats above the physical screen bottom.
    static let bareFloat: CGFloat = 12
    /// Vertical chrome around the pinned search field (16 top clears the
    /// grabber, 6 below) — part of every detent's height budget.
    static var searchBlockHeight: CGFloat {
        fieldHeight + 16 + 6
    }
    /// The rest detent: the floating search bar. Detent heights are measured
    /// from the screen bottom (they include the home-indicator region), so
    /// this is bar + float.
    static var peekHeight: CGFloat {
        searchBlockHeight + bareFloat
    }
    static var peekDetent: PresentationDetent {
        .height(peekHeight)
    }
    /// Detents while nothing is staged: the floating bar, browse height, and
    /// full height for search. `.medium` must stay a member of *every* detent
    /// set — `presentationBackgroundInteraction(.enabled(upThrough: .medium))`
    /// resolves against the set, and without the member the system falls back
    /// to a fully modal (dimmed, touch-blocking) presentation. The
    /// fit-to-content compact detent joins once the tray holds doses (see
    /// ``QuickLogDock/refreshDetents()``).
    static var emptyDetents: Set<PresentationDetent> {
        [peekDetent, .medium, .large]
    }
}

// MARK: - Live sheet geometry

/// The dock sheet's live content height, reported by geometry every layout
/// tick of an interactive detent drag. An `@Observable` box — not view
/// `@State` — so those per-frame writes never re-evaluate the dock's whole
/// body. Only the threshold-crossing ``isHeightBare`` flag is read by the
/// body (via ``QuickLogDock/isBare``), and it's written only when it flips, so
/// body-level readers re-evaluate once per crossing instead of once per frame.
@Observable
@MainActor
final class DockSheetGeometry {
    /// Live height of the sheet's content area — the detent `selection` only
    /// updates when a drag settles.
    private(set) var height: CGFloat = 0
    /// Whether the live height is inside the bare (Maps collapsed-pill) zone.
    /// Combined with the tray's emptiness at the read sites: the bare face
    /// only exists for an empty tray (see ``QuickLogDock/isBare``).
    private(set) var isHeightBare = true

    func update(height: CGFloat) {
        if self.height != height { self.height = height }
        let bare = height < QuickLogDockMetrics.peekHeight + 40
        guard bare != isHeightBare else { return }
        isHeightBare = bare
        Self.log.debug("isHeightBare=\(bare, privacy: .public) at height=\(height, privacy: .public)")
    }

    private static let log = Logger(subsystem: "dev.yumeji.piru", category: "dock-geometry")
}

// MARK: - Dock Sheet

/// The staging dock — a native detented sheet presented over the quick-log
/// cover (the Apple Maps model: browse list behind, resizable dock on top).
///
/// One search bar is pinned at the top in every detent so it keeps a single
/// view identity as the sheet resizes. Beneath it the content composes rather
/// than swaps: search results (or browse suggestions) appear above the staged
/// list, which never disappears while searching; the shared chips + Log
/// button stay pinned to the sheet's bottom edge whenever something is
/// staged. The sheet is never dismissible (it's the staging basket, not a
/// throwaway sheet); it collapses to its smallest detent instead.
///
/// Detents are dynamic: with an empty tray the dock rests at the bare search
/// pill; once doses are staged the smallest detent becomes a *fit-to-content*
/// compact height (collapsed rows + Log button, measured live). Dragging down
/// to compact collapses every inline editor; dragging back up restores them.
///
/// State ownership: the tray, content caches, and search text live on
/// `QuickLogView` (browse-list taps stage into the same tray). The dock owns
/// only what's local to its surface — keyboard focus and the detent
/// transitions.
struct QuickLogDock: View {
    var tray: DoseTrayModel
    var content: QuickLogContentModel
    /// Height of the quick-log cover — caps the compact detent so a tall
    /// stack never pushes it past medium.
    var containerHeight: CGFloat
    @Binding var searchText: String
    @Binding var searchActive: Bool
    @Binding var detent: PresentationDetent
    @Binding var detents: Set<PresentationDetent>

    let onCreateCustom: () -> Void
    let onCommit: () -> Void

    @FocusState private var searchFocused: Bool

    /// The bare (Maps collapsed-pill) face: nothing but the floating search
    /// pill. Driven by the *live* sheet height, not the settled detent, so the
    /// content morphs pill → surface continuously while the user drags — but
    /// only for an empty tray: with doses staged the smallest detent is the
    /// fit-to-content compact face, so heights in the bare zone are transient
    /// (the presentation animation, a rubber-band squeeze) and the content
    /// must stay put. That emptiness gate is also what stops the one-frame
    /// content pop-in when the dock mounts with a routine already prestaged
    /// (geometry reports 0 on the first pass).
    private var isBare: Bool {
        tray.isEmpty && geometry.isHeightBare
    }

    /// Live sheet geometry — an `@Observable` box so per-frame drag updates
    /// don't re-evaluate this whole body (see ``DockSheetGeometry``).
    @State private var geometry = DockSheetGeometry()

    // MARK: Compact-detent measurements

    /// Rendered height of the pinned commit bar (chips + Log button + any
    /// open panel).
    @State private var commitBarHeight: CGFloat = 0
    /// The detent machine's mutable registers + UIKit handles, boxed in a
    /// plain (non-observable) class on purpose: nothing in this body renders
    /// from them, and as individual `@State`s every transition's bookkeeping
    /// writes re-ran the whole dock body several times per move. See
    /// ``DockDetentBookkeeping``.
    @State private var bookkeeping = DockDetentBookkeeping()
    /// The dock is animating down to the bare pill after its content emptied
    /// (last dose deleted, search cancelled with nothing staged). While set,
    /// the browse suggestions stay unmounted: the shrink passes through
    /// "empty tray, still tall" — exactly the resting *browse* shape — and
    /// letting the family pills pop in for those few frames read as a flash
    /// of the search state. Cleared on reaching bare, or by any move that
    /// isn't headed there (the user grabbing the sheet mid-shrink).
    @State private var awaitingBareCollapse = false
    /// Rows staged while the dock sits at its compact detent, withheld from
    /// the staged card until the sheet has finished growing. The sheet resize
    /// and a SwiftUI row insertion are two separate animations — composed,
    /// they see-saw the bottom-pinned commit bar (down as the taller content
    /// lays out, back up as the platter catches up). Keeping the list
    /// unchanged while the sheet grows leaves the bar genuinely stationary
    /// (its anchor, the sheet's bottom edge, never moves); the new row then
    /// fades into the space the resize opened up.
    @State private var unrevealedItemIDs: Set<UUID> = []
    /// Estimated height of the staged card with every row collapsed, reported
    /// by ``TrayDerivedObserver`` — mirrored into local state so
    /// ``compactHeightValue`` never reads `tray.staged` from this body (a
    /// whole-array dependency would re-run it on every amount keystroke).
    @State private var stagedCardEstimate: CGFloat = 0

    // MARK: Browse suggestions

    /// The effect-family pills shown in the suggestions state (resolved once —
    /// the taxonomy is static over a session).
    @State private var families: [LibraryFamily] = []
    @State private var selectedFamilyID: String?
    /// Top-by-popularity substances of the selected family.
    @State private var browseResults: [Substance] = []

    /// Memoized interaction check — the result depends only on the set of
    /// staged substance names, so it's recomputed in `onChange` rather than on
    /// every body evaluation (which fires per keystroke in the amount field).
    @State private var interactions: [InteractionResult] = []
    /// Measured height of the warnings card — it lives in the scroll content
    /// below the staged rows, and the fit-to-content detent must include it
    /// so warnings stay visible at compact.
    @State private var interactionsHeight: CGFloat = 0

    var body: some View {
        // The probe hangs off `dockContent` as a **background**, not as a sibling
        // in a `ZStack`.
        //
        // A `ZStack` takes the union of its children, and the probe deliberately
        // ignores the bottom container *and* keyboard regions — so it reports a
        // taller size than the sheet proposed, and the stack becomes oversize. An
        // oversize view is not clipped to its container; SwiftUI *centers* it,
        // which lifts its top edge by half the overflow. With a 34pt home
        // indicator that is ~17pt; with a stale keyboard layout guide it is
        // unbounded. That is the one mechanism in this file that moves the entire
        // content column rather than just the field — matching the report that
        // read "the search bar and the whole content shifted up again".
        //
        // A background is sized by its primary content and can never push the
        // host around, while `ignoresSafeArea` inside it still lets the probe
        // extend past the insets, so the measurement is unchanged.
        dockContent
            .background(alignment: .top) { proposalProbe }
    }

    private var proposalProbe: some View {
        Color.clear
            .ignoresSafeArea([.container, .keyboard], edges: .bottom)
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { newValue in
                geometry.update(height: newValue)
            }
    }

    private var dockContent: some View {
        dockLayout
            .onChange(of: searchFocused) { handleSearchFocusChanged() }
            // External exits (staging a result, the browse list's cancel) flip
            // `searchActive` off — release focus and settle onto the right detent.
            .onChange(of: searchActive) { handleSearchActiveChanged() }
            .onChange(of: detent) { oldValue, newValue in
                detentChanged(from: oldValue, to: newValue)
            }
            // A first staged dose (from the browse list behind, at peek) grows
            // the dock just enough to show the collapsed tray + Log button.
            // Staging *another* dose while the dock rests at compact sequences
            // the same move: sheet first (list unchanged, bar stationary), then
            // the new row fades into the opened space — see ``unrevealedItemIDs``.
            .onChange(of: tray.stageTick) { handleStaged() }
            // A draft staged for editing (search result, routine deep link)
            // needs the editor visible — compact can't show it.
            .onChange(of: tray.expandedItemIDs) { handleExpandedItemsChanged() }
            .onChange(of: tray.isEmpty) { handleTrayEmptinessChanged() }
            .onChange(of: isBare) {
                if isBare { awaitingBareCollapse = false }
            }
            // Keep the fit-to-content detent tracking its content: row heights,
            // the commit bar (panels opening), and staging changes all funnel
            // into this one value.
            .onChange(of: compactHeightValue) { handleCompactHeightChanged() }
            // A routine prestaged before the sheet mounted (notification deep
            // link) should land already showing the tray.
            .onAppear(perform: handleAppear)
    }

    private var dockLayout: some View {
        VStack(spacing: 0) {
            // The search bar keeps one identity in every dock state and is simply
            // pinned to the top — a fixed 16pt below the grabber — in all of them.
            // The bare pill used to be *centered* by a measured top padding, but
            // that read the live sheet height, which an orphaned keyboard (left by
            // an app switch clobbering the shared keyboard) inflates via the
            // keyboard layout guide, drifting the pill up and cropping it
            // (TestFlight 2.2 (30), iOS 26.5.2). Top-pinning has no height to
            // corrupt — and it's already what the taller detents do, correctly.
            // The peek detent is sized (``peekHeight``) so the pinned pill + the
            // fixed ``bareFloat`` gap below read as a floating bar.
            DockSearchBar(
                searchText: $searchText,
                searchActive: searchActive,
                searchFocused: $searchFocused,
                onCancel: cancelSearch,
            )
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 6)

            ScrollView {
                DockMiddleContent(
                    isBare: isBare,
                    searchActive: searchActive,
                    searchText: searchText,
                    tray: tray,
                    content: content,
                    families: families,
                    selectedFamilyID: $selectedFamilyID,
                    browseResults: $browseResults,
                    interactions: interactions,
                    interactionsHeight: $interactionsHeight,
                    unrevealedItemIDs: unrevealedItemIDs,
                    awaitingBareCollapse: awaitingBareCollapse,
                    onCreateCustom: {
                        // Release focus before presenting — restoring focus
                        // mid-transition on dismiss caused the SheetBridge
                        // exclusivity crash (builds 13/14).
                        searchFocused = false
                        onCreateCustom()
                    },
                    onDidStage: finishStagingFromSearch,
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            // Maps behavior: dragging up inside the dock resizes it first;
            // content scrolls only at the tallest detent.
            .scrollDisabled(detent != .large)
            .scrollDismissesKeyboard(.interactively)
            // The commit bar lives in the scroll's bottom safe-area bar with
            // the soft edge effect — content passes beneath it instead of
            // being hard-clipped above it.
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .safeAreaBar(edge: .bottom) {
                DockCommitBarArea(
                    tray: tray,
                    content: content,
                    isBare: isBare,
                    commitBarHeight: $commitBarHeight,
                    onCommit: onCommit,
                )
            }
            // The bar above never unmounts (see ``DockCommitBarArea``), so its
            // safe-area inset becomes the scroll region's *minimum* height —
            // taller than the whole bare pill. Left unchecked, that minimum
            // wedges the sheet's shrink to peek: UIKit can't compress the
            // content (it squishes the platter with a scale transform
            // instead) and the proposal never reaches the bare zone, so
            // ``isBare`` never flips back after the last dose is deleted.
            // A frame with *both* bounds sizes to the clamped proposal,
            // ignoring the child's minimum — the scroll region then tracks
            // whatever height the sheet actually proposes, and the hidden
            // bar just overflows out of sight at the small detents.
            .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
        }
        // Fill the sheet and pin to its top edge, in every face. The system
        // sheet's glass platter is the dock's surface throughout — we draw no
        // chrome of our own — and the search bar's position is then one
        // constant (16pt) below the platter. That is the invariant the shear
        // reports violate: measured on a 17 Pro Max / iOS 26.5, the bar's top
        // sits 14.2pt below the sheet's at the bare pill (drawn scaled 0.888),
        // 15.4 at medium (0.964) and 16.0 unscaled at large. Negative means the
        // field has climbed out of its platter.
        //
        // This used to be two stacked frames, the inner one dropping to an
        // intrinsic height while ``isBare``. That made a *measured* value
        // decide the shape of the region the same measurement is taken from —
        // height → flag → layout → height — and the two frames then top-aligned
        // to the same place anyway, so the branch bought nothing but the loop.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // At the small detents the sheet is barely taller than the
        // home-indicator inset, so the content claims it rather than being
        // squeezed above it. Keyed on the tray being empty, not on ``isBare``:
        // the inset only needs respecting when there is a bottom-pinned commit
        // bar to keep clear of it, and that depends on the tray alone. Keying
        // it on the measured flag put the second half of the layout feedback
        // loop here.
        .ignoresSafeArea(.container, edges: tray.isEmpty ? .bottom : [])
        // The dock does NOT keyboard-avoid: the chips + Log bar stay pinned
        // to the sheet's bottom and the keyboard slides over them. Avoidance
        // shoved the whole bottom half upward mid-transition — half the views
        // riding the keyboard animation, half staged — which read as chaos.
        // Search results live at the top, so nothing needed is hidden.
        .ignoresSafeArea(.keyboard)
        // The dose fields use the decimal pad, which has no return key. Rather
        // than the lone floating "Done" accessory (unpolished), a tap anywhere
        // outside the focused field dismisses the keyboard — the value is
        // already committed live per keystroke, so there is nothing to submit.
        // A window-level recognizer is what catches taps in the sheet's large
        // empty area, not just within the laid-out content (see
        // ``KeyboardDismissTap``). Drag/scroll dismissal still applies too.
        .background { KeyboardDismissTap() }
        // The staged-array reads (interaction names, collapsed-card estimate)
        // live in this zero-size leaf, not in this body — otherwise every
        // amount keystroke in a staged editor would re-run the whole dock.
        .background {
            TrayDerivedObserver(
                tray: tray,
                onInteractions: { newValue in
                    if newValue != interactions { interactions = newValue }
                },
                onStagedEstimate: { newValue in
                    if newValue != stagedCardEstimate { stagedCardEstimate = newValue }
                },
            )
        }
        .background { SheetHostProbe(box: bookkeeping.host) }
        // The empty⇄staged face swap mounts/unmounts dock content with NO
        // animation: the sheet's detent change is the one animated element,
        // and the content — laid out at its final frame from the first
        // moment — just rides under the growing platter (the native sheet
        // feel). Without this, the call sites' `withAnimation` played the
        // staged card as a scale-from-center bloom inside the resize. Scoped
        // to the *emptiness* flip only: adding to or removing from an
        // already-visible staged list keeps the callers' animation, so the
        // card grows/shrinks in step with the sheet instead of snapping a
        // row in before the platter has moved. Sits *inside* the isBare
        // animation below so it wins for updates where both change (staging
        // the first dose from the bare pill).
        .transaction(value: tray.isEmpty) { $0.animation = nil }
        .animation(.snappy, value: isBare)
        // Presentation configuration (detents, clear background, background
        // interaction) is applied by `QuickLogView` at the sheet closure's
        // root — attached in here it competes with the nested `.sheet`/
        // `.fullScreenCover` wrappers layered on top of this view. The
        // onChange/onAppear behavior handlers live on `dockContent`.
    }

    private func handleSearchFocusChanged() {
        if searchFocused {
            withAnimation(.snappy) { searchActive = true }
            // Always the full height: the keyboard covers the lower half of
            // the sheet, and UIKit auto-expands a keyboard-covered sheet to
            // its largest detent anyway.
            moveDetent(to: .large)
        } else if searchText.isEmpty, searchActive {
            withAnimation(.snappy) { searchActive = false }
        }
    }

    private func handleSearchActiveChanged() {
        guard !searchActive else { return }
        searchFocused = false
        selectedFamilyID = nil
        browseResults = []
        if tray.isEmpty { awaitingBareCollapse = true }
        withAnimation(.snappy) { settleDetent() }
    }

    private func handleExpandedItemsChanged() {
        guard !tray.expandedItemIDs.isEmpty,
              detent == QuickLogDockMetrics.peekDetent || detent == bookkeeping.compactDetent
        else { return }
        moveDetent(to: .medium)
    }

    private func handleTrayEmptinessChanged() {
        // Only arm the suppression when the dock is genuinely *headed* for the
        // bare pill. ``refreshDetents()`` keeps the current selection whenever
        // it is already a valid empty-tray detent — and `.medium`/`.large` are
        // — so deleting the last dose there moved nothing, `detentChanged`
        // never ran, and the flag that unmounts the browse face never cleared:
        // a blank half-height sheet with only a search bar, recoverable only by
        // closing the cover. Reproduced on iOS 26.5 (stage from search, then
        // delete the row) and it predates the layout simplification above.
        awaitingBareCollapse = tray.isEmpty && !searchActive
            && !QuickLogDockMetrics.emptyDetents.contains(detent)
        if tray.isEmpty { unrevealedItemIDs.removeAll() }
        refreshDetents()
    }

    private func handleAppear() {
        families = LibraryFamily.browsable
        guard !tray.isEmpty else { return }
        refreshDetents()
        if tray.expandedItemIDs.isEmpty, let compactDetent = bookkeeping.compactDetent {
            detent = compactDetent
        } else {
            detent = .medium
        }
    }

    // MARK: Detents

    /// The body-observable trigger for detent refreshes, built from the
    /// observer-mirrored ``stagedCardEstimate`` so this body never reads
    /// `tray.staged`. Handlers don't use it — they compute the staged-card
    /// term fresh from the tray (see ``refreshDetents()``), because the
    /// mirror can lag the mutation that triggered the handler by one update.
    private var compactHeightValue: CGFloat {
        compactHeight(stagedCard: stagedCardEstimate)
    }

    /// The fit-to-content compact height: search block + collapsed staged
    /// card + commit bar, capped below medium so a tall stack degrades
    /// gracefully. `.height` detents measure *above* the home-indicator
    /// inset (the system adds it below), so the inset is not budgeted here.
    private func compactHeight(stagedCard: CGFloat) -> CGFloat {
        // Scroll-content vertical padding around the staged card (8 top + 12 bottom).
        let contentPadding: CGFloat = 20
        // Chips row (12 + chip) + Log button (14 + control) until the bar has
        // been measured — staging at peek mints the compact detent before the
        // bar exists, and minting it at a throwaway height churned the sheet's
        // detent mapping right as it grew. Estimated from type metrics so the
        // pre-measure mint stays close at accessibility sizes too.
        let chipHeight = UIFont.preferredFont(forTextStyle: .subheadline).lineHeight + 20
        let barEstimate = 12 + chipHeight + 14 + DoseTrayMetrics.controlHeight
        let bar = commitBarHeight > 0 ? commitBarHeight : barEstimate
        var raw = QuickLogDockMetrics.searchBlockHeight + contentPadding
        raw += stagedCard
        if !interactions.isEmpty {
            // Card spacing (14) + measured height, estimated until laid out
            // (~66pt per two-line warning row at the default size) so the
            // detent mints once.
            let rowEstimate = UIFontMetrics(forTextStyle: .subheadline).scaledValue(for: 66)
            raw += 14 + (interactionsHeight > 0 ? interactionsHeight : CGFloat(interactions.count) * rowEstimate + 24)
        }
        raw += bar
        let cap: CGFloat = containerHeight > 0 ? containerHeight * 0.5 - 40 : 420
        return min(raw, cap).rounded()
    }

    /// Swap the detent set for the tray's current shape, keeping the
    /// selection valid (and pinned to compact while it's the selection).
    /// `onSettled` fires once the sheet is at rest at the new selection.
    private func refreshDetents(onSettled: (() -> Void)? = nil) {
        if tray.isEmpty {
            bookkeeping.compactDetent = nil
            bookkeeping.compactValue = 0
            let target = QuickLogDockMetrics.emptyDetents
            if target.contains(detent) || searchActive {
                applyDetents(target, selecting: searchActive ? .large : detent, onSettled: onSettled)
            } else {
                applyDetents(
                    target,
                    selecting: QuickLogDockMetrics.peekDetent,
                    height: QuickLogDockMetrics.peekHeight,
                    onSettled: onSettled,
                )
            }
        } else {
            let wasCompact = bookkeeping.compactDetent != nil && detent == bookkeeping.compactDetent
            // Fresh staged-card term, not the mirrored @State: a handler can
            // run before the observer's callback has delivered the estimate
            // for the mutation that triggered it (e.g. staging at peek), and
            // minting from the stale mirror would step the sheet twice.
            let newValue = compactHeight(
                stagedCard: TrayDerivedObserver.estimatedStagedCardHeight(count: tray.staged.count),
            )
            let newCompact = PresentationDetent.height(newValue)
            bookkeeping.compactDetent = newCompact
            bookkeeping.compactValue = newValue
            let target: Set<PresentationDetent> = [newCompact, .medium, .large]
            let needsMove = wasCompact || !target.contains(detent)
            applyDetents(
                target,
                selecting: needsMove ? newCompact : detent,
                height: needsMove ? newValue : nil,
                onSettled: onSettled,
            )
        }
    }

    /// Replace the detent set and animate the selection over to `selection`
    /// through UIKit's own machinery.
    ///
    /// SwiftUI's binding path can't animate this: it applies a detent-set
    /// swap + selection change as a snap, and even a pure selection change
    /// animates as a Core Animation interpolation of the platter against a
    /// content laid out once at final size — displacing bottom-pinned content
    /// (the chips + Log bar) by the whole height delta. UIKit's
    /// `UISheetPresentationController.animateChanges` is the API the system
    /// itself uses and resizes correctly, but SwiftUI doesn't expose it — so
    /// the sheet's presenting controller is memoized by ``SheetHostProbe``
    /// and driven directly: (1) this update grows the SwiftUI detent set to a
    /// superset so the target member exists; (2) one runloop turn later (the
    /// members have reached UIKit) the matching UIKit detent is selected
    /// inside `animateChanges`, with the SwiftUI selection binding synced to
    /// the same member so the model agrees; (3) when the move settles the
    /// stale members are pruned so they never become resting stops.
    private func applyDetents(
        _ target: Set<PresentationDetent>,
        selecting selection: PresentationDetent,
        height: CGFloat? = nil,
        onSettled: (() -> Void)? = nil,
    ) {
        bookkeeping.generation &+= 1
        let generation = bookkeeping.generation
        guard selection != detent else {
            detents = target
            onSettled?()
            return
        }
        // Target members plus the *outgoing* selection as a bridge until the
        // move lands. Members outside the target drop immediately — removing
        // a non-selected detent never moves the sheet, and a lingering
        // member can be actively harmful (UIKit auto-expands to the largest
        // member when the keyboard appears, so capping a search at medium
        // only works if `.large` is already gone).
        detents = target.union([detent])
        Task { @MainActor in
            guard generation == bookkeeping.generation else { return }
            guard let sheet = bookkeeping.host.sheetController else {
                // Not yet presented (first-appear configuration) — a plain
                // binding write is correct here; there is nothing on screen
                // to animate.
                detent = selection
                detents = target
                onSettled?()
                return
            }
            animateSelection(selection, height: height, in: sheet) {
                guard generation == bookkeeping.generation else { return }
                detents = target
                onSettled?()
            }
        }
    }

    /// Animates the sheet to `selection` through the memoized UIKit handle.
    ///
    /// Height→height moves ramp a mutable detent per display frame (see
    /// ``animateHeightDetent(in:from:to:onSettled:)``): both `animateChanges`
    /// and SwiftUI's binding animate the platter as a Core Animation
    /// interpolation over content laid out ONCE at final size, which
    /// displaces everything (frame-strip verified: the whole dock, search
    /// bar to Log button, dips by the height delta and rides back). Only
    /// per-frame layout — what a real drag does — keeps the bottom-pinned
    /// bar stationary.
    ///
    /// Two kinds of move go through `animateChanges` instead:
    /// `.medium`/`.large` (search, editors — full content swaps where
    /// displacement doesn't read), and the shrink to the bare *peek* pill.
    /// The smallest detent's resting look is the floating pill (scaled,
    /// lifted off the bottom edge), which only UIKit can animate into — a
    /// ramp that lands on the logical height leaves UIKit to morph the pill
    /// treatment afterwards, which read as the search bar drifting to its
    /// spot after the resize had visibly finished. The displacement artifact
    /// needs *bottom-pinned* visible content, and a dock headed to bare has
    /// none: the commit bar is hidden and the suggestions suppressed — only
    /// the top-pinned search bar rides the platter, which CA animates
    /// correctly, in one continuous settle like a released drag.
    private func animateSelection(
        _ selection: PresentationDetent,
        height: CGFloat?,
        in sheet: UISheetPresentationController,
        completion: @escaping @MainActor () -> Void,
    ) {
        if let height, let fromLogical = currentLogicalHeight(),
           selection != QuickLogDockMetrics.peekDetent {
            animateHeightDetent(in: sheet, from: fromLogical, to: height) {
                // Land the model on geometry that is already exactly there:
                // an un-animated selection change re-resolves the sheet to
                // the height the ramp just left it at.
                detent = selection
                completion()
            }
            return
        }
        bookkeeping.frameAnimator.cancel()
        bookkeeping.rampLogicalTarget = nil
        var identifier: UISheetPresentationController.Detent.Identifier?
        if selection == .medium {
            identifier = .medium
        } else if selection == .large {
            identifier = .large
        } else if let height {
            let context = SheetDetentResolutionContext(
                containerTraitCollection: sheet.traitCollection,
                maximumDetentValue: maximumDetentValue(of: sheet),
            )
            identifier = sheet.detents.first { candidate in
                guard candidate.identifier != .medium, candidate.identifier != .large,
                      let resolved = candidate.resolvedValue(in: context) else { return false }
                return abs(resolved - height) < 1
            }?.identifier
        }
        guard let identifier else {
            // No UIKit counterpart found — fall back to the binding.
            withAnimation(.snappy) { detent = selection }
            completion()
            return
        }
        CATransaction.begin()
        CATransaction.setCompletionBlock {
            MainActor.assumeIsolated { completion() }
        }
        sheet.animateChanges {
            sheet.selectedDetentIdentifier = identifier
        }
        CATransaction.commit()
        // Sync the SwiftUI model to the member UIKit is now moving to — same
        // underlying detent, so SwiftUI's re-application is a no-op.
        detent = selection
    }

    /// Numeric height of the *current* selection: the in-flight ramp target
    /// when one is running (chained retargets), otherwise the resting value
    /// tracked by ``detentChanged(from:to:)``. `nil` for `.medium`/`.large`.
    private func currentLogicalHeight() -> CGFloat? {
        bookkeeping.rampLogicalTarget ?? bookkeeping.restingLogicalHeight
    }

    /// The interpolated drag, through the controller's own machinery: a
    /// custom detent with a *mutable* height is injected and selected
    /// un-animated (it resolves to the current height — no motion), then the
    /// height is eased on a display link with `invalidateDetents()` per tick.
    /// Each invalidation re-resolves the detent and runs the sheet's full
    /// resize path at the new height — real layout every frame, exactly like
    /// the pan gesture, with none of the controller's bookkeeping bypassed.
    /// (Direct `presentedView.frame` writes fought the controller: it
    /// reasserted its own frame — no visible animation — and compensated
    /// with residual scale transforms that accumulated into permanent layout
    /// corruption, lldb-verified.)
    private func animateHeightDetent(
        in sheet: UISheetPresentationController,
        from fromLogical: CGFloat,
        to toLogical: CGFloat,
        onSettled: @escaping @MainActor () -> Void,
    ) {
        // Chained retarget: continue from the ramp's live height.
        let start = bookkeeping.rampLogicalTarget != nil ? bookkeeping.rampDetent.height : fromLogical
        bookkeeping.rampLogicalTarget = toLogical
        bookkeeping.rampDetent.height = start
        installRampDetent(in: sheet)
        bookkeeping.frameAnimator.run(from: start, to: toLogical) { height in
            bookkeeping.rampDetent.height = height
            // Self-heal: a SwiftUI presentation update mid-ramp can rewrite
            // the sheet's detents/selection; re-assert before invalidating.
            installRampDetent(in: sheet)
            sheet.invalidateDetents()
        } completion: {
            bookkeeping.rampLogicalTarget = nil
            onSettled()
        }
    }

    /// Ensures the mutable ramp detent is a member of the sheet's detents and
    /// is the selection (both idempotent — no-ops while already installed).
    private func installRampDetent(in sheet: UISheetPresentationController) {
        if !sheet.detents.contains(where: { $0.identifier == MutableSheetDetent.identifier }) {
            sheet.detents += [bookkeeping.rampDetent.detent]
        }
        if sheet.selectedDetentIdentifier != MutableSheetDetent.identifier {
            sheet.selectedDetentIdentifier = MutableSheetDetent.identifier
        }
    }

    /// The container height `.height` detents resolve against — only needs to
    /// exceed the dock's real heights for exact matching, so the fallback is
    /// generous.
    private func maximumDetentValue(of sheet: UISheetPresentationController) -> CGFloat {
        guard let container = sheet.containerView else { return 2_000 }
        return container.bounds.height - container.safeAreaInsets.top
    }

    /// Detent-selection side effects: leaving `.large` cancels search;
    /// arriving at compact collapses every editor; growing out of compact
    /// restores them.
    private func detentChanged(from oldValue: PresentationDetent, to newValue: PresentationDetent) {
        // Track the resting numeric height for the frame-level resize (every
        // settle passes through here — drags and programmatic moves alike).
        if newValue == QuickLogDockMetrics.peekDetent {
            bookkeeping.restingLogicalHeight = QuickLogDockMetrics.peekHeight
        } else if let compactDetent = bookkeeping.compactDetent, newValue == compactDetent {
            bookkeeping.restingLogicalHeight = bookkeeping.compactValue
        } else {
            bookkeeping.restingLogicalHeight = nil
        }
        // Any move that isn't headed to the bare pill revives the suggestions
        // (the user grabbed the sheet mid-shrink).
        if newValue != QuickLogDockMetrics.peekDetent { awaitingBareCollapse = false }
        // Dragging the dock down leaves search — Maps behavior.
        if newValue != .large, searchActive {
            searchFocused = false
            withAnimation(.snappy) {
                searchActive = false
                searchText = ""
            }
        }
        guard let compactDetent = bookkeeping.compactDetent else { return }
        // The expansion side effects run a turn later: mutating the sheet's
        // content inside the same transaction as the detent change cancels
        // the sheet's settle animation — the selection lands on the new
        // detent while the sheet visually springs back to the old one.
        if newValue == compactDetent, oldValue != compactDetent {
            Task { @MainActor in
                // The compact detent fits *collapsed* rows only.
                withAnimation(.snappy) {
                    tray.expandedItemIDs.removeAll()
                }
            }
        } else if oldValue == compactDetent,
                  newValue == .medium || newValue == .large,
                  tray.expandedItemIDs.isEmpty {
            Task { @MainActor in
                // Growing the dock re-opens every staged editor.
                withAnimation(.snappy) {
                    tray.expandedItemIDs = Set(tray.staged.map(\.id))
                }
            }
        }
    }

    /// Reacts to a new staged row (``DoseTrayModel/stageTick``). At peek the
    /// dock simply grows to its fit-to-content detent; at compact the same
    /// move is *sequenced* — sheet first with the list unchanged, then the
    /// new row fades into the opened space (see ``unrevealedItemIDs``).
    private func handleStaged() {
        guard !searchActive else { return }
        if detent == QuickLogDockMetrics.peekDetent {
            refreshDetents()
        } else if let compactDetent = bookkeeping.compactDetent, detent == compactDetent,
                  let newest = tray.staged.last,
                  !tray.expandedItemIDs.contains(newest.id) {
            unrevealedItemIDs.insert(newest.id)
            refreshDetents {
                withAnimation(.snappy) { _ = unrevealedItemIDs.remove(newest.id) }
            }
        }
    }

    /// Keeps the fit-to-content detent tracking the content height. A shrink
    /// while resting *at* compact (a row swiped away) is deferred until the
    /// row's exit animation has finished — run concurrently, the two
    /// animations see-saw the bottom-pinned commit bar (the mirror image of
    /// the staged-row sequencing in ``handleStaged()``).
    private func handleCompactHeightChanged() {
        guard !tray.isEmpty, abs(compactHeightValue - bookkeeping.compactValue) >= 6 else { return }
        if compactHeightValue < bookkeeping.compactValue,
           let compactDetent = bookkeeping.compactDetent, detent == compactDetent {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                guard !tray.isEmpty, abs(compactHeightValue - bookkeeping.compactValue) >= 6 else { return }
                refreshDetents()
            }
        } else {
            refreshDetents()
        }
    }

    /// Animate a pure selection move on the next runloop turn. In-update
    /// moves share the triggering content mutation's transaction and snap —
    /// see ``swapDetents(to:selecting:)``. The target must already be a
    /// member of ``detents``.
    private func moveDetent(to selection: PresentationDetent, height: CGFloat? = nil) {
        applyDetents(detents, selecting: selection, height: height)
    }

    private func settleDetent() {
        if tray.isEmpty {
            // Full empty set as the target — search may have capped the set
            // at medium (see ``enterSearchDetents()``), and the resting bare
            // dock must offer `.large` again for browse drags.
            applyDetents(
                QuickLogDockMetrics.emptyDetents,
                selecting: QuickLogDockMetrics.peekDetent,
                height: QuickLogDockMetrics.peekHeight,
            )
        } else {
            refreshDetents()
            if tray.expandedItemIDs.isEmpty, let compactDetent = bookkeeping.compactDetent {
                moveDetent(to: compactDetent, height: bookkeeping.compactValue)
            } else {
                moveDetent(to: .medium)
            }
        }
    }

    // MARK: Keyboard & search dismissal

    private func cancelSearch() {
        searchFocused = false
        withAnimation(.snappy) {
            searchActive = false
            searchText = ""
        }
    }

    /// Ends the search after a result is staged: dismisses the keyboard, drops
    /// the search state, and settles onto medium with the staged rows expanded.
    ///
    /// Leaving search up (the old behavior) left the results list and keyboard
    /// covering the row the user had just added — so a stage from search now
    /// finishes the search the same way picking a result in a search field
    /// dismisses it. No-op when nothing is searching, which keeps a tap on the
    /// browse suggestions (dragged tall with the field unfocused) growing the
    /// dock in place as before.
    ///
    /// The exit is deferred a runloop turn on purpose. Staging fires its *own*
    /// detent bookkeeping this turn — `tray.isEmpty` flipping (first dose) and
    /// `stageTick` each run `refreshDetents`, which bumps the detent
    /// generation. Closing the search in the same transaction would schedule
    /// the `.medium` settle and then have that later refresh cancel it (the
    /// generation guard in ``applyDetents``), stranding the dock at `.large`
    /// with a collapsed row. Run next turn, the close owns the transaction:
    /// expanding every row first makes ``settleDetent`` land on `.medium` with
    /// the editors open rather than the compact collapsed face.
    private func finishStagingFromSearch() {
        guard searchActive else { return }
        Task { @MainActor in
            tray.expandedItemIDs = Set(tray.staged.map(\.id))
            searchFocused = false
            withAnimation(.snappy) {
                searchActive = false
                searchText = ""
            }
        }
    }
}

// MARK: - Tap-outside-to-dismiss

/// Installs a tap recognizer on the host window that resigns the keyboard on a
/// tap outside the focused field — the polished substitute for a "Done"
/// accessory the decimal pad can't host (it has no return key). The dose fields
/// commit their value live on every keystroke, so dismissing *is* the only job.
///
/// Why window-level (not a SwiftUI `onTapGesture`): the sheet's empty region —
/// the tall gap below a short staged card when the keyboard is up — lies
/// *outside* the laid-out content, where a content-attached gesture never
/// fires. A window recognizer sees every tap in the presentation.
///
/// `cancelsTouchesInView = false` lets the tap still reach whatever it hit, so
/// buttons/steppers/menus keep working; the delegate declines taps that land in
/// a text input (`UITextField`/`UITextView`, which back SwiftUI's amount and
/// note fields) so *re-tapping a field* doesn't immediately blur it. The
/// recognizer is torn down with the dock, so it's live only while staging.
private struct KeyboardDismissTap: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> InstallerView {
        let view = InstallerView()
        view.isUserInteractionEnabled = false
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_: InstallerView, context _: Context) {}

    static func dismantleUIView(_: InstallerView, coordinator: Coordinator) {
        coordinator.detach()
    }

    /// Installs/removes the recognizer as it actually enters and leaves a
    /// window — `didMoveToWindow` is the reliable hook (the window is not yet
    /// attached inside `makeUIView`).
    final class InstallerView: UIView {
        weak var coordinator: Coordinator?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window { coordinator?.attach(to: window) } else { coordinator?.detach() }
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var window: UIWindow?
        private weak var recognizer: UITapGestureRecognizer?

        func attach(to window: UIWindow) {
            guard self.recognizer == nil else { return }
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            tap.cancelsTouchesInView = false
            tap.delegate = self
            window.addGestureRecognizer(tap)
            self.window = window
            self.recognizer = tap
        }

        func detach() {
            if let recognizer { window?.removeGestureRecognizer(recognizer) }
            recognizer = nil
            window = nil
        }

        @objc
        private func handleTap() {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil,
            )
        }

        /// Let the sheet's own pan/scroll gestures run alongside this tap.
        func gestureRecognizer(
            _: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer,
        ) -> Bool {
            true
        }

        /// Don't fire when the tap lands in a text input — that tap is the user
        /// (re)focusing a field, and dismissing would fight it.
        func gestureRecognizer(
            _: UIGestureRecognizer, shouldReceive touch: UITouch,
        ) -> Bool {
            var view = touch.view
            while let current = view {
                if current is UITextField || current is UITextView { return false }
                view = current.superview
            }
            return true
        }
    }
}

// MARK: - Geometry & tray leaves

/// Zero-size leaf owning the dock's derived reads of the staged array — the
/// interaction-check names and the collapsed-card height estimate. Both fold
/// per-dose mutations down to values that only change on structural edits, so
/// an amount keystroke (which mutates `tray.staged` and would re-run any body
/// observing it) invalidates just this leaf; the dock body hears about it only
/// when a folded value actually changes, via the callbacks.
private struct TrayDerivedObserver: View {
    var tray: DoseTrayModel
    let onInteractions: ([InteractionResult]) -> Void
    let onStagedEstimate: (CGFloat) -> Void

    private var stagedNameSet: Set<String> {
        Set(tray.staged.map(\.substanceName))
    }

    /// One collapsed row's height, derived from the type metrics `TrayRow`
    /// renders with (body title + subheadline detail + 2pt spacing + 12pt
    /// vertical padding each side). Computed, not measured: live geometry
    /// reports animated in-between frames during expand/collapse, which
    /// churned the fit-to-content detent mid-gesture.
    private static var collapsedRowHeight: CGFloat {
        let title = UIFont.preferredFont(forTextStyle: .body).lineHeight
        let subtitle = UIFont.preferredFont(forTextStyle: .subheadline).lineHeight
        return (title + subtitle + 2 + 24).rounded(.up)
    }

    /// Height of the staged card with every row collapsed. Static so the
    /// dock's handlers can compute it fresh from the tray without waiting for
    /// the observer's callback round-trip.
    static func estimatedStagedCardHeight(count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        let rows = collapsedRowHeight * CGFloat(count)
        let dividers = CGFloat(max(0, count - 1)) * (1.0 / 3.0)
        return rows + dividers
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: stagedNameSet, initial: true) { _, names in
                // The dock sits above the commit bar mid-log. Only findings
                // that have earned an interruption get a row here; the rest are
                // a count that opens the explorer.
                onInteractions(
                    names.count >= 2
                        ? InteractionChecker.checkBatch(Array(names), against: [])
                        : [],
                )
            }
            .onChange(of: Self.estimatedStagedCardHeight(count: tray.staged.count), initial: true) { _, estimate in
                onStagedEstimate(estimate)
            }
    }
}
