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
    @State private var model = PharmaTableModel()

    /// The opt-in PK columns switched on from the navbar menu — presentation only,
    /// so toggling one never invalidates the row set the model holds.
    @State private var enabledOptionalColumns: Set<PharmaColumn> = []

    /// Header horizontal shift, driven by the body's horizontal scroll offset.
    /// An `@Observable` box rather than plain `@State`: only ``HeaderPan`` reads
    /// it, so a scroll tick re-positions the header without re-running this
    /// view's whole body (which would re-filter and re-sort every visible row
    /// per frame).
    @State private var headerOffset = PharmaHeaderOffset()

    private var visibleColumns: [PharmaColumn] {
        PharmaColumn.allCases.filter { $0.isDefault || enabledOptionalColumns.contains($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            PharmaSearchField(text: $model.searchText)
            Divider()
            if model.isLoading {
                PharmaLoadingState()
            } else if model.visibleRows.isEmpty {
                PharmaEmptyState()
            } else {
                PharmaTableGrid(model: model, columns: visibleColumns, headerOffset: headerOffset)
            }
        }
        .background(Theme.background)
        .navigationTitle(Text("Pharma Table"))
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .platformTopBarTrailing) {
                PharmaFilterMenu(
                    scope: $model.scope,
                    halfLifeOnly: $model.halfLifeOnly,
                    enabledOptionalColumns: $enabledOptionalColumns,
                    availableCategories: model.availableCategories,
                )
            }
        }
        .task { await model.load() }
        // Resolve receptor/mechanism parameters for the current scope off-main, once per scope. Keyed on
        // the loaded row count (so it fires when the base rows land) + the scope descriptor (so switching
        // scope re-resolves the newly-visible set). Already-cached names are skipped.
        .task(id: "\(model.allRows.count)|\(model.scope.descriptor)") {
            await model.resolvePharmacologyForScope()
        }
    }
}

// MARK: - Metrics

/// The table's fixed geometry. A frozen column and a scrolling region only line
/// up while the header and every row agree on these to the point.
private enum PharmaTableMetrics {
    static let nameColumnWidth: CGFloat = 148
    static let rowHeight: CGFloat = 52
    static let headerHeight: CGFloat = 44
}

/// Zebra striping for the row at `index`, drawn identically behind the frozen
/// name cell and the scrolling data row so a stripe never splits at the seam.
private func pharmaRowBackground(_ index: Int) -> Color {
    index.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.035)
}

// MARK: - Search (pill)

private struct PharmaSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.secondaryLabel)
                .accessibilityHidden(true)
            TextField(text: $text) {
                Text("Search substances")
            }
            .neverAutocapitalize()
            .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.secondaryLabel)
                }
                .accessibilityLabel(Text("Clear search"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, Spacing.lg)
        .themeCapsule()
        .padding(.horizontal, Spacing.xxl)
        .padding(.vertical, Spacing.lg)
    }
}

// MARK: - Filter + columns menu (navbar)

private struct PharmaFilterMenu: View {
    @Binding var scope: PharmaTableModel.Scope
    @Binding var halfLifeOnly: Bool
    @Binding var enabledOptionalColumns: Set<PharmaColumn>
    let availableCategories: [SubstanceCategory]

