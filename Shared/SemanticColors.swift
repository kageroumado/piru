import SwiftUI

/// Leading-dot shorthands for the semantic color tokens.
///
/// Xcode generates `Color.Semantic.Caution.text` from the asset catalog
/// (`ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS`), but it only
/// emits the `ShapeStyle` shorthand for `AccentColor` — namespaced assets don't
/// get one. So `.foregroundStyle(.cautionText)` does not compile out of the box,
/// only the longer `.foregroundStyle(Color.Semantic.Caution.text)`.
///
/// This restores the shorthand the same way SwiftUI's own `.red` / `.secondary`
/// work. It is **sugar over the generated symbols**, never a re-declaration:
/// every value below forwards to the catalog symbol, so there are no string
/// lookups here and a renamed colorset is still a compile error.
///
/// Names are flat rather than nested because leading-dot syntax resolves against
/// static members of the extended type — a nested `enum Semantic` would not
/// participate, which is exactly why the generated symbols need the `Color.`
/// prefix in the first place.
///
/// ## Choosing between `text` and `accent`
///
/// - `text` — small copy and any glyph *inside* a filled pill. Gated at
///   WCAG AA 4.5:1 against both the bare card and its own fill.
/// - `accent` — standalone marks on the card: dots, bar fills, chip strokes,
///   chart series. Gated at the 3:1 non-text floor, so it is more saturated.
///
/// An `accent` glyph on an `accent`-derived fill recreates the self-tint failure
/// one level down (measured 2.82:1), which is why pill icons use `text`.
///
/// `fill` is not a token: it is `accent` at 0.10 alpha over the card. Derive it,
/// never author it.
///
/// Rationale, measurements, and the migration plan: `design-system/`.
public extension ShapeStyle where Self == Color {
    /// Destructive or genuinely dangerous states. Small copy.
    static var dangerText: Color {
        .Semantic.Danger.text
    }
    /// Destructive or genuinely dangerous states. Standalone marks.
    static var dangerAccent: Color {
        .Semantic.Danger.accent
    }

    /// Advisory states that are not dangerous. Small copy.
    static var cautionText: Color {
        .Semantic.Caution.text
    }
    /// Advisory states that are not dangerous. Standalone marks.
    static var cautionAccent: Color {
        .Semantic.Caution.accent
    }

    /// Confirmations and healthy states. Small copy.
    static var successText: Color {
        .Semantic.Success.text
    }
    /// Confirmations and healthy states. Standalone marks.
    static var successAccent: Color {
        .Semantic.Success.accent
    }

    /// Neutral information carrying no valence. Small copy.
    static var infoText: Color {
        .Semantic.Info.text
    }
    /// Neutral information carrying no valence. Standalone marks.
    static var infoAccent: Color {
        .Semantic.Info.accent
    }
}
