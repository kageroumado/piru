import SwiftUI
import SwiftData
import WidgetKit

struct QuickLogView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \DoseEntry.timestamp, order: .reverse, transaction: .init(animation: nil)) private var allEntries: [DoseEntry]
    @Query private var substanceColors: [SubstanceColor]
    @Query(sort: \DailyDoseItem.sortOrder) private var dailyDoseItems: [DailyDoseItem]
    @Query(sort: \FavoriteSubstance.createdAt, order: .reverse) private var favorites: [FavoriteSubstance]

    @State private var searchText = ""
    @AppStorage("dailyDoseCategories") private var categoriesData = Data()

    @State private var medicationCategory: MedicationCategoryItem?
    @State private var showColorPicker = false
    @State private var colorPickerSubstance = ""
    @State private var entryFormPrefill: EntryPrefill?
    @State private var pendingLogAction: (() -> Void)?

    @State private var multiSelectEnabled = false
    @State private var selectedDoses: [DoseSelection] = []

    @State private var cachedCards: [SubstanceCard] = []
    @State private var cachedFavoriteSet: Set<String> = []
    @State private var cachedHistoryNames: Set<String> = []
    @State private var cachedLibraryResults: [Substance] = []
    @State private var cachedColorLookup: [String: String] = [:]

    private var dailyDoseCategories: [String] {
        (try? JSONDecoder().decode([String].self, from: categoriesData)) ?? []
    }

    // MARK: - Grouping

    private func rebuildColorLookup() {
        cachedColorLookup = Array(substanceColors).hexColorMap
    }

    private func rebuildCards() {
        let entries = allEntries
        let newCards: [SubstanceCard]
        let newHistoryNames: Set<String>

        let colorLookup = cachedColorLookup

        var groupMap: [String: SubstanceGroup] = [:]

        for entry in entries {
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
                    librarySubstance: SubstanceLibrary.lookupByNameOrAlias(nameLower),
                    latestTimestamp: entry.timestamp
                )
                group.addEntry(entry)
                groupMap[key] = group
            }
        }

        var cardMap: [String: [SubstanceGroup]] = [:]
        for group in groupMap.values {
            cardMap[group.id.components(separatedBy: "|").first ?? "", default: []].append(group)
        }

        newCards = cardMap.values.map { routes in
            let sorted = routes.sorted { $0.latestTimestamp > $1.latestTimestamp }
            let first = sorted[0]
            return SubstanceCard(
                substanceName: first.substanceName,
                colorHex: first.colorHex,
                routes: sorted,
                latestTimestamp: sorted[0].latestTimestamp
            )
        }.sorted { $0.latestTimestamp > $1.latestTimestamp }

        newHistoryNames = Set(newCards.map(\.id))

        cachedCards = newCards
        cachedHistoryNames = newHistoryNames
        rebuildFavorites()
    }

    private func rebuildFavorites() {
        cachedFavoriteSet = Set(favorites.map { $0.substance.lowercased() })
    }

    private var filteredCards: [SubstanceCard] {
        guard !searchText.isEmpty else { return cachedCards }
        let query = searchText.lowercased()
        return cachedCards.filter { $0.id.contains(query) }
    }

    // MARK: - Favorites

    private var favoriteCards: [SubstanceCard] {
        guard searchText.isEmpty else { return [] }
        return cachedCards.filter { cachedFavoriteSet.contains($0.id) }
    }

    private var nonFavoriteCards: [SubstanceCard] {
        if searchText.isEmpty {
            return cachedCards.filter { !cachedFavoriteSet.contains($0.id) }
        }
        return filteredCards
    }

    private var favoriteLibrarySubstances: [Substance] {
        guard searchText.isEmpty else { return [] }
        return favorites
            .filter { !cachedHistoryNames.contains($0.substance.lowercased()) }
            .compactMap { SubstanceLibrary.lookupByNameOrAlias($0.substance.lowercased()) }
    }

    private func toggleFavorite(_ name: String) {
        let lowered = name.lowercased()
        if let existing = favorites.first(where: { $0.substance.lowercased() == lowered }) {
            cachedFavoriteSet.remove(lowered)
            modelContext.delete(existing)
        } else {
            cachedFavoriteSet.insert(lowered)
            modelContext.insert(FavoriteSubstance(substance: name))
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if !dailyDoseItems.isEmpty && searchText.isEmpty {
                        medicationsButton
                    }

                    if cachedCards.isEmpty && searchText.isEmpty {
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
                .padding(.bottom, 64)
            }
            .safeAreaInset(edge: .bottom) {
                searchBar
                    .padding(.horizontal)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Quick Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        withAnimation {
                            multiSelectEnabled.toggle()
                            if !multiSelectEnabled { selectedDoses.removeAll() }
                        }
                    } label: {
                        Image(systemName: multiSelectEnabled ? "checklist.checked" : "checklist")
                    }
                    if multiSelectEnabled && !selectedDoses.isEmpty {
                        Button("Add (\(selectedDoses.count))") {
                            batchLog()
                        }
                        .fontWeight(.semibold)
                    }
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
            .sheet(item: $medicationCategory) { item in
                LogMedicationsView(category: item.category)
            }
            .task {
                // Defer rebuild to next run loop so sheet presentation isn't blocked
                try? await Task.sleep(for: .milliseconds(50))
                rebuildColorLookup()
                rebuildCards()
            }
            .task(id: allEntries.count) {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                rebuildCards()
            }
            .onChange(of: substanceColors.count) {
                rebuildColorLookup()
                rebuildCards()
            }
            .onChange(of: favorites.count) { rebuildFavorites() }
            .task(id: searchText) {
                guard !searchText.isEmpty else {
                    cachedLibraryResults = []
                    return
                }
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                cachedLibraryResults = SubstanceLibrary.search(searchText)
                    .filter { !cachedHistoryNames.contains($0.name.lowercased()) }
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.secondaryLabel)
            TextField("Search substances...", text: $searchText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 12)
        .frame(height: 50)
        .glassEffect(.regular, in: .capsule)
    }

    // MARK: - Scroll Content

    private static let helpKeywords: Set<String> = [
        "help", "emergency", "overdose", "bad trip", "dying", "scared",
        "panic", "ambulance", "hospital", "not okay", "freaking out",
        "call 911", "911", "poisoning", "too much", "od", "can't breathe"
    ]

    private var isHelpSearch: Bool {
        guard !searchText.isEmpty else { return false }
        let query = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        return Self.helpKeywords.contains(where: { query.contains($0) })
    }

    @ViewBuilder
    private var scrollContentInner: some View {
        // Multi-select hint
        if !multiSelectEnabled {
            HStack(spacing: 4) {
                Text("Press the")
                Image(systemName: "checklist")
                    .imageScale(.small)
                Text("icon or long press doses to select multiple at once")
            }
            .font(.caption2)
            .foregroundStyle(Theme.secondaryLabel)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if multiSelectEnabled && !selectedDoses.isEmpty {
            selectedDosesSection
        } else {
            Text("Tap doses to select them, then tap Add to log together.")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        // Help resources — shown when user searches for help
        if isHelpSearch {
            quickLogHelpBanner
        }

        // Favorites section (only when not searching)
        if !favoriteCards.isEmpty || !favoriteLibrarySubstances.isEmpty {
            Section {
                ForEach(favoriteCards) { card in
                    substanceCard(card, isFavorite: true)
                        .id("\(card.id)_fav")
                }
                ForEach(favoriteLibrarySubstances) { substance in
                    libraryRow(substance)
                }
            } header: {
                Label("Favorites", systemImage: "star.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryLabel)
                    .textCase(.uppercase)
            }
        }

        // Recent / search results
        if !nonFavoriteCards.isEmpty {
            Section {
                ForEach(nonFavoriteCards) { card in
                    substanceCard(card, isFavorite: false)
                        .id("\(card.id)_recent")
                }
            } header: {
                if !favoriteCards.isEmpty && searchText.isEmpty {
                    Label("Recent", systemImage: "clock")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.secondaryLabel)
                        .textCase(.uppercase)
                }
            }
        } else if !searchText.isEmpty && cachedLibraryResults.isEmpty && favoriteCards.isEmpty {
            ContentUnavailableView.search(text: searchText)
        }

        if !cachedLibraryResults.isEmpty {
            Section {
                ForEach(cachedLibraryResults) { substance in
                    libraryRow(substance)
                }
            } header: {
                Text("From Library")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryLabel)
                    .textCase(.uppercase)
                    .padding(.top, 8)
            }
        }
    }

    // MARK: - Medications

    private var medicationsButton: some View {
        let activeCategories = dailyDoseCategories.filter { cat in
            dailyDoseItems.contains { $0.category == cat }
        }
        let uncategorized = dailyDoseItems.filter { $0.category.isEmpty }

        return VStack(spacing: 6) {
            ForEach(activeCategories, id: \.self) { cat in
                let catCount = dailyDoseItems.filter { $0.category == cat }.count
                medicationRow(
                    title: cat,
                    icon: iconForCategory(cat),
                    count: catCount,
                    category: cat
                )
            }

            if !uncategorized.isEmpty {
                medicationRow(
                    title: activeCategories.isEmpty ? "Prescriptions" : "Other",
                    icon: "pills",
                    count: uncategorized.count,
                    category: ""
                )
            }
        }
    }

    private func medicationRow(title: String, icon: String, count: Int, category: String) -> some View {
        Button {
            medicationCategory = MedicationCategoryItem(category: category)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text("\(count) prescription\(count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            .padding(12)
            .background(Theme.accent.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func iconForCategory(_ category: String) -> String {
        switch category.lowercased() {
        case "morning": return "sunrise"
        case "afternoon": return "sun.max"
        case "noon", "midday": return "sun.max"
        case "evening": return "sunset"
        case "night", "bedtime": return "moon"
        default: return "tag"
        }
    }

    // MARK: - Substance Card

    private func substanceCard(_ card: SubstanceCard, isFavorite: Bool) -> some View {
        let color = card.colorHex.map { Color(hex: $0) } ?? .gray

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                Text(card.substanceName)
                    .font(.headline)
                Spacer()
                Button {
                    withAnimation(.snappy) {
                        toggleFavorite(card.substanceName)
                    }
                } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.body)
                        .foregroundStyle(isFavorite ? Color.yellow : Theme.secondaryLabel)
                        .contentTransition(.symbolEffect(.replace))
                        .padding(.horizontal, 4)
                        .contentShape(Rectangle())
                }
            }

            if let lastEntry = mostRecentEntry(for: card.substanceName) {
                DoseSuggestionCard(
                    substanceName: card.substanceName,
                    lastDoseAmount: lastEntry.amount,
                    lastDoseTimestamp: lastEntry.timestamp,
                    unit: lastEntry.unit,
                    route: lastEntry.route
                )
            }

            ForEach(card.routes) { group in
                routeSection(group, color: color)
            }
        }
        .padding(.vertical, 4)
    }

    private func routeSection(_ group: SubstanceGroup, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(group.route.displayName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.secondaryLabel)
                .padding(.top, 4)

            doseChips(for: group, color: color)
        }
    }

    private func doseChips(for group: SubstanceGroup, color: Color) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(group.doses) { chip in
                let selected = multiSelectEnabled && isSelected(group: group, chip: chip)
                HStack(spacing: 4) {
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.caption2.weight(.bold))
                    }
                    Text("\(chip.formattedAmount) \(chip.unit)")
                }
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selected ? color : color.opacity(0.15))
                .foregroundStyle(selected ? .white : color)
                .clipShape(Capsule())
                .contentShape(Capsule())
                .onTapGesture {
                    if multiSelectEnabled {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            toggleSelection(group: group, chip: chip)
                        }
                    } else {
                        instantLog(group: group, chip: chip)
                    }
                }
                .onLongPressGesture {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if !multiSelectEnabled { multiSelectEnabled = true }
                        toggleSelection(group: group, chip: chip)
                    }
                }
            }

            if !multiSelectEnabled {
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
    }

    // MARK: - Library Row

    private func libraryRow(_ substance: Substance) -> some View {
        Button {
            openLibrarySubstance(substance)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "pill")
                    .foregroundStyle(Theme.secondaryLabel)
                VStack(alignment: .leading, spacing: 2) {
                    Text(substance.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text("\(substance.defaultRoute.displayName) \u{2014} \(substance.defaultUnit)")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Actions

    private func instantLog(group: SubstanceGroup, chip: DoseChip) {
        guard chip.amount > 0 else { return }
        let entry = DoseEntry(
            substance: group.substanceName,
            amount: chip.amount,
            unit: chip.unit,
            route: group.route
        )
        modelContext.insert(entry)
        WidgetCenter.shared.reloadAllTimelines()

        // Schedule wellness notifications & check cumulative dose
        scheduleWellnessIfNeeded(entry: entry, substance: group.librarySubstance)

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

    // MARK: - Multi-Select

    @ViewBuilder
    private var selectedDosesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(selectedDoses) { dose in
                HStack(spacing: 8) {
                    if let hex = dose.colorHex {
                        Circle().fill(Color(hex: hex)).frame(width: 8, height: 8)
                    }
                    Text(dose.substanceName)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(dose.amount.doseFormatted) \(dose.unit) — \(dose.route.displayName)")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                    Button {
                        withAnimation { selectedDoses.removeAll { $0.id == dose.id } }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                    .buttonStyle(.plain)
                }
            }

            let interactions = selectedInteractions
            if !interactions.isEmpty {
                Divider()
                ForEach(Array(interactions.enumerated()), id: \.offset) { _, warning in
                    InteractionWarningRow(warning: warning)
                }
            }
        }
        .padding(12)
        .background(Theme.accent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var selectedInteractions: [InteractionResult] {
        let names = Array(Set(selectedDoses.map(\.substanceName)))
        guard names.count >= 2 else { return [] }
        return InteractionChecker.checkBatch(names, against: [])
    }

    private func isSelected(group: SubstanceGroup, chip: DoseChip) -> Bool {
        let key = "\(group.substanceName.lowercased())|\(group.route.rawValue)|\(chip.amount)|\(chip.unit)"
        return selectedDoses.contains { $0.id == key }
    }

    private func toggleSelection(group: SubstanceGroup, chip: DoseChip) {
        let key = "\(group.substanceName.lowercased())|\(group.route.rawValue)|\(chip.amount)|\(chip.unit)"
        if let index = selectedDoses.firstIndex(where: { $0.id == key }) {
            selectedDoses.remove(at: index)
        } else {
            selectedDoses.append(DoseSelection(
                substanceName: group.substanceName,
                amount: chip.amount,
                unit: chip.unit,
                route: group.route,
                colorHex: group.colorHex,
                librarySubstance: group.librarySubstance
            ))
        }
    }

    private func batchLog() {
        for dose in selectedDoses {
            let entry = DoseEntry(
                substance: dose.substanceName,
                amount: dose.amount,
                unit: dose.unit,
                route: dose.route
            )
            modelContext.insert(entry)
            scheduleWellnessIfNeeded(entry: entry, substance: dose.librarySubstance)

            let colorHex = substanceColors.first {
                $0.substance.lowercased() == dose.substanceName.lowercased()
            }?.hexColor ?? "007AFF"

            LiveActivityManager.shared.addDose(
                entry: entry,
                substance: dose.librarySubstance,
                colorHex: colorHex,
                allColors: Array(substanceColors)
            )
        }
        WidgetCenter.shared.reloadAllTimelines()
        dismiss()
    }

    // MARK: - Helpers

    private var takenColorMap: [String: String] {
        Array(substanceColors).takenColorMap
    }

    private func hasColor(for name: String) -> Bool {
        Array(substanceColors).hasColor(for: name)
    }

    private func mostRecentEntry(for substanceName: String) -> DoseEntry? {
        let lowered = substanceName.lowercased()
        return allEntries.first { $0.substance.lowercased() == lowered }
    }

    // MARK: - Help Banner

    private var quickLogHelpBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "hand.raised.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Take a breath.")
                        .font(.headline)
                    Text("You're going to be okay. This feeling is temporary.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                helpBannerLink(title: "Emergency: 911", url: "tel:911")
                helpBannerLink(title: "Poison Control: 1-800-222-1222", url: "tel:18002221222")
                helpBannerLink(title: "Crisis Lifeline: 988", url: "tel:988")
                helpBannerLink(title: "Crisis Text: HOME to 741741", url: "sms:741741&body=HOME")
            }

            Text("Breathe slowly. 4 seconds in, hold for 4, out for 4. You are safe.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
        }
        .padding(14)
        .background(Color.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func helpBannerLink(title: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 6) {
                Image(systemName: "phone.fill")
                    .font(.caption)
                    .foregroundStyle(.blue)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
            }
        }
    }

    // MARK: - Wellness Notifications

    private func scheduleWellnessIfNeeded(entry: DoseEntry, substance: Substance?) {
        let category = substance?.category
        let duration = substance?.resolveDuration(for: entry.route)
        let stimHours = RampDownScheduler.stimulantSessionHours(from: Array(allEntries))

        RampDownScheduler.scheduleWellnessNotifications(
            substanceName: entry.substance,
            category: category,
            doseTime: entry.timestamp,
            duration: duration,
            recentStimHours: stimHours
        )

        // Check cumulative dose
        let (total, shouldAlert) = RampDownScheduler.checkCumulativeDose(
            substanceName: entry.substance,
            newAmount: entry.amount,
            unit: entry.unit,
            route: entry.route,
            existingEntries: Array(allEntries)
        )
        if shouldAlert {
            RampDownScheduler.scheduleCumulativeDoseNotification(
                substanceName: entry.substance,
                totalAmount: total,
                unit: entry.unit,
                category: category
            )
        }
    }
}

// MARK: - Data Types

struct SubstanceCard: Identifiable {
    let substanceName: String
    let colorHex: String?
    let routes: [SubstanceGroup]
    let latestTimestamp: Date

    var id: String { substanceName.lowercased() }
}

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

struct MedicationCategoryItem: Identifiable {
    let id = UUID()
    let category: String
}

struct EntryPrefill: Identifiable, Hashable {
    let id = UUID()
    let substance: String
    let route: RouteOfAdministration
    let unit: String
}

struct DoseSelection: Identifiable {
    let substanceName: String
    let amount: Double
    let unit: String
    let route: RouteOfAdministration
    let colorHex: String?
    let librarySubstance: Substance?

    var id: String { "\(substanceName.lowercased())|\(route.rawValue)|\(amount)|\(unit)" }
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