    var body: some View {
        Menu {
            Picker(selection: $scope) {
                Text("Common").tag(PharmaTableModel.Scope.common)
                Text("All substances").tag(PharmaTableModel.Scope.all)
                ForEach(availableCategories, id: \.self) { category in
                    Text(category.displayName).tag(PharmaTableModel.Scope.category(category))
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
}

// MARK: - Table

/// The frozen-column table. A `GeometryReader` bounds the horizontal scroll region to
/// `width − nameColumnWidth`; without an explicit width the nested `ScrollView(.horizontal)` expands
/// to its content width, blowing up the enclosing stack and shoving everything off-screen.
private struct PharmaTableGrid: View {
    let model: PharmaTableModel
    let columns: [PharmaColumn]
    let headerOffset: PharmaHeaderOffset

    var body: some View {
        GeometryReader { geometry in
            let dataViewportWidth = max(0, geometry.size.width - PharmaTableMetrics.nameColumnWidth)
            VStack(spacing: 0) {
                PharmaHeaderRow(
                    model: model,
                    columns: columns,
                    headerOffset: headerOffset,
                    dataViewportWidth: dataViewportWidth,
                )
                Divider()
                PharmaBodyRows(
                    model: model,
                    rows: model.visibleRows,
                    columns: columns,
                    headerOffset: headerOffset,
                    dataViewportWidth: dataViewportWidth,
                )
            }
        }
    }
}

private struct PharmaHeaderRow: View {
    let model: PharmaTableModel
    let columns: [PharmaColumn]
    let headerOffset: PharmaHeaderOffset
    let dataViewportWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            PharmaSubstanceHeaderCell(model: model)
            HeaderPan(model: headerOffset, width: dataViewportWidth) {
                PharmaDataHeaderCells(model: model, columns: columns)
            }
        }
        .frame(height: PharmaTableMetrics.headerHeight)
        .background(Theme.background)
    }
}

private struct PharmaSubstanceHeaderCell: View {
    let model: PharmaTableModel

    private var isActive: Bool {
        model.sortKey == .name
    }

    var body: some View {
        Button {
            model.toggleSort(.name)
        } label: {
            HStack(spacing: Spacing.xs) {
                Text("Substance")
                    .font(.footnote.weight(.semibold))
                PharmaSortChevron(isActive: isActive, ascending: model.sortAscending)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.xl)
            .frame(
                width: PharmaTableMetrics.nameColumnWidth,
                height: PharmaTableMetrics.headerHeight,
                alignment: .leading,
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isActive ? Theme.accent : .primary)
        .accessibilityLabel(Text("Sort by substance name"))
        .accessibilityValue(PharmaCellFormat.sortAccessibilityValue(isActive: isActive, ascending: model.sortAscending))
    }
}

private struct PharmaDataHeaderCells: View {
    let model: PharmaTableModel
    let columns: [PharmaColumn]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(columns) { column in
                let isActive = model.sortKey == .column(column)
                Button {
                    model.toggleSort(.column(column))
                } label: {
                    VStack(alignment: column.isText ? .leading : .trailing, spacing: 1) {
                        HStack(spacing: 3) {
                            if !column.isText {
                                PharmaSortChevron(isActive: isActive, ascending: model.sortAscending)
                            }
                            Text(column.title)
                                .font(.footnote.weight(.semibold))
                                .lineLimit(1)
                            if column.isText {
                                PharmaSortChevron(isActive: isActive, ascending: model.sortAscending)
                            }
                        }
                        if let unit = column.unit {
                            Text(verbatim: unit)
                                .font(.caption2)
                                .foregroundStyle(Theme.secondaryLabel)
                        }
                    }
                    .padding(column.isText ? .leading : .trailing, Spacing.xl)
                    .frame(
                        width: column.width,
                        height: PharmaTableMetrics.headerHeight,
                        alignment: column.frameAlignment,
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(isActive ? Theme.accent : .primary)
                .accessibilityLabel(Text("Sort by \(column.accessibilityName)"))
                .accessibilityValue(
                    PharmaCellFormat.sortAccessibilityValue(isActive: isActive, ascending: model.sortAscending),
                )
            }
        }
    }
}

private struct PharmaSortChevron: View {
    let isActive: Bool
    let ascending: Bool

    var body: some View {
        if isActive {
            Image(systemName: ascending ? "chevron.up" : "chevron.down")
                .font(.caption2.weight(.bold))
                .accessibilityHidden(true)
        }
    }
}

private struct PharmaBodyRows: View {
    let model: PharmaTableModel
    let rows: [PharmaTableRow]
    let columns: [PharmaColumn]
    let headerOffset: PharmaHeaderOffset
    let dataViewportWidth: CGFloat

    var body: some View {
        ScrollView(.vertical) {
            HStack(alignment: .top, spacing: 0) {
                // Frozen left column — outside any horizontal scroll.
                LazyVStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        PharmaNameCell(row: row, index: index)
                    }
                }
                .frame(width: PharmaTableMetrics.nameColumnWidth)

                // Single horizontal scroll holds every data row, so horizontal
                // scrolling is inherently synchronized across all rows. An explicit
                // viewport width keeps it from expanding to its content width.
                ScrollView(.horizontal, showsIndicators: true) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            PharmaDataRow(
                                row: row,
                                index: index,
                                columns: columns,
                                params: model.pharmacologyByName[row.name],
                                resolving: model.resolvingPharma,
                            )
                        }
                    }
                }
                .frame(width: dataViewportWidth)
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.x
                } action: { [headerOffset] _, newValue in
                    headerOffset.value = max(0, newValue)
                }
            }
        }
    }
}

private struct PharmaNameCell: View {
    let row: PharmaTableRow
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
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
        .padding(.horizontal, Spacing.xl)
        .frame(
            width: PharmaTableMetrics.nameColumnWidth,
            height: PharmaTableMetrics.rowHeight,
            alignment: .leading,
        )
        .background(pharmaRowBackground(index))
    }
}

private struct PharmaDataRow: View {
    let row: PharmaTableRow
    let index: Int
    let columns: [PharmaColumn]
    let params: PharmacologyParameters?
    let resolving: Bool

    var body: some View {
        HStack(spacing: 0) {
            ForEach(columns) { column in
                PharmaDataCell(column: column, row: row, params: params, resolving: resolving)
            }
        }
        .background(pharmaRowBackground(index))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PharmaCellFormat.rowAccessibilityLabel(row, columns: columns, params: params))
    }
}

