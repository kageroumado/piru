import SwiftUI

// MARK: - Type roles

extension View {
    /// Secondary caption text — the app's de-emphasized annotation under a value
    /// or beside a label.
    func captionSecondary() -> some View {
        font(.caption).foregroundStyle(Theme.secondaryLabel)
    }

    /// The label above a group of rows inside a card. Always the system face:
    /// this role also carries data (receptor names, section titles), and a
    /// skin's label face is for chips and badges, where a word is a token,
    /// not something to read.
    func sectionLabel() -> some View {
        font(.subheadline.weight(.semibold))
    }

    /// The title of a card or a banner. In the skin's display face.
    func cardTitle() -> some View {
        font(.piru(.headline))
    }

    /// The title at the top of a screen or a full-width sheet. In the skin's
    /// display face.
    func screenTitle() -> some View {
        font(.piru(.title3, weight: .semibold))
    }
}

// MARK: - Fixed-size roles

extension Font {
    /// 9 pt regular — a value printed directly on a chart mark.
    ///
    /// Fixed size, so it does not scale with Dynamic Type: a chart gutter is a
    /// fixed number of points wide and a scaled label truncates or overlaps the
    /// plot rather than reflowing.
    ///
    /// Pinned to `.system(size: 9)`, the most frequent form in the 8–9 pt cluster
    /// across `Piru/Views` (10 sites; next is `size: 8, weight: .bold` at 6).
    static let chartAnnotation = Font.system(size: 9)

    /// 10 pt semibold — an axis tick or legend label.
    ///
    /// Fixed size: an axis label that grows past its gutter shifts the plot area
    /// out from under the data.
    ///
    /// Pinned to `.system(size: 10, weight: .semibold)`, the most frequent form
    /// in the 10 pt cluster across `Piru/Views` (4 sites; next is the `.rounded`
    /// variant at 3).
    static let chartLabel = Font.system(size: 10, weight: .semibold)

    /// 38 pt bold — the single large numeral a stat card is built around.
    ///
    /// Scales with Dynamic Type relative to `.largeTitle`, capped at 64 pt: the
    /// numeral is already the largest thing on its card, and past the cap it
    /// crowds out its unit rather than getting more legible.
    ///
    /// Pinned to `.system(size: 38, weight: .bold)`, the most frequent form in
    /// the 38–40 pt cluster across `Piru/Views` (3 sites; next is
    /// `size: 40, weight: .heavy, design: .rounded` at 2).
    static var heroStat: Font {
        .piru(size: 38, weight: .bold, relativeTo: .largeTitle, maximumSize: 64)
    }

    /// 17 pt semibold — a toolbar glyph (the Journal's and Inventory's "More",
    /// "Filter" and timeline-options buttons) and the icon on a Library class
    /// card.
    ///
    /// Fixed size, so it does not scale with Dynamic Type: a toolbar keeps its
    /// height at every content size, and a navigation bar item shows enlarged
    /// through the Large Content Viewer on long-press instead. Prefer
    /// ``SwiftUI/View/screenTitle()`` for any heading that can reflow.
    ///
    /// Pinned to `.system(size: 17, weight: .semibold)`, the most frequent form
    /// in the 17 pt cluster across `Piru/Views` (5 sites; next is
    /// `size: 17, weight: .bold` at 1).
    static var sectionTitle: Font {
        .piru(size: 17, weight: .semibold, relativeTo: .headline, scaling: false)
    }
}

// MARK: - Hand-sized roles that scale

extension View {
    /// The system face at a hand-picked point size that still scales with
    /// Dynamic Type relative to `style`, up to `maximumSize` when one is given.
    ///
    /// For labels sized between the text styles — an 8 pt tier name, an 11 pt
    /// gutter time — where `.font(.system(size:))` would hold the size at every
    /// content size. At the default content size it renders exactly `size`.
    func scaledSystemFont(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design? = nil,
        relativeTo style: Font.TextStyle,
        maximumSize: CGFloat? = nil,
        monospacedDigit: Bool = false,
    ) -> some View {
        modifier(ScaledSystemFont(
            size: size,
            weight: weight,
            design: design,
            style: style,
            maximumSize: maximumSize,
            monospacedDigit: monospacedDigit,
        ))
    }
}

private struct ScaledSystemFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    let weight: Font.Weight
    let design: Font.Design?
    let maximumSize: CGFloat?
    let monospacedDigit: Bool

    init(size: CGFloat, weight: Font.Weight, design: Font.Design?, style: Font.TextStyle, maximumSize: CGFloat?, monospacedDigit: Bool) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.weight = weight
        self.design = design
        self.maximumSize = maximumSize
        self.monospacedDigit = monospacedDigit
    }

    func body(content: Content) -> some View {
        let font = Font.system(size: min(size, maximumSize ?? size), weight: weight, design: design)
        content.font(monospacedDigit ? font.monospacedDigit() : font)
    }
}
