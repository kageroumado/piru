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

    /// The dock is in search mode: field focused, results render inside the
    /// dock surface. Entered from the idle pill or the tray's "Add another…";
    /// exits automatically when focus ends with nothing typed.
    @State private var searchActive = false
    @FocusState private var searchFocused: Bool

    /// Gates the empty-state placeholder: it must not show until the first
    /// rebuild has actually run, or the sheet briefly flashes "No Previous
    /// Substances" on every open before the (now warm-cache, fast) caches fill.
    @State private var hasLoaded = false

    @State private var cachedCards: [SubstanceCard] = []
    @State private var cachedFavoriteSet: Set<String> = []
    @State private var cachedFavoriteOrder: [String: Int] = [:]
    @State private var cachedHistoryNames: Set<String> = []
    @State private var cachedLibraryResults: [Substance] = []
    @State private var cachedColorLookup: [String: String] = [:]

    /// Everything derived from the (large) `allEntries` query is computed once
    /// per change and cached — otherwise each of these scanned the full dose
    /// history on *every* `body` evaluation, which is what made tapping a chip
    /// (a body re-eval) and opening the sheet cost hundreds of ms in the trace.
    /// Lowercased substance names logged today — drives the routine "done" check.
    @State private var cachedLoggedToday: Set<String> = []
    /// Most-recent entry per lowercased substance name — feeds each card's PK badge.
    @State private var cachedMostRecent: [String: DoseEntry] = [:]
    /// Distinct dose locations, most recent first — the tray's location panel.
    @State private var cachedRecentLocations: [PickedLocation] = []
    /// Tag suggestions (used-most-first + common extras) — the tray's tag panel.
    @State private var cachedTagSuggestions: [String] = []

    /// Favorite/recent card partitions and the favorite-only library rows.
    /// Cached off the body so the per-eval filter/sort + library lookups (read
    /// twice — toolbar *and* scroll content) don't run on every chip tap.
    @State private var cachedFavoriteCards: [SubstanceCard] = []
    @State private var cachedNonFavoriteCards: [SubstanceCard] = []
    @State private var cachedFavoriteLibrarySubstances: [Substance] = []

    /// Routine pills — the sort+filter+grouping that builds them ran on every
    /// body eval (≈18 ms in the profiler); cached off the body and rebuilt only
    /// when the routines, daily items, or today's log change.
    @State private var cachedDailyGroups: [DailyCategoryGroup] = []

    // MARK: - Grouping

    private func rebuildColorLookup() {
        cachedColorLookup = Array(substanceColors).hexColorMap
    }

    /// Cheap content fingerprint of the dose history, used as the rebuild
    /// trigger. `allEntries.count` alone misses an in-place edit (re-dating a
    /// dose, renaming its substance, retagging): the count is unchanged, so
    /// the caches would go stale. Hashing the fields the derived caches
    /// depend on closes that gap.
    private var entriesSignature: Int {
        var hasher = Hasher()
        for entry in allEntries {
            hasher.combine(entry.persistentModelID)
            hasher.combine(entry.timestamp)
            hasher.combine(entry.substance)
            hasher.combine(entry.tags)
            hasher.combine(entry.locationName)
        }
        return hasher.finalize()
    }

    /// Recompute everything derived from `allEntries` in a single pass. Called
    /// on open and whenever the history changes (a logged dose) — never from
    /// `body`, so chip taps and sheet presentation no longer re-scan the whole
    /// dose history. `allEntries` is newest-first, which every consumer relies
    /// on (today's slice stops at the first non-today row; most-recent wins).
    private func rebuildEntryDerived() {
        var loggedToday: Set<String> = []
        var mostRecent: [String: DoseEntry] = [:]
        var seenLocations = Set<String>()
        var locations: [PickedLocation] = []
        var tagCounts: [String: Int] = [:]
        var stillToday = true

        for entry in allEntries {
            let lower = entry.substance.lowercased()
            if mostRecent[lower] == nil { mostRecent[lower] = entry }
            if stillToday, Calendar.current.isDateInToday(entry.timestamp) {
                loggedToday.insert(lower)
            } else {
                stillToday = false
            }
            for tag in entry.tags {
                tagCounts[tag, default: 0] += 1
            }
            if locations.count < 10,
               let name = entry.locationName, !name.isEmpty,
               let latitude = entry.latitude, let longitude = entry.longitude,
               seenLocations.insert(name).inserted {
                locations.append(PickedLocation(name: name, latitude: latitude, longitude: longitude))
            }
        }

        let used = tagCounts.sorted { $0.value > $1.value }.map(\.key)
        let extras = TagExtractor.suggestions.filter { !used.contains($0) }

        cachedLoggedToday = loggedToday
        cachedMostRecent = mostRecent
        cachedRecentLocations = locations
        cachedTagSuggestions = Array((used + extras).prefix(8))
        // `makeDailyGroups` reads `cachedLoggedToday` (the "done" check), so it
        // must rebuild after that's assigned above.
        cachedDailyGroups = makeDailyGroups()
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
                    // Batch-cache lookup (class/routes/doses/salts/durations) —
                    // all a card needs — instead of the heavy per-substance SQL
                    // resolve, which cold-stalled the first open. Same path the
                    // journal uses; pre-warmed via `ensureAllLoaded()` on open.
                    librarySubstance: SubstanceLibrary.timelineLookup(nameLower),
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

        // Favorites hold their user-given positions (the reorder sheet) instead
        // of jumping around with logging recency like the Recent section.
        cachedFavoriteCards = cachedCards
            .filter { cachedFavoriteSet.contains($0.id) }
            .sorted { (cachedFavoriteOrder[$0.id] ?? .max) < (cachedFavoriteOrder[$1.id] ?? .max) }
        cachedNonFavoriteCards = cachedCards.filter { !cachedFavoriteSet.contains($0.id) }
        cachedFavoriteLibrarySubstances = favorites
            .filter { !cachedHistoryNames.contains($0.substance.lowercased()) }
            .compactMap { SubstanceLibrary.timelineLookup($0.substance.lowercased()) }
    }

    // MARK: - Favorites

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
            .compactMap { SubstanceLibrary.timelineLookup($0.name) ?? $0.asSubstance }
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
        if FavoriteService.toggle(name, in: modelContext) {
            cachedFavoriteSet.insert(lowered)
        } else {
            cachedFavoriteSet.remove(lowered)
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if !hasLoaded {
                        // Loading: render nothing (the dock stays put) rather than
                        // the empty-state placeholder — the caches fill within a
                        // frame or two off the warm batch cache, so this avoids the
                        // jarring "No Previous Substances" flash on open.
                        EmptyView()
                    } else if cachedCards.isEmpty, cachedDailyGroups.isEmpty {
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
                // Edit (reorder favorites) lives in the nav bar as an icon,
                // per convention — not as a text button in a section header.
                if !cachedFavoriteCards.isEmpty || !cachedFavoriteLibrarySubstances.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showFavoritesEditor = true
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .accessibilityLabel("Edit Favorites")
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
                // Wait for the launch prewarm so the card lookups below land on
                // the warm batch cache instead of cold per-substance SQL (returns
                // immediately if already loaded; the rebuild is then cheap enough
                // not to block the present animation).
                await SubstanceStore.shared.ensureAllLoaded()
                QuickLogManager.seedIfNeeded(history: allEntries, context: modelContext)
                RoutineMigrator.seedIfNeeded(context: modelContext)
                seedFavoriteOrderIfNeeded()
                rebuildColorLookup()
                rebuildEntryDerived()
                rebuildCards()
                hasLoaded = true
                if let prestagedRoutine {
                    stageRoutine(named: prestagedRoutine)
                }
            }
            .task(id: quickLogDoses.count) {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                rebuildCards()
            }
            // A logged dose (here or elsewhere) changes the history-derived
            // caches — refresh them off the body, keyed on a content signature
            // so in-place edits invalidate too.
            .onChange(of: entriesSignature) {
                rebuildEntryDerived()
            }
            .onChange(of: substanceColors.count) {
                rebuildColorLookup()
                rebuildCards()
            }
            // Keyed on names, not count — a reorder changes order only.
            .onChange(of: favorites.map(\.substance)) { rebuildFavorites() }
            // Routine pills depend on the routine rows + daily items; refresh
            // the cache when either is edited (the Manage Routines sheet).
            .onChange(of: routineSignature) { cachedDailyGroups = makeDailyGroups() }
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

    /// The dock is showing nothing but the search field — idle, or search
    /// with nothing typed yet. The field *itself* is then the glass element
    /// (a floating capsule, like Maps' collapsed bar); content morphs it
    /// into the full surface. A bare field inside the big surface would
    /// force a corner radius taller than the face and distort the shape.
    private var dockIsBareField: Bool {
        switch dockState {
        case .idle: true
        case .search: searchText.isEmpty
        case .tray: false
        }
    }

    private var dock: some View {
        GlassDock(isBare: dockIsBareField) {
            switch dockState {
            case .idle: idleDock
            case .search: searchDock
            case .tray: trayDock
            }
        }
        // Every result-set change resizes the surface — animate it, same as
        // the bare⇄full flip GlassDock already animates.
        .animation(.snappy, value: dockResults.map(\.id))
        .sensoryFeedback(.impact(weight: .light), trigger: tray.stageTick)
        .sensoryFeedback(.increase, trigger: tray.incrementTick)
    }

    /// The field's visual: bare on the glass platter while nothing is typed
    /// (the capsule platter *is* the field), fading in a grey fill once text
    /// appears and the surface grows around it.
    private func fieldCapsule(filled: Bool, @ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.secondaryLabel)
            content()
        }
        .padding(.horizontal, 14)
        .frame(height: GlassDockMetrics.controlHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemFill).opacity(filled ? 1 : 0), in: Capsule())
    }

    private var idleDock: some View {
        Button(action: activateSearch) {
            fieldCapsule(filled: false) {
                Text("Search substances...")
                    .foregroundStyle(Theme.secondaryLabel)
                Spacer(minLength: 0)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(GlassDockMetrics.bareInset)
    }

    private var trayDock: some View {
        DoseTrayView(
            model: tray,
            tagSuggestions: cachedTagSuggestions,
            recentLocations: cachedRecentLocations,
            onAddMore: activateSearch,
            onCommit: commitTray,
        )
    }

    /// Results stack *above* the field — the field stays pinned at the bottom
    /// of the dock while suggestions grow upward. With nothing typed the face
    /// is the bare glass capsule, so the field carries no fill or padding;
    /// once typed it sits at the same frame as the tray's Log button, so the
    /// two morph into one another when a result stages.
    private var searchDock: some View {
        VStack(spacing: 0) {
            if isHelpSearch {
                QuickLogHelpBanner()
                    .padding(.horizontal, GlassDockMetrics.contentInsets.leading)
                    .padding(.bottom, 8)
            } else if !searchText.isEmpty {
                QuickLogSearchResults(
                    results: dockResults,
                    onStageRecent: stageFromCard,
                    onOpenSubstance: openLibrarySubstance,
                    onCreateCustom: {
                        // Release search focus before presenting, like every
                        // other handoff out of the search surface. Leaving it
                        // set makes SwiftUI restore focus mid-transition when
                        // the form later dismisses — the keyboard churn behind
                        // the builds-13/14 SheetBridge exclusivity crash (and
                        // the "search bar stuck mid-air" feedback).
                        searchFocused = false
                        showCustomForm = true
                    },
                )
            }

            fieldCapsule(filled: !dockIsBareField) {
                TextField("Search substances...", text: $searchText)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($searchFocused)
                    .submitLabel(.search)
                if !searchText.isEmpty {
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
            .padding(.horizontal, dockIsBareField ? GlassDockMetrics.bareInset : GlassDockMetrics.contentInsets.leading)
            .padding(.bottom, dockIsBareField ? GlassDockMetrics.bareInset : GlassDockMetrics.contentInsets.bottom)
        }
        .padding(.top, dockIsBareField ? GlassDockMetrics.bareInset : GlassDockMetrics.contentInsets.top)
        .onAppear { searchFocused = true }
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

    /// The ranked search hits shown inside the dock (recent → library →
    /// custom). Presentation lives in ``QuickLogSearchResults``.
    private var dockResults: [QuickLogSearchResult] {
        let query = searchText.lowercased()
        guard !query.isEmpty else { return [] }
        var results: [QuickLogSearchResult] = cachedCards
            .filter { $0.id.contains(query) }
            .prefix(2)
            .map { .recent($0) }
        results += cachedLibraryResults.prefix(3).map { .library($0) }
        results += filteredCustomSubstances.prefix(1).map { .custom($0) }
        return Array(results.prefix(4))
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

    // MARK: - Scroll Content

    private var isHelpSearch: Bool {
        CrisisKeywords.matches(searchText)
    }

    @ViewBuilder
    private var scrollContentInner: some View {
        if !cachedDailyGroups.isEmpty {
            dailySection
        }

        if !cachedFavoriteCards.isEmpty || !cachedFavoriteLibrarySubstances.isEmpty {
            Section {
                ForEach(cachedFavoriteCards) { card in
                    cardView(card, isFavorite: true)
                        .id("\(card.id)_fav")
                }
                ForEach(cachedFavoriteLibrarySubstances) { substance in
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

        if !cachedNonFavoriteCards.isEmpty {
            Section {
                ForEach(cachedNonFavoriteCards) { card in
                    cardView(card, isFavorite: false)
                        .id("\(card.id)_recent")
                }
            } header: {
                if !cachedFavoriteCards.isEmpty {
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

    /// Cheap change-signature for the routine pills' inputs (tiny N), used to
    /// invalidate `cachedDailyGroups` on an in-place edit from the settings
    /// sheet. Covers both the routine rows and the daily items in one key so
    /// the body adds a single `onChange` rather than two.
    private var routineSignature: [String] {
        var parts: [String] = []
        for routine in routines {
            let minutes = routine.timeMinutes ?? -1
            parts.append("r:\(routine.name)|\(minutes)|\(routine.sortOrder)")
        }
        for item in dailyDoseItems {
            parts.append("i:\(item.substance)|\(item.category)|\(item.sortOrder)")
        }
        return parts
    }

    private func makeDailyGroups() -> [DailyCategoryGroup] {
        guard !dailyDoseItems.isEmpty else { return [] }
        let loggedToday = cachedLoggedToday

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

    private var dailySection: some View {
        Section {
            FlowLayout(spacing: 8) {
                ForEach(cachedDailyGroups) { group in
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
            librarySubstance: SubstanceLibrary.timelineLookup(item.substance.lowercased()),
            isFromDailySet: true,
            isBackgroundMed: item.isBackgroundMed,
        )
    }

    // MARK: - Substance Card

    /// Builds the extracted ``SubstanceCardView`` for a recent/favorite card,
    /// wiring the parent-owned actions (favorite toggle + curated-list edits)
    /// while the card itself owns its layout and ephemeral expansion state.
    private func cardView(_ card: SubstanceCard, isFavorite: Bool) -> some View {
        SubstanceCardView(
            card: card,
            isFavorite: isFavorite,
            lastEntry: cachedMostRecent[card.id],
            tray: tray,
            onToggleFavorite: { withAnimation(.snappy) { toggleFavorite(card.substanceName) } },
            onMoveChip: { group, chip, toFront in moveChip(group: group, chip: chip, toFront: toFront) },
            onRemoveChip: { group, chip in removeChip(group: group, chip: chip) },
        )
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

        // Snapshot everything the writes need *before* dismissing. The view's
        // `@State` tray and `@Query` results start tearing down the instant we
        // dismiss, so reading them inside the deferred block would be racy.
        let stagedItems = tray.staged
        let sharedTime = tray.time.resolved
        let tags = Array(tray.tags)
        let location = tray.location
        let fixedOrder = quickLogFixedOrder
        let context = modelContext
        let recentEntries = Array(allEntries)
        var colors = Array(substanceColors)

        // The success haptic + dismiss fire *first*, on this runloop, so the
        // sheet starts sliding away immediately. (Haptic played directly
        // because the sheet tears down before a `sensoryFeedback` trigger
        // would fire.) Quick-log completes a flow, so clear the whole chain.
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        navigator.dismissAll()

        // Tier 1 — next runloop tick: the work that makes the dose *appear*
        // and persist (inserts, session assignment, colour, active-session
        // update, one save). Deferred a tick so it doesn't block the
        // dismissal's first frame, but kept prompt so the journal behind the
        // sheet shows the dose as the sheet slides away — no pop-in.
        DispatchQueue.main.async {
            var createdEntries: [DoseEntry] = []
            var curation: [QuickLogManager.LoggedDose] = []

            for item in stagedItems {
                let entry = DoseEntry(
                    substance: item.substanceName,
                    amount: item.totalAmount,
                    unit: item.unit,
                    route: item.route,
                    saltForm: item.saltForm,
                    timestamp: sharedTime,
                    notes: item.note.isEmpty ? nil : item.note,
                    tags: tags,
                    isBackgroundMed: item.isBackgroundMed,
                    locationName: location?.name,
                    latitude: location?.latitude,
                    longitude: location?.longitude,
                )
                context.insert(entry)
                SessionService.assignSession(for: entry, in: context)
                createdEntries.append(entry)

                // Record each component's chip amount (not the merged total) so
                // the curated list floats the chips the user actually tapped,
                // without minting a chip for every sum. Daily routine items keep
                // their own surface and don't mint quick-log chips.
                if !item.isFromDailySet {
                    for component in item.components {
                        curation.append(QuickLogManager.LoggedDose(substance: item.substanceName, route: item.route, amount: component.amount, unit: item.unit))
                    }
                }

                // Auto-assign a stable palette colour for a brand-new substance
                // up front (deterministic hash, the same colour the graph uses),
                // tracking it in the local `colors` snapshot so the session
                // picks it up immediately without a store round-trip.
                if !colors.hasColor(for: item.substanceName) {
                    let newColor = SubstanceColor(substance: item.substanceName, hexColor: PresetColor.deterministic(for: item.substanceName).hex)
                    context.insert(newColor)
                    colors.append(newColor)
                }

                ActiveSessionManager.shared.addDose(
                    entry: entry,
                    substance: item.librarySubstance,
                    colorHex: SubstancePalette.hex(for: item.substanceName, hexMap: colors.hexColorMap),
                    allColors: colors,
                )
            }
            try? context.save()

            // Tier 2 — after the dismissal animation: bookkeeping that isn't
            // on screen (curated-list maintenance, wellness notifications,
            // widget reload). Running it now would drop frames *during* the
            // slide-down; none of it is visible until the next quick-log open
            // or a widget refresh, so it waits for the transition to settle.
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.postCommitDelay) {
                QuickLogManager.record(curation, fixedOrder: fixedOrder, context: context)
                for entry in createdEntries {
                    DoseNotificationManager.doseLogged(entry: entry, recentEntries: recentEntries)
                }
                InventoryService.recomputeAll(in: context)
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }

    /// Delay before the non-visible post-commit bookkeeping runs — long enough
    /// to clear the sheet's dismissal animation so it doesn't drop frames.
    private static let postCommitDelay: TimeInterval = 0.45

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
                librarySubstance: SubstanceLibrary.timelineLookup(prefill.substance.lowercased()),
            )
            searchActive = false
            searchText = ""
        }
    }
}
