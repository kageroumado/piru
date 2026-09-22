import SwiftData
import SwiftUI

/// Every substance the user has met, with its color, grouped by class. A row
/// opens the picker; a custom color can be reset from its row, and all of them
/// from the toolbar.
struct SubstanceColorsListView: View {
    @Query(sort: \SubstanceColor.substance) private var substanceColors: [SubstanceColor]
    @Environment(\.modelContext) private var modelContext
    @State private var editing: EditingSubstance?
    @State private var searchText = ""
    @State private var collapsed: Set<SubstanceCategory> = []
    @State private var confirmingResetAll = false

    private struct EditingSubstance: Identifiable {
        let name: String
        var id: String { name }
    }

    private struct ClassSection: Identifiable {
        let category: SubstanceCategory
        let rows: [SubstanceColor]
        var id: SubstanceCategory { category }
    }

    /// Rows matching the search, bucketed by class in the class enum's order.
    /// An unresolvable name (a removed custom substance) files under `other`.
    private var sections: [ClassSection] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        var buckets: [SubstanceCategory: [SubstanceColor]] = [:]
        for row in substanceColors {
            let display = CustomSubstanceStore.shared.displayName(for: row.substance)
            guard query.isEmpty || row.substance.lowercased().contains(query) || display.lowercased().contains(query)
            else { continue }
            buckets[SubstanceLibrary.lookup(row.substance)?.category ?? .other, default: []].append(row)
        }
        return SubstanceCategory.allCases.compactMap { category in
            buckets[category].map { ClassSection(category: category, rows: $0) }
        }
    }

    private var hasCustomColors: Bool {
        substanceColors.contains { !$0.usesDefault || $0.isLegacy }
    }

    /// A search expands every section, so a match is never hidden in a fold.
    private func isExpanded(_ category: SubstanceCategory) -> Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty || !collapsed.contains(category)
    }

    var body: some View {
        List {
            if substanceColors.isEmpty {
                ContentUnavailableView(
                    "No Substance Colors",
                    systemImage: "paintpalette",
                    description: Text("Colors appear here after you log your first entry. Tap one to change it."),
                )
                .listRowBackground(Color.clear)
            } else if sections.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(sections) { section in
                    Section {
                        if isExpanded(section.category) {
                            ForEach(section.rows) { row in
                                SubstanceColorRow(row: row) { editing = EditingSubstance(name: row.substance) }
                                    .swipeActions(edge: .trailing) {
                                        if !row.usesDefault || row.isLegacy {
                                            Button("Reset") {
                                                SubstanceColorStore.apply(.default, to: row.substance, in: modelContext)
                                            }
                                        }
                                    }
                            }
                            .listRowBackground(CardBackground())
                        }
                    } header: {
                        CollapsibleCategoryHeader(
                            category: section.category, count: section.rows.count,
                            isExpanded: isExpanded(section.category),
                        ) {
                            collapsed.formSymmetricDifference([section.category])
                        }
                    }
                }
            }
        }
        .themedPage()
        .navigationTitle("Substance Colors")
        .inlineNavigationTitle()
        .alwaysVisibleSearch(text: $searchText, prompt: Text("Search Colors"))
        .toolbar {
            ToolbarItem(placement: .platformTopBarTrailing) {
                Button("Reset All") { confirmingResetAll = true }
                    .disabled(!hasCustomColors)
            }
        }
        .confirmationDialog(
            "Reset every substance to its class color?",
            isPresented: $confirmingResetAll,
            titleVisibility: .visible,
        ) {
            Button("Reset All", role: .destructive) { SubstanceColorStore.resetAll(in: modelContext) }
        } message: {
            Text("Colors you picked yourself are replaced.")
        }
        .sheet(item: $editing) { target in
            SubstanceColorPickerView(substanceName: target.name) { editing = nil }
        }
    }
}

private struct SubstanceColorRow: View {
    let row: SubstanceColor
    let edit: () -> Void

    var body: some View {
        Button(action: edit) {
            HStack(spacing: Spacing.xl) {
                Circle()
                    .fill(row.color)
                    .frame(width: IconSize.iconCompact, height: IconSize.iconCompact)
                    .accessibilityHidden(true)
                Text(CustomSubstanceStore.shared.displayName(for: row.substance))
                    .foregroundStyle(.primary)
                Spacer()
                if !row.usesDefault || row.isLegacy {
                    Text("Custom")
                        .captionSecondary()
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
