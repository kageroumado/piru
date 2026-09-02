import SwiftData
import SwiftUI

/// Rich stock card below Dose & Duration: amount, doses-left, supply bar, and
/// run-out when tracked; a quiet "Not tracked · Track" row otherwise. Its own
/// invalidation boundary, keyed on the substance's inventory rows and the
/// selected salt.
struct InventoryStockSection: View {
    let substanceName: String
    let selectedSaltForm: String?
    let inventoryItems: [InventoryItem]
    @Binding var showAllInventory: Bool

    @Environment(\.modelContext) private var modelContext
    @Environment(\.appNavigator) private var navigator

    /// The tracked item for this substance, preferring the currently-selected
    /// salt, then the base form. Matched by resolved substance identity, so an
    /// item stocked under an alias (e.g. "IC-26") still shows on its canonical
    /// substance's page ("Methiodone").
    private var trackedItem: InventoryItem? {
        let key = InventoryMath.matchKey(for: substanceName)
        let matches = inventoryItems.filter { InventoryMath.matchKey(for: $0.substance) == key }
        return matches.first { $0.saltForm == selectedSaltForm }
            ?? matches.first { $0.saltForm == nil }
            ?? matches.first
    }

    var body: some View {
        Section {
            if let item = trackedItem {
                trackedStockCard(item)
            } else {
                HStack {
                    Text("Not tracked")
                        .foregroundStyle(Theme.secondaryLabel)
                    Spacer()
                    inventoryPill("Track") {
                        navigator.present(.inventoryItemForm(
                            id: nil,
                            prefillSubstance: substanceName,
                            prefillSalt: selectedSaltForm,
                        ))
                    }
                }
            }
        } header: {
            HStack {
                Text("Inventory")
                Spacer()
                Button { showAllInventory = true } label: {
                    HStack(spacing: Spacing.xxs) {
                        Text("Show All")
                        Image(systemName: "chevron.right").font(.caption2)
                            .accessibilityHidden(true)
                    }
                    .font(.subheadline)
                    .foregroundStyle(Theme.accent)
                    .textCase(nil)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func trackedStockCard(_ item: InventoryItem) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    StockAmountText(item: item, style: .title2)
                    if let subtitle = stockSubtitle(item) {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                }
                Spacer(minLength: 12)
                inventoryPill("Restock") {
                    navigator.present(.inventoryItemForm(id: item.id))
                }
            }
            if let fraction = item.fillFraction {
                InventorySupplyBar(fraction: fraction, tint: item.stockStatus.barTint, status: item.stockStatus)
            }
            if hasUnitMismatch(item) {
                Label("Doses in other units aren't counted.", systemImage: "info.circle")
                    .captionSecondary()
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    /// The shared accent text-pill used for both Track and Restock, so the two
    /// states read as one affordance.
    private func inventoryPill(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .sectionLabel()
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, Spacing.md)
                .background(Theme.accent.opacity(Theme.Opacity.tint), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Subtitle under the amount: "Citrate · ~24 doses · ~3 weeks left" when
    /// stocked (salt + the combined supply line), or "last dose <date>" when out
    /// (so we don't echo "Out").
    private func stockSubtitle(_ item: InventoryItem) -> String? {
        if item.stockStatus == .out {
            guard let last = InventoryMath.doses(for: item, in: modelContext).map(\.timestamp).max() else {
                return nil
            }
            let formatted = last.formatted(.dateTime.month().day())
            return String(localized: "last dose \(formatted)")
        }
        var parts: [String] = []
        if let salt = item.saltForm, !salt.isEmpty { parts.append(salt) }
        let runOut = InventoryMath.runOut(for: item, in: modelContext)
        if let supply = inventorySupplyLine(for: item, runOut: runOut) {
            parts.append(supply)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// True when any matching dose can't be converted into the item's unit, so
    /// the card can show a calm "not counted" hint.
    private func hasUnitMismatch(_ item: InventoryItem) -> Bool {
        InventoryMath.doses(for: item, in: modelContext).contains {
            InventoryMath.convert($0.amount, from: $0.unit, to: item.unit) == nil
        }
    }
}
