import SwiftData
import SwiftUI
import TipKit
import UIKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appNavigator) private var navigator
    @Environment(\.modelContext) private var modelContext

    /// A thin root. `MainTabView` now owns its own search state (no bindings in),
    /// so it has zero stored inputs and SwiftUI skips re-evaluating it whenever
    /// this body re-runs (scene-phase change). The launch chrome — onboarding,
    /// the Discord invite, the store-health alert + diagnostics — lives in
    /// self-owning `ViewModifier`s so their `@State` churn stays out of this body
    /// (and out of the tab tree). No more `.equatable()` band-aid: an input-free
    /// view is trivially comparable.
    var body: some View {
        MainTabView()
            .sheetStackPresenter(navigator)
            .modifier(OnboardingGateModifier())
            .modifier(DiscordInviteModifier())
            .modifier(StoreDiagnosticsModifier())
            .onOpenURL { handleDeepLink($0) }
            .onChange(of: scenePhase) {
                if scenePhase == .active {
                    ActiveSessionManager.shared.refresh()
                }
            }
    }

    // MARK: - Deep Linking

    private func handleDeepLink(_ url: URL) {
        guard let outcome = DeepLink.decode(url) else { return }
        // A `piru://day` link targets the current session; resolving its id
        // here lets the navigator reveal an already-open session screen
        // instead of presenting a duplicate sheet over it.
        let sessionID = outcome.sheet == .sessionDetail ? mostRecentSessionID(in: modelContext) : nil
        navigator.apply(outcome, currentSessionID: sessionID)
    }
}

/// The session the `.sessionDetail` sheet would resolve — the most recent by
/// start date (mirrors `CurrentSessionHost`). Used by the deep link handler
/// and the session accessory to reveal an already-open session screen rather
/// than presenting a duplicate sheet.
private func mostRecentSessionID(in context: ModelContext) -> UUID? {
    var descriptor = FetchDescriptor<Session>(sortBy: [SortDescriptor(\.startDate, order: .reverse)])
    descriptor.fetchLimit = 1
    return try? context.fetch(descriptor).first?.id
}

// MARK: - Launch Chrome Modifiers

/// Presents onboarding until the user completes it. Owns the `@AppStorage` flag
/// so its toggling never re-runs the root body.
private struct OnboardingGateModifier: ViewModifier {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: .init(
            get: { !hasCompletedOnboarding },
            set: { if !$0 { hasCompletedOnboarding = true } },
        )) {
            OnboardingView()
        }
    }
}

/// Invites the user to the community Discord — but only once they're genuinely engaged: past the
/// first couple of sessions (`appLaunchCount >= 3`) and having logged at least one dose. Shown a
/// single time, never in the first session, and never stacked on the first-run tips (a logged dose
/// means the "log a dose" tip has already retired). A brand-new user is never ambushed; someone who
/// keeps coming back gets a genuine invitation.
private struct DiscordInviteModifier: ViewModifier {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("discordPromptShown") private var discordShown = false
    @AppStorage("discordPromptDismissedForever") private var discordDismissed = false
    @AppStorage("appLaunchCount") private var appLaunchCount = 0
    @Environment(\.modelContext) private var modelContext
    @State private var showDiscordPrompt = false

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showDiscordPrompt) {
                DiscordPromptView()
            }
            .task {
                guard hasCompletedOnboarding, !discordShown, !discordDismissed, appLaunchCount >= 3
                else { return }
                let hasDose = ((try? modelContext.fetchCount(FetchDescriptor<DoseEntry>())) ?? 0) > 0
                guard hasDose else { return }
                try? await Task.sleep(for: .seconds(1.0))
                guard !discordShown, !discordDismissed else { return }
                discordShown = true
                showDiscordPrompt = true
            }
    }
}