private struct PharmaDataCell: View {
    let column: PharmaColumn
    let row: PharmaTableRow
    let params: PharmacologyParameters?
    let resolving: Bool

    var body: some View {
        // Distinguish "resolving" (receptor batch in flight) from "no data" so a Common-scope open never
        // flashes an empty Targets column as though the drug had no receptors.
        let awaiting = column.needsParams && params == nil && resolving
        let text = awaiting
            ? PharmaCellFormat.resolvingPlaceholder
            : PharmaCellFormat.cellText(row, column, params: params)
        let isFaint = text == PharmaCellFormat.missingPlaceholder || text == PharmaCellFormat.resolvingPlaceholder
        Text(text)
            .font(column.isText ? .footnote : .footnote.monospacedDigit())
            .foregroundStyle(isFaint ? AnyShapeStyle(Theme.secondaryLabel.opacity(0.6)) : AnyShapeStyle(.primary))
            .lineLimit(column.isText ? 2 : 1)
            .multilineTextAlignment(column.isText ? .leading : .trailing)
            .padding(column.isText ? .leading : .trailing, Spacing.xl)
            .padding(column.isText ? .trailing : .leading, Spacing.md)
            .frame(width: column.width, height: PharmaTableMetrics.rowHeight, alignment: column.frameAlignment)
    }
}

// MARK: - States

private struct PharmaLoadingState: View {
    var body: some View {
        VStack(spacing: Spacing.xl) {
            ProgressView()
            Text("Loading pharmacology…")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PharmaEmptyState: View {
    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "tablecells")
                .font(.largeTitle)
                .foregroundStyle(Theme.secondaryLabel)
                .accessibilityHidden(true)
            Text("No substances match these filters.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Formatting

/// Cell text and the VoiceOver strings built from it — pure functions of a row,
/// a column, and whatever receptor parameters have resolved so far.
private enum PharmaCellFormat {
    static let missingPlaceholder = "—"
    static let resolvingPlaceholder = "…"

    static func cellText(_ row: PharmaTableRow, _ column: PharmaColumn, params: PharmacologyParameters?) -> String {
        if column.isText {
            return column.textValue(row, params: params) ?? missingPlaceholder
        }
        guard let value = column.numericValue(row, params: params) else { return missingPlaceholder }
        switch column {
        case .halfLife, .tmax:
            return formatDuration(value)
        case .potency:
            return formatNm(value) // shared with the detail-screen receptor rows; the "nM" unit is in the header
        default:
            return formatNumber(value)
        }
    }

    /// Human duration: "35 min", "4.5 h", "3 days". Mirrors `HalfLifeCalculatorView.formatDuration`.
    static func formatDuration(_ minutes: Double) -> String {
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
    static func formatNumber(_ value: Double) -> String {
        if value == value.rounded() {
            return String(Int(value))
        }
        return value >= 100
            ? String(Int(value.rounded()))
            : String(format: "%.1f", value)
    }

    static func rowAccessibilityLabel(
        _ row: PharmaTableRow,
        columns: [PharmaColumn],
        params: PharmacologyParameters?,
    ) -> Text {
        var parts: [String] = [row.name]
        if let category = row.category {
            parts.append(String(localized: category.displayName))
        }
        for column in columns {
            let value = cellText(row, column, params: params)
            guard value != missingPlaceholder, value != resolvingPlaceholder else { continue }
            let unit = column.unit.map { " \($0)" } ?? ""
            parts.append("\(String(localized: column.title)) \(value)\(unit)")
        }
        return Text(parts.joined(separator: ", "))
    }

    static func sortAccessibilityValue(isActive: Bool, ascending: Bool) -> Text {
        guard isActive else { return Text("Not sorted") }
        return ascending ? Text("Sorted ascending") : Text("Sorted descending")
    }
}

// MARK: - Columns

/// The scrollable data columns, in display order (default receptor/mechanism story first, PK detail after).
/// Each knows its header title, unit, width, alignment, whether it's textual, and how to read its value off
/// a ``PharmaTableRow`` + resolved ``PharmacologyParameters`` (for sorting and cell formatting).
enum PharmaColumn: String, CaseIterable, Identifiable {
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

// MARK: - Header pan

/// The header's horizontal scroll offset — see the `headerOffset` property.
@Observable @MainActor
final class PharmaHeaderOffset {
    var value: CGFloat = 0
}

/// Shifts the data header cells by the body scroll's offset. The only view that
/// reads ``PharmaHeaderOffset``, so per-frame scroll updates re-evaluate just
/// this wrapper — the `content` it positions was built by the parent and is
/// reused as-is.
private struct HeaderPan<Content: View>: View {
    let model: PharmaHeaderOffset
    let width: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        content
            .offset(x: -model.value)
            .frame(width: width, alignment: .leading)
            .clipped()
    }
}

#Preview {
    NavigationStack { PharmaTableView() }
}
