import SwiftUI

/// A spreadsheet-style browser over the library's **pharmacology** — receptors, mechanism, and PK — one
/// representative row per substance, the **Substance** column frozen on the left while the data columns
/// scroll horizontally in sync. The default columns lead with the interesting story (Mechanism/class,
/// primary receptor Targets, Half-life, and a Potency signal); the PK detail columns (Tmax, Bioavailability,
/// Cmax, Protein binding, Vd, Clearance) are opt-in from the navbar menu. That same menu holds the scope
/// filter (Common / All substances / each present category) and a "Has half-life" toggle — the pill search
/// bar at the very top is the only inline control.
///
/// Layout shape (the frozen-column trick): the header and body each split into a fixed left column and a
/// horizontally-scrolling right region. Because **all** data rows live inside one `ScrollView(.horizontal)`,
/// their horizontal offset is inherently shared — only the header must be re-synced, which it does by
/// reading the body scroll view's `contentOffset.x` via `onScrollGeometryChange` and shifting its own data
/// cells by that amount (clipped to the viewport). The frozen name column never moves.
///
/// Performance: the table defaults to the **Common** scope (~20 rows) so it never renders all ~1100
/// substances on open. The PK base rows resolve once off-main (`pharmaTableRowsOffMain`). The receptor
/// columns (Targets/Potency) need `PharmacologyParameters`, which is resolved off-main *per scope* via
/// `pharmacologyParametersBatchOffMain` and cached by name — so Common is instant and only the opt-in
/// "All substances" scope pays the ~1100-substance batch (once, with a resolving hint on those cells).
struct PharmaTableView: View {
    @State private var allRows: [PharmaTableRow] = []
    @State private var isLoading = true

    /// Lowercased canonical names carrying the metadata `"common"` tag — the same set the Library's
    /// "Common" card surfaces (`SubstanceLibrary.substances(taggedWith: "common")`). Populated at load.
    @State private var commonNames: Set<String> = []

    /// Receptor/mechanism parameters resolved off-main for a scope, cached by canonical name so
    /// re-filtering / re-sorting never re-resolves. Drives the Targets + Potency columns.
    @State private var pharmacologyByName: [String: PharmacologyParameters] = [:]
    @State private var resolvingPharma = false

    @State private var searchText = ""
    @State private var scope: Scope = .common
    @State private var halfLifeOnly = false
    @State private var enabledOptionalColumns: Set<PharmaColumn> = []

    @State private var sortKey: SortKey = .name
    @State private var sortAscending = true

    /// Header horizontal shift, driven by the body's horizontal scroll offset.
    @State private var headerOffset: CGFloat = 0

