import SwiftData
import SwiftUI

// MARK: - Sorting

private extension InventoryItem {
    /// Sort priority: out first, then low, then healthy.
    var sortPriority: Int {
        switch stockStatus {
        case .out: 0
        case .low: 1
        case .ok: 2
        }
    }

    /// Most recent manual activity, falling back to creation — used to order
    /// items of equal status by "recently used".
    var lastActivity: Date {
        manualEvents.map(\.date).max() ?? createdAt
    }
}

/// Order by status (out → low → ok), then most-recent activity within a status.
private func inventorySorted(_ items: [InventoryItem]) -> [InventoryItem] {
    items.sorted {
        if $0.sortPriority != $1.sortPriority { return $0.sortPriority < $1.sortPriority }
        return $0.lastActivity > $1.lastActivity
    }
}

// MARK: - Tools summary card

/// The Inventory entry on the Tools tab: a compact hub card showing the three
/// highest-priority items (out → low → recent), tapping into the manager.
struct InventorySummaryCard: View {
    @Query private var items: [InventoryItem]
    @Query private var substanceColors: [SubstanceColor]

    private var colorMap: [String: Color] {
        Array(substanceColors).colorMap
    }
    private var topItems: [InventoryItem] {
        Array(inventorySorted(items).prefix(3))
    }

    var body: some View {
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
                InventorySupplyBar(fraction: fraction, tint: item.supplyBarTint(colorMap: colorMap))
                    .padding(.leading, 19)
            }
        }
    }
}

// MARK: - Manager list

/// The inventory manager: one grouped list (no section headers — low/out simply
/// sort to the top), each row tapping into the item detail. The `+` opens the
/// generic add form.
struct InventoryListView: View {
    @Query private var items: [InventoryItem]
    @Query private var substanceColors: [SubstanceColor]
    @Environment(\.appNavigator) private var navigator
    @Environment(\.modelContext) private var modelContext

    private var colorMap: [String: Color] {
        Array(substanceColors).colorMap
    }

    /// Display order: the user's manual arrangement once they've dragged a row,
    /// otherwise the status-based auto-sort. Every item starts at `sortOrder == 0`,
    /// so a list nobody has reordered stays status-sorted; the first drag renumbers
    /// the whole list and `sortOrder` takes over from then on.
    private var sorted: [InventoryItem] {
        if items.allSatisfy({ $0.sortOrder == 0 }) {
            return inventorySorted(items)
        }
        return items.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        Group {
            if items.isEmpty {
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
            } else {
                List {
                    ForEach(sorted) { item in
                        NavigationLink {
                            InventoryItemDetailView(item: item)
                        } label: {
                            InventoryRow(item: item, colorMap: colorMap)
                        }
                        .listRowBackground(CardBackground())
                    }
                    .onMove(perform: move)
                    .onDelete(perform: delete)
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Theme.background)
        .navigationTitle("Inventory")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !items.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
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

    /// Persist the dragged order, renumbering the whole list so `sortOrder`
    /// governs display from here on.
    private func move(from source: IndexSet, to destination: Int) {
        var ordered = sorted
        ordered.move(fromOffsets: source, toOffset: destination)
        InventoryService.reorder(ordered)
    }

    /// Stop tracking the swiped items.
    private func delete(at offsets: IndexSet) {
        let toDelete = offsets.map { sorted[$0] }
        for item in toDelete {
            InventoryService.delete(item, in: modelContext)
        }
    }
}

/// A manager row: dot, title (+ salt inline), a subtitle (doses-left, or
/// last-dose date when out), the plain trailing number, and a status-tinted bar
/// below when the item has a baseline.
private struct InventoryRow: View {
    let item: InventoryItem
    let colorMap: [String: Color]

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                SubstanceDot(name: item.substance, colorMap: colorMap, size: 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayTitle)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                }
                Spacer(minLength: 8)
                StockAmountText(item: item, style: .title3)
            }
            if let fraction = item.fillFraction {
                InventorySupplyBar(fraction: fraction, tint: item.supplyBarTint(colorMap: colorMap))
                    .padding(.leading, 22)
            }
        }
        .padding(.vertical, 4)
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
                    .foregroundStyle(status.numberColor)
                Text(item.unit)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
            }
        }
    }
}
