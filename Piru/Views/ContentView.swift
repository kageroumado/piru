import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appNavigator) private var navigator

    @State private var searchText = ""
    @State private var librarySearchText = ""

    /// Remembers the last content tab so the Search tab can mirror Library or
    /// Journal depending on what the user was browsing.
    @State private var lastContentTab: AppTab = .journal

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("discordPromptDismissedForever") private var discordDismissed = false
    @State private var showDiscordPrompt = false

    var body: some View {
        @Bindable var navigator = navigator
        liquidGlassBody
            .onChange(of: navigator.selectedTab) { oldValue, newValue in
                if newValue == .search {
                    lastContentTab = oldValue
                }
                searchText = ""
                librarySearchText = ""
            }
            .sheetStackPresenter(navigator)
            .fullScreenCover(isPresented: .init(
                get: { !hasCompletedOnboarding },
                set: { if !$0 { hasCompletedOnboarding = true } }
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
            .toolbar { sharedToolbar }
    }

    private var libraryContent: some View {
        SubstanceLibraryView(searchText: $librarySearchText)
            .toolbar { sharedToolbar }
    }

    private var toolsContent: some View {
        ToolsView()
            .toolbar { sharedToolbar }
    }

    private var insightsContent: some View {
        InsightsView()
            .toolbar { sharedToolbar }
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
                    Group {
                        if lastContentTab == .library {
                            SubstanceLibraryView(searchText: $librarySearchText)
                                .navigationTitle("Search Library")
                                .toolbar { sharedToolbar }
                                .searchable(text: $librarySearchText, prompt: "Search substances...")
                        } else {
                            EntryListView(searchText: $searchText)
                                .navigationTitle("Search Journal")
                                .toolbar { sharedToolbar }
                                .searchable(text: $searchText, prompt: "Search entries...")
                        }
                    }
                    .withAppDestinations()
                }
            }
        }
        .withSessionAccessory(
            isActive: ActiveSessionManager.shared.hasActiveSession,
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
                }
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
                }
            )
        )
    }

    // MARK: - Add Menu

    private var addMenu: some View {
        Button {
            guard navigator.sheetStack.isEmpty else { return }
            navigator.present(.quickLog)
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .frame(width: 56, height: 56)
                .contentShape(Circle())
                .glassEffect(.regular.interactive(), in: Circle())
                .tint(Theme.accent)
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
                Image(systemName: "staroflife")
            }
        }
    }

    // MARK: - Deep Linking

    private func handleDeepLink(_ url: URL) {
        guard let outcome = DeepLink.decode(url) else { return }
        navigator.apply(outcome)
    }
}

// MARK: - Session Bottom Accessory

private extension View {
    @ViewBuilder
    func withSessionAccessory(
        isActive: Bool,
        showingSessionDetail: Binding<Bool>,
        showingForm: Binding<Bool>
    ) -> some View {
        if #available(iOS 26.1, *) {
            self.tabViewBottomAccessory(isEnabled: isActive) {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    SessionAccessoryView(
                        states: ActiveSessionManager.shared.activeSubstanceStates,
                        isLiveActivityRunning: LiveActivityManager.shared.isLiveActivityRunning,
                        currentTime: context.date,
                        onTapSession: { showingSessionDetail.wrappedValue = true },
                        onToggleActivity: {
                            let manager = LiveActivityManager.shared
                            if manager.isLiveActivityRunning {
                                manager.hideLiveActivity()
                            } else {
                                manager.restartLiveActivity()
                            }
                        },
                        onAdd: { showingForm.wrappedValue = true }
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
    @AppStorage("stackRedoses", store: UserDefaults(suiteName: "group.dev.yumeji.piru")) private var stackRedoses = false

    let states: [ActiveSubstanceState]
    let isLiveActivityRunning: Bool
    let currentTime: Date
    var onTapSession: () -> Void
    var onToggleActivity: () -> Void
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
                            stackRedoses: stackRedoses
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

            HStack(spacing: 20) {
                Button(action: onToggleActivity) {
                    Image(systemName: isLiveActivityRunning ? "stop.fill" : "play.fill")
                        .font(.body)
                }

                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .padding(.horizontal, 16)
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

        if hours > 0 && minutes > 0 {
            return String(localized: "\(hours)h \(minutes)m")
        } else if hours > 0 {
            return String(localized: "\(hours)h")
        } else {
            return String(localized: "\(minutes)m")
        }
    }
}
