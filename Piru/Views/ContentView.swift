import SwiftData
import SwiftUI
import TipKit

#if canImport(UIKit)
    import UIKit
#endif

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appNavigator) private var navigator
    @Environment(\.modelContext) private var modelContext

    /// A thin root. `MainTabView` owns its own search state and takes no inputs,
    /// so SwiftUI skips re-evaluating it whenever this body re-runs (a scene-phase
    /// change, a sheet present or dismiss). The launch chrome — onboarding, the
    /// launch sheets, the store-health alert and diagnostics — lives in
    /// self-owning `ViewModifier`s so their `@State` stays out of this body and
    /// out of the tab tree.
    var body: some View {
        MainTabView()
            .sheetStackPresenter(navigator)
            .dismissesKeyboardOnTap()
            .modifier(OnboardingGateModifier())
            .modifier(LaunchSheetModifier())
            .modifier(StoreDiagnosticsModifier())
            .onOpenURL { handleDeepLink($0) }
        #if DEBUG
            // `-piruRoute <piru://url>` lands on a screen at launch, for
            // simulator screenshots: `simctl openurl` is blocked by the
            // untappable "Open in Piru?" sheet. `-piruRouteTour` walks a list
            // of them in one session, for profiling (see `RouteTour`).
            .task {
                let args = ProcessInfo.processInfo.arguments
                // A substance route resolves in the pushed view's body; a
                // cold `SubstanceStore.all` asserts in DEBUG.
                if let i = args.firstIndex(of: "-piruRoute"), args.indices.contains(i + 1),
                   let url = URL(string: args[i + 1]) {
                    await SubstanceStore.shared.ensureAllLoaded()
                    handleDeepLink(url)
                } else if let tour = RouteTour(arguments: args) {
                    await SubstanceStore.shared.ensureAllLoaded()
                    await tour.run(navigator: navigator) { url in
                        handleDeepLink(url.resolvingLatestSession(in: modelContext))
                    }
                }
            }
        #endif
            .onChange(of: scenePhase) {
                if scenePhase == .active {
                    ActiveSessionManager.shared.refresh()
                    // The foreground tick died with the suspension; the Lock
                    // Screen widget gets a current push and a re-armed tick.
                    LiveActivityManager.shared.resumeIfRunning()
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
        #if os(iOS)
            content.fullScreenCover(isPresented: .init(
                get: { !hasCompletedOnboarding },
                set: { if !$0 { hasCompletedOnboarding = true } },
            )) {
                OnboardingView()
            }
        #else
            content.sheet(isPresented: .init(
                get: { !hasCompletedOnboarding },
                set: { if !$0 { hasCompletedOnboarding = true } },
            )) {
                OnboardingView()
            }
        #endif
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
                        .padding(Spacing.xxxl)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.container))
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
/// A separate view with no stored inputs, so the root's re-runs on every sheet
/// present and dismiss (it observes `navigator.sheetStack` to drive them) skip
/// it. Its body reads only the selected tab. Everything that follows the
/// journal's path or the live session — the accessory's face, the first-run
/// tip, the "viewing the active day" check — is read inside
/// ``SessionAccessoryHost``, so a push, a pop or a session update re-renders
/// the accessory and never the tab tree behind it.
private struct MainTabView: View {
    @Environment(\.appNavigator) private var navigator

    @State private var searchScope: SearchTabScope = .library
    @State private var searchText = ""
    @State private var librarySearchText = ""

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
        // the session accessory into its inline placement, which
        // `BottomAccessoryContent` adapts to.
        #if os(iOS)
            #if canImport(UIKit)
                .tabBarMinimizeBehavior(.onScrollDown)
            #endif
        #endif
            .withSessionAccessory()
            .onChange(of: navigator.selectedTab) { oldValue, newValue in
                if newValue == .search {
                    // Seed the scope from where the user came from; Library is the
                    // natural default from Tools/Insights/Search itself.
                    searchScope = (oldValue == .journal) ? .journal : .library
                }
                searchText = ""
                librarySearchText = ""
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
            // The system's scope bar, shown under the field once it is focused —
            // the control Music uses for "Apple Music | Library".
            .searchScopes($scope, activation: .onSearchPresentation) {
                ForEach(SearchTabScope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
    }
}

/// The Search tab's content, with three phases driven by `\.isSearching`:
///
/// - **landing** (field not focused): a browse screen (`SearchLandingView`) with
///   the large "Search" title and *no* keyboard.
/// - **focusedEmpty** (focused, nothing typed): recent activity
///   (`SearchActivityList`) above the keyboard.
/// - **typing**: results from the catalog or the journal, by the search scope.
///
/// The navbar *modifier* stays permanently mounted — only its visibility varies
/// per phase, so focus changes never flash chrome.
private struct SearchSurface: View {
    @Environment(\.appNavigator) private var navigator
    @Environment(\.isSearching) private var isSearching
    @Binding var scope: SearchTabScope
    @Binding var searchText: String

    /// Captures `isSearching` before a NavigationLink push resets it to `false`.
    /// The path-change `onChange` fires *after* the push, at which point
    /// `isSearching` is already gone — reading the live value there would always
    /// see `.landing` and never record anything.
    @State private var wasSearching = false

    private enum Phase { case landing, focusedEmpty, typing }
    private var phase: Phase {
        guard isSearching else { return .landing }
        return searchText.isEmpty ? .focusedEmpty : .typing
    }

    var body: some View {
        content
            .scrollEdgeEffectStyle(.soft, for: .top)
            // Large "Search" title at rest; suppressed once focused (the
            // `enabled: false` branch returns the view untouched).
            .appNavigationBar("Search", enabled: phase == .landing)
            .onChange(of: isSearching) { _, searching in
                if searching {
                    wasSearching = true
                } else {
                    // Cancel and push-dismissal both land here. A push's path
                    // append arrives in the same transaction, so defer the
                    // reset one tick: the recording onChange still sees the
                    // flag for a real search push, while Cancel followed by
                    // browsing the landing grid records nothing.
                    Task { wasSearching = false }
                }
            }
            .onChange(of: navigator.path(for: .search)) { _, newPath in
                guard wasSearching, case let .substance(name) = newPath.last else { return }
                SearchHistoryStore.shared.record(name)
                wasSearching = false
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
}

// MARK: - Session Bottom Accessory

private extension View {
    /// The tab bar's bottom accessory — Piru's "now logging" surface, the analog
    /// of Music's now-playing bar. It is *always* mounted (iOS 26.0+) and morphs
    /// between two faces: the live-session pill when a session is active, and an
    /// idle "Record an entry" call-to-action otherwise. Anchoring the primary action
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
    @ViewBuilder
    func withSessionAccessory() -> some View {
        #if os(iOS)
            tabViewBottomAccessory {
                SessionAccessoryHost()
            }
        #else
            self
        #endif
    }
}

// MARK: - Session Accessory Host

#if os(iOS)
    /// Decides the accessory's face and wires its two actions. Reading the
    /// journal's path and the live session here, inside the accessory, is what
    /// keeps a push, a pop or a session update from re-rendering the tab tree.
    private struct SessionAccessoryHost: View {
        @Environment(\.appNavigator) private var navigator
        @Environment(\.modelContext) private var modelContext

        /// Whether the journal stack's top screen is the active session's detail.
        /// Computed in `.task(id:)` so the membership `fetch` it needs never runs
        /// during a body pass.
        @State private var viewingActiveSessionDay = false

        var body: some View {
            BottomAccessoryContent(
                showSessionPill: sessionAccessoryActive,
                // The "log a dose" tip may only appear on the Journal root — the
                // accessory it anchors to is otherwise on every tab and every pushed
                // screen. Attaching the popover only here (rather than gating it with
                // a TipKit rule) is what dismisses it on navigate-away: TipKit
                // doesn't retract a shown popover when a rule flips false.
                showLogTip: onJournalRoot,
                // Plain actions, never sheetStack-reading bindings: a getter that
                // reads `sheetStack` subscribes this view to every sheet present and
                // dismiss. Closures read it only when tapped.
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
            // The key changes when the journal's top route, the selected tab, or
            // the active doses change — exactly when the answer can flip.
            .task(id: activeSessionDayKey) {
                viewingActiveSessionDay = computeViewingActiveSessionDay()
            }
        }

        /// Whether the accessory shows the live-session pill rather than the idle
        /// "Record an entry" call-to-action. The accessory is always mounted; this only
        /// chooses its content. It falls back to the CTA while the journal already
        /// surfaces the live session — its day detail, or the journal root, where
        /// the hero card carries it — since the pill would only duplicate them.
        private var sessionAccessoryActive: Bool {
            ActiveSessionManager.shared.hasActiveSession
                && !viewingActiveSessionDay
                && !onJournalRoot
        }

        /// The Journal tab's root screen — nothing pushed. Gates the first-run tip
        /// and, with a live session, stands in for the hero card that already
        /// carries it (the journal root is never a search surface, so this matches
        /// `EntryListView`'s own hero condition).
        private var onJournalRoot: Bool {
            navigator.selectedTab == .journal && navigator.path(for: .journal).isEmpty
        }

        /// Identity for the `viewingActiveSessionDay` task: the selected tab, the
        /// journal's top route and the active doses.
        private var activeSessionDayKey: String {
            let top = navigator.path(for: .journal).last.map { "\($0)" } ?? "none"
            let stamps = ActiveSessionManager.shared.activeSubstanceStates
                .map { "\($0.doseTimestamp.timeIntervalSince1970)" }
                .joined(separator: ",")
            return "\(navigator.selectedTab)|\(top)|\(stamps)"
        }

        /// True when the journal stack's top screen is the detail for the session
        /// the active doses belong to. Matches by membership: the viewed session
        /// holds any active dose — covering the current cluster even when a
        /// separate, overlapping session also has a still-active long-acting dose.
        private func computeViewingActiveSessionDay() -> Bool {
            guard navigator.selectedTab == .journal,
                  case let .session(id) = navigator.path(for: .journal).last
            else { return false }
            let activeStamps = ActiveSessionManager.shared.activeSubstanceStates.map(\.doseTimestamp)
            guard !activeStamps.isEmpty else { return false }
            var descriptor = FetchDescriptor<Session>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            guard let session = try? modelContext.fetch(descriptor).first else { return false }
            return session.orderedDoses.contains { dose in
                activeStamps.contains { abs($0.timeIntervalSince(dose.timestamp)) < 1 }
            }
        }
    }
#endif

// MARK: - Bottom Accessory Content

// The tab bar's bottom-accessory content, with two faces: the live-session
// pill and the idle action bar (shortcut slots · label · "+"), configured in
// the Log sheet's Edit surface (`DockPreferences`).
//
// Layout is one full-width **body button** with the "+" **overlaid** on top as
// its own button. So the whole surface is tappable — a tap anywhere logs a dose
// (idle) or opens the session (live) — while the "+" still logs directly. The
// "+" lives outside the crossfading body, pinned trailing, so it stays solid
// and never moves between the two faces; only the body content crossfades. (We
// avoid `matchedGeometryEffect` across the swap: iOS hosts accessory content in
// a context separate from the main view tree — the same boundary that stops a
// `matchedTransition` from anchoring the sheet zoom — so a geometry match there
// snaps rather than animates.)
#if os(iOS)
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

        @State private var preferences = DockPreferences.shared
        /// Med slots due right now — the "+" badge; set by the idle label's
        /// derivation so the badge and the "N due" label never disagree.
        @State private var dueCount = 0

        var body: some View {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                ZStack {
                    Button(action: showSessionPill ? onShowSessionDetail : onAdd) {
                        bodyContent(currentTime: context.date)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    // The visible text changes every minute ("Next: … in 12h 2m"),
                    // so Voice Control gets names that hold still.
                    .accessibilityInputLabels(showSessionPill ? [Text("Session")] : [Text("Next dose"), Text("Log")])

                    HStack(spacing: 0) {
                        // Shortcuts need the width the session curve takes, so
                        // they show only on the idle face.
                        if !showSessionPill {
                            DockShortcutSlots(currentTime: context.date, compact: compact, controlSide: controlSide)
                                .transition(.opacity)
                        }
                        Spacer()
                        plusButton
                    }
                }
                .padding(.leading, Spacing.xxl)
                .padding(.trailing, 11)
                .animation(.snappy, value: showSessionPill)
            }
            // Attached outside the periodic closure, because re-creating the anchor on
            // the 60 s tick resurrects a dismissed tip; and only while on the Journal
            // root, so leaving tears the popover down.
            .modifier(LogTipAnchor(active: showLogTip))
        }

        private func bodyContent(currentTime: Date) -> some View {
            HStack(spacing: Spacing.lg) {
                if showSessionPill {
                    SessionAccessoryInfo(
                        states: ActiveSessionManager.shared.activeSubstanceStates,
                        currentTime: currentTime,
                        placement: placement,
                    )
                    .transition(.opacity)

                    Spacer(minLength: 0)
                } else {
                    // Reserve the width the overlaid shortcut slots occupy, so the
                    // label centers between them and the "+". No slots, no room.
                    Color.clear
                        .frame(
                            width: DockShortcutSlots.reservedWidth(
                                slots: DockShortcutSlots.visibleCount(of: preferences.shortcuts.count, compact: compact),
                                controlSide: controlSide,
                            ),
                            height: controlSide,
                        )

                    Spacer(minLength: 0)

                    DockLabelText(currentTime: currentTime, compact: compact, dueCount: $dueCount)
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
        /// tab bar's search button. Carries the meds-due count badge in both faces.
        private var plusButton: some View {
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font((compact ? Font.subheadline : Font.title3).weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: controlSide, height: controlSide)
                    .contentShape(Circle())
                    .overlay(alignment: .topTrailing) {
                        DockDueBadge(count: dueCount)
                            .offset(x: compact ? 2 : 0, y: compact ? -2 : 2)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Record an entry"))
            .accessibilityInputLabels([Text("Record an entry"), Text("Record"), Text("Add")])
        }
    }
#endif

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

// MARK: - Session Accessory Info

/// The live-session summary shown in the accessory's pill face: a compact
/// timeline, the substance names, and elapsed/remaining times. Collapses to just
/// the names when the tab bar minimizes (`.inline`).
private struct SessionAccessoryInfo: View {
    @AppStorage("stackRedoses", store: UserDefaults(suiteName: AppIdentity.appGroup)) private var stackRedoses = true

    let states: [ActiveSubstanceState]
    let currentTime: Date
    let placement: TabViewBottomAccessoryPlacement?

    var body: some View {
        HStack(spacing: Spacing.lg) {
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

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(uniqueNames)
                    .sectionLabel()
                    .lineLimit(1)

                if placement != .inline {
                    Text("\(elapsedText) in \u{00B7} \(remainingText) left")
                        .captionSecondary()
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
