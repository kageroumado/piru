import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var searchText = ""
    @State private var librarySearchText = ""
    @State private var isSearching = false
    @FocusState private var searchFieldFocused: Bool

    @State private var lastContentTab = 0
    @State private var showingForm = false
    @State private var showingSettings = false
    @State private var showingHelp = false
    @State private var showingSessionDetail = false

    var body: some View {
        Group {
            if #available(iOS 26, *) {
                liquidGlassBody
            } else {
                legacyBody
            }
        }
        .onChange(of: selectedTab) { oldValue, newValue in
            if newValue == 5 {
                lastContentTab = oldValue
            }
            searchText = ""
            librarySearchText = ""
            searchFieldFocused = false
            withAnimation(.snappy(duration: 0.25)) {
                isSearching = false
            }
        }
        .sheet(isPresented: $showingForm) {
            QuickLogView()
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView()
            }
        }
        .sheet(isPresented: $showingHelp) {
            HelpView()
        }
        .sheet(isPresented: $showingSessionDetail) {
            NavigationStack {
                DayDetailView(date: .now)
                    .navigationDestination(for: DoseEntry.self) { entry in
                        EntryDetailView(entry: entry)
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") {
                                showingSessionDetail = false
                            }
                        }
                    }
            }
        }
    }

    // MARK: - Shared Tab Content

    private var journalContent: some View {
        EntryListView(searchText: $searchText)
            .navigationTitle("Piru")
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

    // MARK: - Liquid Glass (iOS 26+)

    @available(iOS 26, *)
    private var liquidGlassBody: some View {
        TabView(selection: $selectedTab) {
            Tab("Journal", systemImage: "book", value: 0) {
                NavigationStack {
                    journalContent
                        .overlay(alignment: .bottom) {
                            if !LiveActivityManager.shared.hasActiveSession {
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
            isActive: LiveActivityManager.shared.hasActiveSession,
            showingSessionDetail: $showingSessionDetail,
            showingForm: $showingForm
        )
    }

    // MARK: - Add Menu

    private var addMenu: some View {
        Button {
            showingForm = true
        } label: {
            Image(systemName: "plus")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(Theme.accent, in: Circle())
                .shadow(color: Theme.accent.opacity(0.3), radius: 8, y: 4)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var sharedToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showingHelp = true
            } label: {
                Image(systemName: "heart.circle")
            }
        }
    }

    // MARK: - Legacy Body (pre-iOS 26)

    private var legacyBody: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case 0: NavigationStack { journalContent }
                case 1: NavigationStack { libraryContent }
                case 2: NavigationStack { toolsContent }
                case 3: NavigationStack { insightsContent }
                default: EmptyView()
                }
            }

            if isSearching {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        dismissSearch()
                    }
            }

            VStack(spacing: 12) {
                if selectedTab == 0 && !isSearching {
                    addMenu
                }
                legacyBottomBar
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Legacy Bottom Bar

    private var showSearchButton: Bool {
        selectedTab == 0 || selectedTab == 1
    }

    private var activeSearchText: Binding<String> {
        selectedTab == 1 ? $librarySearchText : $searchText
    }

    @ViewBuilder
    private var legacyBottomBar: some View {
        if isSearching {
            legacySearchBar
        } else {
            legacyTabBar
        }
    }

    private var legacySearchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.secondaryLabel)
                .font(.subheadline.weight(.medium))
            TextField(selectedTab == 1 ? "Search substances..." : "Search entries...", text: activeSearchText)
                .font(.subheadline)
                .focused($searchFieldFocused)
                .submitLabel(.search)
            if !activeSearchText.wrappedValue.isEmpty {
                Button {
                    activeSearchText.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
            Button {
                dismissSearch()
            } label: {
                Text("Cancel")
                    .font(.subheadline.weight(.medium))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .themeCapsule()
        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .trailing)))
    }

    private var legacyTabBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                legacyTabButton(icon: "book", label: "Journal", tab: 0)
                legacyTabButton(icon: "books.vertical", label: "Library", tab: 1)
                legacyTabButton(icon: "wrench.and.screwdriver", label: "Tools", tab: 2)
                legacyTabButton(icon: "chart.line.uptrend.xyaxis", label: "Insights", tab: 3)
            }
            .padding(4)
            .themeCapsule()

            if showSearchButton {
                Button {
                    withAnimation(.snappy(duration: 0.25)) {
                        isSearching = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        searchFieldFocused = true
                    }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.body.weight(.medium))
                        .frame(width: 64, height: 64)
                        .themeCircle()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .leading)))
    }

    @ViewBuilder
    private func legacyTabButton(icon: String, label: String, tab: Int) -> some View {
        let isSelected = selectedTab == tab
        Button {
            withAnimation(.snappy(duration: 0.2)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 1) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(isSelected ? Theme.accent : Theme.secondaryLabel)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .padding(.horizontal, 6)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Theme.accent.opacity(0.1))
                }
            }
        }
        .animation(.snappy(duration: 0.2), value: isSelected)
    }

    // MARK: - Dismiss Search

    private func dismissSearch() {
        searchFieldFocused = false
        searchText = ""
        librarySearchText = ""
        withAnimation(.snappy(duration: 0.25)) {
            isSearching = false
        }
    }
}

// MARK: - Day Detail Navigation Destination

private extension View {
    func withDayDetailDestination() -> some View {
        self.navigationDestination(for: Date.self) { date in
            DayDetailView(date: date)
                .navigationDestination(for: DoseEntry.self) { entry in
                    EntryDetailView(entry: entry)
                }
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
                        states: LiveActivityManager.shared.activeSubstanceStates,
                        isLiveActivityRunning: LiveActivityManager.shared.isLiveActivityRunning,
                        currentTime: context.date,
                        onTapSession: { showingSessionDetail.wrappedValue = true },
                        onToggleActivity: {
                            let manager = LiveActivityManager.shared
                            if manager.isLiveActivityRunning {
                                manager.stopLiveActivity()
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
                            compact: true
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
