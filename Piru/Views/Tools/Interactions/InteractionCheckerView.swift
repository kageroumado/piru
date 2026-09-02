import SwiftData
import SwiftUI

struct InteractionCheckerView: View {
    @Query(sort: \DoseEntry.timestamp, order: .reverse) private var allEntries: [DoseEntry]
    @Query private var substanceColors: [SubstanceColor]

    @State private var selected: [String] = []
    @State private var results: [InteractionResult] = []
    @State private var combinationMetabolites: [CombinationMetabolite.Formation] = []
    @State private var searchText = ""
    @State private var searchResults: [Substance] = []
    @State private var showSearchResults = false
    @State private var searchTrigger = 0
    @FocusState private var isSearchFocused: Bool

    private var colorMap: [String: Color] {
        substanceColors.colorMap
    }

    /// Per-substance use counts, sorted most-used first — bucketed once per
    /// dose-log revision in the `.task`, not per body pass.
    @State private var usedCounts: [(name: String, count: Int)] = []

    /// Top 6 most-used substances, excluding already-selected ones — a cheap
    /// filter over the precomputed unique-substance counts.
    private var mostUsed: [(name: String, count: Int)] {
        let selectedLower = Set(selected.map { $0.lowercased() })
        return Array(
            usedCounts
                .filter { !selectedLower.contains($0.name.lowercased()) }
                .prefix(6),
        )
    }

    private func rebuildUsedCounts() {
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
        usedCounts = counts.values
            .sorted { $0.count > $1.count }
            .map { (name: $0.displayName, count: $0.count) }
    }

    private var hasExactMatch: Bool {
        let q = searchText.lowercased()
        return searchResults.contains { $0.name.lowercased() == q || $0.aliases.contains { $0.lowercased() == q } }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xxl) {
                searchSection
                selectedSection
                frequentlyUsedSection
                emptyStatePrompt
                resultsSection
                combinationSection
            }
            .padding(.horizontal)
            .padding(.bottom, 80)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .task(id: DoseLogService.shared.revision) {
            rebuildUsedCounts()
        }
    }

    // MARK: - Search

    private var searchSection: some View {
        VStack(spacing: Spacing.md) {
            HStack(spacing: Spacing.md) {
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
                        let results = await SubstanceLibrary.searchAsync(searchText, limit: 8)
                        guard !Task.isCancelled else { return }
                        searchResults = results
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
            .padding(.horizontal, Spacing.xxl)
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
            FlowLayout(spacing: Spacing.md) {
                ForEach(selected, id: \.self) { name in
                    substanceCapsule(name, removable: true) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selected.removeAll { $0 == name }
                            recheckInteractions()
                        }
                    }
                }
            }
            .padding(.vertical, Spacing.xs)
        }
    }

    @ViewBuilder
    private var emptyStatePrompt: some View {
        if selected.isEmpty, !showSearchResults {
            HStack(spacing: Spacing.md) {
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
                HStack(spacing: Spacing.lg) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.Semantic.Success.accent)
                        .font(.title3)
                        .accessibilityHidden(true)
                    Text("No known interactions found.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryLabel)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.xxl)
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
                    // Max severity, not the first row's: results are ordered by
                    // relevance score, which can rank a caution above a danger.
                    .foregroundStyle((results.map(\.severity).max() ?? .caution).labelColor)
                    .textCase(.uppercase)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, Spacing.xxl)
                    .padding(.top, Spacing.xl)
                    .padding(.bottom, Spacing.md)

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
                                    .accessibilityHidden(true)
                            }
                            .padding(.horizontal, Spacing.xxl)
                            .padding(.vertical, Spacing.md)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, Spacing.xs)
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
            VStack(alignment: .leading, spacing: Spacing.xl) {
                Text("Frequently used")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryLabel)
                    .textCase(.uppercase)
                    .accessibilityAddTraits(.isHeader)

                FlowLayout(spacing: Spacing.md) {
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
                    Divider().padding(.leading, Spacing.xxl)
                }
                Button {
                    addSubstance(substance.name)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(substance.name)
                                .font(.body)
                                .foregroundStyle(.primary)
                            if !substance.aliases.isEmpty {
                                Text(substance.aliases.prefix(3).joined(separator: ", "))
                                    .captionSecondary()
                            }
                        }
                        Spacer()
                        Text(substance.category.displayName)
                            .font(.caption2)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.xxs)
                            .background(.fill.secondary, in: Capsule())
                    }
                    .padding(.horizontal, Spacing.xxl)
                    .padding(.vertical, Spacing.lg)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if showCustom {
                if !shown.isEmpty {
                    Divider().padding(.leading, Spacing.xxl)
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
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.xxs)
                            .background(Theme.accent.opacity(Theme.Opacity.emphasis), in: Capsule())
                            .foregroundStyle(Theme.accent)
                    }
                    .padding(.horizontal, Spacing.xxl)
                    .padding(.vertical, Spacing.lg)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .themeCard(cornerRadius: Theme.CornerRadius.container)
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
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, 7)
            .background(color.opacity(Theme.Opacity.tint))
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
            combinationMetabolites = []
            return
        }
        results = InteractionChecker.checkBatch(selected, against: [], policy: .explore)
        combinationMetabolites = CombinationMetabolite.formed(
            among: selected, catalog: SubstanceStore.shared.combinationMetabolites(),
        )
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
                    .padding(.horizontal, Spacing.xxl)
                    .padding(.top, Spacing.xl)
                    .padding(.bottom, Spacing.md)

                ForEach(Array(combinationMetabolites.enumerated()), id: \.offset) { index, formation in
                    if index > 0 {
                        Divider().padding(.leading, 46)
                    }
                    CombinationMetaboliteBanner(formation: formation)
                        .padding(.horizontal, Spacing.xxl)
                        .padding(.vertical, Spacing.md)
                }
                .padding(.bottom, Spacing.xs)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .themeCard()
        }
    }
}
