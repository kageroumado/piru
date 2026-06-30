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
        NavigationLink(value: PushRoute.tool(.inventory)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    Image(systemName: Tool.inventory.icon)
                        .font(.title2)
                        .foregroundStyle(Theme.accent)
                        .frame(width: 32)
                    Text(Tool.inventory.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.secondaryLabel)
                }

                if topItems.isEmpty {
                    Text("Track how much you have on hand")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryLabel)
                } else {
                    VStack(spacing: 10) {
                        ForEach(topItems) { item in
                            InventorySummaryRow(item: item, colorMap: colorMap)
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .themeCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// One image-style row inside the Tools summary card: dot + name, the plain
/// number (colored only for Low/Out), and a bar below when a baseline exists.
private struct InventorySummaryRow: View {
    let item: InventoryItem
    let colorMap: [String: Color]

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                SubstanceDot(name: item.substance, colorMap: colorMap, size: 12)
                Text(item.displayTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                StockAmountText(item: item, style: .headline)
            }
            if let fraction = item.fillFraction {
                InventorySupplyBar(fraction: fraction, tint: item.stockStatus.barTint)
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

    private var colorMap: [String: Color] {
        Array(substanceColors).colorMap
    }
    private var sorted: [InventoryItem] {
        inventorySorted(items)
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
                        .listRowBackground(Theme.cardBackground)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Theme.background)
        .navigationTitle("Inventory")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
                InventorySupplyBar(fraction: fraction, tint: item.stockStatus.barTint)
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
