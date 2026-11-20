import SwiftUI

/// The card a scrubbed chart shows over the selection: a title for the instant, then one row per
/// item (its key, its name, its value), or `emptyText` when there are no items.
struct ChartScrubReadout<Item, ID: Hashable, Key: View>: View {
    let title: String
    let items: [Item]
    let id: KeyPath<Item, ID>
    let emptyText: Text
    let name: (Item) -> String
    let value: (Item) -> Text
    @ViewBuilder let key: (Item) -> Key

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
            ForEach(items, id: id) { item in
                HStack(spacing: 5) {
                    key(item)
                    Text(name(item))
                        .font(.caption2)
                    Spacer(minLength: 8)
                    value(item)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
            if items.isEmpty {
                emptyText
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryLabel)
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard(cornerRadius: Theme.CornerRadius.inner)
        .accessibilityElement(children: .combine)
        .transition(.opacity)
    }
}
