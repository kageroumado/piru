import SwiftData
import SwiftUI
import UIKit

struct SubstanceLibraryView: View {
    @Binding var searchText: String

    /// When embedded in the Search tab: drop the "Library" header + category
    /// browse, showing only recent substances (empty) or results (typed).
    var isSearchSurface = false

    var body: some View {
        Group {
            if searchText.isEmpty, !isSearchSurface {
                // Library tab browse: the bold family-card flow.
                LibraryBrowseView()
            } else {
                List {
                    if searchText.isEmpty {
                        RecentSubstancesSection()
                    } else {
                        // The search concern (results, help resources, and the
                        // favorites @Query) lives in its own child so the browse
                        // branch above never subscribes to favorites.
                        SubstanceSearchResultsList(searchText: searchText)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Theme.background)
            }
        }
        .appNavigationBar("Library", enabled: !isSearchSurface)
    }
}

// MARK: - Search Results

/// The Library/Search typed-query results: matched substances (with favorite
/// swipe + personal-name override) plus the crisis "help resources" section.
/// Owns the `favorites` @Query, the off-main search task, and the result state —
/// so the Library tab's browse flow doesn't subscribe to any of it.
private struct SubstanceSearchResultsList: View {
    let searchText: String
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FavoriteSubstance.createdAt, order: .reverse) private var favorites: [FavoriteSubstance]
    @State private var searchResults: [Substance] = []
    /// Cached so each search-result row's swipe action doesn't rebuild the set.
    @State private var favoriteNames: Set<String> = []
    /// Held here so the row's personal-name override is resolved once per row
    /// in this body (one subscription) rather than each row subscribing itself.
    @State private var customStore = CustomSubstanceStore.shared

    var body: some View {
        Group {
            if isHelpSearch {
                helpResourcesSection
            }

            if searchResults.isEmpty, !isHelpSearch {
                ContentUnavailableView(
                    "No Results",
                    systemImage: "magnifyingglass",
                    description: Text("No substances match \"\(searchText)\""),
                )
            } else if !searchResults.isEmpty {
                Section("\(searchResults.count) results") {
                    ForEach(searchResults) { substance in
                        NavigationLink(value: PushRoute.substance(name: substance.name)) {
                            SubstanceRowView(substance: substance, personalName: customStore.personalName(for: substance))
                        }
                        .swipeActions(edge: .trailing) {
                            let isFav = favoriteNames.contains(substance.name.lowercased())
                            Button {
                                FavoriteService.toggle(substance: substance.name, substanceUID: substance.substanceUID, in: modelContext)
                            } label: {
                                Label(isFav ? "Unfavorite" : "Favorite", systemImage: isFav ? "star.slash" : "star")
                            }
                            .tint(.yellow)
                        }
                        .listRowBackground(CardBackground())
                    }
                }
            }
        }
        .task(id: searchText) {
            guard !searchText.isEmpty else {
                searchResults = []
                return
            }
            // Debounce, then rank + resolve OFF the main actor — the ranking
            // scans the whole name/alias index and the resolution used to run the
            // heavy per-substance SQL for every result, so doing it inline stalled
            // the keyboard on each keystroke. The `.task(id:)` cancels the prior
            // run when the text changes, so only the latest query resolves.
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            let results = await SubstanceLibrary.searchAsync(searchText)
            guard !Task.isCancelled else { return }
            searchResults = results
        }
        .task(id: favoritesSignature) {
            favoriteNames = Set(favorites.map { $0.substance.lowercased() })
        }
    }

    /// Favorite identities, not just `count`, so a same-count swap still
    /// refreshes the cached swipe-action label set.
    private var favoritesSignature: Int {
        var hasher = Hasher()
        for favorite in favorites {
            hasher.combine(favorite.substance)
        }
        return hasher.finalize()
    }

    private var isHelpSearch: Bool {
        CrisisKeywords.matches(searchText)
    }

    // MARK: - Help Resources

    private var helpResourcesSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "hand.raised.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.blue)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Take a breath.")
                            .font(.title3.weight(.semibold))
                        Text("You're going to be okay. Whatever you're feeling right now is temporary.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("If you need help right now:")
                        .font(.subheadline.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)

                    helpLink(
                        icon: "phone.fill",
                        color: .red,
                        title: "Emergency Services",
                        detail: "Call 911 (US) or your local emergency number",
                        url: "tel:911",
                    )
                    helpLink(
                        icon: "cross.case.fill",
                        color: .orange,
                        title: "Poison Control",
                        detail: "1-800-222-1222 (US)",
                        url: "tel:18002221222",
                    )
                    helpLink(
                        icon: "phone.badge.waveform.fill",
                        color: .purple,
                        title: "988 Suicide & Crisis Lifeline",
                        detail: "Call or text 988",
                        url: "tel:988",
                    )
                    helpLink(
                        icon: "message.fill",
                        color: .green,
                        title: "Crisis Text Line",
                        detail: "Text HOME to 741741",
                        url: "sms:741741&body=HOME",
                    )
                    helpLink(
                        icon: "heart.fill",
                        color: .pink,
                        title: "SAMHSA Helpline",
                        detail: "1-800-662-4357 — Free, confidential, 24/7",
                        url: "tel:18006624357",
                    )
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("While you wait or if you just need to calm down:")
                        .font(.subheadline.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text("Breathe slowly: 4 seconds in, hold for 4, out for 4.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                    Text("Put your feet flat on the floor. Feel the ground beneath you.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                    Text("Name 5 things you can see. 4 you can touch. 3 you can hear.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                    Text("You are not alone. People care about you and help is available.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func helpLink(icon: String, color: Color, title: LocalizedStringKey, detail: LocalizedStringKey, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryLabel)
                    .accessibilityHidden(true)
            }
        }
    }
}

