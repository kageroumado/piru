import SwiftUI

/// Square metrics for icons, glyph wells, and hit targets.
///
/// Each is applied as `.frame(width:height:)` with the same value in both slots,
/// so a name here always means a square.
enum IconSize {
    /// 44 pt — the minimum comfortable hit target (Apple HIG). Wrap a smaller
    /// visual in a frame this size rather than growing the visual.
    static let touchTarget: CGFloat = 44
    /// 34 pt — a circular avatar or weekday toggle.
    static let icon: CGFloat = 34
    /// 28 pt — a leading row glyph well.
    static let iconSmall: CGFloat = 28
    /// 24 pt — a compact inline glyph.
    static let iconCompact: CGFloat = 24
    /// 22 pt — the smallest glyph well that still reads as a well.
    static let iconMini: CGFloat = 22
    /// 8 pt — a legend or status dot.
    static let dot: CGFloat = 8
}
