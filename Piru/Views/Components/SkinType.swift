import SwiftUI
#if canImport(UIKit)
    import UIKit
#else
    import AppKit
#endif

// The typography layer of the skin system. Two roles: display (titles) and
// label (chips, eyebrows). Body copy is always the system face — a skin
// reshapes it through `Skin.fontDesign` at the root, never through a bundled
// family. Every custom font is created `relativeTo:` its text style so
// Dynamic Type keeps scaling it.

extension Font {
    /// A semantic text style in the skin's face for its role.
    ///
    /// Display styles (`largeTitle` … `headline`) resolve to the skin's
    /// display family when it has one; every other style, and every skin
    /// without a display face, is the plain system style — so this is safe to
    /// use at any call site that used `.font(.headline)` before. `weight`
    /// defaults to the system's own weight for the style (headline is
    /// semibold), and `design` is honoured by the system fallback.
    static func piru(_ style: Font.TextStyle, design: Font.Design? = nil, weight: Font.Weight? = nil) -> Font {
        let weight = weight ?? style.defaultWeight
        guard style.isDisplay, let font = SkinFace.display(weight: weight, size: style.defaultPointSize, relativeTo: style) else {
            let base: Font = design.map { .system(style, design: $0) } ?? .system(style)
            return base.weight(weight)
        }
        return font
    }

    /// A fixed-size display title in the skin's display face — for the few
    /// hero titles that are sized by hand rather than by text style (Library
    /// card titles, the substance hero). Scales with Dynamic Type relative to
    /// `relativeTo`. Skins without a display face get the system font at that
    /// size, weight and design, exactly as before.
    static func piru(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design? = nil, relativeTo style: Font.TextStyle = .title, scaling: Bool = true) -> Font {
        guard let font = SkinFace.display(weight: weight, size: size, relativeTo: style, scaling: scaling) else {
            return .system(size: size, weight: weight, design: design)
        }
        return font
    }

    /// A semantic text style in the skin's label face — for chips, badges and
    /// eyebrows only. Falls back to the system style.
    static func piruLabel(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        guard let font = SkinFace.label(weight: weight, size: style.defaultPointSize, relativeTo: style) else {
            return Font.system(style).weight(weight)
        }
        return font
    }
}

#if canImport(UIKit)
/// Resolves a skin's family + weight to a **registered font name**, and builds
/// the `Font` through UIKit.
///
/// Two traps, both silent: `Font.custom` wants a font name (`Fredoka-Bold`),
/// not a family (`Fredoka`), and even with the right name it rendered the
/// system font for this variable font's named instances on device, while
/// `UIFont(name:)` resolved them — which is why the navigation bar (UIKit) was
/// right when card titles (SwiftUI) were wrong. So the name is checked against
/// UIKit, and the `Font` is a wrapped `UIFont` scaled by `UIFontMetrics` for
/// Dynamic Type, never `Font.custom`.
enum SkinFace {
    /// The skin's display family at `weight`, as a `Font`, or nil for system.
    static func display(weight: Font.Weight, size: CGFloat, relativeTo style: Font.TextStyle, scaling: Bool = true) -> Font? {
        let typeface = SkinStore.shared.current.typeface
        return typeface.display.map { font(family: $0, weight: weight, size: size * typeface.displayScale, relativeTo: style, scaling: scaling) }
    }

    /// The skin's label family at `weight`, as a `Font`, or nil for system.
    static func label(weight: Font.Weight, size: CGFloat, relativeTo style: Font.TextStyle) -> Font? {
        SkinStore.shared.current.typeface.label.map { font(family: $0, weight: weight, size: size, relativeTo: style) }
    }

    /// Builds the face by **family + weight descriptor** — the lookup the
    /// navigation bar uses, and the one that resolves a variable font's
    /// instances before anything else has touched the family. `UIFont(name:)`
    /// returned nil for `Fredoka-Bold` on the first render of a launch while
    /// this returned the right face, which is why card titles were the system
    /// font under a Fredoka nav title. Scaled by `UIFontMetrics` for Dynamic Type.
    static func font(family: String, weight: Font.Weight, size: CGFloat, relativeTo style: Font.TextStyle, scaling: Bool = true) -> Font {
        let base = baseFont(family: family, weight: weight, size: size)
        // `scaling: false` is for the fixed-size chart/stat roles in TextRoles,
        // which are laid out against fixed-height cards and gutters.
        return Font(scaling ? UIFontMetrics(forTextStyle: style.uiTextStyle).scaledFont(for: base) : base)
    }