// MARK: - Recent (Search surface)

/// The Search surface's empty-query content: up to 10 most recently logged
/// substances, de-duplicated and resolved to their library entries.
///
/// Owns the `DoseEntry` query so that *only this section* — which exists just
/// while the search surface shows it — invalidates when doses change. Hosting
/// the query on ``SubstanceLibraryView`` itself subscribed the entire Library
/// tab to every dose mutation for the sake of these ten rows.
private struct RecentSubstancesSection: View {
    @Query(sort: \DoseEntry.timestamp, order: .reverse) private var recentEntries: [DoseEntry]
    @State private var customStore = CustomSubstanceStore.shared

    /// Resolved once per dose-history change instead of per body — each rebuild
    /// is up to 10 synchronous `SubstanceLibrary.lookup` calls.
    @State private var recentSubstances: [Substance] = []

    private var recentSignature: Int {
        var hasher = Hasher()
        // The 10 most-recent distinct substances are what we render; the newest
        // ~20 timestamps comfortably cover that window for change detection.
        for entry in recentEntries.prefix(20) {
            hasher.combine(entry.substance)
        }
        return hasher.finalize()
    }

    private func rebuildRecent() {
        var seen = Set<String>()
        var result: [Substance] = []
        for entry in recentEntries {
            let key = entry.substance.lowercased()
            if seen.insert(key).inserted, let substance = SubstanceLibrary.lookup(key) {
                result.append(substance)
                if result.count >= 10 { break }
            }
        }
        recentSubstances = result
    }

    var body: some View {
        content
            .task(id: recentSignature) {
                await SubstanceStore.shared.ensureAllLoaded()
                rebuildRecent()
            }
    }

    @ViewBuilder
    private var content: some View {
        if recentSubstances.isEmpty {
            ContentUnavailableView(
                "Search Substances",
                systemImage: "magnifyingglass",
                description: Text("Find any substance by name or alias."),
            )
        } else {
            Section("Recent") {
                ForEach(recentSubstances) { substance in
                    NavigationLink(value: PushRoute.substance(name: substance.name)) {
                        SubstanceRowView(substance: substance, personalName: customStore.personalName(for: substance))
                    }
                    .listRowBackground(CardBackground())
                }
            }
        }
    }
}

// MARK: - Category Substance List

struct SubstanceCategoryListView: View {
    let title: LocalizedStringResource
    var category: SubstanceCategory?
    /// Tag-backed list (the Library's Common card); mutually exclusive with
    /// `category`. When both are nil the view shows Favorites.
    var tag: String?
    @Query(sort: \FavoriteSubstance.createdAt, order: .reverse) private var favorites: [FavoriteSubstance]
    @Environment(\.modelContext) private var modelContext
    @State private var customStore = CustomSubstanceStore.shared

    enum SortMode: String, CaseIterable { case popularity, name }
    @State private var sortMode: SortMode = .popularity

    /// Whether this list browses a class (category or tag) versus Favorites —
    /// browse lists are sortable, Favorites keep the user's own order.
    private var isBrowse: Bool {
        category != nil || tag != nil
    }

    /// Resolved + sorted once per (category/tag/sort/favorites) change, not per
    /// body. `substances(in:)`/`(taggedWith:)` and the sort were re-running on
    /// every body pass; the sort is O(n log n) over a full category.
    @State private var sortedSubstances: [Substance] = []
    /// Favorite name set, cached so the per-row swipe action doesn't rebuild it.
    @State private var favoriteNames: Set<String> = []

    /// The inputs the resolved list depends on; drives the rebuild task.
    private var listSignature: Int {
        var hasher = Hasher()
        hasher.combine(category)
        hasher.combine(tag)
        hasher.combine(sortMode)
        // Favorites are this list's content when browsing neither category nor
        // tag, and always drive the swipe-action label set. Hash identities, not
        // just `count`, so a same-count swap (remove one, add another) still
        // rebuilds instead of leaving the favorites list / swipe labels stale.
        for favorite in favorites {
            hasher.combine(favorite.substance)
        }
        return hasher.finalize()
    }

