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
                description: Text("Find any substance by name or alias.")
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

    @ViewBuilder
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
        "call 911", "911", "poisoning", "too much", "od", "can't breathe"
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

        if searchResults.isEmpty && !isHelpSearch {
            ContentUnavailableView(
                "No Results",
                systemImage: "magnifyingglass",
                description: Text("No substances match \"\(searchText)\"")
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
                        url: "tel:911"
                    )
                    helpLink(
                        icon: "cross.case.fill",
                        color: .orange,
                        title: "Poison Control",
                        detail: "1-800-222-1222 (US)",
                        url: "tel:18002221222"
                    )
                    helpLink(
                        icon: "phone.badge.waveform.fill",
                        color: .purple,
                        title: "988 Suicide & Crisis Lifeline",
                        detail: "Call or text 988",
                        url: "tel:988"
                    )
                    helpLink(
                        icon: "message.fill",
                        color: .green,
                        title: "Crisis Text Line",
                        detail: "Text HOME to 741741",
                        url: "sms:741741&body=HOME"
                    )
                    helpLink(
                        icon: "heart.fill",
                        color: .pink,
                        title: "SAMHSA Helpline",
                        detail: "1-800-662-4357 — Free, confidential, 24/7",
                        url: "tel:18006624357"
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

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(substance.displayTitle)
                    .font(.body)
                    .foregroundStyle(.primary)
                if let subtitle = substance.displaySubtitle {
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
    let substance: Substance
    @Environment(\.modelContext) private var modelContext
    @Query private var historyEntries: [DoseEntry]
    @Query private var favorites: [FavoriteSubstance]
    @State private var showAllHistory = false
    @State private var showEntries = false

    // Holding the @Observable store as @State (rather than reading
    // `SubstanceStore.shared.userProfile` via a plain computed) is what makes
    // SwiftUI re-render this view when the user changes profile in Settings.
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
    @State private var literatureBindings: [SubstanceStore.BindingHit] = []
    @State private var provenance: SubstanceStore.SubstanceProvenance?

    private var profile: UserProfile { store.userProfile }
    private var policy: DisclosurePolicy { .init(profile: profile) }
    private var displayClass: CompoundDisplayClass { substance.displayClass }

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
           substance.formula != nil || substance.cas != nil || substance.inchikey != nil {
            Section("Chemistry") {
                if let f = substance.formula {
                    LabeledContent("Formula") { Text(f) }
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
        self.substance = substance
        let name = substance.name
        _historyEntries = Query(
            filter: #Predicate<DoseEntry> { entry in
                entry.substance == name
            },
            sort: \DoseEntry.timestamp,
            order: .reverse
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

    /// Dose ladder + duration per route. Surfaced near the top of the detail
    /// view — the primary thing people open a substance for.
    @ViewBuilder private var doseDurationSections: some View {
        ForEach(substance.routes, id: \.route) { substanceRoute in
            if displayClass.showsDoseLadder {
                Section("Dosage — \(String(localized: substanceRoute.route.localizedName))") {
                    let unit = substanceRoute.unit
                    let doses = substanceRoute.doses

                    DoseLevelIndicator(doseRange: doses, currentDose: nil)
                        .padding(.vertical, 4)

                    DoseRangeRows(doseRange: doses, unit: unit)

                    if doses.requiresVolumetricDosing(unit: unit) {
                        VolumetricDosingDisclaimer()
                            .padding(.vertical, 4)
                    }

                    if let slug = doseSourceSlug(for: substanceRoute.route) {
                        SourceAttributionRow(slug: slug, label: "Dose data")
                    }
                }
            }

            if let duration = substanceRoute.duration,
               displayClass.showsDuration,
               !(displayClass == .otc && substance.durationImplausible) {
                Section("Duration — \(String(localized: substanceRoute.route.localizedName))") {
                    DurationInfoView(duration: duration)
                        .padding(.vertical, 4)

                    if let slug = durationSourceSlug(for: substanceRoute.route) {
                        SourceAttributionRow(slug: slug, label: "Duration data")
                    }
                }
            }
        }
    }

    /// Name / aliases / route / chemistry — demoted below dosing and collapsed.
    /// Chemists who want the full identity follow the PubChem link.
    @ViewBuilder private var infoDisclosure: some View {
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

            if displayClass == .medicalRx || displayClass == .nonRecreational {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(displayClass == .medicalRx ? "Prescription medication" : "Medical information only",
                              systemImage: "cross.case.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.blue)
                        Text("Dosing for this medication is determined by a healthcare provider and is not shown here. The information below is for recognition and reference only.")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                }
            } else if substance.hasNoDoseData {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Limited human data", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)
                        Text("This compound has no validated human dose data. Information below is for reference only — see the linked sources for primary literature. Do not extrapolate doses from related compounds.")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                }
            }

            if policy.showsMechanism,
               let moa = substance.mechanismOfAction
                ?? MechanismOfActionDatabase.categoryFallback(for: substance.category) {
                Section {
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { mechanismExpanded ?? policy.mechanismDefaultExpanded },
                            set: { mechanismExpanded = $0 }
                        )
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

            if policy.showsReceptorLiterature && !literatureBindings.isEmpty {
                Section {
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { receptorLitExpanded ?? policy.receptorLitDefaultExpanded },
                            set: { receptorLitExpanded = $0 }
                        )
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

            if !substance.effects.isEmpty && displayClass != .nonRecreational {
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

            if policy.showsRichSubjective && !substance.subjectiveEffects.isEmpty
                && (displayClass == .recreational || displayClass == .dualUse) {
                Section {
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { subjectiveExpanded ?? policy.subjectiveDefaultExpanded },
                            set: { subjectiveExpanded = $0 }
                        )
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

            if policy.showsSources && !substance.sources.isEmpty {
                Section {
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { sourcesExpanded ?? policy.sourcesDefaultExpanded },
                            set: { sourcesExpanded = $0 }
                        )
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
            }
            .listRowBackground(Theme.cardBackground)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(substance.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    toggleFavorite()
                } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .foregroundStyle(isFavorite ? Color.yellow : Theme.secondaryLabel)
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

    @ViewBuilder
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
                        Text("")
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
                                ForEach(0..<3, id: \.self) { i in
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

        ForEach(moa.references, id: \.self) { ref in
            if let info = AppSources.info(for: ref),
               let url = URL(string: info.url), !info.url.isEmpty {
                Link(destination: url) {
                    Label(ref, systemImage: "book.closed")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                }
            } else {
                Label(ref, systemImage: "book.closed")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
            }
        }
    }

    @ViewBuilder
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
            for a in amounts { freq[a, default: 0] += 1 }
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
                if entries.count > 10 && !showAllHistory {
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
        if value >= 10  { return String(format: "%.1f", value) }
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

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let arrangement = arrange(subviews: subviews, in: width)
        return CGSize(width: arrangement.size.width, height: arrangement.size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrange(subviews: subviews, in: bounds.width)
        for (idx, sub) in subviews.enumerated() {
            let origin = arrangement.offsets[idx]
            sub.place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: .unspecified
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
