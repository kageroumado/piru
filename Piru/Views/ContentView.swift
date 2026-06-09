import SwiftData
import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appNavigator) private var navigator

    @State private var searchText = ""
    @State private var librarySearchText = ""

    /// Which dataset the Search tab is currently querying. Seeded from the tab
    /// the user came from (Library → library, anything else → library), then
    /// user-switchable via the scope picker.
    @State private var searchScope: SearchTabScope = .library

    /// Bumped to rebuild the search scope picker after its (global) title-font
    /// appearance changes — see ``applyScopePickerFont(forSearchActive:)``.
    @State private var scopePickerToken = 0

    /// The tab the user was on before entering Search. Cancelling search returns
    /// here, matching the Music app (the X exits the search surface entirely
    /// rather than leaving you stranded on a dismissed Search tab).
    @State private var tabBeforeSearch: AppTab = .library

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
        liquidGlassBody
            .onChange(of: navigator.selectedTab) { oldValue, newValue in
                if newValue == .search {
                    // Seed the scope from where the user came from; Library is
                    // the natural default from Tools/Insights/Search itself.
                    searchScope = (oldValue == .journal) ? .journal : .library
                    tabBeforeSearch = oldValue
                }
                searchText = ""
                librarySearchText = ""
                applyScopePickerFont(forSearchActive: newValue == .search)
            }
            .task {
                // Initial application — `onChange` doesn't fire for the tab the
                // app launches on, so cover the launch-onto-Search case here.
                applyScopePickerFont(forSearchActive: navigator.selectedTab == .search)
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

    // MARK: - Shared Tab Content

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

    // MARK: - Tab View

    private var liquidGlassBody: some View {
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
                        pickerRebuildToken: scopePickerToken,
                        onExitSearch: { navigator.selectedTab = tabBeforeSearch },
                    )
                    .toolbar { sharedToolbar }
                    .withAppDestinations()
                }
            }
        }
        .withSessionAccessory(
            isActive: sessionAccessoryActive,
            // Only treat the toggle as "on" when the sheet is at the TOP of
            // the stack — anything buried under another sheet isn't actually
            // visible, so flipping the toggle would otherwise no-op against
            // a stale getter reading. Same for setting: refuse to stack a
            // second sheet on top of an existing one (matches the addMenu
            // guard).
            //
            // The accessory's sheets present as a normal slide-up. iOS hosts
            // the accessory in a separate context, so a zoom can't anchor to
            // it — see the note in `withSessionAccessory`.
            showingSessionDetail: Binding(
                get: { navigator.sheetStack.last == .sessionDetail },
                set: { isShowing in
                    if isShowing {
                        guard navigator.sheetStack.isEmpty else { return }
                        navigator.present(.sessionDetail)
                    } else if navigator.sheetStack.last == .sessionDetail {
                        navigator.dismiss()
                    }
                },
            ),
            showingForm: Binding(
                get: {
                    if case .quickLog? = navigator.sheetStack.last { true } else { false }
                },
                set: { isShowing in
                    if isShowing {
                        guard navigator.sheetStack.isEmpty else { return }
                        navigator.present(.quickLog(routine: nil))
                    } else if case .quickLog? = navigator.sheetStack.last {
                        navigator.dismiss()
                    }
                },
            ),
        )
    }

    /// Whether the floating session accessory is shown. Suppressed while the
    /// journal already surfaces the live session — on its day-detail (curve /
    /// substances / timing on screen) or at the journal root, where the hero
    /// card carries it — since the pill would only duplicate them.
    private var sessionAccessoryActive: Bool {
        ActiveSessionManager.shared.hasActiveSession
            && !viewingActiveSessionDay
            && !journalShowingActiveHero
    }

    /// True when the journal stack's top screen is the detail for the session the
    /// active doses belong to. The session accessory would only echo what that
    /// screen already shows, so we hide it there. Matches by membership: the
    /// viewed session contains the active session's earliest dose.
    /// True when the journal is at its root with a live session — the new hero
    /// card there already carries the session, so the floating accessory would
    /// only echo it. (The journal root is never a search surface, so this lines
    /// up exactly with `EntryListView`'s own hero-visibility condition.)
    private var journalShowingActiveHero: Bool {
        navigator.selectedTab == .journal
            && navigator.path(for: .journal).isEmpty
            && ActiveSessionManager.shared.hasActiveSession
    }

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

    // MARK: - Add Menu

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

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var sharedToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                guard navigator.sheetStack.isEmpty else { return }
                navigator.present(.settings)
            } label: {
                Image(systemName: "gearshape")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                guard navigator.sheetStack.isEmpty else { return }
                navigator.present(.help)
            } label: {
                Image(systemName: "lifepreserver")
            }
        }
    }

    // MARK: - Deep Linking

    private func handleDeepLink(_ url: URL) {
        guard let outcome = DeepLink.decode(url) else { return }
        navigator.apply(outcome)
    }

    /// Enlarges the search scope picker's title font while Search is active and
    /// restores the default otherwise. SwiftUI's segmented `Picker` ignores a
    /// `.font` on its labels, so the global `UISegmentedControl` appearance
    /// proxy is the only lever. Managing it here on the always-mounted root —
    /// rather than inside `SearchView` — means the restore runs in the tab-change
    /// transaction *before* a sibling tab's picker is created, so the app's other
    /// segmented controls (Tools, Insights, …) never inherit the larger font.
    private func applyScopePickerFont(forSearchActive active: Bool) {
        let attributes: [NSAttributedString.Key: Any]? = active
            ? [.font: UIFont.preferredFont(forTextStyle: .body)]
            : nil
        UISegmentedControl.appearance().setTitleTextAttributes(attributes, for: .normal)
        UISegmentedControl.appearance().setTitleTextAttributes(attributes, for: .selected)
        if active { scopePickerToken += 1 }
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

/// Single search surface shared by the catalog and the journal. A native
/// full-width segmented `Picker` selects the dataset (Library/Journal); the
/// search field auto-activates on tab entry so the keyboard appears without a
/// second tap (matching the Music app).
private struct SearchView: View {
    @Environment(\.appNavigator) private var navigator
    @Binding var scope: SearchTabScope
    @Binding var searchText: String

    /// Forces the segmented `Picker` to rebuild whenever the parent changes the
    /// global `UISegmentedControl` title-font appearance — the proxy only
    /// affects controls created *after* it's set, so an existing instance won't
    /// pick up the larger font without being re-created.
    let pickerRebuildToken: Int

    /// Invoked when the user cancels search (taps the X) so the parent can leave
    /// the Search tab and return to where they came from.
    let onExitSearch: () -> Void

    /// Drives the system search field's presented/focused state. Set true when
    /// the Search tab becomes active so the keyboard rises immediately.
    @State private var isSearchActive = false

    var body: some View {
        VStack(spacing: 0) {
            // Full-width scope selector pinned above the results, matching the
            // Music app's prominent top toggle. A native segmented Picker (not
            // `.searchScopes`, whose bar can't be widened/enlarged and renders
            // inconsistently with a tab-bar search field).
            Picker("Search scope", selection: $scope) {
                ForEach(SearchTabScope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.large)
            .labelsHidden()
            .id(pickerRebuildToken)
            .padding(.horizontal)
            .padding(.vertical, 8)

            content
        }
        .searchable(
            text: $searchText,
            isPresented: $isSearchActive,
            prompt: Text(scope.prompt),
        )
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        // Raise the search field (and keyboard) whenever the Search tab is
        // active. `.task(id:)` runs after first render and re-runs on every
        // tab change, so it catches both the initial mount and later
        // re-entries.
        //
        // Leaving the tab resets `isSearchActive` to false: the system hides
        // the presentation without flipping our binding, so without this a
        // re-entry would write true→true — no published change, field stays
        // collapsed. The brief sleep lets the `.searchable` field finish
        // installing on first mount before we present it.
        .task(id: navigator.selectedTab) {
            guard navigator.selectedTab == .search else {
                isSearchActive = false
                return
            }
            try? await Task.sleep(for: .milliseconds(50))
            guard navigator.selectedTab == .search else { return }
            isSearchActive = true
        }
        // Tapping the search field's cancel (X) flips `isSearchActive` to
        // false while we're still on the Search tab — that's the user
        // exiting search, so leave the tab entirely (Music behaviour) rather
        // than stranding them on a dismissed search surface. Our own
        // programmatic dismissal only happens once `selectedTab` has already
        // left `.search`, so guarding on it avoids a feedback loop.
        .onChange(of: isSearchActive) { _, active in
            if !active, navigator.selectedTab == .search {
                onExitSearch()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch scope {
        case .library:
            SubstanceLibraryView(searchText: $searchText, isSearchSurface: true)
        case .journal:
            EntryListView(searchText: $searchText, isSearchSurface: true)
        }
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
        showingSessionDetail: Binding<Bool>,
        showingForm: Binding<Bool>,
    ) -> some View {
        if #available(iOS 26.1, *) {
            self.tabViewBottomAccessory(isEnabled: isActive) {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    SessionAccessoryView(
                        states: ActiveSessionManager.shared.activeSubstanceStates,
                        currentTime: context.date,
                        onTapSession: { showingSessionDetail.wrappedValue = true },
                        onAdd: { showingForm.wrappedValue = true },
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
