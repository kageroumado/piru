import SwiftUI
import SwiftData

struct QuickLogView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \DoseEntry.timestamp, order: .reverse) private var allEntries: [DoseEntry]
    @Query private var substanceColors: [SubstanceColor]
    @Query(sort: \DailyDoseItem.sortOrder) private var dailyDoseItems: [DailyDoseItem]
    @Query(sort: \FavoriteSubstance.createdAt, order: .reverse) private var favorites: [FavoriteSubstance]

    @State private var searchText = ""
    @State private var showingDailyDose = false
    @State private var showColorPicker = false
    @State private var colorPickerSubstance = ""
    @State private var entryFormPrefill: EntryPrefill?
    @State private var pendingLogAction: (() -> Void)?

    @State private var cachedGroups: [SubstanceGroup] = []
    @State private var cachedFavoriteSet: Set<String> = []

    // MARK: - Grouping

    private func rebuildGroups() {
        var colorLookup: [String: String] = [:]
        for sc in substanceColors {
            colorLookup[sc.substance.lowercased()] = sc.hexColor
        }

        var groupMap: [String: SubstanceGroup] = [:]

        for entry in allEntries {
            let nameLower = entry.substance.lowercased()
            let key = "\(nameLower)|\(entry.route.rawValue)"
            if var group = groupMap[key] {
                group.addEntry(entry)
                groupMap[key] = group
            } else {
                var group = SubstanceGroup(
                    substanceName: entry.substance,
                    route: entry.route,
                    colorHex: colorLookup[nameLower],
                    librarySubstance: SubstanceLibrary.lookup(nameLower),
                    latestTimestamp: entry.timestamp
                )
                group.addEntry(entry)
                groupMap[key] = group
            }
        }

        cachedGroups = groupMap.values.sorted { $0.latestTimestamp > $1.latestTimestamp }
    }

    private func rebuildFavoriteSet() {
        cachedFavoriteSet = Array(favorites).favoriteSet
    }

    private var filteredGroups: [SubstanceGroup] {
        guard !searchText.isEmpty else { return cachedGroups }
        let query = searchText.lowercased()
        return cachedGroups.filter { $0.substanceName.lowercased().contains(query) }
    }

    private var libraryResults: [Substance] {
        guard !searchText.isEmpty else { return [] }
        let historyNames = Set(cachedGroups.map { $0.substanceName.lowercased() })
        return SubstanceLibrary.search(searchText).filter { !historyNames.contains($0.name.lowercased()) }
    }

    // MARK: - Favorites

    private var favoriteGroups: [SubstanceGroup] {
        guard searchText.isEmpty else { return [] }
        return cachedGroups.filter { cachedFavoriteSet.contains($0.substanceName.lowercased()) }
    }

    private var nonFavoriteGroups: [SubstanceGroup] {
        let groups = searchText.isEmpty ? cachedGroups : filteredGroups
        if searchText.isEmpty {
            return groups.filter { !cachedFavoriteSet.contains($0.substanceName.lowercased()) }
        }
        return groups
    }

    private var favoriteLibrarySubstances: [Substance] {
        guard searchText.isEmpty else { return [] }
        let historyNames = Set(cachedGroups.map { $0.substanceName.lowercased() })
        return favorites
            .filter { !historyNames.contains($0.substance.lowercased()) }
            .compactMap { SubstanceLibrary.lookup($0.substance.lowercased()) }
    }

    private func isFavorite(_ name: String) -> Bool {
        cachedFavoriteSet.contains(name.lowercased())
    }

    private func toggleFavorite(_ name: String) {
        let lowered = name.lowercased()
        if let existing = favorites.first(where: { $0.substance.lowercased() == lowered }) {
            modelContext.delete(existing)
        } else {
            modelContext.insert(FavoriteSubstance(substance: name))
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if !dailyDoseItems.isEmpty && searchText.isEmpty {
                        dailyDoseButton
                    }

                    if cachedGroups.isEmpty && searchText.isEmpty {
                        ContentUnavailableView(
                            "No Previous Substances",
                            systemImage: "magnifyingglass",
                            description: Text("Search for a substance to log your first entry.")
                        )
                    } else {
                        scrollContentInner
                    }
                }
                .padding(.horizontal)
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
            .safeAreaInset(edge: .top) {
                searchBar
            }
            .navigationTitle("Quick Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showColorPicker, onDismiss: onColorPickerDismiss) {
                SubstanceColorPickerView(
                    substanceName: colorPickerSubstance,
                    takenColors: takenColorMap
                ) { hex in
                    let sc = SubstanceColor(substance: colorPickerSubstance, hexColor: hex)
                    modelContext.insert(sc)
                }
                .presentationDetents([.large])
            }
            .sheet(item: $entryFormPrefill) { prefill in
                EntryFormView(prefillSubstance: prefill.substance, prefillRoute: prefill.route, prefillUnit: prefill.unit)
            }
            .sheet(isPresented: $showingDailyDose) {
                LogDailyDoseView()
            }
            .task { rebuildGroups(); rebuildFavoriteSet() }
            .onChange(of: allEntries.count) { rebuildGroups() }
            .onChange(of: substanceColors.count) { rebuildGroups() }
            .onChange(of: favorites.count) { rebuildFavoriteSet() }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search substances...", text: $searchText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
        }
        .padding(10)
        .background(.bar)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .padding(.bottom, 8)
        .background(.bar)
    }

    // MARK: - Scroll Content

    @ViewBuilder
    private var scrollContentInner: some View {
        // Favorites section (only when not searching)
        if !favoriteGroups.isEmpty || !favoriteLibrarySubstances.isEmpty {
            Section {
                ForEach(favoriteGroups) { group in
                    substanceRow(group)
                }
                ForEach(favoriteLibrarySubstances) { substance in
                    libraryRow(substance)
                }
            } header: {
                Label("Favorites", systemImage: "star.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
        }

        // Recent / search results
        if !nonFavoriteGroups.isEmpty {
            if !favoriteGroups.isEmpty && searchText.isEmpty {
                Text("Recent")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.top, 8)
            }
            ForEach(nonFavoriteGroups) { group in
                substanceRow(group)
            }
        } else if !searchText.isEmpty && libraryResults.isEmpty && favoriteGroups.isEmpty {
            ContentUnavailableView.search(text: searchText)
        }

        if !libraryResults.isEmpty {
            Section {
                ForEach(libraryResults) { substance in
                    libraryRow(substance)
                }
            } header: {
                Text("From Library")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.top, 8)
            }
        }
    }

    // MARK: - Daily Dose Button

    private var dailyDoseButton: some View {
        Button {
            showingDailyDose = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "pills")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Log Daily Dose")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text("\(dailyDoseItems.count) item\(dailyDoseItems.count == 1 ? "" : "s") configured")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Theme.accent.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Substance Row

    private func substanceRow(_ group: SubstanceGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(group.colorHex.map { Color(hex: $0) } ?? .gray)
                    .frame(width: 10, height: 10)
                Text(group.substanceName)
                    .font(.headline)
                Text(group.route.displayName)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .clipShape(Capsule())
                Spacer()
                Button {
                    toggleFavorite(group.substanceName)
                } label: {
                    Image(systemName: isFavorite(group.substanceName) ? "star.fill" : "star")
                        .font(.body)
                        .foregroundStyle(isFavorite(group.substanceName) ? Color.yellow : Color.secondary.opacity(0.3))
                }
                .buttonStyle(.plain)
            }

            FlowLayout(spacing: 6) {
                ForEach(group.doses) { chip in
                    Button {
                        instantLog(group: group, chip: chip)
                    } label: {
                        Text("\(chip.formattedAmount) \(chip.unit)")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                (group.colorHex.map { Color(hex: $0) } ?? Theme.accent).opacity(0.15)
                            )
                            .foregroundStyle(group.colorHex.map { Color(hex: $0) } ?? Theme.accent)
                            .clipShape(Capsule())
                    }
                }

                Button {
                    openOtherDose(group: group)
                } label: {
                    Label("Other dose", systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.tint.opacity(0.12))
                        .foregroundStyle(.tint)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Library Row

    private func libraryRow(_ substance: Substance) -> some View {
        Button {
            openLibrarySubstance(substance)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "pill")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(substance.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text("\(substance.defaultRoute.displayName) \u{2014} \(substance.defaultUnit)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Actions

    private func instantLog(group: SubstanceGroup, chip: DoseChip) {
        let entry = DoseEntry(
            substance: group.substanceName,
            amount: chip.amount,
            unit: chip.unit,
            route: group.route
        )
        modelContext.insert(entry)

        if hasColor(for: group.substanceName) {
            startLiveActivity(entry: entry, group: group)
            dismiss()
        } else {
            pendingLogAction = {
                startLiveActivity(entry: entry, group: group)
                dismiss()
            }
            colorPickerSubstance = group.substanceName
            showColorPicker = true
        }
    }

    private func openOtherDose(group: SubstanceGroup) {
        entryFormPrefill = EntryPrefill(
            substance: group.substanceName,
            route: group.route,
            unit: group.doses.first?.unit ?? "mg"
        )
    }

    private func openLibrarySubstance(_ substance: Substance) {
        entryFormPrefill = EntryPrefill(
            substance: substance.name,
            route: substance.defaultRoute,
            unit: substance.defaultUnit
        )
    }

    private func startLiveActivity(entry: DoseEntry, group: SubstanceGroup) {
        let colorHex = substanceColors.first {
            $0.substance.lowercased() == entry.substance.lowercased()
        }?.hexColor ?? "007AFF"

        LiveActivityManager.shared.addDose(
            entry: entry,
            substance: group.librarySubstance,
            colorHex: colorHex,
            allColors: Array(substanceColors)
        )
    }

    private func onColorPickerDismiss() {
        if let action = pendingLogAction {
            action()
            pendingLogAction = nil
        } else {
            dismiss()
        }
    }

    // MARK: - Helpers

    private var takenColorMap: [String: String] {
        Array(substanceColors).takenColorMap
    }

    private func hasColor(for name: String) -> Bool {
        Array(substanceColors).hasColor(for: name)
    }
}

// MARK: - Data Types

struct SubstanceGroup: Identifiable {
    let id: String
    let substanceName: String
    let route: RouteOfAdministration
    let colorHex: String?
    let librarySubstance: Substance?
    var latestTimestamp: Date
    private var doseCounts: [String: (amount: Double, unit: String, count: Int)] = [:]

    var doses: [DoseChip] {
        doseCounts.values
            .sorted { $0.count > $1.count }
            .map { DoseChip(amount: $0.amount, unit: $0.unit, count: $0.count) }
    }

    init(substanceName: String, route: RouteOfAdministration, colorHex: String?, librarySubstance: Substance?, latestTimestamp: Date) {
        self.id = "\(substanceName.lowercased())|\(route.rawValue)"
        self.substanceName = substanceName
        self.route = route
        self.colorHex = colorHex
        self.librarySubstance = librarySubstance
        self.latestTimestamp = latestTimestamp
    }

    mutating func addEntry(_ entry: DoseEntry) {
        let key = "\(entry.amount)|\(entry.unit)"
        if var existing = doseCounts[key] {
            existing.count += 1
            doseCounts[key] = existing
        } else {
            doseCounts[key] = (amount: entry.amount, unit: entry.unit, count: 1)
        }
        if entry.timestamp > latestTimestamp {
            latestTimestamp = entry.timestamp
        }
    }
}

struct EntryPrefill: Identifiable {
    let id = UUID()
    let substance: String
    let route: RouteOfAdministration
    let unit: String
}

struct DoseChip: Identifiable {
    let amount: Double
    let unit: String
    let count: Int

    var id: String { "\(amount)|\(unit)" }

    var formattedAmount: String {
        amount.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", amount)
            : String(format: "%.2g", amount)
    }
}
