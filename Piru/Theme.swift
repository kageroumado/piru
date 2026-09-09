import SwiftUI

/// The app's colour tokens, resolved through the active ``Skin``.
///
/// Every accessor is a computed property that reads `SkinStore.shared.current`.
/// Observation tracks that read wherever it happens during a view's `body`, so
/// the ~1,000 existing `Theme.*` call sites re-render on a skin change without
/// being touched. Each skin returns Xcode's generated catalog symbol for its
/// namespace — never a string lookup, so a renamed colorset is a compile error.
enum Theme {
    private static var skin: Skin {
        SkinStore.shared.current
    }

    /// Brand accent and control tint. Soft pink light / hot pink dark in the
    /// default skin.
    static var accent: Color {
        skin.accent
    }

    /// De-emphasized body text. Kept as an accessor over the catalog symbol
    /// for its ~600 call sites; gated by `ColorContrastTests`.
    ///
    /// Never swap this for the system `.secondary`: it measures 2.17:1 on the
    /// light card and fails WCAG AA.
    static var secondaryLabel: Color {
        skin.secondaryLabel
    }

    // MARK: - Surfaces

    // Colorsets, never `UIColor { traits }` closures: a closure branches on
    // `userInterfaceStyle` alone and cannot express the Any+HC / Dark+HC
    // variants.

    /// Page backdrop. True black in dark mode for OLED in the default skin.
    static var background: Color {
        skin.background
    }

    /// Card / raised surface fill.
    static var cardBackground: Color {
        skin.cardBackground
    }

    /// Text-field and other input fills.
    static var inputBackground: Color {
        skin.inputBackground
    }

    // MARK: - Card geometry

    /// The card corner the app draws when nothing overrides it. `22` matches
    /// the system grouped-list / Library card rounding.
    static let cardCornerRadius: CGFloat = 22

    /// The standard card shape — concentric, so it inherits its radius from the
    /// enclosing container and only falls back to ``cardCornerRadius``.
    static var cardShape: ConcentricRectangle {
        ConcentricRectangle(corners: .concentric(minimum: .fixed(cardCornerRadius)), isUniform: true)
    }
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
            .tapTrail()
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
    /// Draw the skin's dashed inner border (``Skin/cardInsetDash``). On for
    /// cards, off for capsules — a dash inside a pill reads as a broken ring.
    var insetDash = false

    func body(content: Content) -> some View {
        let skin = SkinStore.shared.current
        switch skin.surface {
        case .glass:
            if colorScheme == .dark {
                content.background(Theme.cardBackground, in: shape)
            } else {
                content.background(.ultraThinMaterial, in: shape)
            }
        case let .soft(stroke, glow, glowRadius):
            content.background {
                shape.fill(Theme.cardBackground)
                    .shadow(color: glow.opacity(colorScheme == .dark ? 0.28 : 0.35), radius: glowRadius, y: 4)
                shape.stroke(stroke.opacity(0.35), lineWidth: 1)
            }
        case let .paper(stroke, grain):
            content.background {
                shape.fill(Theme.cardBackground)
                shape.fill(SkinTextures.grain(grain, dark: colorScheme == .dark))
                shape.stroke(stroke.opacity(0.18), lineWidth: 1)
            }
        case let .neon(stroke, glow):
            content.background {
                shape.fill(Theme.cardBackground.opacity(colorScheme == .dark ? 0.85 : 1))
                    .shadow(color: glow.opacity(colorScheme == .dark ? 0.55 : 0.25), radius: 8)
                shape.stroke(stroke, lineWidth: 1.5)
                shape.stroke(Color.white.opacity(0.18), lineWidth: 0.5).padding(2)
            }
        case let .frosted(stroke, highlight):
            content.background {
                shape.fill(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.55))
                shape.stroke(stroke.opacity(colorScheme == .dark ? 0.15 : 0.6), lineWidth: 1)
                shape.stroke(highlight.opacity(0.25), lineWidth: 1).mask {
                    LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.25))
                }
            }
        case let .edged(stroke, strokeWidth, shadow, shadowOffset):
            content.background {
                shape.fill(shadow).offset(shadowOffset)
                shape.fill(Theme.cardBackground)
                shape.stroke(stroke, lineWidth: strokeWidth)
                if insetDash, let dash = skin.cardInsetDash {
                    // `ConcentricRectangle` is not insettable; a padded frame
                    // draws the same shape 5pt inside the card.
                    shape
                        .stroke(dash.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        .padding(5)
                }
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
        case .edged, .soft, .paper, .neon:
            Theme.cardBackground
        case .frosted:
            Color.white.opacity(colorScheme == .dark ? 0.08 : 0.55)
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
    /// Note: this does not also call `containerShape`, which requires an
    /// `InsettableShape` that `ConcentricRectangle` is not. Cards still derive
    /// from whatever container the system provides (sheet, screen, grouped
    /// list); they just don't yet re-publish themselves as a container for
    /// their own children. Nested content still needs an explicit radius.
    ///
    /// A skin never changes a container's shape — a card's radius is the
    /// caller's, so what nests inside it (the timeline envelope's bubbles, a
    /// grouped list's rows) keeps nesting. Skins change fill, edge and shadow only.
    func themeCard(cornerRadius: CGFloat = Theme.cardCornerRadius) -> some View {
        modifier(ThemedBackground(
            shape: ConcentricRectangle(corners: .concentric(minimum: .fixed(cornerRadius)), isUniform: true),
            insetDash: true,
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

    /// A capsule, or — under an edged skin, whose chips and fields are all
    /// squared — the skin's input rounding.
    func themeCapsule() -> some View {
        let shape = switch SkinStore.shared.current.surface {
        case .glass, .soft, .frosted: AnyShape(Capsule())
        case .edged, .paper: AnyShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.input, style: .continuous))
        case .neon: AnyShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
        }
        return modifier(ThemedBackground(shape: shape))
    }
}
