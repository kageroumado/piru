import SwiftUI

/// The app's colour tokens, resolved through the active ``Skin``.
///
/// Every accessor is a computed property that reads `SkinStore.shared.current`.
/// Observation tracks that read wherever it happens during a view's `body`, so
/// the ~1,000 existing `Theme.*` call sites re-render on a skin change without
/// being touched. Each skin returns Xcode's generated catalog symbol for its
/// namespace — never a string lookup, so a renamed colorset is a compile error.
enum Theme {
    private static var skin: Skin { SkinStore.shared.current }

    /// Brand accent and control tint. Soft pink light / hot pink dark in the
    /// default skin.
    static var accent: Color { skin.accent }

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

    /// De-emphasized body text. ~700 call sites, so this accessor stays even
    /// though the value comes from the asset catalog.
    ///
    /// Gated by `ColorContrastTests` at WCAG AA 4.5:1 against the measured
    /// card — not pure white, which is the optimistic mistake that once put a
    /// wrong number in the audit's own findings.
    static var secondaryLabel: Color { skin.secondaryLabel }

    // MARK: - Surfaces

    // Colorsets rather than `UIColor { traits }` closures: a closure branches on
    // `userInterfaceStyle` alone, so it cannot express high contrast at all —
    // as colorsets they gain the Any+HC / Dark+HC slots.

    /// Page backdrop. True black in dark mode for OLED in the default skin.
    static var background: Color { skin.background }

    /// Card / raised surface fill.
    static var cardBackground: Color { skin.cardBackground }

    /// Text-field and other input fills.
    static var inputBackground: Color { skin.inputBackground }
}

// MARK: - Root

/// Wraps the app's root so skin-wide modifiers (`fontDesign`, the colour-scheme
/// override) are read inside a `View.body`, where Observation tracks them.
struct SkinnedRoot<Content: View>: View {
    @State private var skins = SkinStore.shared
    @ViewBuilder let content: Content

    var body: some View {
        content
            // Re-created on a skin change, so UIKit bars pick up the new
            // title face from the appearance proxy.
            .id(skins.current)
            .tint(Theme.accent)
            .fontDesign(skins.current.fontDesign)
            .preferredColorScheme(skins.colorScheme.colorScheme)
            .onAppear { SkinNavigationTitles.apply(skins.current) }
            .onChange(of: skins.current) { _, skin in SkinNavigationTitles.apply(skin) }
    }
}

// MARK: - Theme View Modifiers

/// The skin's card treatment on an arbitrary shape.
///
/// `.glass`: `.ultraThinMaterial` in light, the solid card colour in dark — the
/// treatment the app shipped with. `.edged`: solid card colour in both schemes,
/// a stroke, and a hard offset shadow drawn as a second fill behind the shape
/// (unblurred by design — an edged skin has no soft shadows anywhere).
struct ThemedBackground<S: Shape>: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    let shape: S

    func body(content: Content) -> some View {
        switch SkinStore.shared.current.surface {
        case .glass:
            if colorScheme == .dark {
                content.background(Theme.cardBackground, in: shape)
            } else {
                content.background(.ultraThinMaterial, in: shape)
            }
        case let .edged(stroke, strokeWidth, shadow, shadowOffset):
            content.background {
                shape.fill(shadow).offset(shadowOffset)
                shape.fill(Theme.cardBackground)
                shape.stroke(stroke, lineWidth: strokeWidth)
            }
        }
    }
}

/// The card fill as a standalone view, for `listRowBackground` and other spots
/// that need the fill directly. Rows share their grouped container's edge, so
/// an edged skin gives rows the solid fill only — the stroke and shadow belong
/// to the container, not to every row inside it.
struct CardBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        switch SkinStore.shared.current.surface {
        case .glass:
            if colorScheme == .dark {
                Theme.cardBackground
            } else {
                Rectangle().fill(.ultraThinMaterial)
            }
        case .edged:
            Theme.cardBackground
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
    /// `minimum: 22` matches the system grouped-list / Library card rounding
    /// (the 16 the app shipped with read too boxy beside them).
    ///
    /// Note: this does not also call `containerShape`, which requires an
    /// `InsettableShape` that `ConcentricRectangle` is not. Cards still derive
    /// from whatever container the system provides (sheet, screen, grouped
    /// list); they just don't yet re-publish themselves as a container for
    /// their own children. Nested content still needs an explicit radius.
    ///
    /// A skin with a fixed ``Skin/cardCornerRadius`` (its cards are drawn
    /// objects, not system surfaces) overrides the caller's radius.
    func themeCard(cornerRadius: CGFloat = 22) -> some View {
        let radius = SkinStore.shared.current.cardCornerRadius ?? cornerRadius
        return modifier(ThemedBackground(
            shape: ConcentricRectangle(corners: .concentric(minimum: .fixed(radius)), isUniform: true),
        ))
    }

    /// Conditionally apply the card background — for rows that live inside a
    /// shared grouped container, where the container draws the background and the
    /// row should not.
    @ViewBuilder
    func themeCard(enabled: Bool, cornerRadius: CGFloat = 16) -> some View {
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