    private let nameColumnWidth: CGFloat = 148
    private let rowHeight: CGFloat = 52

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            if isLoading {
                loadingState
            } else if visibleRows.isEmpty {
                emptyState
            } else {
                table
            }
        }
        .background(Theme.background)
        .navigationTitle(Text("Pharma Table"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                filterMenu
            }
        }
        .task {
            guard allRows.isEmpty else { return }
            commonNames = Set(SubstanceLibrary.substances(taggedWith: "common").map { $0.name.lowercased() })
            let resolved = await SubstanceStore.shared.pharmaTableRowsOffMain()
            allRows = resolved
            isLoading = false
        }
        // Resolve receptor/mechanism parameters for the current scope off-main, once per scope. Keyed on
        // the loaded row count (so it fires when the base rows land) + the scope descriptor (so switching
        // scope re-resolves the newly-visible set). Already-cached names are skipped.
        .task(id: "\(allRows.count)|\(scope.descriptor)") {
            await resolvePharmacologyForScope()
        }
    }

    // MARK: - Search (pill)

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.secondaryLabel)
            TextField(text: $searchText) {
                Text("Search substances")
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.secondaryLabel)
                }
                .accessibilityLabel(Text("Clear search"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .themeCapsule()
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Filter + columns menu (navbar)

    private var filterMenu: some View {
        Menu {
            Picker(selection: $scope) {
                Text("Common").tag(Scope.common)
                Text("All substances").tag(Scope.all)
                ForEach(availableCategories, id: \.self) { category in
                    Text(category.displayName).tag(Scope.category(category))
                }
            } label: {
                Text("Show")
            }

            Section {
                Toggle(isOn: $halfLifeOnly) {
                    Label("Has half-life", systemImage: "clock.arrow.circlepath")
                }
            }

            Section {
                ForEach(PharmaColumn.optionalColumns) { column in
                    Toggle(isOn: columnBinding(column)) {
                        Text(column.title)
                    }
                }
            } header: {
                Text("PK columns")
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel(Text("Filters and columns"))
    }

    private func columnBinding(_ column: PharmaColumn) -> Binding<Bool> {
        Binding(
            get: { enabledOptionalColumns.contains(column) },
            set: { isOn in
                if isOn { enabledOptionalColumns.insert(column) } else { enabledOptionalColumns.remove(column) }
            },
        )
    }

    // MARK: - Table

    /// The frozen-column table. A `GeometryReader` bounds the horizontal scroll region to
    /// `width − nameColumnWidth`; without an explicit width the nested `ScrollView(.horizontal)` expands
    /// to its content width, blowing up the enclosing stack and shoving everything off-screen.
    private var table: some View {
        GeometryReader { geometry in
            let dataViewportWidth = max(0, geometry.size.width - nameColumnWidth)
            VStack(spacing: 0) {
                headerRow(dataViewportWidth: dataViewportWidth)
                Divider()
                bodyRows(dataViewportWidth: dataViewportWidth)
            }
        }
    }

    private func headerRow(dataViewportWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            substanceHeaderCell
            dataHeaderCells
                .offset(x: -headerOffset)
                .frame(width: dataViewportWidth, alignment: .leading)
                .clipped()
        }
        .frame(height: 44)
        .background(Theme.background)
    }

    private var substanceHeaderCell: some View {
        Button {
            toggleSort(.name)
        } label: {
            HStack(spacing: 4) {
                Text("Substance")
                    .font(.footnote.weight(.semibold))
                sortChevron(for: .name)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(width: nameColumnWidth, height: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(sortKey == .name ? Theme.accent : .primary)
        .accessibilityLabel(Text("Sort by substance name"))
        .accessibilityValue(sortAccessibilityValue(for: .name))
    }

    private var dataHeaderCells: some View {
        HStack(spacing: 0) {
            ForEach(visibleColumns) { column in
                Button {
                    toggleSort(.column(column))
                } label: {
                    VStack(alignment: column.isText ? .leading : .trailing, spacing: 1) {
                        HStack(spacing: 3) {
                            if !column.isText { sortChevron(for: .column(column)) }
                            Text(column.title)
                                .font(.footnote.weight(.semibold))
                                .lineLimit(1)
                            if column.isText { sortChevron(for: .column(column)) }
                        }
                        if let unit = column.unit {
                            Text(verbatim: unit)
                                .font(.caption2)
                                .foregroundStyle(Theme.secondaryLabel)
                        }
                    }
                    .padding(column.isText ? .leading : .trailing, 12)
                    .frame(width: column.width, height: 44, alignment: column.frameAlignment)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(sortKey == .column(column) ? Theme.accent : .primary)
                .accessibilityLabel(Text("Sort by \(column.accessibilityName)"))
                .accessibilityValue(sortAccessibilityValue(for: .column(column)))
            }
        }
    }

    private func bodyRows(dataViewportWidth: CGFloat) -> some View {
        let rows = visibleRows
        return ScrollView(.vertical) {
            HStack(alignment: .top, spacing: 0) {
                // Frozen left column — outside any horizontal scroll.
                LazyVStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        nameCell(row, index: index)
                    }
                }
                .frame(width: nameColumnWidth)

                // Single horizontal scroll holds every data row, so horizontal
                // scrolling is inherently synchronized across all rows. An explicit
                // viewport width keeps it from expanding to its content width.
                ScrollView(.horizontal, showsIndicators: true) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            dataRow(row, index: index)
                        }
                    }
                }
                .frame(width: dataViewportWidth)
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.x
                } action: { _, newValue in
                    headerOffset = max(0, newValue)
                }
            }
        }
    }

    private func nameCell(_ row: PharmaTableRow, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.name)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let category = row.category {
                Text(category.displayName)
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryLabel)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .frame(width: nameColumnWidth, height: rowHeight, alignment: .leading)
        .background(rowBackground(index))
    }

    private func dataRow(_ row: PharmaTableRow, index: Int) -> some View {
        let params = pharmacologyByName[row.name]
        return HStack(spacing: 0) {
            ForEach(visibleColumns) { column in
                dataCell(column, row: row, params: params, index: index)
            }
        }
        .background(rowBackground(index))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rowAccessibilityLabel(row, params: params))
    }

    private func dataCell(_ column: PharmaColumn, row: PharmaTableRow, params: PharmacologyParameters?, index _: Int) -> some View {
        // Distinguish "resolving" (receptor batch in flight) from "no data" so a Common-scope open never
        // flashes an empty Targets column as though the drug had no receptors.
        let awaiting = column.needsParams && params == nil && resolvingPharma
        let text = awaiting ? Self.resolvingPlaceholder : cellText(row, column, params: params)
        let isFaint = text == Self.missingPlaceholder || text == Self.resolvingPlaceholder
        return Text(text)
            .font(column.isText ? .footnote : .footnote.monospacedDigit())
            .foregroundStyle(isFaint ? AnyShapeStyle(Theme.secondaryLabel.opacity(0.6)) : AnyShapeStyle(.primary))
            .lineLimit(column.isText ? 2 : 1)
            .multilineTextAlignment(column.isText ? .leading : .trailing)
            .padding(column.isText ? .leading : .trailing, 12)
            .padding(column.isText ? .trailing : .leading, 8)
            .frame(width: column.width, height: rowHeight, alignment: column.frameAlignment)
    }

    private func rowBackground(_ index: Int) -> some View {
        index.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.035)
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading pharmacology…")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tablecells")
                .font(.largeTitle)
                .foregroundStyle(Theme.secondaryLabel)
            Text("No substances match these filters.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Derived data

    /// The scope-only slice of the base rows (before search / half-life / sort). Also the set whose
    /// receptor parameters the resolve task warms.
    private var scopeFilteredRows: [PharmaTableRow] {
        switch scope {
        case .common: allRows.filter { commonNames.contains($0.name.lowercased()) }
        case .all: allRows
        case let .category(category): allRows.filter { $0.category == category }
        }
    }

    private var visibleRows: [PharmaTableRow] {
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

    private var visibleColumns: [PharmaColumn] {
        PharmaColumn.allCases.filter { $0.isDefault || enabledOptionalColumns.contains($0) }
    }

    private var availableCategories: [SubstanceCategory] {
        let present = Set(allRows.compactMap(\.category))
        return SubstanceCategory.allCases.filter { present.contains($0) }
    }

    private func resolvePharmacologyForScope() async {
        let names = scopeFilteredRows.map(\.name).filter { pharmacologyByName[$0] == nil }
        guard !names.isEmpty else { return }
        resolvingPharma = true
        defer { resolvingPharma = false }
        let resolved = await SubstanceStore.shared.pharmacologyParametersBatchOffMain(forNames: names)
        for (key, value) in resolved {
            pharmacologyByName[key] = value
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

    private func toggleSort(_ key: SortKey) {
        if sortKey == key {
            sortAscending.toggle()
        } else {
            sortKey = key
            sortAscending = true
        }
    }

    @ViewBuilder
    private func sortChevron(for key: SortKey) -> some View {
        if sortKey == key {
            Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                .font(.caption2.weight(.bold))
        }
    }

    private func sortAccessibilityValue(for key: SortKey) -> Text {
        guard sortKey == key else { return Text("Not sorted") }
        return sortAscending ? Text("Sorted ascending") : Text("Sorted descending")
    }

    // MARK: - Formatting

    private static let missingPlaceholder = "—"
    private static let resolvingPlaceholder = "…"

    private func cellText(_ row: PharmaTableRow, _ column: PharmaColumn, params: PharmacologyParameters?) -> String {
        if column.isText {
            return column.textValue(row, params: params) ?? Self.missingPlaceholder
        }
        guard let value = column.numericValue(row, params: params) else { return Self.missingPlaceholder }
        switch column {
        case .halfLife, .tmax:
            return Self.formatDuration(value)
        case .potency:
            return formatNm(value) // shared with the detail-screen receptor rows; the "nM" unit is in the header
        default:
            return Self.formatNumber(value)
        }
    }

    /// Human duration: "35 min", "4.5 h", "3 days". Mirrors `HalfLifeCalculatorView.formatDuration`.
    private static func formatDuration(_ minutes: Double) -> String {
        if minutes < 60 {
            return String(localized: "\(Int(minutes.rounded())) min")
        }
        let hours = minutes / 60
        if hours < 48 {
            return String(localized: "\(formatNumber(hours)) h")
        }
        let days = Int((minutes / 1_440).rounded())
        return String(localized: "\(days) days")
    }

    /// Compact decimal: integers stay integers, otherwise up to one significant fractional digit,
    /// with trailing zeros trimmed. Keeps numeric cells narrow and aligned.
    private static func formatNumber(_ value: Double) -> String {
        if value == value.rounded() {
            return String(Int(value))
        }
        return value >= 100
            ? String(Int(value.rounded()))
            : String(format: "%.1f", value)
    }

    private func rowAccessibilityLabel(_ row: PharmaTableRow, params: PharmacologyParameters?) -> Text {
        var parts: [String] = [row.name]
        if let category = row.category {
            parts.append(String(localized: category.displayName))
        }
        for column in visibleColumns {
            let value = cellText(row, column, params: params)
            guard value != Self.missingPlaceholder, value != Self.resolvingPlaceholder else { continue }
            let unit = column.unit.map { " \($0)" } ?? ""
            parts.append("\(String(localized: column.title)) \(value)\(unit)")
        }
        return Text(parts.joined(separator: ", "))
    }
}

/// The table's scope filter: the friendly Common default, the full library, or one browse category.
private enum Scope: Hashable {
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
private enum SortKey: Equatable {
    case name
    case column(PharmaColumn)
}

/// The scrollable data columns, in display order (default receptor/mechanism story first, PK detail after).
/// Each knows its header title, unit, width, alignment, whether it's textual, and how to read its value off
/// a ``PharmaTableRow`` + resolved ``PharmacologyParameters`` (for sorting and cell formatting).
private enum PharmaColumn: String, CaseIterable, Identifiable {
    // Default (always-on) — the point of the table.
    case mechanism
    case targets
    case halfLife
    case potency
    // Optional (PK detail) — off by default, switched on from the navbar menu.
    case tmax
    case bioavailability
    case cmax
    case proteinBinding
    case vd
    case clearance

    var id: String {
        rawValue
    }

    static let defaultColumns: [PharmaColumn] = [.mechanism, .targets, .halfLife, .potency]
    static let optionalColumns: [PharmaColumn] = [.tmax, .bioavailability, .cmax, .proteinBinding, .vd, .clearance]

    var isDefault: Bool {
        Self.defaultColumns.contains(self)
    }

    /// Textual columns (Mechanism, Targets) sort alphabetically, left-align, wrap to two lines, and get a
    /// wider cell — a Double sort / right-alignment doesn't apply to prose.
    var isText: Bool {
        self == .mechanism || self == .targets
    }

    /// Columns whose value comes from the (lazily-resolved) receptor parameters, not the base PK row.
    var needsParams: Bool {
        self == .targets || self == .potency
    }

    var width: CGFloat {
        switch self {
        case .mechanism: 224
        case .targets: 172
        default: 108
        }
    }

    var frameAlignment: Alignment {
        isText ? .leading : .trailing
    }

    var title: LocalizedStringResource {
        switch self {
        case .mechanism: "Mechanism"
        case .targets: "Targets"
        case .halfLife: "Half-life"
        case .potency: "Potency"
        case .tmax: "Tmax"
        case .bioavailability: "Bioavailability"
        case .cmax: "Cmax"
        case .proteinBinding: "Protein binding"
        case .vd: "Vd"
        case .clearance: "Clearance"
        }
    }

    /// VoiceOver-friendly full name for the sortable header.
    var accessibilityName: LocalizedStringResource {
        switch self {
        case .mechanism: "mechanism of action"
        case .targets: "primary receptor targets"
        case .halfLife: "half-life"
        case .potency: "primary target potency"
        case .tmax: "time to peak"
        case .bioavailability: "bioavailability"
        case .cmax: "maximum concentration"
        case .proteinBinding: "protein binding"
        case .vd: "volume of distribution"
        case .clearance: "clearance"
        }
    }

    /// Scientific unit symbol shown under the header. `nil` for duration + text columns, whose cells carry
    /// their own unit (min / h / days) or none. Unit symbols are international notation — not localized.
    var unit: String? {
        switch self {
        case .mechanism, .targets, .halfLife, .tmax: nil
        case .potency: "nM"
        case .bioavailability, .proteinBinding: "%"
        case .cmax: "ng/mL"
        case .vd: "L/kg"
        case .clearance: "mL/min/kg"
        }
    }

    /// Numeric value for a numeric column (nil for text columns) — used for sorting + cell formatting.
    func numericValue(_ row: PharmaTableRow, params: PharmacologyParameters?) -> Double? {
        switch self {
        case .halfLife: row.halfLifeMin
        case .potency: params?.primaryTarget?.halfMaxNanomolar
        case .tmax: row.tmaxMin
        case .bioavailability: row.bioavailabilityPct
        case .cmax: row.cmaxNgPerMl
        case .proteinBinding: row.proteinBindingPct
        case .vd: row.vdLPerKg
        case .clearance: row.clearanceMlPerMinPerKg
        case .mechanism, .targets: nil
        }
    }

    /// Text value for a text column (nil for numeric columns / when unresolved).
    func textValue(_ row: PharmaTableRow, params: PharmacologyParameters?) -> String? {
        switch self {
        case .mechanism:
            return row.mechanismLabel
        case .targets:
            guard let params else { return nil }
            // Top receptors by affinity (targets are pre-sorted tightest-first), collapsed to distinct
            // base names so one receptor measured at two actions/enantiomers doesn't fill the cell.
            var seen = Set<String>()
            var names: [String] = []
            for engagement in params.targets {
                let name = splitTarget(engagement.target).name
                if seen.insert(name).inserted { names.append(name) }
                if names.count == 3 { break }
            }
            return names.isEmpty ? nil : names.joined(separator: " · ")
        default:
            return nil
        }
    }
}

#Preview {
    NavigationStack { PharmaTableView() }
}
