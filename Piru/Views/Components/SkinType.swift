import SwiftUI
import UIKit

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
    /// use at any call site that used `.font(.headline)` before.
    static func piru(_ style: Font.TextStyle) -> Font {
        guard style.isDisplay, let family = SkinStore.shared.current.typeface.display else {
            return .system(style)
        }
        return .custom(family, size: style.defaultPointSize, relativeTo: style)
    }

    /// A semantic text style in the skin's label face — for chips, badges and
    /// eyebrows only. Falls back to the system style.
    static func piruLabel(_ style: Font.TextStyle) -> Font {
        guard let family = SkinStore.shared.current.typeface.label else {
            return .system(style)
        }
        return .custom(family, size: style.defaultPointSize, relativeTo: style)
    }
}

extension Font.TextStyle {
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
        guard let family = skin.typeface.display else {
            bar.largeTitleTextAttributes = nil
            bar.titleTextAttributes = nil
            return
        }
        let large = UIFont.TextStyle.largeTitle
        let inline = UIFont.TextStyle.headline
        bar.largeTitleTextAttributes = [.font: font(family, weight: .bold, style: large)]
        bar.titleTextAttributes = [.font: font(family, weight: .semibold, style: inline)]
    }

    /// A weighted face from a (variable) family, scaled for Dynamic Type.
    private static func font(_ family: String, weight: UIFont.Weight, style: UIFont.TextStyle) -> UIFont {
        let size = UIFont.preferredFont(forTextStyle: style).pointSize
        let descriptor = UIFontDescriptor(fontAttributes: [
            .family: family,
            .traits: [UIFontDescriptor.TraitKey.weight: weight],
        ])
        return UIFontMetrics(forTextStyle: style).scaledFont(for: UIFont(descriptor: descriptor, size: size))
    }
}
