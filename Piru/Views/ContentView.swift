import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedTab = 0
    @State private var searchText = ""
    @State private var librarySearchText = ""

    @State private var lastContentTab = 0
    @State private var activeSheet: SheetDestination?
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    enum SheetDestination: Identifiable {
        case quickLog
        case settings
        case help
        case sessionDetail
        case entryDetail(DoseEntry)

        var id: Int {
            switch self {
            case .quickLog: 0
            case .settings: 1
            case .help: 2
            case .sessionDetail: 3
            case .entryDetail: 4
            }
        }
    }

    var body: some View {
        liquidGlassBody
        .onChange(of: selectedTab) { oldValue, newValue in
            if newValue == 5 {
                lastContentTab = oldValue
            }
            searchText = ""
            librarySearchText = ""
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .quickLog:
                QuickLogView()
            case .settings:
                NavigationStack {
                    SettingsView()
                }
            case .help:
                HelpView()
            case .sessionDetail:
                NavigationStack {
                    DayDetailView(date: .now)
                        .navigationDestination(for: DoseEntry.self) { entry in
                            EntryDetailView(entry: entry)
                        }
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button {
                                    activeSheet = nil
                                } label: {
                                    Image(systemName: "xmark")
                                }
                            }
                        }
                }
            case .entryDetail(let entry):
                NavigationStack {
                    EntryDetailView(entry: entry)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button {
                                    activeSheet = nil
                                } label: {
                                    Image(systemName: "xmark")
                                }
                            }
                        }
                }
            }
        }
        .fullScreenCover(isPresented: .init(
            get: { !hasCompletedOnboarding },
            set: { if !$0 { hasCompletedOnboarding = true } }
        )) {
            OnboardingView()
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
            .withDayDetailDestination()
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
            .withDayDetailDestination()
    }

    // MARK: - Tab View

    private var liquidGlassBody: some View {
        TabView(selection: $selectedTab) {
            Tab("Journal", systemImage: "book", value: 0) {
                NavigationStack {
                    journalContent
                        .overlay(alignment: .bottom) {
                            if !ActiveSessionManager.shared.hasActiveSession {
                                addMenu
                                    .padding(.bottom, 16)
                            }
                        }
                }
            }
            Tab("Library", systemImage: "books.vertical", value: 1) {
                NavigationStack {
                    libraryContent
                }
            }
            Tab("Tools", systemImage: "wrench.and.screwdriver", value: 2) {
                NavigationStack { toolsContent }
            }
            Tab("Insights", systemImage: "chart.line.uptrend.xyaxis", value: 3) {
                NavigationStack { insightsContent }
            }
            Tab("Search", systemImage: "magnifyingglass", value: 5, role: .search) {
                NavigationStack {
                    if lastContentTab == 1 {
                        SubstanceLibraryView(searchText: $librarySearchText)
                            .navigationTitle("Search Library")
                            .toolbar { sharedToolbar }
                            .searchable(text: $librarySearchText, prompt: "Search substances...")
                    } else {
                        EntryListView(searchText: $searchText)
                            .withDayDetailDestination()
                            .navigationTitle("Search Journal")
                            .toolbar { sharedToolbar }
                            .searchable(text: $searchText, prompt: "Search entries...")
                    }
                }
            }
        }
        .withSessionAccessory(
            isActive: ActiveSessionManager.shared.hasActiveSession,
            showingSessionDetail: Binding(
                get: { activeSheet?.id == SheetDestination.sessionDetail.id },
                set: { if $0 { activeSheet = .sessionDetail } else { activeSheet = nil } }
            ),
            showingForm: Binding(
                get: { activeSheet?.id == SheetDestination.quickLog.id },
                set: { if $0 { activeSheet = .quickLog } else { activeSheet = nil } }
            )
        )
    }

    // MARK: - Add Menu

    private var addMenu: some View {
        Button {
            guard activeSheet == nil else { return }
            activeSheet = .quickLog
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
                guard activeSheet == nil else { return }
                activeSheet = .settings
            } label: {
                Image(systemName: "gearshape")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                guard activeSheet == nil else { return }
                activeSheet = .help
            } label: {
                Image(systemName: "staroflife")
            }
        }
    }

    // MARK: - Deep Linking

    private func handleDeepLink(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "piru" else { return }

        switch components.host {
        case "day":
            selectedTab = 0
            activeSheet = .sessionDetail

        case "entry":
            if let tsString = components.path.split(separator: "/").first,
               let ts = TimeInterval(tsString) {
                let target = Date(timeIntervalSince1970: ts)
                let lower = target.addingTimeInterval(-2)
                let upper = target.addingTimeInterval(2)
                let descriptor = FetchDescriptor<DoseEntry>(
                    predicate: #Predicate { entry in
                        entry.timestamp >= lower && entry.timestamp <= upper
                    }
                )
                if let entry = try? modelContext.fetch(descriptor).first {
                    selectedTab = 0
                    activeSheet = .entryDetail(entry)
                } else {
                    // Entry not found — fall back to day view
                    selectedTab = 0
                    activeSheet = .sessionDetail
                }
            }

        default:
            break
        }
    }
}

// MARK: - Day Detail Navigation Destination

private extension View {
    func withDayDetailDestination() -> some View {
        self.navigationDestination(for: Date.self) { date in
            DayDetailView(date: date)
        }
        .navigationDestination(for: DoseEntry.self) { entry in
            EntryDetailView(entry: entry)
        }
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
        guard let start = states.map(\.doseTimestamp).min() else { return "0m" }
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
            return "\(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(minutes)m"
        }
    }
}
