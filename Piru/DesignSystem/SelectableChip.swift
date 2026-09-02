import SwiftUI

extension View {
    /// The circular toggle grammar: a ``IconSize/icon``-wide tinted circle inside
    /// a ``IconSize/touchTarget`` hit area, filled with `tint` when selected and
    /// with `tertiarySystemFill` otherwise.
    ///
    /// The two frames are both required. The inner one sizes the visible circle;
    /// the outer one widens the tappable area to the HIG minimum without growing
    /// the mark, and `contentShape` makes the whole of it hit-test.
    ///
    /// Every branch is a ternary on a value, never an `if`/`else` producing two
    /// different view types: a type switch destroys structural identity, so the
    /// circle is torn down and rebuilt on every toggle instead of animating
    /// between fills.
    func selectableChip(isSelected: Bool, tint: Color = Theme.accent) -> some View {
        frame(width: IconSize.icon, height: IconSize.icon)
            .background(isSelected ? tint : Color(.tertiarySystemFill))
            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .clipShape(Circle())
            .frame(width: IconSize.touchTarget, height: IconSize.touchTarget)
            .contentShape(Rectangle())
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// The capsule variant of the same toggle grammar, for a label too wide to
    /// fit a circle.
    ///
    /// The selected fill is ``Theme/Opacity/tintActive`` rather than
    /// ``Theme/Opacity/tint`` because the label above it is `.primary`, not the
    /// fill's own color — the 0.10 ceiling only applies to a color drawn on a
    /// tint of itself.
    func selectableCapsule(isSelected: Bool, tint: Color = Theme.accent) -> some View {
        padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
            .background(
                isSelected ? tint.opacity(Theme.Opacity.tintActive) : Color(.tertiarySystemFill),
                in: Capsule(),
            )
            .foregroundStyle(.primary)
            .overlay(
                Capsule().strokeBorder(
                    isSelected ? tint : Color(.quaternaryLabel),
                    lineWidth: 1,
                ),
            )
            .contentShape(Capsule())
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
