import SwiftUI

/// Everything ``PharmaTableView`` shows and every filter that narrows it: the base
/// PK rows, the lazily-resolved receptor parameters, and the search / scope /
/// half-life / sort state that turns them into ``visibleRows``.
///
/// The table's async work lives here so a keystroke in the search field or a
/// scroll tick in the header cannot re-run it: the view holds this by `@State`
/// and keeps only its own presentation toggles.
@Observable
@MainActor
final class PharmaTableModel {
    /// The table's scope filter: the friendly Common default, the full library, or one browse category.
    enum Scope: Hashable {
        case common
        case all
        case category(SubstanceCategory)

        /// Stable string used to key the receptor-parameter resolve task.
        var descriptor: String {
            switch self {
            case .common: "common"
            case .all: "all"
            case let .category(category): "cat:\(category.rawValue)"
            }
        }
    }

    /// The active sort target: the frozen name column or one data column.
    enum SortKey: Equatable {
        case name
        case column(PharmaColumn)
    }

    private(set) var allRows: [PharmaTableRow] = []
    private(set) var isLoading = true

    /// Lowercased canonical names carrying the metadata `"common"` tag — the same set the Library's
    /// "Common" card surfaces (`SubstanceLibrary.substances(taggedWith: "common")`). Populated at load.
    private(set) var commonNames: Set<String> = []

    /// Receptor/mechanism parameters resolved off-main for a scope, cached by canonical name so
    /// re-filtering / re-sorting never re-resolves. Drives the Targets + Potency columns.
    private(set) var pharmacologyByName: [String: PharmacologyParameters] = [:]
    private(set) var resolvingPharma = false

    var searchText = ""
    var scope: Scope = .common
    var halfLifeOnly = false

    var sortKey: SortKey = .name
    var sortAscending = true

    // MARK: - Loading

    func load() async {
        guard allRows.isEmpty else { return }
        // Warm the batch cache first — the tag filter and the row seeding
        // below both read `all`, and a cold cache builds it synchronously
        // on the main actor.
        await SubstanceStore.shared.ensureAllLoaded()
        commonNames = Set(SubstanceLibrary.substances(taggedWith: "common").map { $0.name.lowercased() })
        let resolved = await SubstanceStore.shared.pharmaTableRowsOffMain()
        allRows = resolved
        isLoading = false
    }

    func resolvePharmacologyForScope() async {
        let names = scopeFilteredRows.map(\.name).filter { pharmacologyByName[$0] == nil }
        guard !names.isEmpty else { return }
        resolvingPharma = true
        defer { resolvingPharma = false }
        let resolved = await SubstanceStore.shared.pharmacologyParametersBatchOffMain(forNames: names)
        for (key, value) in resolved {
            pharmacologyByName[key] = value
        }
    }

    // MARK: - Derived data

    /// The scope-only slice of the base rows (before search / half-life / sort). Also the set whose
    /// receptor parameters the resolve task warms.
    var scopeFilteredRows: [PharmaTableRow] {
        switch scope {
        case .common: allRows.filter { commonNames.contains($0.name.lowercased()) }
        case .all: allRows
        case let .category(category): allRows.filter { $0.category == category }
        }
    }

    var visibleRows: [PharmaTableRow] {
        var rows = scopeFilteredRows
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            rows = rows.filter { $0.name.localizedCaseInsensitiveContains(query) }
        }
        if halfLifeOnly {
            rows = rows.filter { $0.halfLifeMin != nil }
        }
        return sortedRows(rows)
    }

    var availableCategories: [SubstanceCategory] {
        let present = Set(allRows.compactMap(\.category))
        return SubstanceCategory.allCases.filter { present.contains($0) }
    }

    // MARK: - Sorting

    func toggleSort(_ key: SortKey) {
        if sortKey == key {
            sortAscending.toggle()
        } else {
            sortKey = key
            sortAscending = true
        }
    }

    private func sortedRows(_ rows: [PharmaTableRow]) -> [PharmaTableRow] {
        switch sortKey {
        case .name:
            rows.sorted { lhs, rhs in
                let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                return sortAscending ? order == .orderedAscending : order == .orderedDescending
            }
        case let .column(column) where column.isText:
            rows.sorted { lhs, rhs in
                let left = column.textValue(lhs, params: pharmacologyByName[lhs.name])
                let right = column.textValue(rhs, params: pharmacologyByName[rhs.name])
                switch (left, right) {
                case let (leftValue?, rightValue?):
                    let order = leftValue.localizedCaseInsensitiveCompare(rightValue)
                    if order == .orderedSame {
                        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                    }
                    return sortAscending ? order == .orderedAscending : order == .orderedDescending
                case (nil, _?): return false
                case (_?, nil): return true
                case (nil, nil): return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
            }
        case let .column(column):
            rows.sorted { lhs, rhs in
                let left = column.numericValue(lhs, params: pharmacologyByName[lhs.name])
                let right = column.numericValue(rhs, params: pharmacologyByName[rhs.name])
                switch (left, right) {
                case let (leftValue?, rightValue?):
                    if leftValue == rightValue {
                        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                    }
                    return sortAscending ? leftValue < rightValue : leftValue > rightValue
                case (nil, _?): return false // missing values sort last regardless of direction
                case (_?, nil): return true
                case (nil, nil): return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
            }
        }
    }
}
