import SwiftUI

enum Theme {
    /// Soft pink in light mode, hot pink in dark mode.
    ///
    /// Xcode's generated symbol rather than `Color("AccentColor")` — a string
    /// lookup resolves to a silent fallback if the asset is ever renamed, where
    /// this is a compile error.
    static let accent = Color.accent

    // `legibleYellow` lived here. It was a hue pretending to be a role, and the
    // whole design system exists because of what that cost: the same "darken it
    // for light mode" fix was independently rediscovered four times, in four
    // files, none of which could share the others' work.
    //
    // Its four consumers each turned out to be a different *kind* of thing —
    // one L1 status (interaction caution) and three L2 encoding scales (dose
    // tier, and two evidence grades). Naming by appearance is what let them all
    // collapse onto one value; naming by role is what pulled them apart.
    // See `design-system/color/color-system.md`.

    /// De-emphasized body text. ~566 call sites, so this accessor stays even
    /// though the value now comes from the asset catalog.
    ///
    /// The old hand-rolled pair (`#7A7A80` / `#A6A6AD`) was half right. Its
    /// light value genuinely beat the system colour — 3.89:1 against system's
    /// 2.17:1 — but **still failed WCAG AA**, which the original audit missed by
    /// computing against pure white instead of the measured `#f5f5f5` card. Its
    /// dark value was simply worse than the system's (7.79 vs 9.97).
    ///
    /// Now `#6E6E73` light (4.65:1) and the system's own `#BCBCC4` dark
    /// (9.97:1). Gated by `ColorContrastTests`.
    static let secondaryLabel = Color.Text.secondary

    // MARK: - Surfaces

    // These were `UIColor { traits }` closures. A closure branches on
    // `userInterfaceStyle` alone, so it cannot express high contrast at all —
    // as colorsets they gain the Any+HC / Dark+HC slots the app has never had.
    //
    // Light values are the system colours the closures already resolved to
    // (`systemBackground`, `systemGray6`, `systemGroupedBackground`), which are
    // fixed published values, so pinning them loses nothing. The dark values
    // are the app's deliberate OLED choice — which is *why* the closures
    // existed, since the system's own dark surfaces sit around `#1C1C1E` and
    // never reach true black.

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
/// Replaces the bare `Theme.cardBackground` (a cold `systemGray6` in light) so
/// grouped Lists match the rest of the app.
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
