import SwiftData
import SwiftUI

struct SubstanceLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var searchText: String

    /// When embedded in the Search tab: drop the "Library" header + category
    /// browse, showing only recent substances (empty) or results (typed).
    var isSearchSurface = false

    @Query(sort: \FavoriteSubstance.createdAt, order: .reverse) private var favorites: [FavoriteSubstance]
    @Query(sort: \DoseEntry.timestamp, order: .reverse) private var recentEntries: [DoseEntry]
    @State private var searchResults: [Substance] = []

    /// Up to 10 most recently logged substances, de-duplicated, resolved to the
    /// library entry. Drives the Search surface's empty state.
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

    private var favoriteSubstances: [Substance] {
        favorites.compactMap { fav in
            SubstanceLibrary.lookup(fav.substance.lowercased())
        }
    }

    private var favoriteNames: Set<String> {
        Set(favorites.map { $0.substance.lowercased() })
    }

    private func toggleFavorite(_ name: String) {
        let lowered = name.lowercased()
        if let existing = favorites.first(where: { $0.substance.lowercased() == lowered }) {
            modelContext.delete(existing)
        } else {
            modelContext.insert(FavoriteSubstance(substance: name))
        }
    }

    var body: some View {
        List {
            if searchText.isEmpty {
                if isSearchSurface {
                    recentSection
                } else {
                    categoryGrid
                }
            } else {
                searchResultsList
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .appHeader("Library", enabled: !isSearchSurface)
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

    // MARK: - Recent (Search surface)

    @ViewBuilder
    private var recentSection: some View {
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
                }
            }
            .listSectionSeparator(.hidden, edges: .top)
        }
    }

    // MARK: - Category Grid

    private var categoryGrid: some View {
        Section {
            if !favoriteSubstances.isEmpty {
                let count = favoriteSubstances.count
                NavigationLink(value: PushRoute.libraryFavorites) {
                    HStack {
                        Image(systemName: "star.fill")
                            .font(.title3)
                            .foregroundStyle(.yellow)
                            .frame(width: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Favorites")
                                .font(.body)
                            Text("\(count) substance\(count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryLabel)
                        }
                        Spacer()
                    }
                }
            }

            ForEach(SubstanceLibrary.nonEmptyCategories) { category in
                let count = SubstanceLibrary.substances(in: category).count
                NavigationLink(value: PushRoute.libraryCategory(category)) {
                    HStack {
                        Image(systemName: category.icon)
                            .font(.title3)
                            .foregroundStyle(category.color)
                            .frame(width: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(category.displayName)
                                .font(.body)
                            Text("\(count) substance\(count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryLabel)
                        }
                        Spacer()
                    }
                }
            }
        }
        .listSectionSeparator(.hidden, edges: .top)
    }

    // MARK: - Search Results

    private static let helpKeywords: Set<String> = [
        "help", "emergency", "overdose", "bad trip", "dying", "scared",
        "panic", "ambulance", "hospital", "not okay", "freaking out",
        "call 911", "911", "poisoning", "too much", "od", "can't breathe",
    ]

    private var isHelpSearch: Bool {
        let query = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return false }
        // Match single-word keywords on whole-word boundaries so a substance
        // name that merely *contains* a keyword as a substring (e.g. "armod"
        // contains "od") doesn't trip the crisis panel. Multi-word keywords
        // ("bad trip", "call 911") are matched as phrases.
        let words = Set(query.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        return Self.helpKeywords.contains { keyword in
            keyword.contains(" ") ? query.contains(keyword) : words.contains(keyword)
        }
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
                            toggleFavorite(substance.name)
                        } label: {
                            Label(isFav ? "Unfavorite" : "Favorite", systemImage: isFav ? "star.slash" : "star")
                        }
                        .tint(.yellow)
                    }
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

    private func helpLink(icon: String, color: Color, title: String, detail: String, url: String) -> some View {
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

// MARK: - Category Substance List

struct SubstanceCategoryListView: View {
    let title: LocalizedStringResource
    let category: SubstanceCategory?
    @Query(sort: \FavoriteSubstance.createdAt, order: .reverse) private var favorites: [FavoriteSubstance]
    @Environment(\.modelContext) private var modelContext

    enum SortMode: String, CaseIterable { case popularity, name }
    @State private var sortMode: SortMode = .popularity

    private var substances: [Substance] {
        if let category {
            return SubstanceLibrary.substances(in: category)
        }
        return favorites.compactMap { SubstanceLibrary.lookup($0.substance.lowercased()) }
    }

    /// Category browse is sortable (popularity surfaces well-known substances
    /// above obscure research chemicals); Favorites keep the user's own order.
    private var sortedSubstances: [Substance] {
        let list = substances
        guard category != nil else { return list }
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

    private func toggleFavorite(_ name: String) {
        let lowered = name.lowercased()
        if let existing = favorites.first(where: { $0.substance.lowercased() == lowered }) {
            modelContext.delete(existing)
        } else {
            modelContext.insert(FavoriteSubstance(substance: name))
        }
    }

    var body: some View {
        List {
            ForEach(sortedSubstances) { substance in
                NavigationLink(value: PushRoute.substance(name: substance.name)) {
                    SubstanceRowView(substance: substance)
                }
                .swipeActions(edge: .trailing) {
                    let isFav = favoriteNames.contains(substance.name.lowercased())
                    Button {
                        toggleFavorite(substance.name)
                    } label: {
                        Label(isFav ? "Unfavorite" : "Favorite", systemImage: isFav ? "star.slash" : "star")
                    }
                    .tint(.yellow)
                }
            }
            .listSectionSeparator(.hidden, edges: .top)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(Text(title))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if category != nil {
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
    @State private var customStore = CustomSubstanceStore.shared

    /// Personal display-name override, if it differs from the library title.
    private var personalName: String? {
        let resolved = customStore.displayName(for: substance.name, fallback: substance.displayTitle)
        return resolved == substance.displayTitle ? nil : resolved
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(personalName ?? substance.displayTitle)
                    .font(.body)
                    .foregroundStyle(.primary)
                // When personalized, show the canonical name as the subtitle so
                // the user can tell what "joint" actually maps to.
                if let subtitle = personalName != nil ? substance.name : substance.displaySubtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(substance.category.displayName)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.fill.secondary, in: Capsule())
                Text(substance.defaultUnit)
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryLabel)
            }
        }
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

    /// The route the dose/duration card is showing. `nil` defaults to the
    /// substance's default route (resolved in ``activeSubstanceRoute``).
    @State private var selectedRoute: RouteOfAdministration?

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
    @State private var referencesExpanded: Bool?
    @State private var receptorLitExpanded: Bool?
    /// The Info block (name/aliases/route/chemistry) is demoted below dosing and
    /// collapsed by default — few users need the chemical identity up front.
    @State private var infoExpanded = false
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

    /// Compact chemical-identity section (formula / CAS / InChIKey). Reference
    /// data, surfaced above the casual tier when present.
    @ViewBuilder private var chemistrySection: some View {
        if policy.showsMechanism,
           substance.formula != nil || substance.cas != nil || substance.inchikey != nil || substance.molarMass != nil {
            Section("Chemistry") {
                if let f = substance.formula {
                    LabeledContent("Formula") { Text(f) }
                }
                if let mw = substance.molarMass, !substance.usesPeptidePresentation {
                    LabeledContent("Molar mass") { Text("\(mw.doseFormatted) g/mol") }
                }
                if let c = substance.cas {
                    LabeledContent("CAS") { Text(c) }
                }
                if let k = substance.inchikey {
                    LabeledContent("InChIKey") {
                        Text(k).font(.caption.monospaced()).multilineTextAlignment(.trailing)
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
        let lowered = substance.name.lowercased()
        if let existing = favorites.first(where: { $0.substance.lowercased() == lowered }) {
            modelContext.delete(existing)
        } else {
            modelContext.insert(FavoriteSubstance(substance: substance.name))
        }
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
            set: { selectedRoute = $0 },
        )
    }

    /// Dose ladder + duration for the selected route, behind a segmented route
    /// switcher when more than one route applies. Surfaced near the top of the
    /// detail view — the primary thing people open a substance for. One
    /// consolidated card per route replaces the old two-sections-per-route
    /// stack, so a multi-route compound reads in a single screenful.
    @ViewBuilder
    private var doseDurationSections: some View {
        if presentableRoutes.count > 1 {
            Section {
                let picker = Picker("Route", selection: routeSelection) {
                    ForEach(presentableRoutes, id: \.route) { route in
                        Text(route.route.localizedName).tag(route.route)
                    }
                }
                // Segmented reads best for a couple of routes; past three the
                // labels truncate, so fall back to a menu that keeps them full.
                if presentableRoutes.count >= 4 {
                    picker.pickerStyle(.menu)
                } else {
                    picker.pickerStyle(.segmented)
                        .listRowSeparator(.hidden)
                }
            }
        }

        if let route = activeSubstanceRoute {
            Section {
                RouteDosingCard(
                    route: route.route,
                    unit: route.unit,
                    doses: route.doses,
                    duration: durationVisible ? route.duration : nil,
                    releaseWindow: route.durationOfAction?.formattedWindow,
                    showsDoseLadder: displayClass.showsDoseLadder,
                    showsDuration: durationVisible,
                    showsTitle: false,
                )
                .listRowSeparator(.hidden)

                if displayClass.showsDoseLadder, route.doses.hasAnyValue,
                   let slug = doseSourceSlug(for: route.route) {
                    SourceAttributionRow(slug: slug, label: "Dose data")
                }
                if durationVisible, route.duration != nil,
                   let slug = durationSourceSlug(for: route.route) {
                    SourceAttributionRow(slug: slug, label: "Duration data")
                }
            } header: {
                Text(route.route.localizedName)
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

    /// Primary references for the compound's curated claims — DOIs / PMIDs /
    /// URLs render as tappable links; free-text labels as plain text.
    @ViewBuilder private var referencesSection: some View {
        if policy.showsSources, !substance.references.isEmpty {
            Section {
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { referencesExpanded ?? policy.sourcesDefaultExpanded },
                        set: { referencesExpanded = $0 },
                    ),
                ) {
                    ForEach(substance.references, id: \.self) { ref in
                        if let url = ref.resolvedURL {
                            Link(destination: url) {
                                Label(ref.label, systemImage: "link")
                                    .font(.subheadline)
                                    .labelStyle(EffectLabelStyle())
                            }
                        } else {
                            Text(ref.label)
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondaryLabel)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } label: {
                    Label("References", systemImage: "text.book.closed")
                        .font(.subheadline.weight(.semibold))
                }
            } footer: {
                Text("Primary references for this compound's data. Tap to open. Always verify against the original source.")
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
                LabeledContent("Name", value: substance.name)
                if !substance.aliases.isEmpty {
                    LabeledContent("Also known as") {
                        Text(substance.aliases.joined(separator: ", "))
                            .multilineTextAlignment(.trailing)
                    }
                }
                LabeledContent("Category") {
                    Text(substance.category.displayName)
                }
                LabeledContent("Default Route") {
                    Text(substance.defaultRoute.localizedName)
                }
                if let reg = substance.regulatoryStatus {
                    LabeledContent("Availability") {
                        Text(regulatoryDisplay(reg)).multilineTextAlignment(.trailing)
                    }
                }
                if displayClass.showsDoseLadder, let dz = substance.diazepamEquivalent, let text = dz.displayText {
                    LabeledContent("Diazepam equivalent") {
                        Text(text).multilineTextAlignment(.trailing)
                    }
                }
                if !substance.tags.isEmpty {
                    SubstanceTagFlow(tags: substance.tags, accent: substance.category.color)
                        .padding(.vertical, 4)
                }
                if let url = substance.pubChemURL {
                    Link(destination: url) {
                        Label("View on PubChem", systemImage: "atom")
                    }
                    .font(.subheadline)
                }
                if let slug = provenance?.categorySource {
                    SourceAttributionRow(slug: slug, label: "Category")
                }
                if let slug = provenance?.halfLifeSource, substance.halfLifeMinutes != nil {
                    SourceAttributionRow(slug: slug, label: "Half-life")
                }
            } label: {
                Label("Info", systemImage: "info.circle")
                    .font(.subheadline.weight(.semibold))
            }
        }
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
                            SourceAttributionRow(slug: slug, label: "Mechanism")
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

                if !substance.effects.isEmpty, displayClass != .nonRecreational {
                    Section("Effects") {
                        ForEach(substance.effects, id: \.self) { effect in
                            Label(effect, systemImage: "circle.fill")
                                .font(.subheadline)
                                .labelStyle(EffectLabelStyle())
                        }
                    }
                }

                // Medical context (indications / contraindications / boxed warnings)
                // — shown for any compound that has clinical data. Net-new surface.
                medicalInfoSection

                // Name / aliases / route / chemistry — demoted here, below dosing,
                // and collapsed by default.
                infoDisclosure

                if policy.showsRichSubjective, !substance.subjectiveEffects.isEmpty,
                   displayClass == .recreational || displayClass == .dualUse {
                    Section {
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { subjectiveExpanded ?? policy.subjectiveDefaultExpanded },
                                set: { subjectiveExpanded = $0 },
                            ),
                        ) {
                            ForEach(substance.subjectiveEffects, id: \.name) { effect in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(effect.name)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Text(effect.description)
                                        .font(.caption)
                                        .foregroundStyle(Theme.secondaryLabel)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(.vertical, 2)
                            }
                        } label: {
                            Label("Reported Subjective Effects", systemImage: "person.wave.2")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }

                chemistrySection

                if policy.showsSources, !substance.sources.isEmpty {
                    Section {
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { sourcesExpanded ?? policy.sourcesDefaultExpanded },
                                set: { sourcesExpanded = $0 },
                            ),
                        ) {
                            ForEach(substance.sources, id: \.self) { source in
                                sourceRow(source)
                            }
                        } label: {
                            Label("Sources", systemImage: "book.closed")
                                .font(.subheadline.weight(.semibold))
                        }
                    } footer: {
                        Text("Data sourced from peer-reviewed literature, FDA labels, and established pharmacological databases. Always consult a healthcare professional.")
                    }
                }

                referencesSection
            }
            .listRowBackground(Theme.cardBackground)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(substance.displayTitle)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if activeSubstanceRoute != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        generateShareImage()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share drug info")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    toggleFavorite()
                } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .foregroundStyle(isFavorite ? Color.yellow : Theme.secondaryLabel)
                }
                .accessibilityLabel(isFavorite ? "Remove from Favorites" : "Add to Favorites")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        navigator.present(.personalizeSubstance(name: baseSubstance.name))
                    } label: {
                        Label(
                            personalOverride == nil ? "Personalize…" : "Edit Personalization…",
                            systemImage: "slider.horizontal.3",
                        )
                    }
                    if let override = personalOverride {
                        Button(role: .destructive) {
                            customStore.delete(override)
                        } label: {
                            Label("Reset Personalization", systemImage: "arrow.uturn.backward")
                        }
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(personalOverride == nil ? Theme.secondaryLabel : Theme.accent)
                }
                .accessibilityLabel("Personalize substance")
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

    // MARK: - Source attribution

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

    @ViewBuilder
    private func sourceRow(_ source: String) -> some View {
        if let info = AppSources.info(for: source) {
            let deepURL = AppSources.substanceURL(for: source, substance: substance.name)
            if let url = deepURL {
                Link(destination: url) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(source).font(.subheadline.weight(.medium))
                        Text(info.detail).font(.caption).foregroundStyle(Theme.secondaryLabel)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(source).font(.subheadline.weight(.medium))
                    Text(info.detail).font(.caption).foregroundStyle(Theme.secondaryLabel)
                }
            }
        } else {
            Text(source)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
        }
    }

    // MARK: - History

    @ViewBuilder
    private var historySection: some View {
        let entries = historyEntries
        let count = entries.count
        let amounts = entries.map(\.amount)
        let minDose = amounts.min() ?? 0
        let maxDose = amounts.max() ?? 0
        let unit = entries.first?.unit ?? substance.defaultUnit

        // Most common dose
        let mostCommon: Double = {
            var freq: [Double: Int] = [:]
            for a in amounts {
                freq[a, default: 0] += 1
            }
            return freq.max(by: { $0.value < $1.value })?.key ?? 0
        }()

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
                        Text("\(count) entr\(count == 1 ? "y" : "ies")")
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

    private var displayName: String {
        SubstanceStore.shared.sourceDisplayName(forSlug: slug)
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.seal")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
            Text("·")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
            Text(displayName)
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
            Spacer()
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(String(localized: label)), source: \(displayName)"))
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

    private func formatNm(_ value: Double) -> String {
        if value >= 100 { return String(format: "%.0f", value) }
        if value >= 10 { return String(format: "%.1f", value) }
        return String(format: "%.2f", value)
    }
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
        TagFlowLayout(spacing: 6) {
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

/// Minimal flow layout — wraps subviews to additional lines as they overflow
/// the proposed width. Used by ``SubstanceTagFlow`` so the chip row matches
/// row width regardless of tag count.
private struct TagFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let arrangement = arrange(subviews: subviews, in: width)
        return CGSize(width: arrangement.size.width, height: arrangement.size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let arrangement = arrange(subviews: subviews, in: bounds.width)
        for (idx, sub) in subviews.enumerated() {
            let origin = arrangement.offsets[idx]
            sub.place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: .unspecified,
            )
        }
    }

    private func arrange(subviews: Subviews, in maxWidth: CGFloat) -> (offsets: [CGPoint], size: CGSize) {
        var offsets: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            offsets.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            totalWidth = max(totalWidth, x - spacing)
        }
        return (offsets, CGSize(width: totalWidth, height: y + rowHeight))
    }
}
