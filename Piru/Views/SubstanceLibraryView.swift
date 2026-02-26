import SwiftData
import SwiftUI

struct SubstanceLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var searchText: String
    @Query(sort: \FavoriteSubstance.createdAt, order: .reverse) private var favorites: [FavoriteSubstance]
    @State private var selectedCategory: SubstanceCategory?
    @State private var showingFavorites = false
    @State private var selectedSubstance: Substance?

    private var categories: [SubstanceCategory] {
        SubstanceCategory.allCases.filter { category in
            !SubstanceLibrary.substances(in: category).isEmpty
        }
    }

    private var displayedSubstances: [Substance] {
        if !searchText.isEmpty {
            return SubstanceLibrary.search(searchText)
        }
        if showingFavorites {
            return favoriteSubstances
        }
        if let category = selectedCategory {
            return SubstanceLibrary.substances(in: category)
        }
        return []
    }

    private var favoriteSubstances: [Substance] {
        favorites.compactMap { fav in
            SubstanceLibrary.lookup(fav.substance.lowercased())
        }
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
            if searchText.isEmpty && selectedCategory == nil && !showingFavorites {
                categoryGrid
            } else {
                substanceList
            }
        }
        .listSectionSpacing(.compact)
        .navigationTitle("Substance Library")
        .onChange(of: searchText) {
            if !searchText.isEmpty {
                selectedCategory = nil
                showingFavorites = false
            }
        }
        .toolbar {
            if selectedCategory != nil || showingFavorites {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("All Categories") {
                        selectedCategory = nil
                        showingFavorites = false
                    }
                }
            }
        }
        .sheet(item: $selectedSubstance) { substance in
            NavigationStack {
                SubstanceDetailSheet(substance: substance)
            }
        }
    }

    // MARK: - Category Grid

    @ViewBuilder
    private var categoryGrid: some View {
        Section {
            if !favoriteSubstances.isEmpty {
                let count = favoriteSubstances.count
                Button {
                    showingFavorites = true
                } label: {
                    HStack {
                        Image(systemName: "star.fill")
                            .font(.title3)
                            .foregroundStyle(.yellow)
                            .frame(width: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Favorites")
                                .font(.body)
                                .foregroundStyle(.primary)
                            Text("\(count) substance\(count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            ForEach(categories) { category in
                let count = SubstanceLibrary.substances(in: category).count
                Button {
                    selectedCategory = category
                } label: {
                    HStack {
                        Image(systemName: iconFor(category))
                            .font(.title3)
                            .foregroundStyle(colorForCategory(category))
                            .frame(width: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(category.rawValue)
                                .font(.body)
                                .foregroundStyle(.primary)
                            Text("\(count) substance\(count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    // MARK: - Substance List

    @ViewBuilder
    private var substanceList: some View {
        if displayedSubstances.isEmpty {
            ContentUnavailableView(
                "No Results",
                systemImage: "magnifyingglass",
                description: Text("No substances match \"\(searchText)\"")
            )
        } else {
            let header = showingFavorites ? "Favorites" : selectedCategory?.rawValue ?? "\(displayedSubstances.count) results"
            Section(header) {
                ForEach(displayedSubstances) { substance in
                    Button {
                        selectedSubstance = substance
                    } label: {
                        SubstanceRowView(substance: substance)
                    }
                    .swipeActions(edge: .trailing) {
                        let isFav = Array(favorites).isFavorite(substance.name)
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

    // MARK: - Helpers

    private func iconFor(_ category: SubstanceCategory) -> String {
        switch category {
        case .stimulant: "bolt.fill"
        case .psychedelic: "eye.fill"
        case .dissociative: "waveform.path"
        case .opioid: "cross.fill"
        case .benzodiazepine: "moon.fill"
        case .gabapentinoid: "waveform"
        case .empathogen: "heart.fill"
        case .cannabinoid: "leaf.fill"
        case .nootropic: "brain.fill"
        case .depressant: "arrow.down.circle.fill"
        case .antidepressant: "sun.max.fill"
        case .antipsychotic: "shield.fill"
        case .analgesic: "bandage.fill"
        case .antihistamine: "allergens.fill"
        case .supplement: "pill.fill"
        case .other: "pills.fill"
        }
    }

    private func colorForCategory(_ category: SubstanceCategory) -> Color {
        switch category {
        case .stimulant: .orange
        case .psychedelic: .purple
        case .dissociative: .cyan
        case .opioid: .red
        case .benzodiazepine: .blue
        case .gabapentinoid: .indigo
        case .empathogen: .pink
        case .cannabinoid: .green
        case .nootropic: .teal
        case .depressant: .gray
        case .antidepressant: .yellow
        case .antipsychotic: .mint
        case .analgesic: .brown
        case .antihistamine: .secondary
        case .supplement: .green.opacity(0.7)
        case .other: .secondary
        }
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
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(substance.category.rawValue)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.fill.tertiary, in: Capsule())
                Text(substance.defaultUnit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Substance Detail Sheet

struct SubstanceDetailSheet: View {
    let substance: Substance
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DoseEntry.timestamp, order: .reverse) private var allEntries: [DoseEntry]
    @Query private var favorites: [FavoriteSubstance]
    @State private var showAllHistory = false

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
    }

    private var historyEntries: [DoseEntry] {
        let name = substance.name.lowercased()
        let aliases = Set(substance.aliases.map { $0.lowercased() })
        return allEntries.filter {
            let e = $0.substance.lowercased()
            return e == name || aliases.contains(e)
        }
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
                    if let fatal = doses.fatal {
                        doseRow("Fatal", value: "\(fatal.doseFormatted)+ \(unit)", level: .fatal)
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
                                .foregroundStyle(.secondary)
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
                            if let url = URL(string: info.url) {
                                Link(destination: url) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(source)
                                                .font(.subheadline)
                                                .foregroundStyle(.primary)
                                            Text(info.detail)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "arrow.up.right.square")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            } else {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(source)
                                        .font(.subheadline)
                                    Text(info.detail)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            Text(source)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
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
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    toggleFavorite()
                } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .foregroundStyle(isFavorite ? .yellow : .secondary)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
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
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(count) entr\(count == 1 ? "y" : "ies")")
                        .font(.subheadline.weight(.medium))
                    if let earliest, let latest {
                        if Calendar.current.isDate(earliest, equalTo: latest, toGranularity: .month) {
                            Text(earliest.formatted(.dateTime.month(.wide).year()))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(earliest.formatted(.dateTime.month(.abbreviated).year())) – \(latest.formatted(.dateTime.month(.abbreviated).year()))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
                        .foregroundStyle(.secondary)
                }
            }

            let displayEntries = showAllHistory ? entries : Array(entries.prefix(10))
            ForEach(displayEntries) { entry in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(entry.amount.doseFormatted) \(entry.unit)")
                            .font(.subheadline)
                        Text(entry.route.displayName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        }
    }

    @ViewBuilder
    private func doseRow(_ label: String, value: String, level: DoseLevel) -> some View {
        HStack {
            HStack(spacing: 6) {
                Circle()
                    .fill(colorFor(level))
                    .frame(width: 8, height: 8)
                Text(label)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(level == .fatal ? .red : .primary)
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
                .foregroundStyle(.secondary)
            configuration.title
        }
    }
}
