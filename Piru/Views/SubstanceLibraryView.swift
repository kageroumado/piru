import SwiftData
import SwiftUI
import UIKit

struct SubstanceLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var searchText: String

    /// When embedded in the Search tab: drop the "Library" header + category
    /// browse, showing only recent substances (empty) or results (typed).
    var isSearchSurface = false

    @Query(sort: \FavoriteSubstance.createdAt, order: .reverse) private var favorites: [FavoriteSubstance]
    @State private var searchResults: [Substance] = []

    private var favoriteNames: Set<String> {
        Set(favorites.map { $0.substance.lowercased() })
    }

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
                        searchResultsList
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Theme.background)
            }
        }
        .appNavigationBar("Library", enabled: !isSearchSurface)
        .task(id: searchText) {
            guard !searchText.isEmpty else {
                searchResults = []
                return
            }
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            searchResults = SubstanceLibrary.search(searchText)
        }
    }

    // MARK: - Search Results

    private var isHelpSearch: Bool {
        CrisisKeywords.matches(searchText)
    }

    @ViewBuilder
    private var searchResultsList: some View {
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
                        SubstanceRowView(substance: substance)
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

    private var recentSubstances: [Substance] {
        var seen = Set<String>()
        var result: [Substance] = []
        for entry in recentEntries {
            let key = entry.substance.lowercased()
            if seen.insert(key).inserted, let substance = SubstanceLibrary.lookup(key) {
                result.append(substance)
                if result.count >= 10 { break }
            }
        }
        return result
    }

    var body: some View {
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
                        SubstanceRowView(substance: substance)
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

    enum SortMode: String, CaseIterable { case popularity, name }
    @State private var sortMode: SortMode = .popularity

    /// Whether this list browses a class (category or tag) versus Favorites —
    /// browse lists are sortable, Favorites keep the user's own order.
    private var isBrowse: Bool {
        category != nil || tag != nil
    }

    private var substances: [Substance] {
        if let tag {
            return SubstanceLibrary.substances(taggedWith: tag)
        }
        if let category {
            return SubstanceLibrary.substances(in: category)
        }
        // Exact canonical lookup — alias fallback mis-resolves on polluted
        // aliases (e.g. "magnesium" is also an alias of Salicylic acid).
        return favorites.compactMap { SubstanceLibrary.lookup($0.substance) }
    }

    /// Category browse is sortable (popularity surfaces well-known substances
    /// above obscure research chemicals); Favorites keep the user's own order.
    private var sortedSubstances: [Substance] {
        let list = substances
        guard isBrowse else { return list }
        switch sortMode {
        case .name:
            return list.sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
        case .popularity:
            return list.sorted {
                $0.popularity != $1.popularity
                    ? $0.popularity > $1.popularity
                    : $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
            }
        }
    }

    private var favoriteNames: Set<String> {
        Set(favorites.map { $0.substance.lowercased() })
    }

    var body: some View {
        List {
            ForEach(sortedSubstances) { substance in
                NavigationLink(value: PushRoute.substance(name: substance.name)) {
                    // A single-category list already names the class in its title;
                    // tag/favorites lists span classes, so keep the chip there.
                    SubstanceRowView(substance: substance, showsCategoryBadge: category == nil)
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
    /// The trailing class chip (e.g. "Stimulant"). Hidden when the surrounding
    /// list is already scoped to one category — repeating the class on every
    /// row there is just noise.
    var showsCategoryBadge = true
    @State private var customStore = CustomSubstanceStore.shared

    /// Personal display-name override, if it differs from the library title.
    private var personalName: String? {
        let resolved = customStore.displayName(for: substance.name, fallback: substance.displayTitle)
        return resolved == substance.displayTitle ? nil : resolved
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
    /// The library substance as resolved by the browse list (no personal
    /// override applied). Overrides are layered on reactively via `substance`,
    /// so personalizations show on entry and update live after editing.
    let baseSubstance: Substance
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appNavigator) private var navigator
    @Query private var historyEntries: [DoseEntry]
    @Query private var favorites: [FavoriteSubstance]
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

    /// Holding the @Observable store as @State (rather than reading
    /// `SubstanceStore.shared.userProfile` via a plain computed) is what makes
    /// SwiftUI re-render this view when the user changes profile in Settings.
    @State private var store = SubstanceStore.shared

    // Section expansion state. `nil` means "use the policy default for the
    // current tier"; once the user toggles a section, the stored Bool sticks.
    // Reset to nil on profile change so the new tier's defaults take effect
    // (otherwise the user would be permanently stuck on whatever defaults
    // applied the first time the section was rendered).
    @State private var mechanismExpanded: Bool?
    @State private var subjectiveExpanded: Bool?
    @State private var sourcesExpanded: Bool?
    @State private var receptorLitExpanded: Bool?
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
    @State private var literatureBindings: [SubstanceStore.BindingHit] = []
    @State private var provenance: SubstanceStore.SubstanceProvenance?

    private var profile: UserProfile {
        store.userProfile
    }
    private var policy: DisclosurePolicy {
        .init(profile: profile)
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
                    Label(ind, systemImage: "stethoscope")
                        .font(.subheadline)
                        .labelStyle(EffectLabelStyle())
                }
            }
        }
        let boxed = substance.contraindications.filter(\.isBoxedWarning)
        let cautions = substance.contraindications.filter { !$0.isBoxedWarning }
        if !boxed.isEmpty {
            Section("Boxed Warning") {
                ForEach(boxed, id: \.text) { c in
                    Label(c.text, systemImage: "exclamationmark.octagon.fill")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        if !cautions.isEmpty {
            Section("Contraindications & Cautions") {
                ForEach(cautions, id: \.text) { c in
                    Label(c.text, systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .labelStyle(EffectLabelStyle())
                }
            }
        }
    }

    /// Chemical identity (formula / molar mass / CAS / InChIKey) folded into a
    /// collapsed "Chemistry" disclosure below the identity Info card. Every value
    /// is selectable and carries a Copy action — an InChIKey you can't copy is
    /// useless.
    @ViewBuilder private var chemistryDisclosure: some View {
        let hasPubChem = substance.pubChemURL != nil
        if policy.showsMechanism,
           substance.formula != nil || substance.cas != nil || substance.inchikey != nil || substance.molarMass != nil || hasPubChem {
            Section {
                DisclosureGroup(isExpanded: $chemistryExpanded) {
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
                } label: {
                    Label("Chemistry", systemImage: "atom")
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
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
    private func pubChemCell(cid: Int, url: URL) -> some View {
        Link(destination: url) {
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Effects — the merged surface. Curated subjective effects (rich tier) read
    /// as the readable summary; the full PsychonautWiki taxonomy lives one tap
    /// away on the grouped ``AllEffectsView`` so the detail view stays short.
    /// First-hand Erowid reports show on the pushed "All effects" screen, gated
    /// to recreational / dual-use compounds where such reports exist.
    private var showsErowidReports: Bool {
        displayClass == .recreational || displayClass == .dualUse
    }

    @ViewBuilder private var effectsSection: some View {
        let curated = policy.showsRichSubjective ? substance.subjectiveEffects : []
        let hasAllEffects = !substance.effects.isEmpty
        // Only offer "Show All" when the full taxonomy actually adds to the
        // curated summary — otherwise (e.g. Melatonin) it reveals *fewer* rows.
        let showsMoreEffects = substance.effects.count > curated.count
        if displayClass != .nonRecreational, !curated.isEmpty || hasAllEffects {
            Section {
                if !curated.isEmpty {
                    ForEach(curated, id: \.name) { effect in
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
                    if !curated.isEmpty, showsMoreEffects {
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

    init(substance: Substance) {
        self.baseSubstance = substance
        let name = substance.name
        _historyEntries = Query(
            filter: #Predicate<DoseEntry> { entry in
                entry.substance == name
            },
            sort: \DoseEntry.timestamp,
            order: .reverse,
        )
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
        Section {
            DisclosureGroup(isExpanded: $infoExpanded) {
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

                if !substance.aliases.isEmpty {
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
            } label: {
                Label("Info", systemImage: "info.circle")
                    .font(.subheadline.weight(.semibold))
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
        let all = substance.aliases
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

                // Effects — curated summary + grouped "All effects" navigation.
                effectsSection

                if policy.showsMechanism, let moa = composedMechanism {
                    Section {
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { mechanismExpanded ?? policy.mechanismDefaultExpanded },
                                set: { mechanismExpanded = $0 },
                            ),
                        ) {
                            mechanismBody(moa)
                        } label: {
                            Label("Mechanism of Action", systemImage: "atom")
                                .font(.subheadline.weight(.semibold))
                        }
                        if let slug = provenance?.mechanismSource {
                            SourceAttributionRow(
                                slug: slug,
                                label: "Mechanism",
                                deepLink: sourceDeepLink(slug),
                            )
                        }
                    }
                }

                if policy.showsReceptorLiterature, !literatureBindings.isEmpty {
                    Section {
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { receptorLitExpanded ?? policy.receptorLitDefaultExpanded },
                                set: { receptorLitExpanded = $0 },
                            ),
                        ) {
                            receptorLiteratureBody
                        } label: {
                            Label("Receptor Literature", systemImage: "function")
                                .font(.subheadline.weight(.semibold))
                        }
                    } footer: {
                        Text("Ki/EC50 values from primary literature with explicit source attribution. Lower Ki = tighter binding. Distinguish human vs. animal data when interpreting.")
                            .font(.caption2)
                            .foregroundStyle(Theme.secondaryLabel)
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
        }
        .task(id: TaskKey(substanceName: substance.name, profile: profile)) {
            // Always fetch provenance — per-field source attribution is
            // shown to every tier so users can see where each fact came from.
            provenance = store.provenance(forSubstanceName: substance.name)

            // Receptor literature is pharma-nerd-only — skip the query for
            // other tiers.
            if policy.showsReceptorLiterature {
                literatureBindings = store.bindings(forSubstanceName: substance.name)
            } else {
                literatureBindings = []
            }
        }
        .task(id: historySignature) {
            rebuildHistoryStats()
        }
        .onChange(of: profile) { _, _ in
            // Reset stuck Bool? overrides so the new tier's policy defaults
            // win. Any disclosure the user touches after this point sticks
            // until the next profile change.
            mechanismExpanded = nil
            subjectiveExpanded = nil
            sourcesExpanded = nil
            receptorLitExpanded = nil
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

    // MARK: - Mechanism + Literature bodies

    private func mechanismBody(_ moa: MechanismOfAction) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(moa.summary)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(substance.category.color)

            Text(moa.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !moa.bindings.isEmpty {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    GridRow {
                        Text("Target")
                        Text("Action")
                        Text(verbatim: "")
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.secondaryLabel)

                    ForEach(moa.bindings) { binding in
                        GridRow {
                            Text(binding.target)
                                .fontWeight(.medium)
                            Text(binding.action.displayName)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 2) {
                                ForEach(0 ..< 3, id: \.self) { i in
                                    Circle()
                                        .fill(i < binding.affinity.rawValue ? substance.category.color : substance.category.color.opacity(0.15))
                                        .frame(width: 6, height: 6)
                                }
                            }
                        }
                    }
                }
                .font(.caption)
            } else if !moa.primaryTargets.isEmpty {
                HStack(spacing: 0) {
                    Text("Primary Targets: ")
                        .font(.caption.weight(.medium))
                    Text(moa.primaryTargets.joined(separator: " · "))
                        .font(.caption)
                }
                .foregroundStyle(Theme.secondaryLabel)
            }
        }
        .padding(.vertical, 2)
    }

    private var receptorLiteratureBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(literatureBindings) { hit in
                ReceptorLiteratureRow(hit: hit, accent: substance.category.color)
                if hit.id != literatureBindings.last?.id {
                    Divider()
                }
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

/// Single binding row inside the pharma-nerd "Receptor Literature" disclosure.
/// Each row shows the target, action, Ki or EC50 value, optional species,
/// source slug, and a PMID/DOI affordance so the user can verify the claim.
private struct ReceptorLiteratureRow: View {
    let hit: SubstanceStore.BindingHit
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(hit.target)
                    .font(.subheadline.weight(.semibold))
                Text(hit.action)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                affinityLabel
            }
            HStack(spacing: 6) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.caption2)
                Text(hit.sourceSlug)
                    .font(.caption2.monospaced())
                if let species = hit.species, !species.isEmpty {
                    Text("·")
                    Text(species).italic()
                }
                Spacer()
                if let pmid = hit.pmid, let url = URL(string: "https://pubmed.ncbi.nlm.nih.gov/\(pmid)/") {
                    Link(destination: url) {
                        Text("PMID \(pmid)")
                            .font(.caption2)
                            .foregroundStyle(accent)
                    }
                } else if let doi = hit.doi, !doi.isEmpty, let url = URL(string: "https://doi.org/\(doi)") {
                    Link(destination: url) {
                        Text("DOI")
                            .font(.caption2)
                            .foregroundStyle(accent)
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(Theme.secondaryLabel)
        }
    }

    @ViewBuilder
    private var affinityLabel: some View {
        if let ki = hit.kiNm {
            Text("Ki \(formatNm(ki)) nM")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(accent)
        } else if let ec = hit.ec50Nm {
            Text("EC50 \(formatNm(ec)) nM")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(accent)
        }
    }
}

/// Ki/EC50 display formatter shared with `AdvancedSearchView` — precision
/// scales with magnitude so small affinities keep their decimals.
func formatNm(_ value: Double) -> String {
    if value >= 100 { return String(format: "%.0f", value) }
    if value >= 10 { return String(format: "%.1f", value) }
    return String(format: "%.2f", value)
}

// MARK: - Effect Label Style

struct EffectLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
                .font(.system(size: 5))
                .foregroundStyle(Theme.secondaryLabel)
            configuration.title
        }
    }
}

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
