import SwiftUI

/// A checkmark for a selected filter chip, drawn only under Differentiate
/// Without Color. A chip's selection otherwise shows as a tint, which reads the
/// same as an unselected chip to a reader who can't tell the hues apart.
struct DifferentiatedSelectionMark: View {
    let isSelected: Bool

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate

    var body: some View {
        if differentiate, isSelected {
            Image(systemName: "checkmark")
                .font(.caption2.weight(.bold))
                .accessibilityHidden(true)
        }
    }
}
