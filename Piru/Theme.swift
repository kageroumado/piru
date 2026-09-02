import SwiftUI

enum Theme {
    /// Soft pink in light mode, hot pink in dark mode.
    ///
    /// Xcode's generated symbol rather than `Color("AccentColor")` — a string
    /// lookup resolves to a silent fallback if the asset is ever renamed, where
    /// this is a compile error.
    static let accent = Color.accent

    /// De-emphasized body text: `#6E6E73` light (4.65:1 on the card) and the
    /// system's `#BCBCC4` dark (9.97:1), gated by `ColorContrastTests`. Kept as
    /// an accessor over the catalog symbol for its ~600 call sites.
    ///
    /// Never swap this for the system `.secondary`: it measures 2.17:1 on the
    /// light card and fails WCAG AA.
    static let secondaryLabel = Color.Text.secondary

    // MARK: - Surfaces

    // Colorsets, never `UIColor { traits }` closures: a closure branches on
    // `userInterfaceStyle` alone and cannot express the Any+HC / Dark+HC
    // variants. Light values are the published system colours
    // (`systemBackground`, `systemGray6`, `systemGroupedBackground`); dark
    // values are the app's OLED choice, which the system's own dark surfaces
    // (around `#1C1C1E`) never reach.

    /// Page backdrop. True black in dark mode for OLED.
    static let background = Color.Surface.background

    /// Card / raised surface fill.
    static let cardBackground = Color.Surface.card

    /// Text-field and other input fills.
    static let inputBackground = Color.Surface.input

    // MARK: - Shape

    /// The floor for every card corner. `ConcentricRectangle` inherits the
    /// enclosing container's radius and only falls back to this when there is
    /// nothing to inherit from; 22 matches the system grouped-list rounding.
    static let cardCornerRadius: CGFloat = 22

    /// The card outline as a shape — for `contentShape` and clips on views that
    /// sit on `themeCard` or inside one, so hit areas and clips follow the same
    /// container-derived corner the card draws with.
    static var cardShape: ConcentricRectangle {
        ConcentricRectangle(corners: .concentric(minimum: .fixed(cardCornerRadius)), isUniform: true)
    }
}

// MARK: - Theme View Modifiers

struct ThemedBackground<S: Shape>: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    let shape: S

    func body(content: Content) -> some View {
        if colorScheme == .dark {
            content.background(Theme.cardBackground, in: shape)
        } else {
            content.background(.ultraThinMaterial, in: shape)
        }
    }
}

/// The app's standard card fill as a standalone view — the same scheme-adaptive
/// treatment ``themeCard`` applies (`.ultraThinMaterial` in light, a soft solid
/// in dark), for `listRowBackground` and other spots that need the fill directly.
/// Use this rather than the bare `Theme.cardBackground` for list rows: the bare
/// fill is a cold `systemGray6` in light mode and grouped Lists stop matching
/// the rest of the app.
struct CardBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if colorScheme == .dark {
            Theme.cardBackground
        } else {
            Rectangle().fill(.ultraThinMaterial)
        }
    }
}

extension View {
    /// The app's standard card.
    ///
    /// The corner is **system-derived**, not fixed: `ConcentricRectangle` with
    /// `.concentric(minimum:)` inherits its radius from the enclosing container
    /// shape and only falls back to `minimum` when there is nothing to inherit
    /// from. Concentricity — nested shapes whose radii relate mathematically to
    /// their container — is a core principle of the iOS 26 design language, and
    /// a fixed radius breaks it the moment a card is nested or the container
    /// rounding changes.
    ///
    /// The default minimum is ``Theme/cardCornerRadius``; pass a smaller value
    /// only for a card that is itself nested inside another card.
    ///
    /// Note: this does not also call `containerShape`, which requires an
    /// `InsettableShape` that `ConcentricRectangle` is not. Cards still derive
    /// from whatever container the system provides (sheet, screen, grouped
    /// list); they just don't yet re-publish themselves as a container for
    /// their own children. Nested content still needs an explicit radius.
    func themeCard(cornerRadius: CGFloat = Theme.cardCornerRadius) -> some View {
        modifier(ThemedBackground(
            shape: ConcentricRectangle(corners: .concentric(minimum: .fixed(cornerRadius)), isUniform: true),
        ))
    }

    /// Conditionally apply the card background — for rows that live inside a
    /// shared grouped container, where the container draws the background and the
    /// row should not.
    @ViewBuilder
    func themeCard(enabled: Bool, cornerRadius: CGFloat = Theme.cardCornerRadius) -> some View {
        if enabled {
            themeCard(cornerRadius: cornerRadius)
        } else {
            self
        }
    }

    func themeCapsule() -> some View {
        modifier(ThemedBackground(shape: Capsule()))
    }
}
