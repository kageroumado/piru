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
            .sheetStackPresenter(navigator)
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
                        .overlay(alignment: .bottom) {
                            if !ActiveSessionManager.shared.hasActiveSession {
                                addMenu
                                    .padding(.bottom, 16)
                            }
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
            // Suppress the accessory while the journal is showing the day-detail
            // for the session's own day — the curve, substances and timing are
            // already on screen there, so the floating pill only duplicates them.
            isActive: ActiveSessionManager.shared.hasActiveSession && !viewingActiveSessionDay,
            // Only treat the toggle as "on" when the sheet is at the TOP of
            // the stack — anything buried under another sheet isn't actually
            // visible, so flipping the toggle would otherwise no-op against
            // a stale getter reading. Same for setting: refuse to stack a
            // second sheet on top of an existing one (matches the addMenu
            // guard).
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
                get: { navigator.sheetStack.last == .quickLog },
                set: { isShowing in
                    if isShowing {
                        guard navigator.sheetStack.isEmpty else { return }
                        navigator.present(.quickLog)
                    } else if navigator.sheetStack.last == .quickLog {
                        navigator.dismiss()
                    }
                },
            ),
        )
    }

    /// True when the journal stack's top screen is the day-detail for the day the
    /// active session belongs to. The session accessory would only echo what that
    /// screen already shows, so we hide it there.
    private var viewingActiveSessionDay: Bool {
        guard navigator.selectedTab == .journal,
              case let .day(date) = navigator.path(for: .journal).last,
              let sessionStart = ActiveSessionManager.shared.activeSubstanceStates
              .map(\.doseTimestamp).min()
        else { return false }
        let calendar = Calendar.current
        return calendar.sessionDayStart(for: date) == calendar.sessionDayStart(for: sessionStart)
    }

    // MARK: - Add Menu

    private var addMenu: some View {
        Button {
            guard navigator.sheetStack.isEmpty else { return }
            navigator.present(.quickLog)
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .contentShape(Circle())
                .glassEffect(.regular.tint(Theme.accent).interactive(), in: Circle())
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
        let totalMinutes = max(0, Int(interval / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0, minutes > 0 {
            return String(localized: "\(hours)h \(minutes)m")
        } else if hours > 0 {
            return String(localized: "\(hours)h")
        } else {
            return String(localized: "\(minutes)m")
        }
    }
}
