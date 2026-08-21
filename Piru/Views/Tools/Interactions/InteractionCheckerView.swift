import SwiftData
import SwiftUI

struct InteractionCheckerView: View {
    @Query(sort: \DoseEntry.timestamp, order: .reverse) private var allEntries: [DoseEntry]
    @Query private var substanceColors: [SubstanceColor]

    @State private var selected: [String] = []
    @State private var results: [InteractionResult] = []
    @State private var metabolicEffects: [MetabolicModulation.Effect] = []
    @State private var combinationMetabolites: [CombinationMetabolite.Formation] = []
    @State private var searchText = ""
    @State private var searchResults: [Substance] = []
    @State private var showSearchResults = false
    @State private var searchTrigger = 0
    @FocusState private var isSearchFocused: Bool

    private var colorMap: [String: Color] {
        substanceColors.colorMap
    }

    /// Top 6 most-used substance names (by entry count), excluding already-selected ones
    private var mostUsed: [(name: String, count: Int)] {
        var counts: [String: (displayName: String, count: Int)] = [:]
        for entry in allEntries {
            let key = entry.substance.lowercased()
            if var existing = counts[key] {
                existing.count += 1
                counts[key] = existing
            } else {
                counts[key] = (displayName: entry.substance, count: 1)
            }
        }
        let selectedLower = Set(selected.map { $0.lowercased() })
        return counts.values
            .sorted { $0.count > $1.count }
            .filter { !selectedLower.contains($0.displayName.lowercased()) }
            .prefix(6)
            .map { (name: $0.displayName, count: $0.count) }
    }

