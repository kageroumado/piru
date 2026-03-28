import SwiftData
import SwiftUI

enum LibraryDestination: Hashable {
    case category(SubstanceCategory)
    case favorites
}

struct SubstanceLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var searchText: String
    @Query(sort: \FavoriteSubstance.createdAt, order: .reverse) private var favorites: [FavoriteSubstance]
    @State private var searchResults: [Substance] = []

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
                if LibraryLoadingState.shared.isLoading {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            VStack(alignment: .leading, spacing: 2) {
                                Text(LibraryLoadingState.shared.statusText)
                                    .font(.subheadline)
                                Text("\(LibraryLoadingState.shared.substanceCount) loaded so far")
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryLabel)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                categoryGrid
            } else {
                searchResultsList
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Substance Library")
        .navigationDestination(for: LibraryDestination.self) { destination in
            switch destination {
            case .category(let cat):
                SubstanceCategoryListView(title: cat.rawValue, category: cat)
            case .favorites:
                SubstanceCategoryListView(title: "Favorites", category: nil)
            }
        }
        .navigationDestination(for: Substance.self) { substance in
            SubstanceDetailView(substance: substance)
        }
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

    // MARK: - Category Grid

    @ViewBuilder
    private var categoryGrid: some View {
        Section {
            if !favoriteSubstances.isEmpty {
                let count = favoriteSubstances.count
                NavigationLink(value: LibraryDestination.favorites) {
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
                NavigationLink(value: LibraryDestination.category(category)) {
                    HStack {
                        Image(systemName: category.icon)
                            .font(.title3)
                            .foregroundStyle(category.color)
                            .frame(width: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(category.rawValue)
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
    }

    // MARK: - Search Results

    private static let helpKeywords: Set<String> = [
        "help", "emergency", "overdose", "bad trip", "dying", "scared",
        "panic", "ambulance", "hospital", "not okay", "freaking out",
        "call 911", "911", "poisoning", "too much", "od", "can't breathe"
    ]

    private var isHelpSearch: Bool {
        let query = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        return Self.helpKeywords.contains(where: { query.contains($0) })
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
                    NavigationLink(value: substance) {
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
    let title: String
    let category: SubstanceCategory?
    @Query(sort: \FavoriteSubstance.createdAt, order: .reverse) private var favorites: [FavoriteSubstance]
    @Environment(\.modelContext) private var modelContext

    private var substances: [Substance] {
        if let category {
            return SubstanceLibrary.substances(in: category)
        }
        return favorites.compactMap { SubstanceLibrary.lookup($0.substance.lowercased()) }
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
            ForEach(substances) { substance in
                NavigationLink(value: substance) {
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
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Substance Row

struct SubstanceRowView: View {
    let substance: Substance

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(substance.name)
                    .font(.body)
                    .foregroundStyle(.primary)
                if !substance.aliases.isEmpty {
                    Text(substance.aliases.prefix(3).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(substance.category.rawValue)
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

    var body: some View {
        List {
            if !historyEntries.isEmpty {
                historySection
            }

            Section("Info") {
                LabeledContent("Name", value: substance.name)
                if !substance.aliases.isEmpty {
                    LabeledContent("Also known as") {
                        Text(substance.aliases.joined(separator: ", "))
                            .multilineTextAlignment(.trailing)
                    }
                }
                LabeledContent("Category", value: substance.category.rawValue)
                LabeledContent("Default Route", value: substance.defaultRoute.displayName)
            }

            if let moa = substance.mechanismOfAction
                ?? MechanismOfActionDatabase.categoryFallback(for: substance.category) {
                Section("Mechanism of Action") {
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
                        if let info = AppSources.info(for: ref) {
                            if let url = URL(string: info.url), !info.url.isEmpty {
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
                        } else {
                            Label(ref, systemImage: "book.closed")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryLabel)
                        }
                    }
                }
            }

            if !substance.effects.isEmpty {
                Section("Subjective Effects") {
                    ForEach(substance.effects, id: \.self) { effect in
                        Label(effect, systemImage: "circle.fill")
                            .font(.subheadline)
                            .labelStyle(EffectLabelStyle())
                    }
                }
            }

            ForEach(substance.routes, id: \.route) { substanceRoute in
                Section("Dosage — \(substanceRoute.route.displayName)") {
                    let unit = substanceRoute.unit
                    let doses = substanceRoute.doses

                    DoseLevelIndicator(doseRange: doses, currentDose: nil)
                        .padding(.vertical, 4)

                    if let threshold = doses.threshold {
                        doseRow("Threshold", value: "\(threshold.doseFormatted) \(unit)", level: .threshold)
                    }
                    if let light = doses.light {
                        doseRow("Light", value: "\(light.lowerBound.doseFormatted) – \(light.upperBound.doseFormatted) \(unit)", level: .light)
                    }
                    if let common = doses.common {
                        doseRow("Common", value: "\(common.lowerBound.doseFormatted) – \(common.upperBound.doseFormatted) \(unit)", level: .common)
                    }
                    if let strong = doses.strong {
                        doseRow("Strong", value: "\(strong.lowerBound.doseFormatted) – \(strong.upperBound.doseFormatted) \(unit)", level: .strong)
                    }
                    if let heavy = doses.heavy {
                        doseRow("Heavy", value: "\(heavy.doseFormatted)+ \(unit)", level: .heavy)
                    }

                    if doses.requiresVolumetricDosing(unit: unit) {
                        VolumetricDosingDisclaimer()
                            .padding(.vertical, 4)
                    }
                }

                if let duration = substanceRoute.duration {
                    Section("Duration — \(substanceRoute.route.displayName)") {
                        DurationInfoView(duration: duration)
                            .padding(.vertical, 4)
                    }
                }
            }

            if !substance.subjectiveEffects.isEmpty {
                Section("Reported Subjective Effects") {
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
                }
            }

            if !substance.sources.isEmpty {
                Section {
                    ForEach(substance.sources, id: \.self) { source in
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
                } header: {
                    Label("Sources", systemImage: "book.closed")
                } footer: {
                    Text("Data sourced from peer-reviewed literature, FDA labels, and established pharmacological databases. Always consult a healthcare professional.")
                }
            }
        }
        .navigationTitle(substance.name)
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
                            Text(entry.route.displayName)
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

    @ViewBuilder
    private func doseRow(_ label: String, value: String, level: DoseLevel) -> some View {
        HStack {
            HStack(spacing: 6) {
                Circle()
                    .fill(level.swiftUIColor)
                    .frame(width: 8, height: 8)
                Text(label)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .font(.subheadline)
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
