import SwiftData
import SwiftUI
import UIKit
import WidgetKit

struct QuickLogView: View {
    /// Stage this routine's items into the tray on open — the landing state
    /// for a routine-reminder notification tap (`piru://quicklog?routine=`).
    var prestagedRoutine: String?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.appNavigator) private var navigator

    @Query(sort: \DoseEntry.timestamp, order: .reverse, transaction: .init(animation: nil)) private var allEntries: [DoseEntry]
    @Query private var substanceColors: [SubstanceColor]
    @Query(sort: \DailyDoseItem.sortOrder) private var dailyDoseItems: [DailyDoseItem]
    @Query(sort: \DoseRoutine.sortOrder) private var routines: [DoseRoutine]
    @Query(sort: [SortDescriptor(\FavoriteSubstance.sortOrder), SortDescriptor(\FavoriteSubstance.createdAt, order: .reverse)]) private var favorites: [FavoriteSubstance]
    @Query private var quickLogDoses: [QuickLogDose]

    @AppStorage(QuickLogManager.fixedOrderDefaultsKey) private var quickLogFixedOrder = false

    @State private var customSubstanceStore = CustomSubstanceStore.shared

    @State private var searchText = ""
    @State private var showCustomForm = false
    @State private var showFavoritesEditor = false

    @State private var pendingCustomPrefill: EntryPrefillPayload?

    /// Staged-but-uncommitted doses. Tapping a chip stages it here; the dock
    /// (the screen's single bottom surface) is the commit surface for one dose
    /// or a whole stack.
    @State private var tray = DoseTrayModel()
    /// (substance|route) groups showing their full chip set instead of the
    /// single folded row.
    @State private var expandedGroups: Set<String> = []
    /// Substances whose PK badge has been expanded into the full advice card.
    @State private var expandedPK: Set<String> = []

    /// The dock is in search mode: field focused, results render inside the
    /// dock surface. Entered from the idle pill or the tray's "Add another…";
    /// exits automatically when focus ends with nothing typed.
    @State private var searchActive = false
    @FocusState private var searchFocused: Bool

    /// The floating-sheet inset: 8pt off the screen sides and bottom, like a
    /// native partial-detent sheet on iOS 26.
    private static let dockEdgeInset: CGFloat = 8

    /// The dock's corner radius, resolved by UIKit as concentric with the
    /// screen for the glass surface's exact frame (see
    /// ``ConcentricRadiusReader``). Starts at a sane floor until the first
    /// layout pass reports the real value.
    @State private var dockCornerRadius: CGFloat = 24

    @State private var cachedCards: [SubstanceCard] = []
    @State private var cachedFavoriteSet: Set<String> = []
    @State private var cachedFavoriteOrder: [String: Int] = [:]
    @State private var cachedHistoryNames: Set<String> = []
    @State private var cachedLibraryResults: [Substance] = []
    @State private var cachedColorLookup: [String: String] = [:]

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
        // `uniquingKeysWith` guards against two casings of one name colliding
        // when lowercased (the unique attribute is case-sensitive).
        cachedFavoriteOrder = Dictionary(
            favorites.enumerated().map { ($0.element.substance.lowercased(), $0.offset) },
            uniquingKeysWith: { first, _ in first },
        )
    }

    // MARK: - Favorites

    /// Favorites hold their user-given positions (the reorder sheet) instead
    /// of jumping around with logging recency like the Recent section.
    private var favoriteCards: [SubstanceCard] {
        cachedCards
            .filter { cachedFavoriteSet.contains($0.id) }
            .sorted { (cachedFavoriteOrder[$0.id] ?? .max) < (cachedFavoriteOrder[$1.id] ?? .max) }
    }

    private var nonFavoriteCards: [SubstanceCard] {
        cachedCards.filter { !cachedFavoriteSet.contains($0.id) }
    }

    private var favoriteLibrarySubstances: [Substance] {
        favorites
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

    /// Pre-`sortOrder` favorites are all 0 — stamp them with their current
    /// display order (newest first, matching the old query) exactly once, so
    /// reordering has distinct positions to work with.
    private func seedFavoriteOrderIfNeeded() {
        guard favorites.count > 1, favorites.allSatisfy({ $0.sortOrder == 0 }) else { return }
        for (index, favorite) in favorites.sorted(by: { $0.createdAt > $1.createdAt }).enumerated() {
            favorite.sortOrder = index
        }
    }

    private func toggleFavorite(_ name: String) {
        let lowered = name.lowercased()
        if let existing = favorites.first(where: { $0.substance.lowercased() == lowered }) {
            cachedFavoriteSet.remove(lowered)
            modelContext.delete(existing)
        } else {
            cachedFavoriteSet.insert(lowered)
            // Append at the end — a new favorite never displaces the order
            // the user has arranged.
            let nextOrder = (favorites.map(\.sortOrder).max() ?? -1) + 1
            modelContext.insert(FavoriteSubstance(substance: name, sortOrder: nextOrder))
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if cachedCards.isEmpty, dailyGroups.isEmpty {
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
                // Tapping anywhere outside the dock ends a search — the
                // standard iOS dismissal, no dimming, no Cancel button.
                .simultaneousGesture(
                    TapGesture().onEnded {
                        if searchActive { cancelSearch() }
                    },
                    isEnabled: searchActive,
                )
            }
            .safeAreaInset(edge: .bottom) { dock }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .navigationTitle("Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // With staged doses, close is a Menu — it gets the glass
                    // morph out of the button, unlike a confirmationDialog,
                    // which anchors to the toolbar as a stray popover.
                    if tray.isEmpty {
                        Button {
                            navigator.dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                    } else {
                        Menu {
                            Button(role: .destructive) {
                                navigator.dismiss()
                            } label: {
                                Label("Discard Doses", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "xmark")
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            navigator.present(.dailyDoseSettings)
                        } label: {
                            Label("Manage Routines…", systemImage: "pills")
                        }
                        Toggle(isOn: $quickLogFixedOrder) {
                            Label("Fixed Order", systemImage: "pin")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
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
            .sheet(isPresented: $showFavoritesEditor) {
                FavoritesReorderView()
            }
            .task {
                // Defer rebuild to next run loop so sheet presentation isn't blocked
                try? await Task.sleep(for: .milliseconds(50))
                QuickLogManager.seedIfNeeded(history: allEntries, context: modelContext)
                RoutineMigrator.seedIfNeeded(context: modelContext)
                seedFavoriteOrderIfNeeded()
                rebuildColorLookup()
                rebuildCards()
                if let prestagedRoutine {
                    stageRoutine(named: prestagedRoutine)
                }
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
            // Keyed on names, not count — a reorder changes order only.
            .onChange(of: favorites.map(\.substance)) { rebuildFavorites() }
            .onChange(of: searchFocused) {
                if !searchFocused, searchText.isEmpty {
                    withAnimation(.snappy) { searchActive = false }
                }
            }
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
        // Swipe-down dismissal is off: scrolling the list and dragging in the
        // dock pass too close to the sheet's drag region, and an accidental
        // pull-down silently discards staged doses. Closing is the ✕ button,
        // which routes through the discard menu when something is staged.
        .interactiveDismissDisabled()
    }

    // MARK: - Dock

    /// Which face the dock is showing. One surface, three sizes — search pill
    /// when idle, the tray once something is staged, and in-dock search when
    /// the field is active. Never two materials at once.
    private enum DockState {
        case idle
        case search
        case tray
    }

    private var dockState: DockState {
        if searchActive { .search } else if !tray.isEmpty { .tray } else { .idle }
    }

    /// The screen's single bottom surface, styled like a native detented
    /// sheet — full-width, top-rounded, glass bleeding under the home
    /// indicator — but driven by our own state machine: native child sheets
    /// can't morph between faces and never grant programmatic keyboard focus.
    private var dock: some View {
        Group {
            switch dockState {
            case .idle: idleDock
            case .search: searchDock
            case .tray: trayDock
            }
        }
        .frame(maxWidth: .infinity)
        .background {
            // The glass floats: it runs below the content (which respects
            // the safe area) to 8pt above the physical screen bottom. The
            // corner radius is UIKit-resolved as concentric with the screen
            // corners (54pt = display radius − 8pt inset on a Pro Max,
            // capsule-clamped on the short idle face) — SwiftUI's
            // ConcentricRectangle resolves against the presenting sheet's
            // container shape instead and lands on the wrong radius.
            Color.clear
                .glassEffect(.regular, in: .rect(cornerRadius: dockCornerRadius, style: .continuous))
                .overlay {
                    ConcentricRadiusReader { radius in
                        guard radius > 0, abs(radius - dockCornerRadius) > 0.5 else { return }
                        withAnimation(.snappy) { dockCornerRadius = radius }
                    }
                }
                .padding(.bottom, Self.dockEdgeInset)
                .ignoresSafeArea(.container, edges: .bottom)
        }
        .padding(.horizontal, Self.dockEdgeInset)
        .sensoryFeedback(.impact(weight: .light), trigger: tray.stageTick)
        .sensoryFeedback(.increase, trigger: tray.incrementTick)
    }

    /// The field's visual — a filled capsule like a native sheet's search
    /// bar (the glass surface behind it is the sheet, not the field).
    private func fieldCapsule(@ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.secondaryLabel)
            content()
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemFill), in: Capsule())
    }

    private var idleDock: some View {
        Button(action: activateSearch) {
            fieldCapsule {
                Text("Search substances...")
                    .foregroundStyle(Theme.secondaryLabel)
                Spacer(minLength: 0)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var trayDock: some View {
        DoseTrayView(
            model: tray,
            tagSuggestions: sessionTagSuggestions,
            onAddMore: activateSearch,
            onCommit: commitTray,
        )
    }

    /// Results stack *above* the field — the field stays pinned at the bottom
    /// of the dock while suggestions grow upward.
    private var searchDock: some View {
        VStack(spacing: 0) {
            if isHelpSearch {
                quickLogHelpBanner
                    .padding([.horizontal, .top], 10)
            } else if !searchText.isEmpty {
                searchResultsList
            }

            fieldCapsule {
                TextField("Search substances...", text: $searchText)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($searchFocused)
                    .submitLabel(.search)
                if !tray.isEmpty {
                    stagedCountPill
                } else if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
        }
        .padding(.top, 4)
        .onAppear { searchFocused = true }
    }

    /// Returns to the tray without losing the staged stack.
    private var stagedCountPill: some View {
        Button(action: cancelSearch) {
            Text(verbatim: "\(tray.staged.count)")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Theme.accent, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back to staged doses")
    }

    private func activateSearch() {
        withAnimation(.snappy) { searchActive = true }
    }

    private func cancelSearch() {
        searchFocused = false
        withAnimation(.snappy) {
            searchActive = false
            searchText = ""
        }
    }

    // MARK: - In-dock search results

    private enum DockResult: Identifiable {
        case recent(SubstanceCard)
        case library(Substance)
        case custom(Substance)

        var id: String {
            switch self {
            case let .recent(card): "recent|\(card.id)"
            case let .library(substance): "library|\(substance.name.lowercased())"
            case let .custom(substance): "custom|\(substance.name.lowercased())"
            }
        }
    }

    private var dockResults: [DockResult] {
        let query = searchText.lowercased()
        guard !query.isEmpty else { return [] }
        var results: [DockResult] = cachedCards
            .filter { $0.id.contains(query) }
            .prefix(2)
            .map { .recent($0) }
        results += cachedLibraryResults.prefix(3).map { .library($0) }
        results += filteredCustomSubstances.prefix(1).map { .custom($0) }
        return Array(results.prefix(4))
    }

    /// Best match sits at the bottom, adjacent to the field; the create CTA
    /// is farthest away (the list reads upward from the field).
    private var searchResultsList: some View {
        VStack(spacing: 0) {
            if !exactMatchExists {
                createCustomRow
                Divider().padding(.leading, 16)
            }
            ForEach(dockResults.reversed()) { result in
                dockResultRow(result)
                Divider().padding(.leading, 16)
            }
        }
        .padding(.top, 6)
    }

    @ViewBuilder
    private func dockResultRow(_ result: DockResult) -> some View {
        switch result {
        case let .recent(card):
            resultRow(
                name: customSubstanceStore.displayName(for: card.substanceName),
                source: String(localized: "Recent"),
                tint: card.colorHex.map { Color(hex: $0) } ?? .gray,
                detail: card.routes.first?.librarySubstance.flatMap(substanceDetail)
                    ?? card.routes.first.map { String(localized: $0.route.localizedName) },
                description: card.routes.first?.librarySubstance.flatMap(substanceDescription),
            ) {
                stageFromCard(card)
            }
        case let .library(substance):
            resultRow(
                name: substance.name,
                source: String(localized: "Library"),
                tint: substance.category.color,
                detail: substanceDetail(substance),
                description: substanceDescription(substance),
            ) {
                openLibrarySubstance(substance)
            }
        case let .custom(substance):
            resultRow(
                name: substance.name,
                source: String(localized: "Custom"),
                tint: substance.category.color,
                detail: substanceDetail(substance),
                description: substanceDescription(substance),
            ) {
                openLibrarySubstance(substance)
            }
        }
    }

    /// "Psychedelic · Common 75–150 µg" — class plus the default route's
    /// common-dose band.
    private func substanceDetail(_ substance: Substance) -> String? {
        var parts = [String(localized: substance.category.displayName)]
        if let routeInfo = substance.routes.first(where: { $0.route == substance.defaultRoute }),
           let common = routeInfo.doses.common {
            let low = common.lowerBound.doseFormatted
            let high = common.upperBound.doseFormatted
            parts.append(String(localized: "Common \(low)–\(high) \(routeInfo.unit)"))
        }
        return parts.joined(separator: " · ")
    }

    private func substanceDescription(_ substance: Substance) -> String? {
        substance.mechanismOfAction?.summary
    }

    /// Leading chevron (mirroring the trailing source tag for symmetry),
    /// tinted with the substance/category colour.
    private func resultRow(
        name: String,
        source: String,
        tint: Color,
        detail: String?,
        description: String?,
        action: @escaping () -> Void,
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(name)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(source)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryLabel)
                            .lineLimit(1)
                    }
                    if let description {
                        Text(description)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var createCustomRow: some View {
        Button {
            showCustomForm = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "flask.fill")
                    .imageScale(.small)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 16)
                Text("Create \"\(searchText.trimmingCharacters(in: .whitespaces))\"")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// A recent-substance search hit stages a draft from its most recent
    /// route group, same as the card's ⋯ chip.
    private func stageFromCard(_ card: SubstanceCard) {
        guard let group = card.routes.first else { return }
        searchFocused = false
        withAnimation(.snappy) {
            tray.stageDraft(
                substance: group.substanceName,
                route: group.route,
                unit: group.doses.first?.unit ?? "mg",
                colorHex: group.colorHex,
                librarySubstance: group.librarySubstance,
            )
            searchActive = false
            searchText = ""
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
        if !dailyGroups.isEmpty {
            dailySection
        }

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
                HStack {
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
                    Spacer()
                    Button("Edit") {
                        showFavoritesEditor = true
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .buttonStyle(.plain)
                }
            }
        }

        if !nonFavoriteCards.isEmpty {
            Section {
                ForEach(nonFavoriteCards) { card in
                    substanceCard(card, isFavorite: false)
                        .id("\(card.id)_recent")
                }
            } header: {
                if !favoriteCards.isEmpty {
                    Label("Recent", systemImage: "clock")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.secondaryLabel)
                        .textCase(.uppercase)
                }
            }
        }
    }

    // MARK: - Daily routine

    /// "Prescriptions" reconceived: pre-set daily drugs (meds, supplements,
    /// anything routine) as first-class cards whose item-chips stage into the
    /// same tray as everything else.
    private struct DailyCategoryGroup: Identifiable {
        let id: String
        let title: String
        let icon: String
        let items: [DailyDoseItem]
        let remaining: [DailyDoseItem]
    }

    private var dailyGroups: [DailyCategoryGroup] {
        guard !dailyDoseItems.isEmpty else { return [] }
        let loggedToday = substancesLoggedToday

        func remaining(in items: [DailyDoseItem]) -> [DailyDoseItem] {
            items.filter { !loggedToday.contains($0.substance.lowercased()) }
        }

        // Routines flow through the day: timed ones first by clock,
        // untimed after in the user's arranged order.
        let ordered = routines.sorted {
            ($0.timeMinutes ?? .max, $0.sortOrder) < ($1.timeMinutes ?? .max, $1.sortOrder)
        }

        var groups: [DailyCategoryGroup] = []
        var claimed: Set<String> = []
        for routine in ordered {
            claimed.insert(routine.name)
            let items = dailyDoseItems.filter { $0.category == routine.name }
            guard !items.isEmpty else { continue }
            groups.append(DailyCategoryGroup(
                id: routine.name,
                title: routine.name,
                icon: RoutineIcon.symbol(for: routine.name),
                items: items,
                remaining: remaining(in: items),
            ))
        }

        // Items whose category has no routine row (first launch before
        // seeding, or an import) still get a pill so nothing is unreachable.
        let orphans = dailyDoseItems.filter { !claimed.contains($0.category) }
        if !orphans.isEmpty {
            for (category, items) in Dictionary(grouping: orphans, by: \.category).sorted(by: { $0.key < $1.key }) {
                groups.append(DailyCategoryGroup(
                    id: category.isEmpty ? "·uncategorized" : category,
                    title: category.isEmpty ? String(localized: "Routine") : category,
                    icon: RoutineIcon.symbol(for: category),
                    items: items,
                    remaining: remaining(in: items),
                ))
            }
        }
        return groups
    }

    /// Substance-level "taken today" check. Amounts aren't matched so a
    /// double-dose commit (2 × one pill) still marks the routine item done.
    private var substancesLoggedToday: Set<String> {
        var names: Set<String> = []
        for entry in allEntries {
            // allEntries is sorted newest-first; stop at yesterday.
            guard Calendar.current.isDateInToday(entry.timestamp) else { break }
            names.insert(entry.substance.lowercased())
        }
        return names
    }

    private var dailySection: some View {
        Section {
            FlowLayout(spacing: 8) {
                ForEach(dailyGroups) { group in
                    routinePill(group)
                }
            }
        } header: {
            Label {
                Text("Routines")
                    .foregroundStyle(Theme.secondaryLabel)
            } icon: {
                Image(systemName: "repeat")
                    .foregroundStyle(Theme.accent)
            }
            .font(.footnote.weight(.semibold))
            .textCase(.uppercase)
        }
    }

    /// A routine is one pill — a *shortcut* that stages its whole set into
    /// the tray in one tap (the eight-supplements use case), idempotent for
    /// anything already staged. The checkmark is informational ("all of these
    /// were logged today"); the pill stays tappable for re-logs. Long-press
    /// to edit the routine itself.
    private func routinePill(_ group: DailyCategoryGroup) -> some View {
        let done = group.remaining.isEmpty
        let allStaged = group.items.allSatisfy { stagedQuantity($0) > 0 }
        return Button {
            withAnimation(.snappy) {
                for item in group.items where stagedQuantity(item) == 0 {
                    stageDailyItem(item)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: done ? "checkmark" : group.icon)
                    .imageScale(.small)
                Text(group.title)
                Text(verbatim: "· \(group.items.count)")
                    .opacity(0.75)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                allStaged
                    ? AnyShapeStyle(Theme.accent)
                    : done ? AnyShapeStyle(Color.green.opacity(0.12)) : AnyShapeStyle(Theme.accent.opacity(0.12)),
                in: Capsule(),
            )
            .foregroundStyle(
                allStaged
                    ? AnyShapeStyle(.white)
                    : done ? AnyShapeStyle(Color.green) : AnyShapeStyle(Theme.accent),
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                navigator.present(.dailyDoseSettings)
            } label: {
                Label("Edit Routine…", systemImage: "pencil")
            }
        }
    }

    private func stagedQuantity(_ item: DailyDoseItem) -> Int {
        tray.quantity(substance: item.substance, route: item.route, amount: item.amount, unit: item.unit)
    }

    /// Stage every item of the named routine, exactly as if its pill were
    /// tapped (idempotent) — the landing state for a reminder-notification tap.
    private func stageRoutine(named name: String) {
        let items = dailyDoseItems.filter { $0.category == name }
        guard !items.isEmpty else { return }
        withAnimation(.snappy) {
            for item in items where stagedQuantity(item) == 0 {
                stageDailyItem(item)
            }
        }
    }

    private func stageDailyItem(_ item: DailyDoseItem) {
        tray.stage(
            substance: item.substance,
            route: item.route,
            amount: item.amount,
            unit: item.unit,
            colorHex: cachedColorLookup[item.substance.lowercased()],
            librarySubstance: SubstanceLibrary.lookupByNameOrAlias(item.substance.lowercased()),
            isFromDailySet: true,
            isBackgroundMed: item.isBackgroundMed,
        )
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
                // tap to expand the full advice when it actually matters. The
                // badge hides while the card is open so the same fact never
                // shows twice; tapping the card collapses it back.
                if showsBadge, let pkStatus, let lastEntry, !expandedPK.contains(card.id) {
                    Button {
                        withAnimation(.snappy) { _ = expandedPK.insert(card.id) }
                    } label: {
                        DosePKBadge(
                            remainingPercent: pkStatus.remainingPercent,
                            lastDoseAmount: lastEntry.amount,
                            unit: lastEntry.unit,
                            waitMinutes: pkStatus.waitMinutes,
                            lastDoseTimestamp: lastEntry.timestamp,
                        )
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
                Button {
                    withAnimation(.snappy) { _ = expandedPK.remove(card.id) }
                } label: {
                    DoseSuggestionCard(
                        substanceName: card.substanceName,
                        lastDoseAmount: lastEntry.amount,
                        lastDoseTimestamp: lastEntry.timestamp,
                        unit: lastEntry.unit,
                        route: lastEntry.route,
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Collapse")
            }

            ForEach(card.routes) { group in
                routeSection(group, color: color)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20).fill(Theme.cardBackground))
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

    private func doseChips(for group: SubstanceGroup, color: Color) -> some View {
        OneRowChips(
            items: group.doses,
            isExpanded: expandedGroups.contains(group.id),
            onExpand: {
                withAnimation(.snappy) { _ = expandedGroups.insert(group.id) }
            },
        ) { chip in
            doseChip(chip, group: group, color: color)
        } trailing: {
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

    /// A single dose chip. Tapping stages it into the tray; re-tap increments
    /// the count ("took two pills" — one bigger entry, never two). A filled
    /// background + count badge mirror the staged state.
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
                    chipCountBadge(stagedCount)
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

    private func chipCountBadge(_ count: Int) -> some View {
        Text(verbatim: "\(count)")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Theme.accent, in: Capsule())
            .offset(x: 6, y: -7)
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
            .padding(14)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    /// Commit every staged dose at the tray's shared time, stamping the
    /// tray-wide tags and location. One entry per staged item — a count of
    /// 2 × 150 mg commits as a single 300 mg entry, which is PK-equivalent
    /// under linear superposition.
    private func commitTray() {
        guard tray.isCommittable else { return }
        let sharedTime = tray.time.resolved

        for item in tray.staged {
            let entry = DoseEntry(
                substance: item.substanceName,
                amount: item.totalAmount,
                unit: item.unit,
                route: item.route,
                timestamp: sharedTime,
                notes: item.note.isEmpty ? nil : item.note,
                tags: Array(tray.tags),
                isBackgroundMed: item.isBackgroundMed,
                locationName: tray.location?.name,
                latitude: tray.location?.latitude,
                longitude: tray.location?.longitude,
            )
            modelContext.insert(entry)
            SessionService.assignSession(for: entry, in: modelContext)
            // Record each component's chip amount (not the merged total) so
            // the curated list floats the chips the user actually tapped,
            // without minting a chip for every sum. Daily routine items keep
            // their own surface and don't mint quick-log chips.
            if !item.isFromDailySet {
                for component in item.components {
                    QuickLogManager.record(substance: item.substanceName, route: item.route, amount: component.amount, unit: item.unit, fixedOrder: quickLogFixedOrder, context: modelContext)
                }
            }

            // Schedule wellness notifications & check cumulative dose
            DoseNotificationManager.doseLogged(entry: entry, recentEntries: Array(allEntries))

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

        // The commit is the flow's one success moment — the only notification
        // haptic in quick logging. Played directly because the sheet tears
        // down before a `sensoryFeedback` trigger would fire.
        UINotificationFeedbackGenerator().notificationOccurred(.success)

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
        searchFocused = false
        withAnimation(.snappy) {
            tray.stageDraft(
                substance: substance.name,
                route: substance.defaultRoute,
                unit: substance.defaultUnit,
                colorHex: cachedColorLookup[substance.name.lowercased()],
                librarySubstance: substance,
            )
            searchActive = false
            searchText = ""
        }
    }

    private func onCustomFormDismiss() {
        guard let prefill = pendingCustomPrefill else { return }
        pendingCustomPrefill = nil
        searchFocused = false
        withAnimation(.snappy) {
            tray.stageDraft(
                substance: prefill.substance,
                route: prefill.route,
                unit: prefill.unit,
                colorHex: cachedColorLookup[prefill.substance.lowercased()],
                librarySubstance: SubstanceLibrary.lookupByNameOrAlias(prefill.substance.lowercased()),
            )
            searchActive = false
            searchText = ""
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
}

// MARK: - One-Row Chip Fold

/// Lays out chips on exactly one row, folding whatever doesn't fit into a
/// width-aware "+N" chip — the row never wraps. Tapping "+N" is a disclosure:
/// the row expands in place to a wrapping layout showing every chip.
///
/// Implemented with `ViewThatFits`: candidate rows from "all chips" down to
/// "one chip + fold" are proposed in order and the widest that fits wins.
private struct OneRowChips<Item: Identifiable, ChipView: View, TrailingView: View>: View {
    let items: [Item]
    let isExpanded: Bool
    let onExpand: () -> Void
    @ViewBuilder let chip: (Item) -> ChipView
    @ViewBuilder let trailing: () -> TrailingView

    var body: some View {
        if isExpanded || items.count <= 1 {
            FlowLayout(spacing: 6) {
                ForEach(items) { item in
                    chip(item)
                }
                trailing()
            }
        } else {
            ViewThatFits(in: .horizontal) {
                ForEach(Array(stride(from: items.count, through: 1, by: -1)), id: \.self) { visibleCount in
                    candidateRow(visibleCount: visibleCount)
                }
            }
        }
    }

    private func candidateRow(visibleCount: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(items.prefix(visibleCount)) { item in
                chip(item)
                    // Chips must not compress, otherwise every candidate
                    // "fits" and the widest always wins. The last candidate
                    // stays compressible as the give-up fallback.
                    .fixedSize(horizontal: visibleCount > 1, vertical: false)
            }
            if visibleCount < items.count {
                Button(action: onExpand) {
                    Text(verbatim: "+\(items.count - visibleCount)")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(.secondarySystemFill))
                        .foregroundStyle(Theme.secondaryLabel)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .fixedSize()
                .accessibilityLabel("Show \(items.count - visibleCount) more doses")
            }
            trailing()
                .fixedSize()
        }
    }
}

// MARK: - Favorites Reorder

/// Native drag-handle reorder for favorites, presented from the Favorites
/// section header's Edit button. Always in edit mode — drag to reorder,
/// swipe/minus to unfavorite. Local sheet, so `@Environment(\.dismiss)`
/// (NOT `navigator.dismiss()`, which would pop the whole Log sheet).
private struct FavoritesReorderView: View {
    @Query(sort: [SortDescriptor(\FavoriteSubstance.sortOrder), SortDescriptor(\FavoriteSubstance.createdAt, order: .reverse)]) private var favorites: [FavoriteSubstance]
    @Query private var substanceColors: [SubstanceColor]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var customStore = CustomSubstanceStore.shared

    var body: some View {
        NavigationStack {
            List {
                ForEach(favorites) { favorite in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(color(for: favorite.substance))
                            .frame(width: 10, height: 10)
                        Text(customStore.displayName(for: favorite.substance))
                    }
                }
                .onMove(perform: move)
                .onDelete(perform: delete)
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Favorites")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func color(for substance: String) -> Color {
        Array(substanceColors).hexColorMap[substance.lowercased()]
            .map { Color(hex: $0) } ?? .gray
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ordered = favorites
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, favorite) in ordered.enumerated() {
            favorite.sortOrder = index
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(favorites[index])
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

/// Reports the corner radius UIKit resolves as *concentric with the screen*
/// for this view's frame, via the public iOS 26 corner-configuration API.
///
/// SwiftUI's `ConcentricRectangle` resolves against the nearest SwiftUI
/// container shape — inside a sheet that's the presentation's shape, not the
/// device screen, so a bottom-floating surface gets the wrong radius. UIKit's
/// `containerConcentric` resolution walks the real view/window hierarchy, so
/// it derives the radius from the display corners. Overlay this on the glass
/// surface (same frame) and feed the reported value back as a fixed radius.
private struct ConcentricRadiusReader: UIViewRepresentable {
    var onResolve: (CGFloat) -> Void

    func makeUIView(context _: Context) -> ResolverView {
        let view = ResolverView()
        view.onResolve = onResolve
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.cornerConfiguration = .corners(radius: .containerConcentric(minimum: 0))
        return view
    }

    func updateUIView(_ uiView: ResolverView, context _: Context) {
        uiView.onResolve = onResolve
    }

    final class ResolverView: UIView {
        var onResolve: ((CGFloat) -> Void)?

        override func layoutSubviews() {
            super.layoutSubviews()
            let radius = effectiveRadius(corner: .bottomLeft)
            // Defer out of the layout pass before touching SwiftUI state.
            DispatchQueue.main.async { [weak self] in
                self?.onResolve?(radius)
            }
        }
    }
}
