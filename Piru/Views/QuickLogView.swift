import SwiftData
import SwiftUI
import WidgetKit

struct QuickLogView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appNavigator) private var navigator

    @Query(sort: \DoseEntry.timestamp, order: .reverse, transaction: .init(animation: nil)) private var allEntries: [DoseEntry]
    @Query private var substanceColors: [SubstanceColor]
    @Query(sort: \DailyDoseItem.sortOrder) private var dailyDoseItems: [DailyDoseItem]
    @Query(sort: \FavoriteSubstance.createdAt, order: .reverse) private var favorites: [FavoriteSubstance]
    @Query private var quickLogDoses: [QuickLogDose]

    @AppStorage(QuickLogManager.fixedOrderDefaultsKey) private var quickLogFixedOrder = false

    @State private var customSubstanceStore = CustomSubstanceStore.shared

    @State private var searchText = ""
    @State private var showCustomForm = false
    @AppStorage("dailyDoseCategories") private var categoriesData = Data()

    @State private var pendingCustomPrefill: EntryPrefillPayload?

    /// Staged-but-uncommitted doses. Tapping a chip stages it here; the tray
    /// (rendered above the search bar) is the single commit surface for one
    /// dose or a whole stack — no separate multi-select mode.
    @State private var tray = DoseTrayModel()
    /// (substance|route) groups showing their full chip set instead of the
    /// first `chipLimit`.
    @State private var expandedGroups: Set<String> = []
    /// Substances whose PK badge has been expanded into the full advice card.
    @State private var expandedPK: Set<String> = []
    @State private var showDiscardConfirm = false

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
        let newCards: [SubstanceCard]
        let newHistoryNames: Set<String>

        let colorLookup = cachedColorLookup

        var groupMap: [String: SubstanceGroup] = [:]

        // Cards are built from the curated quick-log list (seeded once from
        // history, then maintained on log), not raw history — so a removed chip
        // stays gone and the order is the user's, not just recency.
        for dose in quickLogDoses {
            let nameLower = dose.substance.lowercased()
            let key = "\(nameLower)|\(dose.route.rawValue)"
            if var group = groupMap[key] {
                group.addChip(amount: dose.amount, unit: dose.unit, sortOrder: dose.sortOrder, lastUsedAt: dose.lastUsedAt)
                groupMap[key] = group
            } else {
                var group = SubstanceGroup(
                    substanceName: dose.substance,
                    route: dose.route,
                    colorHex: colorLookup[nameLower],
                    librarySubstance: SubstanceLibrary.lookupByNameOrAlias(nameLower),
                    latestTimestamp: dose.lastUsedAt,
                )
                group.addChip(amount: dose.amount, unit: dose.unit, sortOrder: dose.sortOrder, lastUsedAt: dose.lastUsedAt)
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
                latestTimestamp: sorted[0].latestTimestamp,
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

    private var filteredCustomSubstances: [Substance] {
        guard !searchText.isEmpty else { return [] }
        let query = searchText.lowercased()
        let libraryNames = Set(cachedLibraryResults.map { $0.name.lowercased() })
        return customSubstanceStore.all
            .filter { custom in
                let nameLower = custom.name.lowercased()
                let displayLower = custom.displayName?.lowercased() ?? ""
                // Match the canonical name OR the personal display name, so a
                // relabelled substance is findable by the name the user gave it.
                let matches = nameLower.contains(query) || (!displayLower.isEmpty && displayLower.contains(query))
                return matches
                    && !cachedHistoryNames.contains(nameLower)
                    && !libraryNames.contains(nameLower)
            }
            // Resolve through the library so an override of a shipped substance
            // carries its full dose/duration data (labelled with the personal
            // name); a net-new custom falls back to its own asSubstance.
            .compactMap { SubstanceLibrary.lookupByNameOrAlias($0.name) ?? $0.asSubstance }
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
                    if !dailyDoseItems.isEmpty, searchText.isEmpty {
                        medicationsButton
                    }

                    if cachedCards.isEmpty, searchText.isEmpty {
                        ContentUnavailableView(
                            "No Previous Substances",
                            systemImage: "magnifyingglass",
                            description: Text("Search for a substance to log your first entry."),
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
                VStack(spacing: 10) {
                    if !tray.isEmpty {
                        DoseTrayView(model: tray, tagSuggestions: sessionTagSuggestions, onCommit: commitTray)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    searchBar
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .navigationTitle("Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        if tray.isEmpty {
                            navigator.dismiss()
                        } else {
                            showDiscardConfirm = true
                        }
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
            .confirmationDialog("Discard staged doses?", isPresented: $showDiscardConfirm, titleVisibility: .visible) {
                Button("Discard Doses", role: .destructive) { navigator.dismiss() }
                Button("Keep Logging", role: .cancel) {}
            }
            .sheet(isPresented: $showCustomForm, onDismiss: onCustomFormDismiss) {
                CustomSubstanceFormView(initialName: searchText.trimmingCharacters(in: .whitespaces)) { saved in
                    pendingCustomPrefill = EntryPrefillPayload(
                        substance: saved.name,
                        route: saved.defaultRoute,
                        unit: saved.unit,
                    )
                }
            }
            .task {
                // Defer rebuild to next run loop so sheet presentation isn't blocked
                try? await Task.sleep(for: .milliseconds(50))
                QuickLogManager.seedIfNeeded(history: allEntries, context: modelContext)
                rebuildColorLookup()
                rebuildCards()
            }
            .task(id: quickLogDoses.count) {
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

    // MARK: - Session Tags

    /// Tags offered in the tray's tag panel: the user's previously-used tags
    /// (most frequent first) topped up with a few common suggestions, capped so
    /// the panel stays glanceable. The tray appends any active tag that falls
    /// past the cap.
    private var sessionTagSuggestions: [String] {
        var counts: [String: Int] = [:]
        for entry in allEntries {
            for tag in entry.tags {
                counts[tag, default: 0] += 1
            }
        }
        let used = counts.sorted { $0.value > $1.value }.map(\.key)
        let extras = TagExtractor.suggestions.filter { !used.contains($0) }
        return Array((used + extras).prefix(8))
    }

    // MARK: - Scroll Content

    private static let helpKeywords: Set<String> = [
        "help", "emergency", "overdose", "bad trip", "dying", "scared",
        "panic", "ambulance", "hospital", "not okay", "freaking out",
        "call 911", "911", "poisoning", "too much", "od", "can't breathe",
    ]

    private var isHelpSearch: Bool {
        guard !searchText.isEmpty else { return false }
        let query = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        return Self.helpKeywords.contains(where: { query.contains($0) })
    }

    @ViewBuilder
    private var scrollContentInner: some View {
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
                // Accent-tinted star vs. the neutral "Recent" clock gives the two
                // sections a clear at-a-glance distinction (icon colour carries the
                // meaning; the labels alone read identically).
                Label {
                    Text("Favorites")
                        .foregroundStyle(Theme.secondaryLabel)
                } icon: {
                    Image(systemName: "star.fill")
                        .foregroundStyle(Theme.accent)
                }
                .font(.footnote.weight(.semibold))
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
                if !favoriteCards.isEmpty, searchText.isEmpty {
                    Label("Recent", systemImage: "clock")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.secondaryLabel)
                        .textCase(.uppercase)
                }
            }
        } else if !searchText.isEmpty, cachedLibraryResults.isEmpty, filteredCustomSubstances.isEmpty, favoriteCards.isEmpty {
            ContentUnavailableView.search(text: searchText)
        }

        if !filteredCustomSubstances.isEmpty {
            Section {
                ForEach(filteredCustomSubstances) { substance in
                    customSubstanceRow(substance)
                }
            } header: {
                Label("Custom", systemImage: "flask")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryLabel)
                    .textCase(.uppercase)
                    .padding(.top, 8)
            }
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

        // Show the "Add as custom" CTA whenever the user has typed something
        // that doesn't *exactly* match an existing substance (case- and
        // whitespace-insensitive). Partial matches in the library still
        // appear above; the button lets the user add a new substance without
        // having to clear the search first.
        if !searchText.isEmpty, !exactMatchExists {
            createCustomButton
        }
    }

    /// True when `searchText` exactly matches the name of any substance
    /// already known to the app (library, custom store, or recently logged).
    private var exactMatchExists: Bool {
        let needle = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return false }
        if cachedLibraryResults.contains(where: { $0.name.lowercased() == needle }) { return true }
        if filteredCustomSubstances.contains(where: { $0.name.lowercased() == needle }) { return true }
        if cachedCards.contains(where: { $0.substanceName.lowercased() == needle }) { return true }
        return false
    }

    // MARK: - Medications

    private var medicationsButton: some View {
        let activeCategories = dailyDoseCategories.filter { cat in
            dailyDoseItems.contains { $0.category == cat }
        }
        let uncategorized = dailyDoseItems.filter(\.category.isEmpty)

        // Compact pill per category — the prescriptions flow is a *link*, not
        // content, so it shouldn't out-weigh the dose chips below it.
        return FlowLayout(spacing: 6) {
            ForEach(activeCategories, id: \.self) { cat in
                let catCount = dailyDoseItems.count(where: { $0.category == cat })
                medicationPill(
                    title: cat,
                    icon: iconForCategory(cat),
                    count: catCount,
                    category: cat,
                )
            }

            if !uncategorized.isEmpty {
                medicationPill(
                    title: activeCategories.isEmpty ? String(localized: "Prescriptions") : String(localized: "Other"),
                    icon: "pills",
                    count: uncategorized.count,
                    category: "",
                )
            }
        }
    }

    private func medicationPill(title: String, icon: String, count: Int, category: String) -> some View {
        Button {
            navigator.present(.dailyDoseLog(category: category))
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .imageScale(.small)
                Text(title)
                Text(verbatim: "· \(count)")
                    .opacity(0.7)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.accent.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func iconForCategory(_ category: String) -> String {
        switch category.lowercased() {
        case "morning": "sunrise"
        case "afternoon": "sun.max"
        case "noon", "midday": "sun.max"
        case "evening": "sunset"
        case "night", "bedtime": "moon"
        default: "tag"
        }
    }

    // MARK: - Substance Card

    private func substanceCard(_ card: SubstanceCard, isFavorite: Bool) -> some View {
        let color = card.colorHex.map { Color(hex: $0) } ?? .gray
        let lastEntry = mostRecentEntry(for: card.substanceName)
        let pkStatus = lastEntry.flatMap {
            DosePK.status(substanceName: card.substanceName, route: $0.route, lastDoseTimestamp: $0.timestamp)
        }
        let showsBadge = (pkStatus?.remainingPercent ?? 0) > 5

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                Text(customSubstanceStore.displayName(for: card.substanceName))
                    .font(.headline)
                // PK status as a glanceable badge instead of a two-line card —
                // tap to expand the full advice when it actually matters.
                if showsBadge, let pkStatus, let lastEntry {
                    Button {
                        withAnimation(.snappy) {
                            if expandedPK.contains(card.id) {
                                expandedPK.remove(card.id)
                            } else {
                                expandedPK.insert(card.id)
                            }
                        }
                    } label: {
                        DosePKBadge(remainingPercent: pkStatus.remainingPercent, lastDoseTimestamp: lastEntry.timestamp)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Active dose details")
                }
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
                .accessibilityLabel(isFavorite ? "Remove from Favorites" : "Add to Favorites")
            }

            if showsBadge, expandedPK.contains(card.id), let lastEntry {
                DoseSuggestionCard(
                    substanceName: card.substanceName,
                    lastDoseAmount: lastEntry.amount,
                    lastDoseTimestamp: lastEntry.timestamp,
                    unit: lastEntry.unit,
                    route: lastEntry.route,
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
            Text(group.route.localizedName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.secondaryLabel)
                .padding(.top, 4)

            doseChips(for: group, color: color)
        }
    }

    /// Chips visible per group before the "+N" overflow takes over. Eight
    /// near-duplicate amounts are noise; four cover the habitual doses.
    private static let chipLimit = 4

    private func doseChips(for group: SubstanceGroup, color: Color) -> some View {
        let allDoses = group.doses
        let isExpanded = expandedGroups.contains(group.id)
        let visible = isExpanded ? allDoses : Array(allDoses.prefix(Self.chipLimit))
        let hiddenCount = allDoses.count - visible.count

        return FlowLayout(spacing: 6) {
            ForEach(visible) { chip in
                doseChip(chip, group: group, color: color)
            }

            if hiddenCount > 0 {
                Button {
                    withAnimation(.snappy) { _ = expandedGroups.insert(group.id) }
                } label: {
                    Text(verbatim: "+\(hiddenCount)")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(.secondarySystemFill))
                        .foregroundStyle(Theme.secondaryLabel)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show \(hiddenCount) more doses")
            }

            Button {
                withAnimation(.snappy) {
                    tray.stageDraft(
                        substance: group.substanceName,
                        route: group.route,
                        unit: group.doses.first?.unit ?? "mg",
                        colorHex: group.colorHex,
                        librarySubstance: group.librarySubstance,
                    )
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.tint.opacity(0.12))
                    .foregroundStyle(.tint)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Custom dose")
        }
    }

    /// A single dose chip. Tapping stages it into the tray (re-tap increments
    /// the count); a filled background + count badge mirror the staged state.
    private func doseChip(_ chip: DoseChip, group: SubstanceGroup, color: Color) -> some View {
        let stagedCount = tray.quantity(substance: group.substanceName, route: group.route, amount: chip.amount, unit: chip.unit)
        return Text("\(chip.formattedAmount) \(chip.unit)")
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(stagedCount > 0 ? color : color.opacity(0.15))
            .foregroundStyle(stagedCount > 0 ? .white : color)
            .clipShape(Capsule())
            .contentShape(Capsule())
            .overlay(alignment: .topTrailing) {
                if stagedCount > 1 {
                    Text(verbatim: "\(stagedCount)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Theme.accent, in: Capsule())
                        .offset(x: 6, y: -7)
                }
            }
            .onTapGesture {
                withAnimation(.snappy) {
                    tray.stage(
                        substance: group.substanceName,
                        route: group.route,
                        amount: chip.amount,
                        unit: chip.unit,
                        colorHex: group.colorHex,
                        librarySubstance: group.librarySubstance,
                    )
                }
            }
            .contextMenu {
                Button {
                    moveChip(group: group, chip: chip, toFront: true)
                } label: { Label("Move to Front", systemImage: "arrow.up.to.line") }
                Button {
                    moveChip(group: group, chip: chip, toFront: false)
                } label: { Label("Move to Back", systemImage: "arrow.down.to.line") }
                Divider()
                Button(role: .destructive) {
                    removeChip(group: group, chip: chip)
                } label: { Label("Remove from Quick Log", systemImage: "trash") }
            }
    }

    // MARK: - Custom Substance

    private var createCustomButton: some View {
        Button {
            showCustomForm = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "flask.fill")
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Create \"\(searchText.trimmingCharacters(in: .whitespaces))\"")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text("Add as custom substance")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                }
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Theme.accent)
            }
            .padding(12)
            .background(Theme.accent.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func customSubstanceRow(_ substance: Substance) -> some View {
        Button {
            openLibrarySubstance(substance)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "flask")
                    .foregroundStyle(substance.category.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(substance.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text("\(substance.defaultRoute.displayName) \u{2014} \(substance.defaultUnit)")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                }
                Spacer()
                Text("Custom")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryLabel)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.secondaryLabel.opacity(0.12))
                    .clipShape(Capsule())
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            .padding(.vertical, 4)
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

    /// Commit every staged dose at the tray's shared time (or each item's
    /// override), stamping the tray-wide tags and location. One entry per
    /// staged item — a count of 2 × 150 mg commits as a single 300 mg entry,
    /// which is PK-equivalent under linear superposition.
    private func commitTray() {
        guard tray.isCommittable else { return }
        let sharedTime = tray.time.resolved

        for item in tray.staged {
            let entry = DoseEntry(
                substance: item.substanceName,
                amount: item.totalAmount,
                unit: item.unit,
                route: item.route,
                timestamp: item.timeOverride ?? sharedTime,
                notes: item.note.isEmpty ? nil : item.note,
                tags: Array(tray.tags),
                locationName: tray.location?.name,
                latitude: tray.location?.latitude,
                longitude: tray.location?.longitude,
            )
            modelContext.insert(entry)
            SessionService.assignSession(for: entry, in: modelContext)
            // Record the chip amount (not amount × count) so the curated list
            // floats the chip the user actually tapped, without minting a new
            // chip for every multiple.
            QuickLogManager.record(substance: item.substanceName, route: item.route, amount: item.amount, unit: item.unit, fixedOrder: quickLogFixedOrder, context: modelContext)

            // Schedule wellness notifications & check cumulative dose
            scheduleWellnessIfNeeded(entry: entry, substance: item.librarySubstance)

            // Auto-assign a stable palette colour for a brand-new substance up
            // front (deterministic hash, the same colour the graph already
            // uses), so the session and journal pick it up immediately.
            ensureColor(for: item.substanceName)

            // Add to the active session immediately, now that the colour exists.
            ActiveSessionManager.shared.addDose(
                entry: entry,
                substance: item.librarySubstance,
                colorHex: SubstancePalette.hex(for: item.substanceName, hexMap: Array(substanceColors).hexColorMap),
                allColors: Array(substanceColors),
            )
        }

        WidgetCenter.shared.reloadAllTimelines()

        // Quick-log completes a logging flow; clear the entire sheet chain.
        navigator.dismissAll()
    }

    // MARK: - Quick-log list curation

    /// The curated row backing a chip, matched by substance + route + measurement.
    private func quickLogDose(for group: SubstanceGroup, chip: DoseChip) -> QuickLogDose? {
        let key = QuickLogDose.makeKey(substance: group.substanceName, route: group.route, amount: chip.amount, unit: chip.unit)
        return quickLogDoses.first { $0.key == key }
    }

    private func removeChip(group: SubstanceGroup, chip: DoseChip) {
        guard let dose = quickLogDose(for: group, chip: chip) else { return }
        modelContext.delete(dose)
        try? modelContext.save()
        withAnimation(.snappy) { rebuildCards() }
    }

    /// Move a chip to the front (or back) of its (substance, route) group by
    /// rewriting its `sortOrder` just past the current min/max.
    private func moveChip(group: SubstanceGroup, chip: DoseChip, toFront: Bool) {
        guard let dose = quickLogDose(for: group, chip: chip) else { return }
        let key = "\(group.substanceName.lowercased())|\(group.route.rawValue)"
        let siblings = quickLogDoses.filter { key == "\($0.substance.lowercased())|\($0.route.rawValue)" }
        if toFront {
            dose.sortOrder = (siblings.map(\.sortOrder).min() ?? 0) - 1
        } else {
            dose.sortOrder = (siblings.map(\.sortOrder).max() ?? 0) + 1
        }
        try? modelContext.save()
        withAnimation(.snappy) { rebuildCards() }
    }

    /// Library / custom search results stage an amount-less draft that opens
    /// expanded in the tray with the amount field focused — the full entry
    /// form no longer participates in quick logging.
    private func openLibrarySubstance(_ substance: Substance) {
        withAnimation(.snappy) {
            tray.stageDraft(
                substance: substance.name,
                route: substance.defaultRoute,
                unit: substance.defaultUnit,
                colorHex: cachedColorLookup[substance.name.lowercased()],
                librarySubstance: substance,
            )
            searchText = ""
        }
    }

    private func onCustomFormDismiss() {
        guard let prefill = pendingCustomPrefill else { return }
        pendingCustomPrefill = nil
        searchText = ""
        withAnimation(.snappy) {
            tray.stageDraft(
                substance: prefill.substance,
                route: prefill.route,
                unit: prefill.unit,
                colorHex: cachedColorLookup[prefill.substance.lowercased()],
                librarySubstance: SubstanceLibrary.lookupByNameOrAlias(prefill.substance.lowercased()),
            )
        }
    }

    // MARK: - Helpers

    private func hasColor(for name: String) -> Bool {
        Array(substanceColors).hasColor(for: name)
    }

    /// Persist the substance's stable deterministic colour if it has none yet,
    /// so a first-time substance is coloured the moment it's logged — no extra
    /// picker step. Editable later from the entry detail's colour picker.
    private func ensureColor(for name: String) {
        guard !hasColor(for: name) else { return }
        modelContext.insert(SubstanceColor(substance: name, hexColor: PresetColor.deterministic(for: name).hex))
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
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
            recentStimHours: stimHours,
        )
        RampDownScheduler.schedulePhaseNotifications(
            substanceName: entry.substance,
            doseTime: entry.timestamp,
            duration: duration,
        )

        // Check cumulative dose
        let (total, shouldAlert) = RampDownScheduler.checkCumulativeDose(
            substanceName: entry.substance,
            newAmount: entry.amount,
            unit: entry.unit,
            route: entry.route,
            existingEntries: Array(allEntries),
        )
        if shouldAlert {
            RampDownScheduler.scheduleCumulativeDoseNotification(
                substanceName: entry.substance,
                totalAmount: total,
                unit: entry.unit,
                category: category,
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

    var id: String {
        substanceName.lowercased()
    }
}

struct SubstanceGroup: Identifiable {
    let id: String
    let substanceName: String
    let route: RouteOfAdministration
    let colorHex: String?
    let librarySubstance: Substance?
    var latestTimestamp: Date
    private var chipEntries: [(amount: Double, unit: String, sortOrder: Double)] = []

    var doses: [DoseChip] {
        chipEntries
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { DoseChip(amount: $0.amount, unit: $0.unit) }
    }

    init(substanceName: String, route: RouteOfAdministration, colorHex: String?, librarySubstance: Substance?, latestTimestamp: Date) {
        self.id = "\(substanceName.lowercased())|\(route.rawValue)"
        self.substanceName = substanceName
        self.route = route
        self.colorHex = colorHex
        self.librarySubstance = librarySubstance
        self.latestTimestamp = latestTimestamp
    }

    /// Add a curated chip (sorted by `sortOrder` for display). Tracks the most
    /// recent use so cards order by recency.
    mutating func addChip(amount: Double, unit: String, sortOrder: Double, lastUsedAt: Date) {
        chipEntries.append((amount: amount, unit: unit, sortOrder: sortOrder))
        if lastUsedAt > latestTimestamp {
            latestTimestamp = lastUsedAt
        }
    }
}

struct DoseChip: Identifiable {
    let amount: Double
    let unit: String

    var id: String {
        "\(amount)|\(unit)"
    }

    var formattedAmount: String {
        amount.doseFormatted
    }
}