    private var hasExactMatch: Bool {
        let q = searchText.lowercased()
        return searchResults.contains { $0.name.lowercased() == q || $0.aliases.contains { $0.lowercased() == q } }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                searchSection
                selectedSection
                resultsSection
                combinationSection
                metabolicSection
                frequentlyUsedSection
            }
            .padding(.horizontal)
            .padding(.bottom, 80)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
    }

    // MARK: - Search

    private var searchSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.secondaryLabel)
                    .accessibilityHidden(true)
                TextField("Search substances...", text: $searchText)
                    .autocorrectionDisabled()
                    .focused($isSearchFocused)
                    .onChange(of: searchText) {
                        if searchText.isEmpty {
                            searchResults = []
                            showSearchResults = false
                        } else {
                            searchTrigger += 1
                        }
                    }
                    .task(id: searchTrigger) {
                        guard searchTrigger > 0 else { return }
                        try? await Task.sleep(for: .milliseconds(150))
                        guard !Task.isCancelled, !searchText.isEmpty else { return }
                        searchResults = SubstanceLibrary.search(searchText, limit: 8)
                        showSearchResults = true
                    }
                    .onSubmit {
                        if let first = searchResults.first {
                            addSubstance(first.name)
                        } else if !searchText.isEmpty {
                            addSubstance(searchText)
                        }
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .themeCapsule()

            if showSearchResults, !searchResults.isEmpty {
                searchDropdown
            }
        }
    }

    // MARK: - Selected Capsules

    @ViewBuilder
    private var selectedSection: some View {
        if !selected.isEmpty {
            FlowLayout(spacing: 8) {
                ForEach(selected, id: \.self) { name in
                    substanceCapsule(name, removable: true) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selected.removeAll { $0 == name }
                            recheckInteractions()
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        } else if !showSearchResults {
            HStack(spacing: 8) {
                Image(systemName: "hand.tap")
                    .foregroundStyle(Theme.secondaryLabel)
                    .accessibilityHidden(true)
                Text("Choose at least 2 substances")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsSection: some View {
        if selected.count >= 2 {
            if results.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title3)
                        .accessibilityHidden(true)
                    Text("No known interactions found.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryLabel)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .themeCard()
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Group {
                        if results.count == 1 {
                            Text("1 Interaction Found")
                        } else {
                            Text("\(results.count) Interactions Found")
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle((results.first?.severity ?? .caution).labelColor)
                    .textCase(.uppercase)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                    ForEach(Array(results.enumerated()), id: \.offset) { index, warning in
                        if index > 0 {
                            Divider().padding(.leading, 46)
                        }
                        NavigationLink {
                            InteractionTimelineView(
                                substanceA: warning.substanceA,
                                substanceB: warning.substanceB,
                                severity: warning.severity,
                                mechanism: warning.description,
                            )
                        } label: {
                            HStack {
                                InteractionWarningRow(warning: warning)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Theme.secondaryLabel)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .themeCard()
            }
        }
    }

    // MARK: - Frequently Used

    @ViewBuilder
    private var frequentlyUsedSection: some View {
        if !mostUsed.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Frequently used")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryLabel)
                    .textCase(.uppercase)
                    .accessibilityAddTraits(.isHeader)

                FlowLayout(spacing: 8) {
                    ForEach(mostUsed, id: \.name) { item in
                        substanceCapsule(item.name, removable: false) {
                            addSubstance(item.name)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var searchDropdown: some View {
        let selectedLower = Set(selected.map { $0.lowercased() })
        let shown = Array(searchResults.filter { !selectedLower.contains($0.name.lowercased()) }.prefix(6))
        let showCustom = !searchText.isEmpty && !hasExactMatch

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, substance in
                if index > 0 {
                    Divider().padding(.leading, 16)
                }
                Button {
                    addSubstance(substance.name)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
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
                        Text(substance.category.displayName)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.fill.secondary, in: Capsule())
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if showCustom {
                if !shown.isEmpty {
                    Divider().padding(.leading, 16)
                }
                Button {
                    addSubstance(searchText)
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Theme.accent)
                            .accessibilityHidden(true)
                        Text("Use \"\(searchText)\"")
                            .font(.body)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("Custom")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.accent.opacity(0.25), in: Capsule())
                            .foregroundStyle(Theme.accent)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .themeCard(cornerRadius: 16)
    }

    // MARK: - Capsule View

    private func substanceCapsule(_ name: String, removable: Bool, action: @escaping () -> Void) -> some View {
        let color = colorMap[name.lowercased()] ?? Theme.accent

        return Button(action: action) {
            HStack(spacing: 5) {
                if removable {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                }
                Text(name)
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
        }
        .accessibilityLabel(removable ? Text("Remove \(name)") : Text(name))
    }

    // MARK: - Actions

    private func addSubstance(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        guard !selected.contains(where: { $0.lowercased() == trimmed.lowercased() }) else { return }
        guard selected.count < 8 else { return }

        withAnimation(.easeInOut(duration: 0.2)) {
            selected.append(trimmed)
        }
        searchText = ""
        searchResults = []
        showSearchResults = false
        isSearchFocused = false
        recheckInteractions()
    }

    private func recheckInteractions() {
        guard selected.count >= 2 else {
            results = []
            metabolicEffects = []
            combinationMetabolites = []
            return
        }
        results = InteractionChecker.checkBatch(selected, against: [], policy: .explore)
        metabolicEffects = MetabolicModulation.checkerEffects(among: selected)
        combinationMetabolites = CombinationMetabolite.formed(among: selected)
    }

    // MARK: - Combination metabolites (Stage 4d)

    @ViewBuilder
    private var combinationSection: some View {
        if selected.count >= 2, !combinationMetabolites.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Combination Products")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryLabel)
                    .textCase(.uppercase)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                ForEach(Array(combinationMetabolites.enumerated()), id: \.offset) { index, formation in
                    if index > 0 {
                        Divider().padding(.leading, 46)
                    }
                    CombinationMetaboliteBanner(formation: formation)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .padding(.bottom, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .themeCard()
        }
    }

    // MARK: - Metabolic modulation (Stage 4c)

    @ViewBuilder
    private var metabolicSection: some View {
        if selected.count >= 2, !metabolicEffects.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Metabolic Effects")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryLabel)
                    .textCase(.uppercase)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                ForEach(Array(metabolicEffects.enumerated()), id: \.offset) { index, effect in
                    if index > 0 {
                        Divider().padding(.leading, 46)
                    }
                    MetabolicModulationBanner(effect: effect)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .padding(.bottom, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .themeCard()
        }
    }
}