    private func rebuildList() async {
        // The list itself is a warm-cache dict filter on the main actor; the
        // O(n log n) sort over a full category is the work, so it runs off-main
        // over the `Sendable` `[Substance]` and publishes the result back.
        let list: [Substance] = if let tag {
            SubstanceLibrary.substances(taggedWith: tag)
        } else if let category {
            SubstanceLibrary.substances(in: category)
        } else {
            // Exact canonical lookup — alias fallback mis-resolves on polluted
            // aliases (e.g. "magnesium" is also an alias of Salicylic acid).
            favorites.compactMap { SubstanceLibrary.lookup($0.substance) }
        }
        let favNames = Set(favorites.map { $0.substance.lowercased() })
        let mode = sortMode
        let browse = isBrowse

        // Category browse is sortable (popularity surfaces well-known substances
        // above obscure research chemicals); Favorites keep the user's own order.
        let sorted = await Task.detached(priority: .userInitiated) {
            guard browse else { return list }
            switch mode {
            case .name:
                return list.sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
            case .popularity:
                return list.sorted {
                    $0.popularity != $1.popularity
                        ? $0.popularity > $1.popularity
                        : $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
                }
            }
        }.value

        sortedSubstances = sorted
        favoriteNames = favNames
    }

    var body: some View {
        List {
            ForEach(sortedSubstances) { substance in
                NavigationLink(value: PushRoute.substance(name: substance.name)) {
                    // Pass the list's category so a mixed compound from another
                    // family (e.g. a balanced stimulant in Empathogens) shows a
                    // disambiguating class chip; pure members stay chip-free.
                    SubstanceRowView(substance: substance, contextCategory: category, personalName: customStore.personalName(for: substance))
                }
                .swipeActions(edge: .trailing) {
                    let isFav = favoriteNames.contains(substance.name.lowercased())
                    Button {
                        FavoriteService.toggle(substance: substance.name, substanceUID: substance.substanceUID, in: modelContext)
                    } label: {
                        Label(isFav ? "Unfavorite" : "Favorite", systemImage: isFav ? "star.slash" : "star")
                    }
                    .tint(.yellow)
                }
            }
            .listRowBackground(CardBackground())
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .task(id: listSignature) {
            await SubstanceStore.shared.ensureAllLoaded()
            await rebuildList()
        }
        .navigationTitle(Text(title))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if isBrowse {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort", selection: $sortMode) {
                            Label("Popularity", systemImage: "chart.bar.fill").tag(SortMode.popularity)
                            Label("Name", systemImage: "textformat").tag(SortMode.name)
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .accessibilityLabel(Text("Sort"))
                    }
                }
            }
        }
    }
}

// MARK: - Substance Row

struct SubstanceRowView: View {
    let substance: Substance
    /// The category whose list this row is in (nil for cross-category lists:
    /// search, recents, the Common tag). Drives the trailing class chip: in a
    /// single-category list the chip is hidden for rows that belong there, and
    /// SHOWN for a mixed compound surfacing from another family (e.g. a balanced
    /// stimulant like 3-MMC in Empathogens reads "Stimulant") — the color dot +
    /// label disambiguate why it's here.
    var contextCategory: SubstanceCategory?
    /// Personal display-name override (resolved by the parent list, which holds
    /// the `CustomSubstanceStore`), or `nil` for the library title. Injected as a
    /// plain value so the row holds no store reference — it stays value-comparable
    /// and SwiftUI skips it on an unrelated re-render.
    var personalName: String?

    /// Show the class chip in a cross-category list, or when this row's primary
    /// class differs from the list it's appearing in (a cross-listed mixed case).
    private var showsCategoryBadge: Bool {
        contextCategory == nil || substance.category != contextCategory
    }

    var body: some View {
        HStack(spacing: 12) {
            // Category-color accent — ties each row to the family palette and
            // adds a touch of color to an otherwise flat list.
            Circle()
                .fill(substance.category.color.gradient)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(personalName ?? substance.displayTitle)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                // When personalized, show the canonical name as the subtitle so
                // the user can tell what "joint" actually maps to. One line —
                // long alias lists shouldn't blow a row up to three lines.
                if let subtitle = personalName != nil ? substance.name : substance.displaySubtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            // Genuinely thin entries (zero dose + duration + protocol) get a
            // "Limited data" badge. The unit used to sit here — useless in a
            // browse list, so it's gone.
            if substance.isStub {
                Text("Limited data")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.fill.tertiary, in: Capsule())
            } else if showsCategoryBadge {
                Text(substance.category.displayName)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(substance.category.labelColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    // 0.10 — the alpha every scale's `text` variant is gated against.
                    // At 0.12 the badge measured 4.40:1 on device, just under the
                    // 4.5 gate: a fill 2% darker than the one the token was
                    // derived for is enough to fail it.
                    .background(substance.category.color.opacity(0.10), in: Capsule())
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

// MARK: - Substance Detail

/// Renders a substance's class metadata tags as a wrapping row of small
/// capsule chips. Tags carry mechanism, chemical family, provenance, and
/// status — see ``Substance/tags`` for the vocabulary.
struct SubstanceTagFlow: View {
    let tags: [String]
    let accent: Color

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(accent.opacity(0.15), in: Capsule())
                    .foregroundStyle(accent)
            }
        }
    }
}
