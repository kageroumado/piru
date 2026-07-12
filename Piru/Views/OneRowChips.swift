import SwiftUI

// MARK: - One-Row Chip Fold

/// Lays out chips on exactly one row, folding whatever doesn't fit into a
/// width-aware "+N" chip — the row never wraps. Tapping "+N" is a disclosure:
/// the row expands in place to a wrapping layout showing every chip.
///
/// Implemented with `ViewThatFits`: candidate rows from "all chips" down to
/// "one chip + fold" are proposed in order and the widest that fits wins.
struct OneRowChips<Item: Identifiable, ChipView: View, TrailingView: View>: View {
    let items: [Item]
    let isExpanded: Bool
    let onExpand: () -> Void
    @ViewBuilder let chip: (Item) -> ChipView
    @ViewBuilder let trailing: () -> TrailingView

    var body: some View {
        if isExpanded || items.count <= 1 {
            FlowLayout(spacing: 6) {
                ForEach(items) { item in
                    chip(item)
                }
                trailing()
            }
        } else {
            ViewThatFits(in: .horizontal) {
                ForEach(Array(stride(from: items.count, through: 1, by: -1)), id: \.self) { visibleCount in
                    candidateRow(visibleCount: visibleCount)
                }
            }
        }
    }

    private func candidateRow(visibleCount: Int) -> some View {
        // `maxHeight: .infinity` lets every item grow to the row's tallest child
        // (a two-line drink chip pulls the plain gram chips + trailing controls up
        // to match), so the row reads as one even height. A no-op for uniform rows.
        HStack(spacing: 6) {
            ForEach(items.prefix(visibleCount)) { item in
                chip(item)
                    // Chips must not compress, otherwise every candidate
                    // "fits" and the widest always wins. The last candidate
                    // stays compressible as the give-up fallback.
                    .fixedSize(horizontal: visibleCount > 1, vertical: false)
                    .frame(maxHeight: .infinity)
            }
            if visibleCount < items.count {
                Button(action: onExpand) {
                    Text(verbatim: "+\(items.count - visibleCount)")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12)
                        .frame(maxHeight: .infinity)
                        .background(Color(.secondarySystemFill))
                        .foregroundStyle(Theme.secondaryLabel)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityLabel("Show \(items.count - visibleCount) more doses")
                .accessibilityHint("Shows the remaining doses")
            }
            trailing()
                .fixedSize(horizontal: true, vertical: false)
                .frame(maxHeight: .infinity)
        }
    }
}
