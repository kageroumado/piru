import SwiftData
import SwiftUI
import WidgetKit

// MARK: - Inventory Widget (read-only)

/// A glanceable, read-only stock display. Reads the denormalized
/// ``InventoryItem/currentQuantity`` cache the app keeps fresh (no derivation,
/// no writes) and shows the highest-priority items: out → low → recently used.
struct InventoryWidget: Widget {
    let kind = "InventoryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: InventoryProvider()) { entry in
            InventoryWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetBackground()
                }
        }
        .configurationDisplayName("Inventory")
        .description("See how much you have left of what you track.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Entry

struct InventoryEntry: TimelineEntry {
    let date: Date
    let items: [Item]

    struct Item: Identifiable {
        let id: UUID
        let name: String
        let quantity: Double
        let unit: String
        let colorHex: String
        let isOut: Bool
        let isLow: Bool
    }
}

// MARK: - Provider

struct InventoryProvider: TimelineProvider {
    func placeholder(in _: Context) -> InventoryEntry {
        InventoryEntry(date: .now, items: [
            .init(id: UUID(), name: "Ketamine", quantity: 4.8, unit: "g", colorHex: "78A6F5", isOut: false, isLow: false),
            .init(id: UUID(), name: "Magnesium", quantity: 6, unit: "caps", colorHex: "8CD98C", isOut: false, isLow: true),
        ])
    }

    func getSnapshot(in _: Context, completion: @escaping (InventoryEntry) -> Void) {
        completion(fetchEntry())
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<InventoryEntry>) -> Void) {
        // Stock only changes from in-app actions, which reload the timeline; a
        // daily fallback refresh keeps a long-idle widget from going stale.
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 12, to: .now)!
        completion(Timeline(entries: [fetchEntry()], policy: .after(nextUpdate)))
    }

    private func fetchEntry() -> InventoryEntry {
        guard let container = WidgetStoreAccess.makeContainer() else {
            return InventoryEntry(date: .now, items: [])
        }
        let context = ModelContext(container)
        let items = (try? context.fetch(FetchDescriptor<InventoryItem>())) ?? []
        let hexMap = ((try? context.fetch(FetchDescriptor<SubstanceColor>())) ?? []).hexColorMap

        func isOut(_ item: InventoryItem) -> Bool { item.currentQuantity <= 0 }
        func isLow(_ item: InventoryItem) -> Bool {
            guard let t = item.lowStockThreshold, t > 0 else { return false }
            return item.currentQuantity <= t
        }
        func priority(_ item: InventoryItem) -> Int {
            if isOut(item) { return 0 }
            if isLow(item) { return 1 }
            return 2
        }
        func lastActivity(_ item: InventoryItem) -> Date {
            item.manualEvents.map(\.date).max() ?? item.createdAt
        }

        let sorted = items.sorted {
            if priority($0) != priority($1) { return priority($0) < priority($1) }
            return lastActivity($0) > lastActivity($1)
        }

        return InventoryEntry(
            date: .now,
            items: sorted.prefix(4).map { item in
                InventoryEntry.Item(
                    id: item.id,
                    name: item.substance,
                    quantity: item.currentQuantity,
                    unit: item.unit,
                    colorHex: SubstancePalette.hex(for: item.substance, hexMap: hexMap),
                    isOut: isOut(item),
                    isLow: isLow(item),
                )
            },
        )
    }
}

// MARK: - View

struct InventoryWidgetView: View {
    let entry: InventoryEntry

    @Environment(\.widgetFamily) var family

    private var rowLimit: Int { family == .systemMedium ? 4 : 3 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Inventory")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "shippingbox")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if entry.items.isEmpty {
                Spacer(minLength: 0)
                Text("Nothing tracked")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                ForEach(entry.items.prefix(rowLimit)) { item in
                    row(item)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(2)
    }

    private func row(_ item: InventoryEntry.Item) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(hex: item.colorHex))
                .frame(width: 7, height: 7)
            Text(item.name)
                .font(.caption)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(amountText(item))
                .font(.caption.weight(.semibold))
                .foregroundStyle(amountColor(item))
                .lineLimit(1)
        }
    }

    private func amountText(_ item: InventoryEntry.Item) -> String {
        if item.isOut { return String(localized: "Out") }
        return "\(item.quantity.doseFormatted) \(item.unit)"
    }

    /// Color carries meaning only for Low/Out; a healthy supply reads neutral.
    private func amountColor(_ item: InventoryEntry.Item) -> Color {
        if item.isOut { return .red }
        if item.isLow { return .orange }
        return .primary
    }
}
