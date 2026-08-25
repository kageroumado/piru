import SwiftData
import SwiftUI

// MARK: - Tools summary card

/// The Inventory entry on the Tools tab: a compact hub card showing the first
/// three items in the manager's own order, tapping into the manager.
///
/// By default that's needs-attention-first (out → low → recent), but a sort or
/// class arrangement chosen in the manager reorders this card too — the card is
/// a window onto that screen, so the two agreeing on "first" is the point.
struct InventorySummaryCard: View {
    @Query private var items: [InventoryItem]
    @Query private var substanceColors: [SubstanceColor]

    /// The manager's own model, so a sort or class arrangement chosen there is
    /// reflected here without any syncing.
    private var model: InventoryListModel {
        .shared
    }

    private var colorMap: [String: Color] {
        Array(substanceColors).colorMap
    }

    /// Rows render only once the substance batch cache is warm: the manager's
    /// ordering resolves a category per item, and on a cold cache that falls
    /// through to a synchronous main-actor batch build — the Tools tab's
    /// cold-launch stall. Until then the card shows its subtitle, one frame in
    /// the warm case.
    @State private var warmed = false

    var body: some View {
        // Ordered once per body pass, not as three separate computed-property
        // reads (emptiness, rows, count) — each of those would re-sort the
        // inventory.
        let topItems = warmed ? Array(model.ordered(items).prefix(3)) : []
        GlanceCard(icon: Tool.inventory.icon, title: Text(Tool.inventory.name), route: .tool(.inventory)) {
            if topItems.isEmpty {
                Text("Track how much you have on hand")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
            } else {
                VStack(spacing: 10) {
                    ForEach(topItems) { item in
                        InventorySummaryRow(item: item, colorMap: colorMap)
                    }
                    if items.count > topItems.count {
                        GlanceMoreRow(count: items.count - topItems.count)
                    }
                }
            }
        }
        .task {
            await SubstanceStore.shared.ensureAllLoaded()
            warmed = true
        }
    }
}

/// One image-style row inside the Tools summary card: dot + name, the plain
/// number (colored only for Low/Out), and a bar below when a baseline exists.
private struct InventorySummaryRow: View {
    let item: InventoryItem
    let colorMap: [String: Color]

    var body: some View {
        VStack(spacing: 8) {
            GlanceRow(dotColor: SubstancePalette.color(for: item.substance, colorMap: colorMap), title: Text(item.displayTitle)) {
                StockAmountText(item: item, style: .subheadline)
            }
            if let fraction = item.fillFraction {
                InventorySupplyBar(fraction: fraction, tint: item.stockStatus.barTint, status: item.stockStatus)
                    .padding(.leading, 19)
            }
        }
    }
}

// MARK: - Manager list

/// The inventory manager: a searchable, sortable list of everything tracked,
/// grouped by substance class by default.
///
/// The view is deliberately thin — all the arranging lives in
/// ``InventoryListModel``, and each row is its own `View` so a keystroke in the
/// search field doesn't re-evaluate 80 rows' worth of library lookups.
struct InventoryListView: View {
    @Query private var items: [InventoryItem]
    @Query private var substanceColors: [SubstanceColor]
    @Environment(\.appNavigator) private var navigator
    @Environment(\.modelContext) private var modelContext

    @Bindable private var model = InventoryListModel.shared
    /// Scoped to this `List` (not the whole navigation stack) so entering it from
    /// the menu's "Edit" doesn't put unrelated screens into edit mode.
    @State private var editMode: EditMode = .inactive
    /// A plain local sheet rather than a `SheetRoute`: the editor takes the model
    /// and its current section list as inputs, neither of which a `Codable`
    /// deep-linkable route can carry.
    @State private var showsClassOrder = false

    private var colorMap: [String: Color] {
        Array(substanceColors).colorMap
    }

    private var sections: [InventorySectionGroup] {
        model.sections(for: items)
    }

    var body: some View {
        Group {
            if items.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .background(Theme.background)
        .navigationTitle("Inventory")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        // Always-visible rather than pull-to-reveal: with dozens of tracked items
        // search is the primary way in, and a hidden field reads as "there is no
        // search here".
        .searchable(text: $model.searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Search Inventory"))
        .sheet(isPresented: $showsClassOrder) {
            // Seeded with the manager's *current* section order, so the editor
            // opens showing exactly what's on screen behind it.
            InventoryClassOrderView(model: model, categories: sections.compactMap(\.category))
        }
    }

    // MARK: Empty states

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Inventory Yet", systemImage: "shippingbox")
        } description: {
            Text("Track a substance to see how much you have left as you log doses.")
        } actions: {
            Button("Track a Substance") {
                navigator.present(.inventoryItemForm(id: nil))
            }
            .buttonStyle(.borderedProminent)
        }
    }

    /// Distinct from the "nothing tracked yet" state: here the user *has* items,
    /// they're just all filtered or searched away, so the way out is to widen the
    /// query rather than add stock.
    private var noMatchesState: some View {
        ContentUnavailableView {
            Label("No Matching Items", systemImage: "line.3.horizontal.decrease.circle")
        } description: {
            Text("No tracked substance matches the current search and filters.")
        } actions: {
            if model.hasActiveFilters {
                Button("Clear Filters") { model.clearFilters() }
            }
        }
    }

    // MARK: List