    /// Descriptor matching is font *lookup* — a real cost, and this runs on
    /// every text render of every skinned title and chip. Cached per
    /// family/weight/size; a journal screen resolves the same handful of
    /// fonts thousands of times.
    private struct FontKey: Hashable {
        let family: String
        let weight: UIFont.Weight.RawValue
        let size: CGFloat
    }

    private static var fontCache: [FontKey: UIFont] = [:]

    private static func baseFont(family: String, weight: Font.Weight, size: CGFloat) -> UIFont {
        let uiWeight = uiWeight(weight)
        let key = FontKey(family: family, weight: uiWeight.rawValue, size: size)
        if let cached = fontCache[key] { return cached }
        let descriptor = UIFontDescriptor(fontAttributes: [
            .family: family,
            .traits: [UIFontDescriptor.TraitKey.weight: uiWeight],
        ])
        let font = UIFont(descriptor: descriptor, size: size)
        fontCache[key] = font
        return font
    }

    /// The registered PostScript-style name for `family` at `weight`, or nil.
    /// Diagnostic — `SkinTypeTests` uses it to prove the faces are bundled; the
    /// render path above does not depend on it.
    static func registered(_ family: String, weight: Font.Weight) -> String? {
        for suffix in [suffix(for: weight), "Regular"] {
            let name = "\(family)-\(suffix)"
            if UIFont(name: name, size: 17) != nil { return name }
        }
        return UIFont(name: family, size: 17) != nil ? family : nil
    }

    static func uiWeight(_ weight: Font.Weight) -> UIFont.Weight {
        switch weight {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        default: .regular
        }
    }

    private static func suffix(for weight: Font.Weight) -> String {
        switch weight {
        case .ultraLight, .thin, .light: "Light"
        case .regular: "Regular"
        case .medium: "Medium"
        case .semibold: "SemiBold"
        default: "Bold"
        }
    }
}

extension Font.TextStyle {
    /// The system's default weight for the style — what `.font(.headline)`
    /// renders without an explicit `.weight()`.
    var defaultWeight: Font.Weight {
        self == .headline ? .semibold : .regular
    }

    /// The five styles a skin's display face applies to.
    var isDisplay: Bool {
        switch self {
        case .largeTitle, .title, .title2, .title3, .headline: true
        default: false
        }
    }

    /// The style's point size at the default (`.large`) content size, which is
    /// the base `Font.custom(_:size:relativeTo:)` scales from.
    var defaultPointSize: CGFloat {
        UIFont.preferredFont(
            forTextStyle: uiTextStyle,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .large),
        ).pointSize
    }

    var uiTextStyle: UIFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .body: .body
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        @unknown default: .body
        }
    }
}

// MARK: - Navigation titles

/// Navigation titles are drawn by UIKit, out of SwiftUI's reach, so the skin's
/// display face reaches them through the appearance proxy — the same route
/// `ContentView` already uses for segmented controls. Proxies apply to bars
/// created after the call; a skin change re-creates the root, so that is enough.
enum SkinNavigationTitles {
    @MainActor
    static func apply(_ skin: Skin) {
        let bar = UINavigationBar.appearance()
        let large = UIFont.TextStyle.largeTitle
        let inline = UIFont.TextStyle.headline
        var largeAttributes: [NSAttributedString.Key: Any] = [:]
        if let family = skin.typeface.display {
            let scale = skin.typeface.displayScale
            largeAttributes[.font] = uiFont(family, weight: .bold, style: large, scale: scale)
            bar.titleTextAttributes = [.font: uiFont(family, weight: .semibold, style: inline, scale: scale)]
        } else if let design = skin.fontDesign {
            largeAttributes[.font] = systemFont(design: design, weight: .bold, style: large)
            bar.titleTextAttributes = [.font: systemFont(design: design, weight: .semibold, style: inline)]
        } else {
            bar.titleTextAttributes = nil
        }
        if let outline = skin.titleOutline {
            // The site's `h1`: filled, with a hard unblurred drop. **No
            // `.strokeWidth` here**: UIKit strokes every contour of the glyph,
            // and Fredoka (a variable font with overlapping components) shows
            // the stroke along each internal overlap as dark seams inside the
            // letters. The SwiftUI hero gets its outline from stacked shadows
            // of the composite fill instead (`.skinHeroTitle()`).
            let drop = NSShadow()
            drop.shadowColor = UIColor(outline.shadow)
            drop.shadowOffset = outline.shadowOffset
            drop.shadowBlurRadius = outline.shadowBlur
            if let fill = outline.fill { largeAttributes[.foregroundColor] = UIColor(fill) }
            largeAttributes[.shadow] = drop
        }
        bar.largeTitleTextAttributes = largeAttributes.isEmpty ? nil : largeAttributes
    }

