import SwiftUI

// MARK: - Type roles

extension View {
    /// Secondary caption text — the app's de-emphasized annotation under a value
    /// or beside a label.
    func captionSecondary() -> some View {
        font(.caption).foregroundStyle(Theme.secondaryLabel)
    }

    /// The label above a group of rows inside a card.
    func sectionLabel() -> some View {
        font(.subheadline.weight(.semibold))
    }

    /// The title of a card or a banner.
    func cardTitle() -> some View {
        font(.headline)
    }

    /// The title at the top of a screen or a full-width sheet.
    func screenTitle() -> some View {
        font(.title3.weight(.semibold))
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
    /// Fixed size: the hero numeral is laid out against a card whose height is
    /// fixed, and scaling it pushes the caption beneath it off the card.
    ///
    /// Pinned to `.system(size: 38, weight: .bold)`, the most frequent form in
    /// the 38–40 pt cluster across `Piru/Views` (3 sites; next is
    /// `size: 40, weight: .heavy, design: .rounded` at 2).
    static let heroStat = Font.system(size: 38, weight: .bold)

    /// 17 pt semibold — a heading that must hold a fixed optical size beside a
    /// chart or a fixed-height header.
    ///
    /// Fixed size, so it does not scale with Dynamic Type; prefer
    /// ``SwiftUI/View/screenTitle()`` for any heading that can reflow.
    ///
    /// Pinned to `.system(size: 17, weight: .semibold)`, the most frequent form
    /// in the 17 pt cluster across `Piru/Views` (5 sites; next is
    /// `size: 17, weight: .bold` at 1).
    static let sectionTitle = Font.system(size: 17, weight: .semibold)
}
