import SwiftUI

/// Bottom sheet for choosing which substances the Usage stats include. Searchable
/// and grouped by category with a per-category select-all, so it scales to a large
/// log — the inline menu became unusable past a handful of substances.
///
/// Writes back to `selection`, where an **empty set — or every substance chosen —
/// both mean "all" (no filter)**. That keeps the filter's two ends collapsed onto
/// one canonical state, so the toolbar only reads as filtered for a real subset,
/// and there is no separate "show nothing" trap.
struct SubstanceFilterSheet: View {
    let substances: [UsageSubstanceRef]
    @Binding var selection: Set<String>

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    /// Local explicit set — every listed substance is either in or out.
    /// Materialized from `selection` on appear so the "empty = all" parent state
    /// shows as everything checked; translated back in ``applyToBinding()``.
    @State private var shown: Set<String> = []

    private var allNames: Set<String> {
        Set(substances.map(\.name))
    }

    private var allSelected: Bool {
        shown.count >= substances.count
    }

    /// Substances grouped by category, each group filtered by the search query, in
    /// the catalog's category order; empty groups drop out.
    private var groups: [(category: SubstanceCategory, items: [UsageSubstanceRef])] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        var byCategory: [Int: [UsageSubstanceRef]] = [:]
        for sub in substances where q.isEmpty
            || sub.displayName.lowercased().contains(q)
            || sub.name.lowercased().contains(q) {
            byCategory[sub.categoryIndex, default: []].append(sub)
        }
        return byCategory.keys.sorted().compactMap { index in
            guard index < SubstanceCategory.allCases.count else { return nil }
            let items = byCategory[index]!.sorted { $0.displayName < $1.displayName }
            return (SubstanceCategory.allCases[index], items)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groups, id: \.category) { group in
                    Section {
                        ForEach(group.items, id: \.name) { substance in
                            row(substance)
                        }
                    } header: {
                        categoryHeader(group.category, items: group.items)
                    }
                }
            }
            .searchable(
                text: $query,
                placement: .automatic,
                prompt: "Search substances",
            )
            .navigationTitle("Substances")
            .inlineNavigationTitle()
            .toolbar {
                #if os(iOS)
                    ToolbarItem(placement: .platformTopBarLeading) {
                        Button(allSelected ? "Deselect All" : "Select All") {
                            shown = allSelected ? [] : allNames
                        }
                    }
                #else
                    ToolbarItem(placement: .automatic) {
                        Button(allSelected ? "Deselect All" : "Select All") {
                            shown = allSelected ? [] : allNames
                        }
                    }
                #endif
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { shown = selection.isEmpty ? allNames : selection }
        .onChange(of: shown) { applyToBinding() }
    }

    private func row(_ substance: UsageSubstanceRef) -> some View {
        Button {
            if shown.contains(substance.name) {
                shown.remove(substance.name)
            } else {
                shown.insert(substance.name)
            }
        } label: {
            HStack {
                Text(substance.displayName)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "checkmark")
                    .foregroundStyle(Theme.accent)
                    .opacity(shown.contains(substance.name) ? 1 : 0)
                    .accessibilityHidden(true)
            }
        }
    }

    /// A category section header with a one-tap select/deselect for the whole
    /// class — "All stimulants", "All benzos" — the reason the sheet exists.
    private func categoryHeader(_ category: SubstanceCategory, items: [UsageSubstanceRef]) -> some View {
        let names = items.map(\.name)
        let allOn = names.allSatisfy { shown.contains($0) }
        return HStack {
            Text(category.displayName)
            Spacer()
            Button(allOn ? "None" : "All") {
                if allOn {
                    names.forEach { shown.remove($0) }
                } else {
                    shown.formUnion(names)
                }
            }
            .font(.caption.weight(.semibold))
            .textCase(nil)
        }
    }

    /// Both ends — nothing checked or everything checked — collapse to the empty
    /// "all substances" state; only a genuine subset is stored as a filter.
    private func applyToBinding() {
        selection = (shown.isEmpty || shown.count == substances.count) ? [] : shown
    }
}
