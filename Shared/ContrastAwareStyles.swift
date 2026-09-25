import SwiftUI

/// A foreground faded to `opacity`, drawn at full strength while Increase
/// Contrast is on.
///
/// Fading a text color trades contrast for hierarchy, and that trade is the one
/// the setting asks the app to stop making. Use it for text and meaningful
/// glyphs; a chart mark, gridline or tint fill keeps the plain `.opacity(_:)`.
nonisolated struct LegibleOpacity<Base: ShapeStyle>: ShapeStyle {
    let base: Base
    let opacity: Double

    func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        base.opacity(environment.colorSchemeContrast == .increased ? 1 : opacity)
    }
}

/// The system `.tertiary` level, or `strong` while Increase Contrast is on.
///
/// `.tertiary` measures under 2:1 on the light card, which is fine for a
/// decorative separator and too faint for anything a reader needs.
nonisolated struct LegibleTertiary: ShapeStyle {
    let strong: Color

    func resolve(in environment: EnvironmentValues) -> AnyShapeStyle {
        environment.colorSchemeContrast == .increased ? AnyShapeStyle(strong) : AnyShapeStyle(.tertiary)
    }
}

extension ShapeStyle {
    /// This style at `opacity`, or at full strength while Increase Contrast is
    /// on. See ``LegibleOpacity``.
    nonisolated func legibleOpacity(_ opacity: Double) -> LegibleOpacity<Self> {
        LegibleOpacity(base: self, opacity: opacity)
    }
}