    @ViewBuilder
    private var list: some View {
        if sections.isEmpty {
            VStack(spacing: 0) {
                if model.hasActiveFilters { InventoryFilterBar(model: model) }
                noMatchesState
            }
        } else {
            List {
                ForEach(sections) { section in
                    Section {
                        // A collapsed section keeps its header (and its count) but
                        // renders no rows — folding it away entirely would lose the
                        // handle to get it back.
                        if section.category.map(model.isExpanded) ?? true {
                            rows(in: section)
                        }
                    } header: {
                        if let category = section.category {
                            sectionHeader(category, count: section.items.count)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .listSectionSpacing(16)
            .environment(\.editMode, $editMode)
            .safeAreaBar(edge: .top) {
                if model.hasActiveFilters { InventoryFilterBar(model: model) }
            }
        }
    }

    /// Rows carry `onMove` only in manual mode — attaching it unconditionally
    /// would let a drag silently renumber a list the user is viewing in some
    /// other order.
    @ViewBuilder
    private func rows(in section: InventorySectionGroup) -> some View {
        if model.canReorder {
            ForEach(section.items) { row($0) }
                .onMove(perform: move)
                .onDelete { delete(at: $0, in: section) }
        } else {
            ForEach(section.items) { row($0) }
                .onDelete { delete(at: $0, in: section) }
        }
    }

    private func row(_ item: InventoryItem) -> some View {
        NavigationLink {
            InventoryItemDetailView(item: item)
        } label: {
            InventoryRow(item: item, colorMap: colorMap)
        }
        .listRowBackground(CardBackground())
    }

    /// The whole header is the fold control — a small chevron alone would be a
    /// poor target, and there's nothing else in a header to tap.
    private func sectionHeader(_ category: SubstanceCategory, count: Int) -> some View {
        let expanded = model.isExpanded(category)
        return Button {
            withAnimation(.snappy(duration: 0.25)) { model.toggleCollapsed(category) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.caption2)
                    .accessibilityHidden(true)
                Text(category.displayName)
                Text(verbatim: "\(count)")
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.secondaryLabel)
                    .rotationEffect(.degrees(expanded ? 0 : -90))
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityValue(Text(expanded ? "Expanded" : "Collapsed"))
        .accessibilityHint(Text(expanded ? "Double tap to collapse" : "Double tap to expand"))
    }

    // MARK: Toolbar

    /// Two states, Files-style. Normally the bar carries just the overflow menu
    /// and the one primary action (`+`); while selecting, it collapses to `Done`
    /// so nothing competes with getting back out.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if editMode == .active {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { editMode = .inactive }
                    .fontWeight(.semibold)
            }
        } else {
            if !items.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    InventoryOptionsMenu(
                        model: model,
                        categories: model.availableCategories(in: items),
                        editMode: $editMode,
                        onArrangeClasses: { showsClassOrder = true },
                    )
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    navigator.present(.inventoryItemForm(id: nil))
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Inventory Item")
            }
        }
    }

    // MARK: Actions

    /// Persist the dragged order, renumbering the whole list so `sortOrder`
    /// governs display from here on. Only reachable in manual, ungrouped mode,
    /// so the visible list *is* the full list.
    private func move(from source: IndexSet, to destination: Int) {
        var ordered = sections.first?.items ?? []
        ordered.move(fromOffsets: source, toOffset: destination)
        InventoryService.reorder(ordered)
    }

    /// Stop tracking the swiped items. Offsets are section-local, so they're
    /// resolved against that section's rows rather than the flat list.
    private func delete(at offsets: IndexSet, in section: InventorySectionGroup) {
        for item in offsets.map({ section.items[$0] }) {
            InventoryService.delete(item, in: modelContext)
        }
    }
}

// MARK: - Row

/// A manager row, built to the app's standard row anatomy (the one the session
/// and journal rows use): a 9pt status dot, a `.body`-weight title over a
/// secondary subtitle, and the trailing amount. The supply bar, when the item
/// has a baseline, sits under the text column.
private struct InventoryRow: View {
    let item: InventoryItem
    let colorMap: [String: Color]

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(SubstancePalette.color(for: item.substance, colorMap: colorMap))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.displayTitle)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                }
                Spacer(minLength: 8)
                StockAmountText(item: item, style: .body)
            }
            if let fraction = item.fillFraction {
                InventorySupplyBar(fraction: fraction, tint: item.stockStatus.barTint, status: item.stockStatus)
                    .padding(.leading, 17)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    /// "~N doses left" when a dose size is tracked; for an Out item the last-dose
    /// date instead (so we don't repeat "Out"); otherwise nothing.
    private var subtitle: String? {
        if item.stockStatus == .out {
            guard let last = InventoryMath.doses(for: item, in: modelContext).map(\.timestamp).max() else {
                return nil
            }
            let formatted = last.formatted(.dateTime.month().day())
            return String(localized: "last dose \(formatted)")
        }
        if let doses = InventoryMath.dosesLeft(for: item) {
            return String(localized: "~\(doses) doses left")
        }
        return nil
    }
}

// MARK: - Amount text

/// The trailing stock number with a dimmed unit, or a colored "Out" — colored
/// only for Low/Out per the governing rule.
struct StockAmountText: View {
    let item: InventoryItem
    var style: Font = .body

    var body: some View {
        let status = item.stockStatus
        if status == .out {
            Text("Out")
                .font(style.weight(.semibold))
                .foregroundStyle(status.numberColor)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(item.currentQuantity.inventoryFormatted)
                    .font(style.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(status.numberColor)
                Text(item.unit)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryLabel)
            }
        }
    }
}
