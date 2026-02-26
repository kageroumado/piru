import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var searchText = ""
    @State private var librarySearchText = ""
    @State private var isSearching = false
    @FocusState private var searchFieldFocused: Bool

    @State private var showingForm = false
    @State private var showingSettings = false

    var body: some View {
        Group {
            if #available(iOS 26, *) {
                liquidGlassBody
            } else {
                legacyBody
            }
        }
        .onChange(of: selectedTab) {
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
    }

    // MARK: - Liquid Glass (iOS 26+)

    @available(iOS 26, *)
    private var liquidGlassBody: some View {
        TabView(selection: $selectedTab) {
            Tab("Journal", systemImage: "book", value: 0) {
                NavigationStack {
                    EntryListView(searchText: $searchText)
                        .navigationTitle("Piru")
                        .toolbar { settingsToolbarItem }
                        .navigationDestination(for: Date.self) { date in
                            DayDetailView(date: date)
                                .navigationDestination(for: DoseEntry.self) { entry in
                                    EntryDetailView(entry: entry)
                                }
                        }
                        .overlay(alignment: .bottom) {
                            addMenu
                                .padding(.bottom, 16)
                        }
                }
            }
            Tab("Library", systemImage: "books.vertical", value: 1) {
                NavigationStack {
                    SubstanceLibraryView(searchText: $librarySearchText)
                        .toolbar { settingsToolbarItem }
                        .searchable(text: $librarySearchText, prompt: Text("Search \(SubstanceLibrary.all.count) substances..."))
                }
            }
            Tab("Interactions", systemImage: "cross.case", value: 2) {
                NavigationStack {
                    InteractionCheckerView()
                        .toolbar { settingsToolbarItem }
                }
            }
            Tab("Insights", systemImage: "chart.line.uptrend.xyaxis", value: 3) {
                NavigationStack {
                    InsightsView()
                        .toolbar { settingsToolbarItem }
                        .navigationDestination(for: Date.self) { date in
                            DayDetailView(date: date)
                                .navigationDestination(for: DoseEntry.self) { entry in
                                    EntryDetailView(entry: entry)
                                }
                        }
                }
            }
            Tab("Search", systemImage: "magnifyingglass", value: 5, role: .search) {
                NavigationStack {
                    EntryListView(searchText: $searchText)
                        .navigationTitle("Search")
                        .toolbar { settingsToolbarItem }
                        .searchable(text: $searchText)
                        .navigationDestination(for: Date.self) { date in
                            DayDetailView(date: date)
                                .navigationDestination(for: DoseEntry.self) { entry in
                                    EntryDetailView(entry: entry)
                                }
                        }
                }
            }
        }
    }

    // MARK: - Add Menu

    private var addMenu: some View {
        Button {
            showingForm = true
        } label: {
            Image(systemName: "plus")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Theme.accent, in: Circle())
                .shadow(color: Theme.accent.opacity(0.3), radius: 8, y: 4)
        }
    }

    // MARK: - Settings Toolbar

    private var settingsToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
        }
    }

    // MARK: - Legacy Body (pre-iOS 26)

    private var legacyBody: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case 0:
                    NavigationStack {
                        EntryListView(searchText: $searchText)
                            .navigationTitle("Piru")
                            .toolbar { settingsToolbarItem }
                            .navigationDestination(for: Date.self) { date in
                                DayDetailView(date: date)
                                    .navigationDestination(for: DoseEntry.self) { entry in
                                        EntryDetailView(entry: entry)
                                    }
                            }
                    }
                case 1:
                    NavigationStack {
                        SubstanceLibraryView(searchText: $librarySearchText)
                            .toolbar { settingsToolbarItem }
                    }
                case 2:
                    NavigationStack {
                        InteractionCheckerView()
                            .toolbar { settingsToolbarItem }
                    }
                case 3:
                    NavigationStack {
                        InsightsView()
                            .toolbar { settingsToolbarItem }
                            .navigationDestination(for: Date.self) { date in
                                DayDetailView(date: date)
                                    .navigationDestination(for: DoseEntry.self) { entry in
                                        EntryDetailView(entry: entry)
                                    }
                            }
                    }
                default:
                    EmptyView()
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

    @State private var tabBarHeight: CGFloat = 46

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
                .foregroundStyle(.secondary)
                .font(.subheadline.weight(.medium))
            TextField("Search", text: activeSearchText)
                .font(.subheadline)
                .focused($searchFieldFocused)
                .submitLabel(.search)
            if !activeSearchText.wrappedValue.isEmpty {
                Button {
                    activeSearchText.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
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
        .background(.ultraThinMaterial, in: Capsule())
        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .trailing)))
    }

    private var legacyTabBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                legacyTabButton(icon: "book", label: "Journal", tab: 0)
                legacyTabButton(icon: "books.vertical", label: "Library", tab: 1)
                legacyTabButton(icon: "cross.case", label: "Interactions", tab: 2)
                legacyTabButton(icon: "chart.line.uptrend.xyaxis", label: "Insights", tab: 3)
            }
            .padding(4)
            .background(.ultraThinMaterial, in: Capsule())

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
                        .frame(width: tabBarHeight, height: tabBarHeight)
                        .background(.ultraThinMaterial, in: Circle())
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
            .foregroundStyle(isSelected ? Theme.accent : .secondary)
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
