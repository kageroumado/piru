import SwiftUI

// MARK: - Chip metrics

/// The one line box every quick-log chip shares — a dose amount, the "+N"
/// fold, the sliders pill. Same text style, same padding, so a row of them is
/// one height whether a member holds a number or a symbol (a symbol goes
/// through `Text(Image)` to take the text's line box rather than its own).
enum OneRowChipMetrics {
    static var font: Font {
        .subheadline.weight(.medium)
    }

    static let horizontalPadding: CGFloat = Spacing.xl
    static let verticalPadding: CGFloat = 6
}

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
            FlowLayout(spacing: Spacing.sm) {
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
        // Every member keeps its own height and sits on the row's midline: a
        // two-line drink chip is taller than the fold and the sliders pill
        // beside it, and the visible capsule is exactly the frame it gets.
        HStack(spacing: Spacing.sm) {
            ForEach(items.prefix(visibleCount)) { item in
                chip(item)
                    // Chips must not compress, otherwise every candidate
                    // "fits" and the widest always wins. The last candidate
                    // stays compressible as the give-up fallback.
                    .fixedSize(horizontal: visibleCount > 1, vertical: false)
            }
            if visibleCount < items.count {
                Button(action: onExpand) {
                    Text(verbatim: "+\(items.count - visibleCount)")
                        .font(OneRowChipMetrics.font)
                        .padding(.horizontal, OneRowChipMetrics.horizontalPadding)
                        .padding(.vertical, OneRowChipMetrics.verticalPadding)
                        .background(Color.platformSecondarySystemFill)
                        .foregroundStyle(Theme.secondaryLabel)
                        .clipShape(skinChipShape())
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityLabel("Show \(items.count - visibleCount) more entries")
                .accessibilityHint("Shows the remaining entries")
            }
            trailing()
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}