/// Launch-time store-health reassurance: when the persistent store can't be
/// opened the app runs in-memory and this surfaces a "your data is safe" alert
/// plus an off-main diagnostics export. Owns all of that churning `@State`.
private struct StoreDiagnosticsModifier: ViewModifier {
    @State private var storeLaunch = StoreLaunchState.shared
    @State private var dismissedStoreAlert = false
    @State private var preparingDiagnostics = false
    @State private var diagnosticsFile: DiagnosticsFile?
    @State private var diagnosticsError: String?

    func body(content: Content) -> some View {
        content
            .alert("Your Data Is Safe", isPresented: storeUnavailableAlertBinding) {
                Button("Send Logs to Developer") { prepareDiagnostics() }
                Button("OK", role: .cancel) {}
            } message: {
                Text("Piru couldn't open your journal this time, so it's running with temporary storage. **Nothing has been deleted** — your doses and sessions are safe on this device and a future update will restore them automatically.\n\nSending the logs helps us ship that fix faster. They describe the storage problem only — never your dose data.")
            }
            .sheet(item: $diagnosticsFile, onDismiss: cleanupDiagnostics) { file in
                ShareSheet(items: [file.url])
            }
            .alert("Couldn't Prepare Logs", isPresented: diagnosticsErrorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(diagnosticsError ?? "")
            }
            .overlay {
                if preparingDiagnostics {
                    ProgressView().controlSize(.large)
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
    }

    private var diagnosticsErrorBinding: Binding<Bool> {
        Binding(get: { diagnosticsError != nil }, set: { if !$0 { diagnosticsError = nil } })
    }

    /// Shows the reassurance alert when the store is unavailable, until dismissed.
    private var storeUnavailableAlertBinding: Binding<Bool> {
        Binding(
            get: { storeLaunch.storeUnavailable && !dismissedStoreAlert },
            set: { if !$0 { dismissedStoreAlert = true } },
        )
    }

    /// Build the diagnostics report off the main actor, then present a share sheet.
    /// On failure, surface an error — never leave the user tapping with no result.
    private func prepareDiagnostics() {
        preparingDiagnostics = true
        Task {
            defer { preparingDiagnostics = false }
            do {
                let url = try await StoreDiagnostics.writeReport()
                diagnosticsFile = DiagnosticsFile(url: url)
            } catch {
                diagnosticsError = error.localizedDescription
            }
        }
    }

    private func cleanupDiagnostics() {
        if let url = diagnosticsFile?.url { try? FileManager.default.removeItem(at: url) }
        diagnosticsFile = nil
    }
}

// MARK: - Main Tab View

/// The tab bar, its five navigation stacks, and the session bottom accessory.
///
/// Extracted from `ContentView` as a dedicated **`Equatable`** struct rather than
/// a computed `some View` property. `ContentView.body` observes
/// `navigator.sheetStack` (via `.sheetStackPresenter`, which must watch it to
/// drive sheet presentation), so it re-runs on every sheet open *and* close. As
/// a computed property the tab view was rebuilt on each of those re-runs —
/// cascading a full journal re-render (the hero card plus every day card,
/// twice) behind whatever sheet was presenting. As a separate `Equatable` view
/// SwiftUI skips re-evaluating it when only `sheetStack` changed; the inputs
/// that genuinely affect it (selected tab, nav paths, active-session state,
/// search text) still update it through `@Observable` tracking or the leaf
/// views' own bindings, independent of the `==` comparison.
private struct MainTabView: View {
    @Environment(\.appNavigator) private var navigator
    @Environment(\.modelContext) private var modelContext

    /// Search state owned here (not threaded down as bindings from the root), so
    /// this view has zero stored inputs and SwiftUI skips re-evaluating it when
    /// the root body re-runs for unrelated chrome/scene churn. The old
    /// `Equatable` + `== { true }` band-aid is gone — an input-free view is
    /// trivially comparable.
    @State private var searchScope: SearchTabScope = .library
    @State private var searchText = ""
    @State private var librarySearchText = ""

    /// Whether the journal stack's top screen is the active session's detail.
    /// Computed off `body` (in `.task(id:)`) so the membership `fetch` it needs
    /// never runs during a body pass.
    @State private var viewingActiveSessionDay = false

    var body: some View {
        @Bindable var navigator = navigator
        return TabView(selection: $navigator.selectedTab) {
            Tab("Journal", systemImage: "book", value: AppTab.journal) {
                NavigationStack(path: navigator.pathBinding(for: .journal)) {
                    journalContent
                        .withAppDestinations()
                }
            }
            Tab("Library", systemImage: "books.vertical", value: AppTab.library) {
                NavigationStack(path: navigator.pathBinding(for: .library)) {
                    libraryContent
                        .withAppDestinations()
                }
            }
            Tab("Tools", systemImage: "wrench.and.screwdriver", value: AppTab.tools) {
                NavigationStack(path: navigator.pathBinding(for: .tools)) {
                    toolsContent
                        .withAppDestinations()
                }
            }
            Tab("Insights", systemImage: "chart.line.uptrend.xyaxis", value: AppTab.insights) {
                NavigationStack(path: navigator.pathBinding(for: .insights)) {
                    insightsContent
                        .withAppDestinations()
                }
            }
            Tab("Search", systemImage: "magnifyingglass", value: AppTab.search, role: .search) {
                NavigationStack(path: navigator.pathBinding(for: .search)) {
                    SearchView(
                        scope: $searchScope,
                        searchText: $searchText,
                    )
                    .withAppDestinations()
                }
            }
        }
        // Apple-Music-style fold: scrolling down minimizes the tab bar and slides
        // the session accessory into its inline placement (which
        // `SessionAccessoryView` already adapts to).
        .tabBarMinimizeBehavior(.onScrollDown)
        .withSessionAccessory(
            showSessionPill: sessionAccessoryActive,
            // The "log a dose" tip may only appear on the Journal root — the
            // accessory it anchors to is otherwise on every tab and every pushed
            // screen. Attaching the popover only here (rather than gating it with
            // a TipKit rule) is what actually dismisses it on navigate-away:
            // TipKit doesn't retract a shown popover when a rule flips false.
            showLogTip: onJournalRoot,
            // Plain actions, *not* sheetStack-reading bindings. The accessory only
            // ever triggers a present (its sheet dismisses itself), so a binding's
            // getter was dead weight — and reading `sheetStack` in that getter
            // subscribed this whole view to it, re-rendering the entire journal
            // behind every sheet present/dismiss. Closures read `sheetStack` only
            // when tapped, so the body no longer depends on it.
            onShowSessionDetail: {
                guard navigator.sheetStack.isEmpty else { return }
                navigator.revealOrPresentSessionDetail(
                    currentSessionID: mostRecentSessionID(in: modelContext),
                )
            },
            onAdd: {
                // Tapping the CTA retires the "log a dose" tip whether or not the
                // log is completed — the point has been made.
                OnboardingTips.logDoseInvoked()
                guard navigator.sheetStack.isEmpty else { return }
                navigator.present(.quickLog(routine: nil))
            },
        )
        .onChange(of: navigator.selectedTab) { oldValue, newValue in
            if newValue == .search {
                // Seed the scope from where the user came from; Library is the
                // natural default from Tools/Insights/Search itself.
                searchScope = (oldValue == .journal) ? .journal : .library
            }
            searchText = ""
            librarySearchText = ""
        }
        // Derive the "viewing the active session's day" flag reactively instead
        // of fetching in `body`. The key changes when the journal's top route,
        // the selected tab, or the active doses change — exactly when the answer
        // can flip.
        .task(id: activeSessionDayKey) {
            viewingActiveSessionDay = computeViewingActiveSessionDay()
        }
    }

    // MARK: Tab Content

    private var journalContent: some View {
        EntryListView(searchText: $searchText)
    }

    private var libraryContent: some View {
        SubstanceLibraryView(searchText: $librarySearchText)
    }

    private var toolsContent: some View {
        ToolsView()
    }

    private var insightsContent: some View {
        InsightsView()
    }

    // MARK: Session Accessory Visibility

    /// Whether the bottom accessory shows the live-session pill (vs. the idle
    /// "Log a dose" call-to-action). The accessory is *always* mounted now; this
    /// only chooses its content. We fall back to the CTA — rather than the pill —
    /// while the journal already surfaces the live session (its day-detail with
    /// the curve / substances / timing on screen, or the journal root where the
    /// hero card carries it), since the pill would only duplicate them.
    private var sessionAccessoryActive: Bool {
        ActiveSessionManager.shared.hasActiveSession
            && !viewingActiveSessionDay
            && !journalShowingActiveHero
    }

    /// The Journal tab's root screen — nothing pushed. Gates the "log a dose"
    /// first-run tip, which points at the always-mounted bottom accessory and so
    /// must be told when it's actually on the screen the tip is about.
    private var onJournalRoot: Bool {
        navigator.selectedTab == .journal && navigator.path(for: .journal).isEmpty
    }

    /// True when the journal is at its root with a live session — the new hero
    /// card there already carries the session, so the floating accessory would
    /// only echo it. (The journal root is never a search surface, so this lines
    /// up exactly with `EntryListView`'s own hero-visibility condition.)
    private var journalShowingActiveHero: Bool {
        navigator.selectedTab == .journal
            && navigator.path(for: .journal).isEmpty
            && ActiveSessionManager.shared.hasActiveSession
    }

    /// Identity for the `viewingActiveSessionDay` task: changes exactly when the
    /// answer could — the selected tab, the journal's top route, or the active
    /// doses. Read here in `body` (these are already observed for the accessory),
    /// so the membership `fetch` runs in the keyed task rather than per body pass.
    private var activeSessionDayKey: String {
        let top = navigator.path(for: .journal).last.map { "\($0)" } ?? "none"
        let stamps = ActiveSessionManager.shared.activeSubstanceStates
            .map { "\($0.doseTimestamp.timeIntervalSince1970)" }
            .joined(separator: ",")
        return "\(navigator.selectedTab)|\(top)|\(stamps)"
    }

    /// True when the journal stack's top screen is the detail for the session the
    /// active doses belong to. The session accessory would only echo what that
    /// screen already shows, so we hide it there. Matches by membership: the
    /// viewed session contains the active session's earliest dose.
    private func computeViewingActiveSessionDay() -> Bool {
        guard navigator.selectedTab == .journal,
              case let .session(id) = navigator.path(for: .journal).last
        else { return false }
        let activeStamps = ActiveSessionManager.shared.activeSubstanceStates.map(\.doseTimestamp)
        guard !activeStamps.isEmpty else { return false }
        var descriptor = FetchDescriptor<Session>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let session = try? modelContext.fetch(descriptor).first else { return false }
        // Suppress the accessory whenever the viewed session holds *any* active
        // dose — covers the current cluster even if a separate, overlapping
        // session also has a still-active long-acting dose.
        return session.orderedDoses.contains { dose in
            activeStamps.contains { abs($0.timeIntervalSince(dose.timestamp)) < 1 }
        }
    }
}

// MARK: - Unified Search

/// The two datasets the Search tab can query. Surfaced as a native search-scope
/// segmented control so the user can search across everything from one place,
/// regardless of which tab they entered search from.
enum SearchTabScope: String, CaseIterable, Identifiable {
    // Order matters: `allCases` drives the segmented picker, and Journal-left /
    // Library-right mirrors the tab bar (Journal precedes Library there).
    case journal
    case library

    var id: Self {
        self
    }

    var title: LocalizedStringKey {
        switch self {
        case .library: "Library"
        case .journal: "Journal"
        }
    }

    var prompt: LocalizedStringKey {
        switch self {
        case .library: "Search substances..."
        case .journal: "Search entries..."
        }
    }
}

/// The Search tab. Declares the `.searchable` field and hands its content to
/// ``SearchSurface``, which reads `\.isSearching` to pick its phase.
///
/// `.searchable` is declared *here* (the parent) but `\.isSearching` is read in
/// the child `SearchSurface` — that split is required: a view reading
/// `\.isSearching` in the same body that declares `.searchable` always sees
/// `false`. Crucially we do **not** pass `isPresented:` — on a `role: .search`
/// tab that binding makes the system auto-focus the field on tab entry (you'd
/// never see the landing) and treat the cancel button as "leave the tab". Letting
/// the system own focus gives the Music behavior: enter → landing, tap field →
/// keyboard, cancel → back to the landing (staying on the tab).
private struct SearchView: View {
    @Binding var scope: SearchTabScope
    @Binding var searchText: String

    var body: some View {
        SearchSurface(scope: $scope, searchText: $searchText)
            .searchable(text: $searchText, prompt: Text(scope.prompt))
    }
}

/// The Search tab's content, with three phases driven by `\.isSearching`:
///
/// - **landing** (field not focused): a browse screen (`SearchLandingView`) with
///   the large "Search" title and *no* keyboard.
/// - **focusedEmpty** (focused, nothing typed): the scope picker + recent
///   activity (`SearchActivityList`) above the keyboard.
/// - **typing**: the scope picker + results, switched between the catalog and the
///   journal by a native segmented `Picker`.
///
/// The navbar and scope-picker *modifiers* stay permanently mounted — only their
/// content/visibility varies per phase, so focus changes never flash chrome.
private struct SearchSurface: View {
    @Environment(\.appNavigator) private var navigator
    @Environment(\.isSearching) private var isSearching
    @Binding var scope: SearchTabScope
    @Binding var searchText: String

    /// Forces the segmented `Picker` to rebuild after the global
    /// `UISegmentedControl` title-font appearance changes (the proxy only affects
    /// controls created *after* it's set). Bumped on focus, when the picker
    /// appears — see ``applyScopePickerFont(_:)``.
    @State private var pickerToken = 0

    private enum Phase { case landing, focusedEmpty, typing }
    private var phase: Phase {
        guard isSearching else { return .landing }
        return searchText.isEmpty ? .focusedEmpty : .typing
    }

    var body: some View {
        content
            .scrollEdgeEffectStyle(.soft, for: .top)
            // Permanently mounted; the picker only appears once focused (an empty
            // builder collapses to zero height without changing identity).
            .safeAreaBar(edge: .top) {
                if phase != .landing {
                    // A separate `View` type, not a computed property, so its
                    // segmented `Picker` only rebuilds when `scope`/`token`
                    // change — not on every `searchText` keystroke (which re-runs
                    // `SearchSurface.body` because it forwards the binding).
                    ScopePickerBar(scope: $scope, token: pickerToken)
                }
            }
            // Large "Search" title at rest; suppressed once focused (the
            // `enabled: false` branch returns the view untouched).
            .appNavigationBar("Search", enabled: phase == .landing)
            // Enlarge the segmented picker font while it's visible (focused),
            // and restore it otherwise so sibling tabs' controls don't inherit it.
            .onChange(of: isSearching) { _, searching in
                applyScopePickerFont(searching)
            }
            // Record into "Recently Searched" whenever a substance is opened from
            // a *focused* search surface (results or the recent lists) — i.e. a
            // substance the user looked up while searching. Browsing from the
            // landing's class grid (phase `.landing`) is deliberately excluded.
            .onChange(of: navigator.path(for: .search)) { _, newPath in
                guard phase != .landing, case let .substance(name) = newPath.last else { return }
                SearchHistoryStore.shared.record(name)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .landing:
            SearchLandingView()
        case .focusedEmpty:
            SearchActivityList()
        case .typing:
            switch scope {
            case .library:
                SubstanceLibraryView(searchText: $searchText, isSearchSurface: true)
            case .journal:
                EntryListView(
                    searchText: $searchText,
                    isSearchSurface: true,
                    onSwitchToLibrary: { scope = .library },
                )
            }
        }
    }

    /// Enlarges the scope picker's title font while the picker is visible.
    /// SwiftUI's segmented `Picker` ignores a `.font` on its labels, so the
    /// global `UISegmentedControl` appearance proxy is the only lever; bumping
    /// `pickerToken` re-creates the control so it adopts the new font.
    private func applyScopePickerFont(_ active: Bool) {
        let attributes: [NSAttributedString.Key: Any]? = active
            ? [.font: UIFont.preferredFont(forTextStyle: .body)]
            : nil
        UISegmentedControl.appearance().setTitleTextAttributes(attributes, for: .normal)
        UISegmentedControl.appearance().setTitleTextAttributes(attributes, for: .selected)
        if active { pickerToken += 1 }
    }
}

/// Full-width scope selector pinned above the results, matching the Music app's
/// prominent top toggle. A native segmented Picker (not `.searchScopes`, whose
/// bar can't be widened/enlarged and renders inconsistently with a tab-bar
/// search field). Its own `View` type so the Picker only rebuilds when the
/// scope or font token changes — not on every keystroke of the search field.
private struct ScopePickerBar: View {
    @Binding var scope: SearchTabScope
    let token: Int

    var body: some View {
        Picker("Search scope", selection: $scope) {
            ForEach(SearchTabScope.allCases) { scope in
                Text(scope.title).tag(scope)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.large)
        .labelsHidden()
        .id(token)
        .frame(height: 44)
        .padding(.horizontal)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}

// MARK: - Session Bottom Accessory

private extension View {
    /// The tab bar's bottom accessory — Piru's "now logging" surface, the analog
    /// of Music's now-playing bar. It is *always* mounted (iOS 26.0+) and morphs
    /// between two faces: the live-session pill when a session is active, and an
    /// idle "Log a dose" call-to-action otherwise. Anchoring the primary action
    /// here (rather than a floating button) keeps it pinned to the tab bar — it
    /// never looks orphaned, and it folds into the bar's inline placement for
    /// free when the tab bar minimizes on scroll.
    ///
    /// **Do not add a grow-from-button zoom to the sheets launched from here.**
    /// iOS hosts accessory content in a context separate from the main view tree,
    /// so a `matchedTransitionSource` placed *inside* the accessory cannot anchor
    /// a sheet's zoom: the transition silently does nothing and the sheet slides
    /// up anyway. The navigator carried the plumbing for one — a `zoomSource`
    /// parameter, a namespace published through the environment — and every piece
    /// of it was unreachable for exactly this reason. A zoom needs a source
    /// control in the main view tree; the primary action lives here instead,
    /// which is the trade this accessory is making.
    func withSessionAccessory(
        showSessionPill: Bool,
        showLogTip: Bool,
        onShowSessionDetail: @escaping () -> Void,
        onAdd: @escaping () -> Void,
    ) -> some View {
        tabViewBottomAccessory {
            BottomAccessoryContent(
                showSessionPill: showSessionPill,
                showLogTip: showLogTip,
                onShowSessionDetail: onShowSessionDetail,
                onAdd: onAdd,
            )
        }
    }
}

// MARK: - Bottom Accessory Content

/// The tab bar's bottom-accessory content, with two faces: the live-session
/// pill and the idle "Log a dose" call-to-action.
///
/// Layout is one full-width **body button** with the "+" **overlaid** on top as
/// its own button. So the whole surface is tappable — a tap anywhere logs a dose
/// (idle) or opens the session (live) — while the "+" still logs directly. The
/// "+" lives outside the crossfading body, pinned trailing, so it stays solid
/// and never moves between the two faces; only the body content crossfades. (We
/// avoid `matchedGeometryEffect` across the swap: iOS hosts accessory content in
/// a context separate from the main view tree — the same boundary that stops a
/// `matchedTransition` from anchoring the sheet zoom — so a geometry match there
/// snaps rather than animates.)
private struct BottomAccessoryContent: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    let showSessionPill: Bool
    /// Whether to offer the first-run "log a dose" tip — true only on the Journal
    /// root. See ``LogTipAnchor``.
    let showLogTip: Bool
    var onShowSessionDetail: () -> Void
    var onAdd: () -> Void

    /// The tab bar is minimized — the accessory is in its folded, inline slot.
    private var compact: Bool {
        placement == .inline
    }
    /// One control footprint for the leading glyph and the "+", shrunk when
    /// folded so the idle CTA keeps its label + glyph rather than collapsing.
    private var controlSide: CGFloat {
        compact ? 34 : 44
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            ZStack(alignment: .trailing) {
                Button(action: showSessionPill ? onShowSessionDetail : onAdd) {
                    bodyContent(currentTime: context.date)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // No explicit label: idle reads "Log a dose" from its Text, and
                // the live pill reads the substance names/times it already shows.

                // Overlaid on the body's reserved trailing slot — always present
                // (outside the crossfade), so it stays put across the swap.
                plusButton
            }
            .padding(.leading, 16)
            .padding(.trailing, 11)
            .animation(.snappy, value: showSessionPill)
        }
        // Attached outside the periodic closure so the 60 s tick doesn't re-create
        // the anchor (which used to resurrect a dismissed tip), and only while on
        // the Journal root so leaving actually tears the popover down.
        .modifier(LogTipAnchor(active: showLogTip))
    }

    private func bodyContent(currentTime: Date) -> some View {
        HStack(spacing: 10) {
            if showSessionPill {
                SessionAccessoryInfo(
                    states: ActiveSessionManager.shared.activeSubstanceStates,
                    currentTime: currentTime,
                    placement: placement,
                )
                .transition(.opacity)

                Spacer(minLength: 0)
            } else {
                // Leading slot: normally a flat-trend glyph (the timeline-
                // before-it-has-data, balancing the trailing "+"); when med
                // slots are due it becomes a quiet "N due" badge — the
                // accessory then names the next action instead of decoration
                // (Specs/meds-ux-review.md §7). Same tap either way: open the
                // log screen, where the due strip is the first thing on it.
                MedsDueGlyph(currentTime: currentTime, compact: compact, controlSide: controlSide)
                    .transition(.opacity)

                Spacer(minLength: 0)

                Text("Log a dose")
                    .font((compact ? Font.caption : Font.subheadline).weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .transition(.opacity)

                Spacer(minLength: 0)
            }

            // Reserve the slot the overlaid "+" occupies, so the body's centered
            // label accounts for it and lands on true center.
            Color.clear
                .frame(width: controlSide, height: controlSide)
        }
    }

    /// Log another dose. Pinned trailing in every face — no background fill (a
    /// bare accent glyph avoids glass-on-glass concentricity issues against the
    /// accessory's own capsule); 11pt trailing so its center lines up with the
    /// tab bar's search button.
    private var plusButton: some View {
        Button(action: onAdd) {
            Image(systemName: "plus")
                .font((compact ? Font.subheadline : Font.title3).weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: controlSide, height: controlSide)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Log dose"))
    }
}

/// Attaches the first-run "log a dose" popover only while `active` (the Journal
/// root). Removing the `.popoverTip` modifier — rather than gating the tip with a
/// TipKit rule — is what dismisses the popover when the user navigates away:
/// TipKit gates when a tip may first appear, but won't retract one already on
/// screen when a rule flips false.
private struct LogTipAnchor: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.popoverTip(LogDoseTip(), arrowEdge: .bottom)
        } else {
            content
        }
    }
}

// MARK: - Meds Due Glyph

/// The idle accessory's leading slot: a flat-trend placeholder glyph, or a
/// "N due" badge when med slots are currently due. Recomputes once per
/// accessory minute-tick (`currentTime`) via the same derivation as the
/// quick-log due strip, over a cheap indexed fetch of today's entries.
private struct MedsDueGlyph: View {
    let currentTime: Date
    let compact: Bool
    let controlSide: CGFloat

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DailyDoseItem.sortOrder) private var items: [DailyDoseItem]

    @State private var dueCount = 0

    var body: some View {
        Group {
            if dueCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "pills.fill")
                        .font(compact ? .caption : .subheadline)
                    Text("\(dueCount) due")
                        .font((compact ? Font.caption2 : Font.caption).weight(.semibold))
                        .fixedSize()
                }
                .foregroundStyle(.secondary)
                .frame(height: controlSide)
                .accessibilityLabel(Text("\(dueCount) meds due"))
            } else {
                Image(systemName: "chart.line.flattrend.xyaxis")
                    .font(compact ? .subheadline : .title3)
                    .foregroundStyle(.secondary)
                    .frame(width: controlSide, height: controlSide)
                    .accessibilityHidden(true)
            }
        }
        .task(id: recomputeKey) { recompute() }
    }

    /// Once per accessory minute-tick, plus whenever the meds list itself
    /// changes or a dose commits (the revision — "due" must update immediately,
    /// not on the next minute tick) — not on every body evaluation.
    private var recomputeKey: String {
        "\(Int(currentTime.timeIntervalSinceReferenceDate / 60))|\(items.count)|\(DoseLogService.shared.revision)"
    }

    private func recompute() {
        guard !items.isEmpty, items.contains(where: { !$0.isAsNeeded }) else {
            dueCount = 0
            return
        }
        let dayStart = Calendar.current.startOfDay(for: currentTime)
        let descriptor = FetchDescriptor<DoseEntry>(
            predicate: #Predicate { $0.timestamp >= dayStart },
        )
        let todays = (try? modelContext.fetch(descriptor)) ?? []
        dueCount = DueNowSlot.derive(items: items, todayEntries: todays, now: currentTime).count
    }
}

