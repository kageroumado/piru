import SwiftUI

/// A list section header for one substance class that folds its section. The
/// whole header is the fold control — a small chevron alone would be a poor
/// target, and there's nothing else in a header to tap.
struct CollapsibleCategoryHeader: View {
    let category: SubstanceCategory
    let count: Int
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) { toggle() }
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: category.icon)
                    .font(.caption2)
                    .accessibilityHidden(true)
                Text(category.displayName)
                Text(verbatim: "\(count)")
                    .foregroundStyle(Theme.tertiaryLabel)
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.secondaryLabel)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityValue(Text(isExpanded ? "Expanded" : "Collapsed"))
        .accessibilityHint(Text(isExpanded ? "Double tap to collapse" : "Double tap to expand"))
    }
}
