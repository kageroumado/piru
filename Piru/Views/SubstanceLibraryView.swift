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
                                FavoriteService.toggle(substance.name, in: modelContext)
                            } label: {
                                Label(isFav ? "Unfavorite" : "Favorite", systemImage: isFav ? "star.slash" : "star")
                            }
                            .tint(.yellow)
                        }
                        .listRowBackground(Theme.cardBackground)
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
                    .listRowBackground(Theme.cardBackground)
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
                        FavoriteService.toggle(substance.name, in: modelContext)
                    } label: {
                        Label(isFav ? "Unfavorite" : "Favorite", systemImage: isFav ? "star.slash" : "star")
                    }
                    .tint(.yellow)
                }
            }
            .listRowBackground(Theme.cardBackground)
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
    /// stimulant like 3-MMC in Empathogens reads "Stimulant") — the colour dot +
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
            // adds a touch of colour to an otherwise flat list.
            Circle()
                .fill(substance.category.color.gradient)
                .frame(width: 10, height: 10)
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
                    .foregroundStyle(substance.category.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(substance.category.color.opacity(0.12), in: Capsule())
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

// MARK: - Substance Detail

struct SubstanceDetailView: View {
    /// The library substance backing this view. Pushed as a **lightweight shell**
    /// (the batch projection's hot fields — name, category, routes/doses,
    /// durations, half-life, aliases) so the header and dose/duration card render
    /// instantly off the navigation push; ``upgradeToFullRecord()`` then resolves
    /// the heavy detail-only fields (mechanism, chemistry identifiers, molar mass,
    /// medical info, protocol dosing, peptide) in a `.task` and swaps them in, so
    /// those sections reveal progressively. Overrides are layered on reactively
    /// via `substance`, so personalizations show on entry and update live.
    @State private var baseSubstance: Substance
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appNavigator) private var navigator
    @Environment(\.openURL) private var openURL
    @Query private var historyEntries: [DoseEntry]
    @Query private var favorites: [FavoriteSubstance]
    @Query private var inventoryItems: [InventoryItem]
    @State private var customStore = CustomSubstanceStore.shared
    @State private var showAllHistory = false
    @State private var showEntries = false
    @State private var showingPersonalize = false

    /// O(n) dose-history aggregates for the history card, memoized off `body`
    /// so toggling a disclosure doesn't re-scan the full history. Rebuilt by
    /// the `historySignature`-keyed task whenever the entries change.
    @State private var historyStats = HistoryStats()

    /// The route the dose/duration card is showing. `nil` defaults to the
    /// substance's default route (resolved in ``activeSubstanceRoute``).
    @State private var selectedRoute: RouteOfAdministration?

    /// The salt/ester form the dose card is showing (Magnesium, Lithium).
    /// `nil` defaults to the active route's first form (resolved in
    /// ``activeSaltVariant``).
    @State private var selectedSaltForm: String?

    /// The user's personal override for this substance, if any (keyed by canonical name).
    private var personalOverride: CustomSubstanceEntry? {
        customStore.first(whereName: baseSubstance.name)
    }

    /// The substance with any personal override applied — display name, dose
    /// ladder, duration, and half-life. Used throughout the view so the detail
    /// reflects the user's customizations and updates live when they change.
    private var substance: Substance {
        personalOverride.map { baseSubstance.applyingOverride(from: $0) } ?? baseSubstance
    }

    @State private var store = SubstanceStore.shared

    /// Holding the @Observable profile store as @State (rather than reading
    /// `UserProfileStore.shared.disclosureTier` via a plain computed) is what makes
    /// SwiftUI re-render this view when the user changes the tier in Settings.
    @State private var profileStore = UserProfileStore.shared

    // Section expansion state. `nil` means "use the policy default for the
    // current tier"; once the user toggles a section, the stored Bool sticks.
    // Reset to nil on profile change so the new tier's defaults take effect
    // (otherwise the user would be permanently stuck on whatever defaults
    // applied the first time the section was rendered).
    @State private var overviewExpanded: Bool?
    @State private var mechanismExpanded: Bool?
    @State private var monoamineProfile: MonoamineProfile?
    @State private var receptorLitExpanded: Bool?
    @State private var pharmacokineticsExpanded: Bool?
    @State private var metabolismExpanded: Bool?
    /// The plain-language help sheet shown from a card header's (i) button (PK / receptor data).
    @State private var glossaryTopic: PharmacologyGlossarySheet.Topic?
    /// Contraindications & cautions — verbose clinical data, collapsed by default
    /// so the screen reads like a harm-reduction app, not a drug monograph.
    @State private var cautionsExpanded = false
    /// The Info block (name/aliases/route/chemistry) is demoted below dosing and
    /// collapsed by default — few users need the chemical identity up front.
    @State private var infoExpanded = false
    /// Chemistry / identifiers — demoted to a collapsed "Additional information"
    /// disclosure; the chemical numbers are reference data few users open.
    @State private var chemistryExpanded = false
    /// Reveals the full alias list behind the "+N more" chip in the Info grid.
    @State private var aliasesExpanded = false
    /// Drives the push to the grouped "All effects" screen from the Effects
    /// header's "Show All" (a header NavigationLink isn't reliably hittable).
    @State private var showAllEffects = false
    /// Drives the push to the full Inventory list from the stock card's "Show All".
    @State private var showAllInventory = false
    @State private var literatureBindings: [SubstanceStore.BindingHit] = []
    @State private var pkRoutes: [SubstanceStore.PKRouteHit] = []
    @State private var metabolismRows: [SubstanceStore.MetabolismHit] = []
    /// Educational metabolic-modulation effects (grapefruit / smoking / self-edge) for this substance
    /// (Stage 4c). Loaded for non-casual tiers from a dedicated metabolism fetch so the card reaches
    /// harm-reduction users even though the full PK table is pharma-nerd-only.
    @State private var metabolicEducation: [MetabolicModulation.Effect] = []
    /// Set when this substance is a meaningful CYP3A4 inducer (modafinil, rifampicin, …) → it can lower
    /// hormonal-contraception levels. Ungated (a safety fact, like a boxed warning), loaded for every tier.
    @State private var contraceptionCaution: MetabolicModulation.Modulator?
    @State private var provenance: SubstanceStore.SubstanceProvenance?

    private var profile: UserProfile {
        profileStore.disclosureTier
    }
    private var policy: DisclosurePolicy {
        .init(profile: profile)
    }
    /// The class-specific hero for the unified Pharmacology card (opioid / benzo / dissociative receptor
    /// panel). `nil` for monoamine and other classes, which fall back to the slider/target grid and keep
    /// the separate Receptor Literature section.
    private var pharmacologyHero: PharmacologyHero? {
        PharmacologyHero.resolve(category: substance.category, bindings: Self.dedupedLiterature(visibleLiteratureBindings))
    }
    private var displayClass: CompoundDisplayClass {
        substance.displayClass
    }

    /// Human-readable availability label from the parsed regulatory_status.
    private func regulatoryDisplay(_ raw: String) -> String {
        switch raw {
        case "otc": return String(localized: "Over-the-counter")
        case "rx": return String(localized: "Prescription only")
        case "rx_otc_dependent": return String(localized: "OTC / Prescription")
        default:
            if raw.hasPrefix("controlled_schedule_"), let n = raw.split(separator: "_").last {
                return String(localized: "Schedule \(String(n)) (controlled)")
            }
            return raw
        }
    }

    /// Net-new clinical section: indications + contraindications + boxed
    /// warnings. Renders only when the compound carries that data (medical/OTC
    /// compounds from pyrls/medtap).
    @ViewBuilder private var medicalInfoSection: some View {
        if !substance.indications.isEmpty {
            Section("Medical Uses") {
                ForEach(substance.indications, id: \.self) { ind in
                    clinicalRow(ind, icon: "stethoscope", tint: Theme.accent)
                }
            }
        }
        let boxed = substance.contraindications.filter(\.isBoxedWarning)
        let cautions = substance.contraindications.filter { !$0.isBoxedWarning }
        if !boxed.isEmpty {
            Section("Boxed Warning") {
                ForEach(boxed, id: \.text) { c in
                    clinicalRow(c.text, icon: "exclamationmark.octagon.fill", tint: .red, lineLimit: nil)
                }
            }
        }
        if !cautions.isEmpty {
            // Verbose DailyMed contraindication prose — collapsed by default,
            // each row clamped to a few lines, and capped to keep the screen
            // from turning into a drug monograph. Full text lives at the source.
            CollapsibleSection(
                "Contraindications & Cautions",
                systemImage: "exclamationmark.triangle",
                count: cautions.count,
                isExpanded: $cautionsExpanded,
            ) {
                ForEach(cautions.prefix(cautionDisplayLimit), id: \.text) { c in
                    clinicalRow(c.text, icon: "exclamationmark.triangle", tint: .orange, lineLimit: 4)
                }
                if cautions.count > cautionDisplayLimit {
                    Text("+\(cautions.count - cautionDisplayLimit) more")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
        }
    }

    /// How many cautions to list before falling back to a "+N more" row.
    private let cautionDisplayLimit = 6

    /// One clinical list row — a readable leading symbol (the old style forced a
    /// 5pt icon that vanished) plus wrapping text clamped to `lineLimit`.
    private func clinicalRow(_ text: String, icon: String, tint: Color, lineLimit: Int? = 2) -> some View {
        Label {
            Text(text)
                .font(.subheadline)
                .lineLimit(lineLimit)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(tint)
        }
    }

    /// Chemical identity (formula / molar mass / CAS / InChIKey) folded into a
    /// collapsed "Chemistry" disclosure below the identity Info card. Every value
    /// is selectable and carries a Copy action — an InChIKey you can't copy is
    /// useless.
    @ViewBuilder private var chemistryDisclosure: some View {
        let hasPubChem = substance.pubChemURL != nil
        let phys = substance.physicochemical
        let hasChem = substance.formula != nil || substance.cas != nil || substance.inchikey != nil
            || substance.molarMass != nil || hasPubChem || substance.smiles != nil
            || substance.iupacName != nil || (phys?.hasAnyValue ?? false)
        if policy.showsMechanism, hasChem {
            CollapsibleSection("Chemistry", systemImage: "atom", isExpanded: $chemistryExpanded) {
                let showMW = substance.molarMass != nil && !substance.usesPeptidePresentation
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 14) {
                    if substance.formula != nil || showMW {
                        GridRow {
                            if let f = substance.formula { gridCell("Formula", f) } else { Color.clear }
                            if showMW, let mw = substance.molarMass {
                                gridCell("Molar mass", "\(mw.doseFormatted) g/mol")
                            } else { Color.clear }
                        }
                    }
                    physicochemicalRows(phys)
                    if let iupac = substance.iupacName {
                        GridRow { gridCell("IUPAC name", iupac).gridCellColumns(2) }
                    }
                    if let smiles = substance.smiles {
                        GridRow { gridCell("SMILES", smiles, mono: true).gridCellColumns(2) }
                    }
                    if let k = substance.inchikey {
                        GridRow { gridCell("InChIKey", k, mono: true).gridCellColumns(2) }
                    }
                    if substance.cas != nil || hasPubChem {
                        GridRow {
                            if let c = substance.cas { gridCell("CAS", c, mono: true) } else { Color.clear }
                            if let cid = substance.pubchemCID, let url = substance.pubChemURL {
                                pubChemCell(cid: cid, url: url)
                            } else { Color.clear }
                        }
                    }
                }
                .padding(.vertical, 4)
                if let phys, phys.hasAnyValue {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Physicochemical values are predicted/computed (PubChem, NPS-DataHub), not measured for this preparation.")
                        if phys.hasLD50 {
                            Text("LD50 is rodent toxicity (order of magnitude) — not a human safe dose.")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                }
            }
        }
    }

    /// The Stage-1 physicochemical descriptors, laid into the Chemistry grid as
    /// two-column rows. logD/pKa are unsourced today (always nil) but the
    /// `if let` guards keep them future-proof — a populated column just appears.
    @ViewBuilder
    private func physicochemicalRows(_ phys: Physicochemical?) -> some View {
        if let phys {
            if phys.logP != nil || phys.tpsa != nil {
                GridRow {
                    if let v = phys.logP { gridCell("LogP", Self.chemNumber(v)) } else { Color.clear }
                    if let v = phys.tpsa { gridCell("TPSA", "\(Self.chemNumber(v)) Å²") } else { Color.clear }
                }
            }
            if phys.hba != nil || phys.hbd != nil {
                GridRow {
                    if let v = phys.hba { gridCell("H-bond acceptors", "\(v)") } else { Color.clear }
                    if let v = phys.hbd { gridCell("H-bond donors", "\(v)") } else { Color.clear }
                }
            }
            if phys.logD != nil || phys.pKa != nil {
                GridRow {
                    if let v = phys.logD { gridCell("LogD", Self.chemNumber(v)) } else { Color.clear }
                    if let v = phys.pKa { gridCell("pKa", Self.chemNumber(v)) } else { Color.clear }
                }
            }
            if phys.meltingPointC != nil || phys.boilingPointC != nil {
                GridRow {
                    if let v = phys.meltingPointC { gridCell("Melting point", "\(Self.chemNumber(v)) °C") } else { Color.clear }
                    if let v = phys.boilingPointC { gridCell("Boiling point", "\(Self.chemNumber(v)) °C") } else { Color.clear }
                }
            }
            if phys.ld50OralMgPerKg != nil || phys.ld50DermalMgPerKg != nil {
                GridRow {
                    if let v = phys.ld50OralMgPerKg { gridCell("LD50 (oral, rodent)", "\(Self.chemNumber(v)) mg/kg") } else { Color.clear }
                    if let v = phys.ld50DermalMgPerKg { gridCell("LD50 (dermal, rodent)", "\(Self.chemNumber(v)) mg/kg") } else { Color.clear }
                }
            }
        }
    }

    /// Compact numeric formatter for chemistry values: drops a trailing `.0`
    /// (so `45.0` → `45`) but keeps real decimals (`2.34` → `2.34`).
    static func chemNumber(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.0f", value) : String(format: "%g", value)
    }

    /// One labelled cell in the Info / Chemistry two-column grids. Only the
    /// *value* is selectable (long-press to select & copy) — the label isn't,
    /// so you can't accidentally grab the neighbouring cell's value (the old
    /// whole-row contextMenu copied the wrong field and felt confusing).
    private func gridCell(_ label: LocalizedStringResource, _ value: String, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
                .textCase(.uppercase)
            Text(value)
                .font(mono ? .footnote.monospaced() : .subheadline)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// PubChem cell — a tappable link out to the curated chemistry record. Lives
    /// in Chemistry (not Info): it's a chemical identifier, same as the rest.
    ///
    /// A borderless `Button` (not a `Link`): a lone `Link` in a Form/List row gets
    /// promoted to a full-row tap target, so the *whole* Chemistry card opened
    /// PubChem. Borderless keeps the hit area to this one cell.
    private func pubChemCell(cid: Int, url: URL) -> some View {
        Button {
            openURL(url)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text("PubChem CID")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryLabel)
                    .textCase(.uppercase)
                HStack(spacing: 3) {
                    Text(verbatim: "\(cid)").font(.subheadline)
                    Image(systemName: "arrow.up.right").font(.caption2)
                }
                .foregroundStyle(Theme.accent)
            }
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.borderless)
    }

    /// Effects — the merged surface. Curated subjective effects (rich tier) read
    /// as the readable summary; the full PsychonautWiki taxonomy lives one tap
    /// away on the grouped ``AllEffectsView`` so the detail view stays short.
    /// First-hand Erowid reports show on the pushed "All effects" screen, gated
    /// to recreational / dual-use compounds where such reports exist.
    private var showsErowidReports: Bool {
        displayClass == .recreational || displayClass == .dualUse
    }

    /// Long-form overview prose (FreeOD Wiki), resolved locale-first by the
    /// store: native Chinese when the app runs in Chinese, machine-translated
    /// English as a fallback. Hidden when no source supplies an overview.
    @ViewBuilder private var overviewSection: some View {
        if let overview = substance.overview, !overview.text.isEmpty {
            // Unlike the other folded blocks, the Overview reads better as a few
            // lines of prose with an inline "Read more" than as a closed
            // disclosure — you see what the substance *is* without a tap.
            let expanded = overviewExpanded ?? false
            let isLong = overview.text.count > overviewCollapsedThreshold
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Overview", systemImage: "text.justify.left")
                        .font(.subheadline.weight(.semibold))
                    Text(overview.text)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryLabel)
                        .lineLimit(isLong && !expanded ? overviewCollapsedLines : nil)
                        .fixedSize(horizontal: false, vertical: true)
                    if isLong {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { overviewExpanded = !expanded }
                        } label: {
                            Text(expanded ? "Read less" : "Read more")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                        }
                        .buttonStyle(.plain)
                    }
                    if overview.machineTranslated {
                        Label("Machine-translated from FreeOD Wiki", systemImage: "character.bubble")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                SourceAttributionRow(
                    slug: overview.sourceSlug,
                    label: "Overview",
                    deepLink: sourceDeepLink(overview.sourceSlug),
                )
            }
        }
    }

    /// Overview collapses to `overviewCollapsedLines` lines with a "Read more"
    /// when the prose exceeds `overviewCollapsedThreshold` characters (≈ that
    /// many lines), so short blurbs show in full with no toggle.
    private let overviewCollapsedLines = 5
    private let overviewCollapsedThreshold = 320

    @ViewBuilder private var effectsSection: some View {
        let curated = policy.showsRichSubjective ? substance.subjectiveEffects : []
        let hasAllEffects = !substance.effects.isEmpty
        // Only the first few curated effects read as the "main effects" summary;
        // a long list (e.g. MPH) belongs behind "Show All", not dumped inline.
        let mainEffects = Array(curated.prefix(mainEffectsLimit))
        // Offer "Show All" when there are more curated effects than we show, or
        // when the full taxonomy adds rows beyond the curated set (not Melatonin,
        // where it would reveal *fewer*).
        let showsMoreEffects = curated.count > mainEffects.count || substance.effects.count > curated.count
        if displayClass != .nonRecreational, !curated.isEmpty || hasAllEffects {
            Section {
                if !mainEffects.isEmpty {
                    ForEach(mainEffects, id: \.name) { effect in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(effect.name)
                                .font(.subheadline)
                            if !effect.description.isEmpty {
                                Text(effect.description)
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryLabel)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } else if hasAllEffects {
                    Button { showAllEffects = true } label: {
                        Label("All effects (\(substance.effects.count))", systemImage: "list.bullet.rectangle")
                            .font(.subheadline)
                    }
                }
            } header: {
                HStack {
                    Text("Effects")
                    Spacer()
                    // Health-style "Show All" → the full PsychonautWiki taxonomy
                    // (and Erowid reports), grouped by category, one tap away.
                    // A header NavigationLink isn't reliably hittable, so drive a
                    // navigationDestination from a Button instead.
                    if !mainEffects.isEmpty, showsMoreEffects {
                        Button { showAllEffects = true } label: {
                            HStack(spacing: 2) {
                                Text("Show All")
                                Image(systemName: "chevron.right").font(.caption2)
                            }
                            .font(.subheadline)
                            .foregroundStyle(Theme.accent)
                            .textCase(nil)
                        }
                    }
                }
            }
        }
    }

    /// How many curated effects show inline before the rest move to "Show All".
    private let mainEffectsLimit = 6

    init(substance: Substance) {
        _baseSubstance = State(initialValue: substance)
        let name = substance.name
        _historyEntries = Query(
            filter: #Predicate<DoseEntry> { entry in
                entry.substance == name
            },
            sort: \DoseEntry.timestamp,
            order: .reverse,
        )
    }

    /// Resolve the full per-field record (mechanism, chemistry identifiers, molar
    /// mass, indications/contraindications, protocol dosing, peptide profile) and
    /// swap it in. Runs off the push in a `.task`; the hot header/dose fields
    /// already render from the shell, and the full record carries the same name,
    /// routes, and category, so only the heavy sections pop in. No-op when the
    /// canonical row can't be resolved (keeps the shell).
    private func upgradeToFullRecord() {
        if let full = SubstanceLibrary.lookup(baseSubstance.name) {
            baseSubstance = full
        }
    }

    private var isFavorite: Bool {
        Array(favorites).isFavorite(substance.name)
    }

    private func toggleFavorite() {
        FavoriteService.toggle(substance.name, in: modelContext)
        try? modelContext.save()
    }

    /// Mechanism shown in the detail card, composed from three sources by
    /// precedence so real receptor data isn't hidden behind a generic template:
    ///
    /// - **Summary text**: a curated DB `mechanisms_summary` row wins; otherwise
    ///   the hand-curated per-name entry, then the per-category fallback.
    /// - **Bindings**: a hand-curated per-name entry wins (its targets are
    ///   deliberately complete — e.g. mitragynine's α2-adrenergic activity that
    ///   the measured opioid panel omits); otherwise measured DB bindings (real
    ///   actions like `releasingAgent`) beat the category fallback's generic
    ///   `.modulator` placeholders.
    ///
    /// This keeps substances with clear receptor data (mephedrone, the MMC
    /// cathinones) from showing a generic "Monoamine Modulator" mechanism.
    private var composedMechanism: MechanismOfAction? {
        MechanismOfActionDatabase.resolvedMechanism(
            dbMechanism: substance.mechanismOfAction,
            substanceName: substance.name,
            category: substance.category,
        )
    }

    /// Whether the acute duration timeline should be shown for this compound.
    private var durationVisible: Bool {
        displayClass.showsDuration && !(displayClass == .otc && substance.durationImplausible)
    }

    /// Routes with something worth showing — a dose ladder, an acute duration,
    /// or a long-acting release window. These populate the route picker.
    private var presentableRoutes: [SubstanceRoute] {
        substance.routes.filter { route in
            (displayClass.showsDoseLadder && route.doses.hasAnyValue)
                || (route.duration != nil && durationVisible)
                || route.durationOfAction != nil
        }
    }

    /// The route currently driving the dose/duration card: the user's pick when
    /// it's still valid, otherwise the default route, otherwise the first.
    private var activeSubstanceRoute: SubstanceRoute? {
        if let selectedRoute, let match = presentableRoutes.first(where: { $0.route == selectedRoute }) {
            return match
        }
        return presentableRoutes.first { $0.route == substance.defaultRoute } ?? presentableRoutes.first
    }

    private var routeSelection: Binding<RouteOfAdministration> {
        Binding(
            get: { activeSubstanceRoute?.route ?? substance.defaultRoute },
            set: { newRoute in
                selectedRoute = newRoute
                // Reset the salt to the new route's default unless it carries
                // the same form (salt is a sub-dimension of route).
                let forms = presentableRoutes.first { $0.route == newRoute }?.saltForms ?? []
                if let current = selectedSaltForm, !forms.contains(where: { $0.saltForm == current }) {
                    selectedSaltForm = nil
                }
            },
        )
    }

    /// Salt forms offered by the active route — drives the browse-time salt picker.
    private var activeSaltForms: [SaltVariant] {
        activeSubstanceRoute?.saltForms ?? []
    }

    /// The salt variant driving the dose card: the user's pick when valid, else
    /// the route's default (first) form. `nil` when the route has no salt dimension.
    private var activeSaltVariant: SaltVariant? {
        let forms = activeSaltForms
        if let selectedSaltForm, let match = forms.first(where: { $0.saltForm == selectedSaltForm }) {
            return match
        }
        return forms.first
    }

    /// Drives the salt ``SaltPicker``. Reads the active variant (the user's pick
    /// or the route's default) so the picker highlights the right form even when
    /// `selectedSaltForm` is still `nil` ("track the default"); writing records
    /// the explicit pick.
    private var saltSelection: Binding<String?> {
        Binding(
            get: { activeSaltVariant?.saltForm ?? activeSaltForms.first?.saltForm },
            set: { selectedSaltForm = $0 },
        )
    }

    // MARK: - Inventory stock card (2B)

    /// The tracked item for this substance, preferring the currently-selected
    /// salt, then the base form. Matched by canonical name (how stock is stored).
    private var trackedItem: InventoryItem? {
        let name = baseSubstance.name.lowercased()
        let matches = inventoryItems.filter { $0.substance.lowercased() == name }
        return matches.first { $0.saltForm == selectedSaltForm }
            ?? matches.first { $0.saltForm == nil }
            ?? matches.first
    }

    /// Rich stock card below Dose & Duration: amount, doses-left, supply bar, and
    /// run-out when tracked; a quiet "Not tracked · Track" row otherwise.
    private var inventoryStockSection: some View {
        Section {
            if let item = trackedItem {
                trackedStockCard(item)
            } else {
                HStack {
                    Text("Not tracked")
                        .foregroundStyle(Theme.secondaryLabel)
                    Spacer()
                    Button("Track") {
                        navigator.present(.inventoryItemForm(
                            id: nil,
                            prefillSubstance: baseSubstance.name,
                            prefillSalt: selectedSaltForm,
                        ))
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.accent)
                }
            }
        } header: {
            HStack {
                Text("Inventory")
                Spacer()
                Button { showAllInventory = true } label: {
                    HStack(spacing: 2) {
                        Text("Show All")
                        Image(systemName: "chevron.right").font(.caption2)
                    }
                    .font(.subheadline)
                    .foregroundStyle(Theme.accent)
                    .textCase(nil)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func trackedStockCard(_ item: InventoryItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            StockAmountText(item: item, style: .title2)
            if let subtitle = stockSubtitle(item) {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            if let fraction = item.fillFraction {
                InventorySupplyBar(fraction: fraction, tint: item.stockStatus.barTint)
            }
            if let runOut = InventoryMath.runOut(for: item, in: modelContext) {
                Text(inventoryRunOutLine(for: item, runOut: runOut))
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            if hasUnitMismatch(item) {
                Label("Doses in other units aren't counted.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            Button("Restock") {
                navigator.present(.inventoryItemForm(id: item.id))
            }
            .buttonStyle(.bordered)
            .tint(Theme.accent)
        }
        .padding(.vertical, 4)
    }

    /// "Glycinate · ~3 doses left" — salt and/or doses-left, whichever apply.
    private func stockSubtitle(_ item: InventoryItem) -> String? {
        var parts: [String] = []
        if let salt = item.saltForm, !salt.isEmpty { parts.append(salt) }
        if let doses = InventoryMath.dosesLeft(for: item) {
            parts.append(String(localized: "~\(doses) doses left"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// True when any matching dose can't be converted into the item's unit, so
    /// the card can show a calm "not counted" hint.
    private func hasUnitMismatch(_ item: InventoryItem) -> Bool {
        InventoryMath.doses(for: item, in: modelContext).contains {
            InventoryMath.convert($0.amount, from: $0.unit, to: item.unit) == nil
        }
    }

    /// Dose ladder + duration for the selected route, behind a segmented route
    /// switcher when more than one route applies. Surfaced near the top of the
    /// detail view — the primary thing people open a substance for. One
    /// consolidated card per route replaces the old two-sections-per-route
    /// stack, so a multi-route compound reads in a single screenful.
    @ViewBuilder
    private var doseDurationSections: some View {
        if let route = activeSubstanceRoute {
            let salt = activeSaltVariant
            Section {
                if presentableRoutes.count > 1 {
                    routeChips
                        .listRowInsets(EdgeInsets(top: 20, leading: 20, bottom: 8, trailing: 20))
                        .listRowSeparator(.hidden)
                }
                if activeSaltForms.count > 1 {
                    SaltPicker(
                        forms: activeSaltForms.map(\.saltForm),
                        selection: saltSelection,
                        style: .formRow,
                    )
                    .listRowSeparator(.hidden)
                }

                RouteDosingCard(
                    route: route.route,
                    unit: salt?.unit ?? route.unit,
                    doses: salt?.doses ?? route.doses,
                    duration: durationVisible ? (salt?.duration ?? route.duration) : nil,
                    releaseWindow: route.durationOfAction?.formattedWindow,
                    elementalFraction: salt?.elementalFraction,
                    showsDoseLadder: displayClass.showsDoseLadder,
                    showsDuration: durationVisible,
                    showsTitle: false,
                )
                .listRowSeparator(.hidden)

                // One source line: dose + duration usually share a source (and a
                // deep link), so collapse to a single row when they match.
                let doseSlug = displayClass.showsDoseLadder && route.doses.hasAnyValue ? doseSourceSlug(for: route.route) : nil
                let durSlug = durationVisible && route.duration != nil ? durationSourceSlug(for: route.route) : nil
                if let doseSlug, doseSlug == durSlug {
                    SourceAttributionRow(slug: doseSlug, label: "Dose & Duration", deepLink: sourceDeepLink(doseSlug))
                } else {
                    if let doseSlug {
                        SourceAttributionRow(slug: doseSlug, label: "Dose data", deepLink: sourceDeepLink(doseSlug))
                    }
                    if let durSlug {
                        SourceAttributionRow(slug: durSlug, label: "Duration data", deepLink: sourceDeepLink(durSlug))
                    }
                }
            } header: {
                Text("Dose & Duration")
            }
        }
    }

    /// Horizontal capsule selector for routes — replaces the segmented/menu
    /// picker. Reads clearly even with many routes (it scrolls) and the active
    /// route is unmistakable.
    private var routeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(presentableRoutes, id: \.route) { r in
                    let isOn = activeSubstanceRoute?.route == r.route
                    Button {
                        routeSelection.wrappedValue = r.route
                    } label: {
                        Text(r.route.localizedName)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(isOn ? Color.white : Color.primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(isOn ? Theme.accent : Color(.tertiarySystemFill)),
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Renders the current route's dose/duration card to a shareable image and
    /// opens the system share sheet. Mirrors the day-log camera export.
    @MainActor
    private func generateShareImage() {
        guard let route = activeSubstanceRoute else { return }
        let card = SubstanceShareCard(
            substance: substance,
            route: route,
            showsDoseLadder: displayClass.showsDoseLadder,
            showsDuration: durationVisible,
        )
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3 // @3x — crisp regardless of device
        if let image = renderer.uiImage {
            ShareSheetPresenter.present(image)
        }
    }

    /// Unified provenance: the **databases** that contributed this compound's
    /// data (deep-linked to their page for it) followed by the **primary
    /// literature** (DOIs / PMIDs / URLs as tappable links, free-text labels as
    /// plain text). Merged into one disclosure — they used to read as two
    /// near-identical "Sources"/"References" sections.
    @ViewBuilder private var sourcesAndReferencesSection: some View {
        let links = mergedSourceLinks
        if policy.showsSources, !links.isEmpty {
            Section {
                ForEach(links) { link in
                    if let url = link.url {
                        Link(destination: url) {
                            sourceLinkRow(link, linked: true)
                        }
                    } else {
                        sourceLinkRow(link, linked: false)
                    }
                }
            } header: {
                Text("Sources")
            } footer: {
                Text("Each link opens this substance's page on that source. Always verify against the original.")
            }
        }
    }

    /// The merged, de-duplicated provenance list: the databases that contributed
    /// this compound's data followed by any primary literature, each deep-linked
    /// to the substance's own page where one exists. Used to be two near-identical
    /// "Databases" / "References" subsections; collapsed into one tappable list.
    private var mergedSourceLinks: [DetailSourceLink] {
        var seenURLs = Set<String>()
        var out: [DetailSourceLink] = []
        func add(label: String, url: URL?) {
            // The same work can arrive as both a database row and a citation
            // (e.g. TiHKAL — the source only knows the book's homepage, the
            // citation has this substance's chapter). Dedup by display label,
            // and let a *linked* candidate upgrade an already-added bare-text
            // one so the chapter URL wins over the missing homepage.
            let labelKey = label.lowercased()
            if let idx = out.firstIndex(where: { $0.label.lowercased() == labelKey }) {
                if out[idx].url == nil, let url {
                    seenURLs.insert(url.absoluteString)
                    out[idx] = DetailSourceLink(label: out[idx].label, url: url)
                }
                return
            }
            if let url {
                if seenURLs.contains(url.absoluteString) { return }
                seenURLs.insert(url.absoluteString)
            }
            out.append(DetailSourceLink(label: label, url: url))
        }
        // `substance.sources` holds wire slugs ("peer-review-primary",
        // "tripsit") — map each to a human source name and its per-substance page.
        for slug in substance.sources {
            add(label: sourceLabel(forSlug: slug), url: sourceDeepLink(slug))
        }
        for ref in substance.references {
            add(label: friendlyReferenceLabel(ref), url: ref.resolvedURL)
        }
        return out
    }

    /// Human-readable name for a source slug — preferring the clean website
    /// names in ``AppSources`` (PubMed, TripSit…), falling back to the bundled
    /// `sources` table's display name (drug.community, Wikidata…).
    private func sourceLabel(forSlug slug: String) -> String {
        if let name = AppSources.slugToName[slug] { return name }
        return SubstanceStore.shared.sourceDisplayName(forSlug: slug)
    }

    /// A tidy display name for a citation that lacks a title — the bare URL
    /// (the old `Citation.label` fallback) reads as clutter, so name the work
    /// (TiHKAL / PiHKAL) when recognisable, else show the host.
    private func friendlyReferenceLabel(_ ref: Citation) -> String {
        if let title = ref.title, !title.isEmpty { return title }
        if let doi = ref.doi, !doi.isEmpty { return "DOI \(doi)" }
        if let pmid = ref.pmid { return "PMID \(pmid)" }
        if let urlString = ref.url?.lowercased() {
            if urlString.contains("tihkal") { return "TiHKAL" }
            if urlString.contains("pihkal") { return "PiHKAL" }
        }
        if let host = ref.resolvedURL?.host() {
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        return ref.label
    }

    private func sourceLinkRow(_ link: DetailSourceLink, linked: Bool) -> some View {
        HStack(spacing: 8) {
            Text(link.label)
                .font(.subheadline)
                .foregroundStyle(linked ? Color.primary : Theme.secondaryLabel)
            Spacer()
            if linked {
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
            }
        }
    }

    /// Peptide / protocol-dosed compounds: clinical-protocol schedule,
    /// reconstitution calculator, and handling/storage — surfaced in place of
    /// the (suppressed) trip-intensity ladder and duration timeline.
    @ViewBuilder private var peptideSections: some View {
        ForEach(substance.routes, id: \.route) { substanceRoute in
            if let pd = substanceRoute.protocolDosing {
                Section("Protocol — \(String(localized: substanceRoute.route.localizedName))") {
                    ProtocolDosingCard(unit: substanceRoute.unit, protocolDosing: pd)
                }
            }
        }

        if let pp = substance.peptideProfile {
            if pp.suppliedForm?.isReconstituted == true {
                Section("Reconstitution calculator") {
                    ReconstitutionCalculatorView(defaultVialMg: pp.typicalVialMg)
                }
            }
            if pp.hasAnyValue {
                Section("Handling & storage") {
                    PeptideHandlingCard(profile: pp, molarMass: substance.molarMass)
                    if let solvent = pp.reconstitutionSolvent {
                        LabeledContent("Reconstitute with") { Text(solvent) }
                            .font(.subheadline)
                    }
                }
            }
        }
    }

    /// The contextual status banner shown above reference content. Peptides and
    /// protocol-dosed performance compounds get framing appropriate to them
    /// instead of the generic "ask your doctor" prescription notice.
    @ViewBuilder private var statusBanner: some View {
        if substance.usesPeptidePresentation {
            banner(
                title: "Peptide — protocol reference",
                systemImage: "syringe.fill",
                tint: .blue,
                message: "Dosing shown reflects clinical or community research protocols, not medical advice. Peptides are injected from reconstituted powder — handle and store as noted below.",
            )
        } else if displayClass == .medicalRx || displayClass == .nonRecreational {
            if substance.primaryProtocolDosing != nil {
                banner(
                    title: "Research / performance compound",
                    systemImage: "flask.fill",
                    tint: .orange,
                    message: "The protocol below reflects community or investigational use, not validated human dosing or medical advice. Many of these compounds are WADA-prohibited and lack human safety data.",
                )
            } else {
                banner(
                    title: displayClass == .medicalRx ? "Prescription medication" : "Medical information only",
                    systemImage: "cross.case.fill",
                    tint: .blue,
                    message: "Dosing for this medication is determined by a healthcare provider and is not shown here. The information below is for recognition and reference only.",
                )
            }
        } else if substance.hasNoDoseData {
            banner(
                title: "Limited human data",
                systemImage: "exclamationmark.triangle.fill",
                tint: .orange,
                message: "This compound has no validated human dose data. Information below is for reference only — see the linked sources for primary literature. Do not extrapolate doses from related compounds.",
            )
        }
    }

    /// Plays along with an in-joke entry (PsychonautWiki's "🍰 Cake"). The emoji
    /// is off the title now — so the gag lives here, deadpan, while making plain
    /// the thing is fictional (this is a harm-reduction app; nobody should go
    /// sourcing "Cake").
    @ViewBuilder private var jokeBanner: some View {
        if let emoji = substance.titlePictograph {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(emoji)
                        Text("Made-up drug")
                            .font(.subheadline.weight(.semibold))
                    }
                    Text("A fictional drug from a 1997 TV satire on media drug panics — “Cake” isn’t real, and nothing below is either. It supposedly overstimulates “Shatner’s Bassoon,” the part of the brain that governs time. Made in Prague.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func banner(title: LocalizedStringResource, systemImage: String, tint: Color, message: LocalizedStringResource) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
        }
    }

    /// Name / aliases / route / chemistry — demoted below dosing and collapsed.
    /// Chemists who want the full identity follow the PubChem link.
    private var infoDisclosure: some View {
        CollapsibleSection("Additional Info", systemImage: "info.circle", isExpanded: $infoExpanded) {
            let extras = infoExtraCells
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 14) {
                GridRow {
                    gridCell("Category", String(localized: substance.category.displayName))
                    gridCell("Default route", String(localized: substance.defaultRoute.localizedName))
                }
                if !extras.isEmpty {
                    GridRow {
                        gridCell(extras[0].0, extras[0].1)
                        if extras.count > 1 { gridCell(extras[1].0, extras[1].1) } else { Color.clear }
                    }
                }
            }
            .padding(.vertical, 4)

            if !substance.displayAliases.isEmpty {
                aliasChips
            }
            if !substance.tags.isEmpty {
                SubstanceTagFlow(tags: substance.tags, accent: substance.category.color)
                    .padding(.vertical, 4)
            }
            if let slug = provenance?.categorySource {
                SourceAttributionRow(
                    slug: slug,
                    label: "Category",
                    deepLink: sourceDeepLink(slug),
                )
            }
            if let slug = provenance?.halfLifeSource, substance.halfLifeMinutes != nil {
                SourceAttributionRow(
                    slug: slug,
                    label: "Half-life",
                    deepLink: sourceDeepLink(slug),
                )
            }
        }
    }

    /// Optional second-row identity cells — availability and (benzodiazepines
    /// only) the cross-benzo diazepam equivalent. Empty for most compounds.
    private var infoExtraCells: [(LocalizedStringResource, String)] {
        var cells: [(LocalizedStringResource, String)] = []
        if let reg = substance.regulatoryStatus {
            cells.append(("Availability", regulatoryDisplay(reg)))
        }
        if displayClass.showsDoseLadder, let dz = substance.diazepamEquivalent, let text = dz.displayText {
            cells.append(("Diazepam equivalent", text))
        }
        return cells
    }

    /// Aliases as a wrapping chip flow, collapsed to the first few with a
    /// "+N more" chip — a long comma list was a single over-tall row before.
    private var aliasChips: some View {
        let all = substance.displayAliases
        let limit = 5
        let shown = aliasesExpanded ? all : Array(all.prefix(limit))
        let hidden = all.count - shown.count
        return VStack(alignment: .leading, spacing: 7) {
            Text("Also known as")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
                .textCase(.uppercase)
            FlowLayout(spacing: 6) {
                ForEach(shown, id: \.self) { alias in
                    aliasChip(Text(alias))
                        .textSelection(.enabled)
                }
                if hidden > 0 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { aliasesExpanded = true }
                    } label: {
                        aliasChip(Text("+\(hidden) more"), accent: true)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func aliasChip(_ text: Text, accent: Bool = false) -> some View {
        text
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(accent ? Theme.accent.opacity(0.12) : Color(.tertiarySystemFill), in: Capsule())
            .foregroundStyle(accent ? Theme.accent : Theme.secondaryLabel)
    }

    var body: some View {
        List {
            Group {
                if !historyEntries.isEmpty {
                    historySection
                }

                doseDurationSections

                inventoryStockSection

                peptideSections

                if let notes = personalOverride?.notes,
                   !notes.trimmingCharacters(in: .whitespaces).isEmpty {
                    Section("Your Notes") {
                        Text(notes)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                statusBanner
                jokeBanner

                overviewSection

                // Effects — curated summary + grouped "All effects" navigation.
                effectsSection

                // Unified Pharmacology card — merges the former Mechanism-of-Action and
                // Monoamine-Profile sections (hybrid redesign step 2). The monoamine slider hero
                // appears inline when the substance has a monoamine profile.
                if policy.showsMechanism, let moa = composedMechanism {
                    CollapsibleSection(
                        "Pharmacology",
                        systemImage: "atom",
                        onInfo: { glossaryTopic = .mechanism },
                        isExpanded: Binding(
                            get: { mechanismExpanded ?? policy.mechanismDefaultExpanded },
                            set: { mechanismExpanded = $0 },
                        ),
                    ) {
                        PharmacologyCard(moa: moa, monoamine: monoamineProfile, category: substance.category, hero: pharmacologyHero)
                        if let slug = provenance?.mechanismSource {
                            SourceAttributionRow(
                                slug: slug,
                                label: "Mechanism",
                                deepLink: sourceDeepLink(slug),
                            )
                        }
                    }
                }

                // Suppressed for receptor-panel classes (opioid/benzo/dissociative): their hero already
                // carries the primary receptors, so a second table would duplicate it.
                if policy.showsReceptorLiterature, pharmacologyHero == nil, !visibleLiteratureBindings.isEmpty {
                    CollapsibleSection(
                        "Receptor Literature",
                        systemImage: "function",
                        onInfo: { glossaryTopic = .receptor },
                        isExpanded: Binding(
                            get: { receptorLitExpanded ?? policy.receptorLitDefaultExpanded },
                            set: { receptorLitExpanded = $0 },
                        ),
                    ) {
                        receptorLiteratureBody
                    }
                }

                if policy.showsPharmacokinetics, !pkRoutes.isEmpty {
                    CollapsibleSection(
                        "Pharmacokinetics",
                        systemImage: "waveform.path.ecg",
                        onInfo: { glossaryTopic = .pharmacokinetics },
                        isExpanded: Binding(
                            get: { pharmacokineticsExpanded ?? policy.pharmacokineticsDefaultExpanded },
                            set: { pharmacokineticsExpanded = $0 },
                        ),
                    ) {
                        pharmacokineticsBody
                    }
                }

                // Metabolism (CYP enzymes / metabolites) — split out of Pharmacokinetics into its own
                // section and placed next to the metabolic-interaction banners below: it's the more
                // actionable, grapefruit-adjacent half of the PK story.
                if policy.showsPharmacokinetics, !metabolismRows.isEmpty {
                    CollapsibleSection(
                        "Metabolism",
                        systemImage: "arrow.triangle.branch",
                        onInfo: { glossaryTopic = .metabolism },
                        isExpanded: Binding(
                            get: { metabolismExpanded ?? policy.pharmacokineticsDefaultExpanded },
                            set: { metabolismExpanded = $0 },
                        ),
                    ) {
                        metabolismBody
                    }
                }

                // Metabolic modulation (Stage 4c) — grapefruit/smoking/self-edge education for
                // substances with a major clearance route through a modulated enzyme.
                if !metabolicEducation.isEmpty {
                    Section {
                        ForEach(metabolicEducation) { effect in
                            MetabolicModulationBanner(effect: effect)
                        }
                    } header: {
                        // Not "fork.knife" — smoking and enzyme induction aren't eating; an up/down glyph
                        // reads as "these change the drug's levels". Trailing (i) explains the section.
                        sectionHeaderWithInfo(
                            "Metabolism Interactions",
                            systemImage: "arrow.up.arrow.down",
                            topic: .metabolismInteractions,
                        )
                    }
                }

                // Enzyme-induction contraceptive caution — a CYP3A4 inducer (modafinil, rifampicin, …)
                // can lower hormonal-contraception levels. Ungated (a safety fact), kept to one compact
                // note since it only applies to people on hormonal birth control.
                if let contraceptionCaution {
                    Section {
                        ContraceptionCautionBanner(inducer: contraceptionCaution)
                    }
                }

                // Medical context (indications / contraindications / boxed warnings)
                // — shown for any compound that has clinical data. Net-new surface.
                medicalInfoSection

                // Identity (name / aliases / route) — collapsed by default.
                infoDisclosure

                // Chemistry numbers — folded into their own collapsed disclosure.
                chemistryDisclosure

                sourcesAndReferencesSection
            }
            .listRowBackground(Theme.cardBackground)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(substance.displayTitle)
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(isPresented: $showAllEffects) {
            AllEffectsView(substanceName: substance.name, showsExperienceReports: showsErowidReports)
        }
        .sheet(item: $glossaryTopic) { topic in
            PharmacologyGlossarySheet(topic: topic)
        }
        .navigationDestination(isPresented: $showAllInventory) {
            InventoryListView()
        }
        .toolbar {
            if activeSubstanceRoute != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        generateShareImage()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(Theme.accent)
                    }
                    .accessibilityLabel("Share drug info")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    toggleFavorite()
                } label: {
                    // Favorited keeps its semantic gold; the resting state shares
                    // the accent tint with the other bar buttons.
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .foregroundStyle(isFavorite ? Color.yellow : Theme.accent)
                }
                .accessibilityLabel(isFavorite ? "Remove from Favorites" : "Add to Favorites")
            }
            ToolbarItem(placement: .topBarTrailing) {
                // No override yet → open personalization directly (a one-item
                // menu was pointless). With an override, offer Edit + Reset.
                if let override = personalOverride {
                    Menu {
                        Button {
                            navigator.present(.personalizeSubstance(name: baseSubstance.name))
                        } label: {
                            Label("Edit Personalization…", systemImage: "slider.horizontal.3")
                        }
                        Button(role: .destructive) {
                            customStore.delete(override)
                        } label: {
                            Label("Reset Personalization", systemImage: "arrow.uturn.backward")
                        }
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(Theme.accent)
                    }
                    .accessibilityLabel("Personalize substance")
                } else {
                    Button {
                        navigator.present(.personalizeSubstance(name: baseSubstance.name))
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(Theme.accent)
                    }
                    .accessibilityLabel("Personalize substance")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                // Detail-level (tier) switcher — makes the Casual / Curious / Pharma-Nerd
                // density switchable in place instead of buried in Settings.
                Menu {
                    Picker("Detail level", selection: Binding(
                        get: { profile },
                        set: { profileStore.setDisclosureTier($0) },
                    )) {
                        ForEach(UserProfile.allCases) { tier in
                            Label(tier.displayName, systemImage: tier.icon).tag(tier)
                        }
                    }
                } label: {
                    Image(systemName: profile.icon)
                        .foregroundStyle(Theme.accent)
                }
                .accessibilityLabel("Detail level")
            }
        }
        .task(id: TaskKey(substanceName: substance.name, profile: profile)) {
            // Always fetch provenance — per-field source attribution is
            // shown to every tier so users can see where each fact came from.
            provenance = store.provenance(forSubstanceName: substance.name)

            // Contraceptive-efficacy caution — a CYP3A4 inducer (modafinil, rifampicin, …) can lower
            // hormonal-contraception levels. Ungated like a boxed warning: a safety fact for every tier.
            contraceptionCaution = MetabolicModulation.contraceptiveEfficacyCaution(forSubstance: substance.name)

            // Binding rows feed two surfaces: the pharma-nerd "Receptor Literature" list AND the
            // broader harm-reduction "Monoamine Profile" card (DA↔5-HT character, releaser/blocker,
            // valvulopathy / mis-sold-as-MDMA flags). The card loads for the mechanism audience (like
            // the metabolic-education surface), so fetch once when either surface is shown.
            if policy.showsMechanism || policy.showsReceptorLiterature {
                let binds = store.bindings(forSubstanceName: substance.name)
                monoamineProfile = MonoamineProfile.from(bindings: binds, substanceName: substance.name)
                // Loaded for the mechanism audience too (not just pharma-nerd): the unified card's
                // class hero (opioid/benzo/dissociative receptor panel) is built from these rows.
                literatureBindings = binds
            } else {
                monoamineProfile = nil
                literatureBindings = []
            }

            // Pharmacokinetics (per-route PK + CYP metabolism) is likewise a
            // pharma-nerd surface — skip the two queries for other tiers.
            if policy.showsPharmacokinetics {
                pkRoutes = store.pharmacokinetics(forSubstanceName: substance.name)
                metabolismRows = store.metabolism(forSubstanceName: substance.name)
            } else {
                pkRoutes = []
                metabolismRows = []
            }

            // Grapefruit/smoking/self-edge education is harm-reduction-relevant, so it loads for
            // non-casual tiers from its own metabolism fetch (the full PK table above stays pharma-nerd).
            if policy.showsMechanism {
                let rows = policy.showsPharmacokinetics ? metabolismRows : store.metabolism(forSubstanceName: substance.name)
                metabolicEducation = MetabolicModulation.educationalEffects(forSubstance: substance.name, metabolism: rows)
            } else {
                metabolicEducation = []
            }
        }
        .task(id: baseSubstance.name) {
            // Upgrade the pushed shell to the full resolved record off the push.
            upgradeToFullRecord()
        }
        .task(id: historySignature) {
            rebuildHistoryStats()
        }
        .onChange(of: profile) { _, _ in
            // Reset stuck Bool? overrides so the new tier's policy defaults
            // win. Any disclosure the user touches after this point sticks
            // until the next profile change.
            mechanismExpanded = nil
            receptorLitExpanded = nil
            pharmacokineticsExpanded = nil
        }
    }

    private struct TaskKey: Hashable {
        let substanceName: String
        let profile: UserProfile
    }

    private struct HistoryStats {
        var minDose: Double = 0
        var maxDose: Double = 0
        var mostCommon: Double = 0
    }

    /// Cheap content fingerprint of the dose history — membership plus the
    /// amounts the aggregates depend on, so an in-place edit invalidates too.
    private var historySignature: Int {
        var hasher = Hasher()
        for entry in historyEntries {
            hasher.combine(entry.persistentModelID)
            hasher.combine(entry.amount)
        }
        return hasher.finalize()
    }

    private func rebuildHistoryStats() {
        let amounts = historyEntries.map(\.amount)
        var freq: [Double: Int] = [:]
        for a in amounts {
            freq[a, default: 0] += 1
        }
        historyStats = HistoryStats(
            minDose: amounts.min() ?? 0,
            maxDose: amounts.max() ?? 0,
            mostCommon: freq.max(by: { $0.value < $1.value })?.key ?? 0,
        )
    }

    // MARK: - Source attribution

    /// Deep link for a source-attribution row. drug.community's `/drug/<slug>`
    /// page resolves only the canonical slug captured at build time (no alias
    /// fallback), so it can't be derived from the app's name; every other source
    /// deep-links from the substance name via ``AppSources``.
    private func sourceDeepLink(_ slug: String) -> URL? {
        if slug == "drug.community" {
            guard let dc = substance.drugCommunitySlug else { return nil }
            return URL(string: "https://drug.community/drug/\(dc)")
        }
        // FreeOD Wiki pages are titled in Chinese, so deep-link the captured
        // page slug rather than the app's (English) substance name.
        if slug == "freeodwiki" {
            return AppSources.freeodwikiURL(slug: substance.freeodwikiSlug)
        }
        // The Shulgin books (PiHKAL/TiHKAL) only have a book homepage, not a
        // per-substance page. The citation carries the real chapter link, so
        // don't offer the misleading homepage — `mergedSourceLinks` upgrades the
        // bare "TiHKAL" row to the citation's chapter URL.
        if slug == "erowid-pihkal" || slug == "erowid-tihkal" { return nil }
        return AppSources.substanceURL(forSlug: slug, substance: substance.name)
    }

    private func doseSourceSlug(for route: RouteOfAdministration) -> String? {
        provenance?.routesBySource[route]?.doseSource
    }

    private func durationSourceSlug(for route: RouteOfAdministration) -> String? {
        provenance?.routesBySource[route]?.durationSource
    }

    // MARK: - Literature bodies

    /// The receptor rows worth showing: the 10 µM relevance cap. Drops a **Kᵢ-based** off-target binding
    /// ≥ 10,000 nM (the standard "no meaningful affinity" cutoff) — ketamine's σ/µ/κ, meth's σ2, MDMA's
    /// 12–15 µM modulators — *unless* it sits within 10× of the substance's tightest binding, so a
    /// substance whose primary targets are all weak (caffeine's matched A1/A2A adenosine pair) keeps them.
    /// EC₅₀/IC₅₀ functional transporter rows are never capped: a releaser's DAT EC₅₀ is legitimately tens
    /// of µM yet is the primary mechanism.
    private var visibleLiteratureBindings: [SubstanceStore.BindingHit] {
        let floor = literatureBindings
            .compactMap { [$0.kiNm, $0.ec50Nm, $0.ic50Nm].compactMap(\.self).min() }
            .min()
        let capped = literatureBindings.filter { hit in
            // Drop curated tier-only rows (no measured value) — they drive the MOA dot table, not this
            // literature list, and would otherwise render as empty rows.
            guard hit.kiNm != nil || hit.ec50Nm != nil || hit.ic50Nm != nil else { return false }
            guard let ki = hit.kiNm, ki >= 10_000 else { return true }
            if let floor, ki <= floor * 10 { return true }
            return false
        }
        // Strongest receptors first: by strength tier desc, then more-potent-first within a tier.
        return Self.dedupedLiterature(capped).sorted { lhs, rhs in
            let lt = strengthTier(for: lhs) ?? 0
            let rt = strengthTier(for: rhs) ?? 0
            if lt != rt { return lt > rt }
            let lv = lhs.kiNm ?? lhs.ec50Nm ?? lhs.ic50Nm ?? .greatestFiniteMagnitude
            let rv = rhs.kiNm ?? rhs.ec50Nm ?? rhs.ic50Nm ?? .greatestFiniteMagnitude
            return lv < rv
        }
    }

    /// Collapse the literature list: when a (target, action) has any **human** row, drop its non-human
    /// (in-vitro / animal) rows — "who cares about in vitro when we have human data" — then remove exact
    /// duplicate measurements (same target+action+value across sources), so MDMA's 5-HT2A 7800 ×2 and
    /// DAT 22000 ×2 collapse to one. Order is preserved (the store already sorts Kᵢ-tightest first, then
    /// functional EC₅₀/IC₅₀), so binding affinities still lead the functional transporter rows.
    private static func dedupedLiterature(_ rows: [SubstanceStore.BindingHit]) -> [SubstanceStore.BindingHit] {
        func isHuman(_ s: String?) -> Bool {
            (s ?? "").lowercased().contains("human")
        }
        let humanTAs = Set(rows.filter { isHuman($0.species) }.map { "\($0.target)|\($0.action)" })
        let preferred = rows.filter { hit in
            humanTAs.contains("\(hit.target)|\(hit.action)") ? isHuman(hit.species) : true
        }
        var seen = Set<String>()
        return preferred.filter { hit in
            let value = if let ki = hit.kiNm {
                "ki\(ki)"
            } else if let ec = hit.ec50Nm {
                "ec\(ec)"
            } else if let ic = hit.ic50Nm {
                "ic\(ic)"
            } else {
                "na"
            }
            return seen.insert("\(hit.target)|\(hit.action)|\(value)").inserted
        }
    }

    private var receptorLiteratureBody: some View {
        GroupedReceptorLiterature(rows: visibleLiteratureBindings, accent: substance.category.color)
            .padding(.vertical, 4)
    }

    /// Strength tier (1–3) for a literature row's dots — the single, systematic `ReceptorStrength`
    /// model (measurement-aware bands). The Mechanism card computes the *same* bands from the *same*
    /// measured values in SQL, so the two cards agree by construction (no per-target inheritance hack).
    private func strengthTier(for hit: SubstanceStore.BindingHit) -> Int? {
        ReceptorStrength.tier(kiNm: hit.kiNm, ec50Nm: hit.ec50Nm, ic50Nm: hit.ic50Nm)
    }

    /// A plain `Section` header (icon + title) with a trailing (i) that opens the card's help sheet —
    /// the equivalent of `CollapsibleSection`'s `onInfo` for the non-collapsible interaction sections.
    private func sectionHeaderWithInfo(
        _ title: LocalizedStringResource,
        systemImage: String,
        topic: PharmacologyGlossarySheet.Topic,
    ) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Button { glossaryTopic = topic } label: {
                Image(systemName: "info.circle")
                    .foregroundStyle(Theme.accent)
                    .textCase(nil)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("What do these mean?")
        }
    }

    /// Per-route PK (bioavailability/tmax/half-life) above the CYP metabolism
    /// pathways, each row carrying its own source/citation. Mirrors the Receptor
    /// Literature layout — dense, attributed, pharma-nerd-only.
    private var pharmacokineticsBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(pkRoutes) { hit in
                PKRouteRow(hit: hit, accent: substance.category.color)
                if hit.id != pkRoutes.last?.id { Divider() }
            }
        }
        .padding(.vertical, 4)
    }

    /// The CYP/enzyme clearance pathways and their metabolites — its own section now, sitting next to the
    /// grapefruit/smoking interaction banners (which act on these same enzymes).
    private var metabolismBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(metabolismRows) { hit in
                MetabolismRow(hit: hit, accent: substance.category.color)
                if hit.id != metabolismRows.last?.id { Divider() }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - History

    @ViewBuilder
    private var historySection: some View {
        let entries = historyEntries
        let count = entries.count
        let minDose = historyStats.minDose
        let maxDose = historyStats.maxDose
        let mostCommon = historyStats.mostCommon
        let unit = entries.first?.unit ?? substance.defaultUnit

        // Date range
        let earliest = entries.last?.timestamp
        let latest = entries.first?.timestamp

        Section("Your History") {
            DisclosureGroup(isExpanded: $showEntries) {
                let displayEntries = showAllHistory ? entries : Array(entries.prefix(10))
                ForEach(displayEntries) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(entry.amount.doseFormatted) \(entry.unit)")
                                .font(.subheadline)
                            Text(entry.route.localizedName)
                                .font(.caption2)
                                .foregroundStyle(Theme.secondaryLabel)
                        }
                        Spacer()
                        Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                }
                if entries.count > 10, !showAllHistory {
                    Button {
                        showAllHistory = true
                    } label: {
                        Text("Show all \(entries.count) entries")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                    }
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("^[\(count) entry](inflect: true)")
                            .font(.subheadline.weight(.medium))
                        if let earliest, let latest {
                            if Calendar.current.isDate(earliest, equalTo: latest, toGranularity: .month) {
                                Text(earliest.formatted(.dateTime.month(.wide).year()))
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryLabel)
                            } else {
                                Text("\(earliest.formatted(.dateTime.month(.abbreviated).year())) – \(latest.formatted(.dateTime.month(.abbreviated).year()))")
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryLabel)
                            }
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        if minDose == maxDose {
                            Text("\(minDose.doseFormatted) \(unit)")
                                .font(.subheadline.weight(.medium))
                        } else {
                            Text("\(minDose.doseFormatted) – \(maxDose.doseFormatted) \(unit)")
                                .font(.subheadline.weight(.medium))
                        }
                        Text("Most common: \(mostCommon.doseFormatted) \(unit)")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                }
            }
        }
    }
}

// MARK: - Source Attribution

/// One row in the merged "Sources" list — a contributing database or a piece of
/// primary literature, deep-linked to this substance's page where one exists.
private struct DetailSourceLink: Identifiable {
    let id = UUID()
    let label: String
    let url: URL?
}

/// Small inline badge that names the source that supplied a specific field
/// after source-priority resolution. Visible to all tiers so users always see
/// where each fact came from — the per-field counterpart to the
/// substance-level "Sources" disclosure at the bottom of the detail view.
///
/// The displayed source name is resolved from the bundled `sources` table
/// via ``SubstanceStore/sourceDisplayName(forSlug:)`` so users see the
/// human-readable name ("TripSit factsheets") instead of the wire slug
/// ("tripsit").
/// The one folded-section look used across the whole substance screen — a
/// `DisclosureGroup` with a semibold subheadline label, a leading SF Symbol, and
/// an optional count badge. Extracted so Mechanism, Receptor Literature, Info,
/// Chemistry and the Cautions list fold identically. Crucially, a section's
/// source-attribution row goes *inside* `content` so it collapses with the body
/// rather than dangling beneath a closed disclosure.
private struct CollapsibleSection<Content: View>: View {
    let title: LocalizedStringResource
    let systemImage: String
    var count: Int?
    /// When set, a trailing (i) button appears in the header that runs this action — used to open a
    /// plain-language help sheet for the denser cards. Borderless so it captures its own tap and
    /// doesn't also toggle the disclosure.
    var onInfo: (() -> Void)?
    @Binding var isExpanded: Bool
    @ViewBuilder var content: () -> Content

    init(
        _ title: LocalizedStringResource,
        systemImage: String,
        count: Int? = nil,
        onInfo: (() -> Void)? = nil,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content,
    ) {
        self.title = title
        self.systemImage = systemImage
        self.count = count
        self.onInfo = onInfo
        _isExpanded = isExpanded
        self.content = content
    }

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $isExpanded) {
                content()
            } label: {
                HStack(spacing: 6) {
                    Label(title, systemImage: systemImage)
                        .font(.subheadline.weight(.semibold))
                    if let count {
                        Text(verbatim: "\(count)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.secondaryLabel)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Theme.secondaryLabel.opacity(0.12), in: Capsule())
                    }
                    if let onInfo {
                        Spacer(minLength: 0)
                        Button(action: onInfo) {
                            Image(systemName: "info.circle")
                                .font(.subheadline)
                                .foregroundStyle(Theme.accent)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("What do these mean?")
                    }
                }
            }
        }
    }
}

private struct SourceAttributionRow: View {
    let slug: String
    let label: LocalizedStringResource
    /// When set, the row becomes a tappable link to the source's page for this
    /// substance. Without it (a source with no deep link), it renders as plain
    /// attribution text.
    var deepLink: URL?

    private var displayName: String {
        SubstanceStore.shared.sourceDisplayName(forSlug: slug)
    }

    private var rowContent: some View {
        let linked = deepLink != nil
        return HStack(spacing: 6) {
            Image(systemName: linked ? "checkmark.seal.fill" : "checkmark.seal")
                .font(.caption2)
                .foregroundStyle(linked ? Theme.accent : Theme.secondaryLabel)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
            Text("·")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
            Text(displayName)
                .font(.caption2)
                .foregroundStyle(linked ? Theme.accent : Theme.secondaryLabel)
            if linked {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            Spacer()
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(String(localized: label)), source: \(displayName)"))
    }

    var body: some View {
        if let deepLink {
            Link(destination: deepLink) { rowContent }
        } else {
            rowContent
        }
    }
}

// MARK: - All Effects

/// The full PsychonautWiki effect taxonomy for a substance, grouped under
/// category headers. Pushed from the detail view's Effects disclosure so the
/// ~60-term list never clutters the main screen.
private struct AllEffectsView: View {
    let substanceName: String
    /// Show the Erowid "Experience reports" group at the bottom — gated to
    /// recreational / dual-use compounds, where first-hand reports exist.
    var showsExperienceReports = false
    @State private var groups: [SubstanceStore.EffectGroup] = []

    var body: some View {
        List {
            ForEach(groups) { group in
                Section {
                    ForEach(group.effects, id: \.self) { effect in
                        Text(effect)
                            .font(.subheadline)
                    }
                } header: {
                    Text(LocalizedStringKey(group.category))
                }
                .listRowBackground(Theme.cardBackground)
            }

            // Erowid lives here as its own group rather than crowding the
            // detail screen's curated Effects card. We can't link a specific
            // page or show a count (Erowid blocks automated access), but a
            // search always opens for the user in their browser.
            if showsExperienceReports, let erowid = AppSources.erowidSearchURL(substance: substanceName) {
                Section {
                    Link(destination: erowid) {
                        Label("Search experiences on Erowid", systemImage: "magnifyingglass")
                            .font(.subheadline)
                    }
                } header: {
                    Text("Experience reports")
                } footer: {
                    Text("First-hand reports from Erowid's Experience Vaults. Opens a search in your browser.")
                }
                .listRowBackground(Theme.cardBackground)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Effects")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: substanceName) {
            groups = SubstanceStore.shared.effectsByCategory(forSubstanceName: substanceName)
        }
    }
}

// MARK: - Shareable Drug-Info Card

/// The dark-themed card rendered to an image when the user shares a substance's
/// dosing. Reuses ``RouteDosingCard`` so the shared image matches what's on
/// screen; self-contained (no environment) so `ImageRenderer` can draw it.
private struct SubstanceShareCard: View {
    let substance: Substance
    let route: SubstanceRoute
    let showsDoseLadder: Bool
    let showsDuration: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text(substance.displayTitle)
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                HStack(spacing: 8) {
                    Circle()
                        .fill(substance.category.color)
                        .frame(width: 10, height: 10)
                    Text(substance.category.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            RouteDosingCard(
                route: route.route,
                unit: route.unit,
                doses: route.doses,
                duration: showsDuration ? route.duration : nil,
                releaseWindow: route.durationOfAction?.formattedWindow,
                showsDoseLadder: showsDoseLadder,
                showsDuration: showsDuration,
                showDisclaimers: false,
                showsTitle: true,
            )
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 20).fill(Color(white: 0.10)))

            Text("Generated by Piru · kagerou.glass/piru")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.35))
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(24)
        .frame(width: 390, alignment: .leading)
        .background(Color(white: 0.04))
        .environment(\.colorScheme, .dark)
    }
}

/// Presents a system share sheet for the rendered drug-info image.
///
/// `UIActivityViewController` is presented directly from the active window's
/// top view controller rather than embedded in a SwiftUI `.sheet`: hosting it
/// inside a sheet (especially with `presentationDetents`) renders an empty
/// sheet that only fills in seconds later, because the activity controller is
/// itself a presentation controller and doesn't lay out as a child.
private enum ShareSheetPresenter {
    @MainActor
    static func present(_ image: UIImage) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
            let root = (scene.keyWindow ?? scene.windows.first)?.rootViewController
        else { return }

        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }

        let activityVC = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        // Anchor the popover on iPad / Mac Catalyst so it has a valid source.
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        top.present(activityVC, animated: true)
    }
}

// MARK: - Receptor Literature Row

// Single binding row inside the pharma-nerd "Receptor Literature" disclosure.
// Each row shows the target, action, Ki or EC50 value, optional species,
// source slug, and a PMID/DOI affordance so the user can verify the claim.

// MARK: - Substance Tag Flow

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