// MARK: - Session Accessory Info

/// The live-session summary shown in the accessory's pill face: a compact
/// timeline, the substance names, and elapsed/remaining times. Collapses to just
/// the names when the tab bar minimizes (`.inline`).
private struct SessionAccessoryInfo: View {
    @AppStorage("stackRedoses", store: UserDefaults(suiteName: "group.dev.yumeji.piru")) private var stackRedoses = true

    let states: [ActiveSubstanceState]
    let currentTime: Date
    let placement: TabViewBottomAccessoryPlacement?

    var body: some View {
        HStack(spacing: 10) {
            // The mini timeline stays in *both* placements — in the folded bar a
            // name + "+" alone read ambiguously; the graph anchors it as a live
            // session and balances the trailing glyph.
            TimelineGraphView(
                substances: states,
                currentTime: currentTime,
                compact: true,
                stackRedoses: stackRedoses,
            )
            .equatable()
            .frame(width: 60, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(uniqueNames)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                if placement != .inline {
                    Text("\(elapsedText) in \u{00B7} \(remainingText) left")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var uniqueNames: String {
        var seen = Set<String>()
        return states.compactMap { state in
            let key = state.substanceName.lowercased()
            guard !seen.contains(key) else { return nil }
            seen.insert(key)
            return CustomSubstanceStore.shared.displayName(for: state.substanceName)
        }.joined(separator: ", ")
    }

    private var elapsedText: String {
        guard let start = states.map(\.doseTimestamp).min() else { return String(localized: "0m") }
        return Self.formatDuration(currentTime.timeIntervalSince(start))
    }

    private var remainingText: String {
        let end = states.map { $0.doseTimestamp.addingTimeInterval($0.totalMinutes * 60) }.max() ?? currentTime
        return Self.formatDuration(max(0, end.timeIntervalSince(currentTime)))
    }

    private static func formatDuration(_ interval: TimeInterval) -> String {
        interval.durationHM
    }
}

/// Identifiable wrapper so a generated diagnostics file can drive a `.sheet(item:)`.
private struct DiagnosticsFile: Identifiable {
    let id = UUID()
    let url: URL
}
