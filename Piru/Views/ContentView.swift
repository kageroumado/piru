import SwiftData
import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appNavigator) private var navigator

    @State private var searchText = ""
    @State private var librarySearchText = ""

    /// Which dataset the Search tab is currently querying. Seeded from the tab
    /// the user came from (Library → library, anything else → library), then
    /// user-switchable via the scope picker.
    @State private var searchScope: SearchTabScope = .library

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("discordPromptDismissedForever") private var discordDismissed = false
    @State private var showDiscordPrompt = false

    /// Launch-time store health. When the persistent store can't be opened the app
    /// runs in-memory; we surface a reassuring alert (the data is safe, not lost).
    @State private var storeLaunch = StoreLaunchState.shared
    @State private var dismissedStoreAlert = false
    @State private var preparingDiagnostics = false
    @State private var diagnosticsFile: DiagnosticsFile?
    @State private var diagnosticsError: String?

    /// Shared namespace for the quick-log zoom transition. The floating add
    /// button and the session accessory's add button tag themselves as the
    /// source; the presented quick-log sheet grows out of whichever is on
    /// screen instead of sliding up from the bottom (Mail-style).
    @Namespace private var quickLogZoom

    var body: some View {
        @Bindable var navigator = navigator
        // `MainTabView` is a dedicated `Equatable` struct, not a computed
        // property: this `body` observes `navigator.sheetStack` (via
        // `.sheetStackPresenter`, which must watch it to present sheets), so it
        // re-runs on every sheet open/close. Extracting the tab view lets SwiftUI
        // skip rebuilding it on those re-runs — the journal no longer re-renders
        // behind a presenting sheet. Its real inputs still update it via
        // `@Observable` tracking; only `scopePickerToken` gates the comparison.
        MainTabView(
            searchScope: $searchScope,
            searchText: $searchText,
            librarySearchText: $librarySearchText,
            quickLogZoom: quickLogZoom,
        )
        .equatable()
        .onChange(of: navigator.selectedTab) { oldValue, newValue in
            if newValue == .search {
                // Seed the scope from where the user came from; Library is
                // the natural default from Tools/Insights/Search itself.
                searchScope = (oldValue == .journal) ? .journal : .library
            }
            searchText = ""
            librarySearchText = ""
        }
        .environment(\.quickLogZoomNamespace, quickLogZoom)
        .sheetStackPresenter(navigator, quickLogZoom: quickLogZoom)
        .fullScreenCover(isPresented: .init(
            get: { !hasCompletedOnboarding },
            set: { if !$0 { hasCompletedOnboarding = true } },
        )) {
            OnboardingView()
        }
        .sheet(isPresented: $showDiscordPrompt) {
            DiscordPromptView()
        }
        .task {
            // Invite to Discord once per launch (after onboarding, so modals
            // don't stack) until the user dismisses it forever.
            guard hasCompletedOnboarding, !discordDismissed else { return }
            try? await Task.sleep(for: .seconds(0.8))
            if hasCompletedOnboarding, !discordDismissed {
                showDiscordPrompt = true
            }
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                ActiveSessionManager.shared.refresh()
            }
        }
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

    // MARK: - Deep Linking

    private func handleDeepLink(_ url: URL) {
        guard let outcome = DeepLink.decode(url) else { return }
        navigator.apply(outcome)
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
private struct MainTabView: View, Equatable {
    @Environment(\.appNavigator) private var navigator
    @Environment(\.modelContext) private var modelContext

    @Binding var searchScope: SearchTabScope
    @Binding var searchText: String
    @Binding var librarySearchText: String
    let quickLogZoom: Namespace.ID

    /// Always equal: nothing `ContentView.body` changes when it re-runs (it does
    /// so on every sheet open/close, via `.sheetStackPresenter`) needs to rebuild
    /// the tab view. Everything that should update it flows through `@Observable`
    /// tracking (selected tab, nav paths, `ActiveSessionManager`) or the leaf
    /// views' bindings (`searchScope`, `searchText`), all of which fire
    /// regardless of this comparison.
    static func == (_: MainTabView, _: MainTabView) -> Bool {
        true
    }

    var body: some View {
        @Bindable var navigator = navigator
        return TabView(selection: $navigator.selectedTab) {
            Tab("Journal", systemImage: "book", value: AppTab.journal) {
                NavigationStack(path: navigator.pathBinding(for: .journal)) {
                    journalContent
                        // The floating add button stays put on the journal root
                        // regardless of session state — muscle memory. (The
                        // session accessory is what we suppress here; see
                        // `journalShowingActiveHero`.)
                        .overlay(alignment: .bottom) {
                            addMenu
                                .padding(.bottom, 16)
                        }
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
            isActive: sessionAccessoryActive,
            // Plain actions, *not* sheetStack-reading bindings. The accessory only
            // ever triggers a present (its sheet dismisses itself), so a binding's
            // getter was dead weight — and reading `sheetStack` in that getter
            // subscribed this whole view to it, re-rendering the entire journal
            // behind every sheet present/dismiss. Closures read `sheetStack` only
            // when tapped, so the body no longer depends on it.
            onShowSessionDetail: {
                guard navigator.sheetStack.isEmpty else { return }
                navigator.present(.sessionDetail)
            },
            onAdd: {
                guard navigator.sheetStack.isEmpty else { return }
                navigator.present(.quickLog(routine: nil))
            },
        )
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

    /// Whether the floating session accessory is shown. Suppressed while the
    /// journal already surfaces the live session — on its day-detail (curve /
    /// substances / timing on screen) or at the journal root, where the hero
    /// card carries it — since the pill would only duplicate them.
    private var sessionAccessoryActive: Bool {
        ActiveSessionManager.shared.hasActiveSession
            && !viewingActiveSessionDay
            && !journalShowingActiveHero
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

    /// True when the journal stack's top screen is the detail for the session the
    /// active doses belong to. The session accessory would only echo what that
    /// screen already shows, so we hide it there. Matches by membership: the
    /// viewed session contains the active session's earliest dose.
    private var viewingActiveSessionDay: Bool {
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

    // MARK: Add Menu

    private var addMenu: some View {
        Button {
            guard navigator.sheetStack.isEmpty else { return }
            navigator.present(.quickLog(routine: nil), zoomSource: QuickLogTransition.floatingID)
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .contentShape(Circle())
                .glassEffect(.regular.tint(Theme.accent).interactive(), in: Circle())
        }
        // Clip the transition source to the button's circle (the default
        // rectangular placeholder leaves a faint card behind the glass capsule
        // as the dismissal zoom completes).
        .matchedTransitionSource(id: QuickLogTransition.floatingID, in: quickLogZoom) { source in
            // Full corner radius (half the 56pt side) → a circle. `clipShape`
            // here only accepts `RoundedRectangle`, so `.circle`/`.capsule` are
            // out; this matches the glass capsule and kills the faint card.
            source.clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
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
/// the system own focus gives the Music behaviour: enter → landing, tap field →
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
                    scopePicker
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

    /// Full-width scope selector pinned above the results, matching the Music
    /// app's prominent top toggle. A native segmented Picker (not
    /// `.searchScopes`, whose bar can't be widened/enlarged and renders
    /// inconsistently with a tab-bar search field).
    private var scopePicker: some View {
        Picker("Search scope", selection: $scope) {
            ForEach(SearchTabScope.allCases) { scope in
                Text(scope.title).tag(scope)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.large)
        .labelsHidden()
        .id(pickerToken)
        .frame(height: 44)
        .padding(.horizontal)
        .padding(.top, 4)
        .padding(.bottom, 8)
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

// MARK: - Session Bottom Accessory

private extension View {
    /// iOS hosts `tabViewBottomAccessory` content in a context separate from the
    /// main view tree, so a `matchedTransitionSource` placed *inside* the
    /// accessory can't anchor a sheet's zoom (it falls back to a centre zoom).
    /// The accessory's sheets therefore present as a normal slide-up rather than
    /// zooming — only the journal's floating + and the day-detail + (both in the
    /// main tree) get the grow-from-button effect.
    @ViewBuilder
    func withSessionAccessory(
        isActive: Bool,
        onShowSessionDetail: @escaping () -> Void,
        onAdd: @escaping () -> Void,
    ) -> some View {
        if #available(iOS 26.1, *) {
            self.tabViewBottomAccessory(isEnabled: isActive) {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    SessionAccessoryView(
                        states: ActiveSessionManager.shared.activeSubstanceStates,
                        currentTime: context.date,
                        onTapSession: onShowSessionDetail,
                        onAdd: onAdd,
                    )
                }
            }
        } else {
            self
        }
    }
}

// MARK: - Session Accessory View

private struct SessionAccessoryView: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @AppStorage("stackRedoses", store: UserDefaults(suiteName: "group.dev.yumeji.piru")) private var stackRedoses = true

    let states: [ActiveSubstanceState]
    let currentTime: Date
    var onTapSession: () -> Void
    var onAdd: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onTapSession) {
                HStack(spacing: 10) {
                    if placement != .inline {
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
                    }

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
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            // Primary action: log another dose. No background fill — a bare
            // accent glyph avoids any glass-on-glass or concentricity issues
            // against the accessory's own capsule. The 44pt hit box matches the
            // tab bar's search button (44pt wide, 12pt trailing) so their
            // centres line up.
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Log dose"))
        }
        .padding(.leading, 16)
        .padding(.trailing, 11)
    }

    private var uniqueNames: String {
        var seen = Set<String>()
        return states.compactMap { state in
            let key = state.substanceName.lowercased()
            guard !seen.contains(key) else { return nil }
            seen.insert(key)
            return state.substanceName
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