    /// The system face in a design (`.rounded` for Tsuki), for the bar — a
    /// root `.fontDesign` reaches SwiftUI text only, never UIKit's titles.
    private static func systemFont(design: Font.Design, weight: UIFont.Weight, style: UIFont.TextStyle) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: style)
        let uiDesign: UIFontDescriptor.SystemDesign = switch design {
        case .rounded: .rounded
        case .serif: .serif
        case .monospaced: .monospaced
        default: .default
        }
        let descriptor = (base.fontDescriptor.withDesign(uiDesign) ?? base.fontDescriptor)
            .addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
        return UIFontMetrics(forTextStyle: style).scaledFont(for: UIFont(descriptor: descriptor, size: base.pointSize))
    }

    /// The same family + weight descriptor `SkinFace` renders with, as a `UIFont`.
    private static func uiFont(_ family: String, weight: UIFont.Weight, style: UIFont.TextStyle, scale: CGFloat = 1) -> UIFont {
        let size = UIFont.preferredFont(forTextStyle: style).pointSize * scale
        let descriptor = UIFontDescriptor(fontAttributes: [
            .family: family,
            .traits: [UIFontDescriptor.TraitKey.weight: weight],
        ])
        return UIFontMetrics(forTextStyle: style).scaledFont(for: UIFont(descriptor: descriptor, size: size))
    }
}
#else

    /// macOS: the app is built for the Mac as well, where fonts resolve
    /// through AppKit. `Font.custom` with the family name is enough there —
    /// the variable-font trap this file works around is a UIKit one.
    enum SkinFace {
        static func display(weight: Font.Weight, size: CGFloat, relativeTo style: Font.TextStyle, scaling: Bool = true) -> Font? {
            SkinStore.shared.current.typeface.display.map { font(family: $0, weight: weight, size: size, relativeTo: style, scaling: scaling) }
        }

        static func label(weight: Font.Weight, size: CGFloat, relativeTo style: Font.TextStyle) -> Font? {
            SkinStore.shared.current.typeface.label.map { font(family: $0, weight: weight, size: size, relativeTo: style) }
        }

        static func font(family: String, weight: Font.Weight, size: CGFloat, relativeTo style: Font.TextStyle, scaling: Bool = true) -> Font {
            (scaling ? Font.custom(family, size: size, relativeTo: style) : Font.custom(family, fixedSize: size)).weight(weight)
        }

        static func registered(_ family: String, weight: Font.Weight) -> String? {
            NSFontManager.shared.availableFontFamilies.contains(family) ? family : nil
        }
    }

    extension Font.TextStyle {
        var defaultWeight: Font.Weight {
            self == .headline ? .semibold : .regular
        }

        var isDisplay: Bool {
            switch self {
            case .largeTitle, .title, .title2, .title3, .headline: true
            default: false
            }
        }

        var defaultPointSize: CGFloat {
            NSFont.preferredFont(forTextStyle: nsTextStyle).pointSize
        }

        var nsTextStyle: NSFont.TextStyle {
            switch self {
            case .largeTitle: .largeTitle
            case .title: .title1
            case .title2: .title2
            case .title3: .title3
            case .headline: .headline
            case .subheadline: .subheadline
            case .body: .body
            case .callout: .callout
            case .footnote: .footnote
            case .caption: .caption1
            case .caption2: .caption2
            @unknown default: .body
            }
        }
    }

    /// macOS has no UIKit navigation bar to style; SwiftUI titles take the
    /// root `fontDesign` and `.skinHeroTitle()` on their own.
    enum SkinNavigationTitles {
        @MainActor
        static func apply(_ skin: Skin) {}
    }
#endif
