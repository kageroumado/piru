import SwiftUI

/// The app's spacing ladder.
///
/// Every step is a value already in wide use across `Piru/Views`; the ladder
/// names them so a stack gap, a padding, and a grid gutter that mean the same
/// thing cannot silently drift apart. Values are points, not multiples — the
/// ladder is deliberately non-uniform below `xxl` because the small end is where
/// SwiftUI's own defaults cluster.
enum Spacing {
    /// 2 pt — hairline separation inside a chip or badge.
    static let xxs: CGFloat = 2
    /// 4 pt — label above its value.
    static let xs: CGFloat = 4
    /// 6 pt — icon beside its text.
    static let sm: CGFloat = 6
    /// 8 pt — the default gap between sibling rows.
    static let md: CGFloat = 8
    /// 10 pt — leading icon to a multi-line block.
    static let lg: CGFloat = 10
    /// 12 pt — between grouped controls.
    static let xl: CGFloat = 12
    /// 16 pt — card inset, section gutter.
    static let xxl: CGFloat = 16
    /// 24 pt — between major sections of a screen.
    static let xxxl: CGFloat = 24
}

extension EdgeInsets {
    /// The standard grouped-list row inset: 16 pt side gutters matching the
    /// system's own, with an asymmetric 4/10 vertical rhythm that sits a row
    /// closer to its header than to the row below.
    ///
    /// Measured as one of the two most frequent explicit `listRowInsets`
    /// argument sets in `Piru/Views` (2 sites, tied with ``rowCompact``).
    static let rowStandard = EdgeInsets(
        top: Spacing.xs,
        leading: Spacing.xxl,
        bottom: Spacing.lg,
        trailing: Spacing.xxl,
    )

    /// The tighter row inset for dense lists — even 8 pt vertical, 12 pt sides.
    ///
    /// Measured at 2 sites in `Piru/Views`.
    static let rowCompact = EdgeInsets(
        top: Spacing.md,
        leading: Spacing.xl,
        bottom: Spacing.md,
        trailing: Spacing.xl,
    )

    /// Zero inset — the row draws edge to edge and owns its own padding.
    ///
    /// The single most frequent form in `Piru/Views` (4 sites, written as a bare
    /// `EdgeInsets()`).
    static let rowFlush = EdgeInsets()
}
