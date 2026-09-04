import SwiftUI

/// The color swatch that stands in for a series in a chart legend, a status row,
/// or a category key.
///
/// A dot is a non-text mark, so it carries no contrast obligation beyond 3:1 —
/// which is why an identity color the app would never set as small text is
/// legitimate here.
struct LegendDot: View {
    /// The mark color the dot stands for.
    let color: Color
    /// How large the dot reads beside its label.
    var size: Size = .regular

    /// The three dot diameters the app uses.
    enum Size {
        /// 7 pt — inside a chip or a dense inline run.
        case compact
        /// 8 pt — the default, matching ``IconSize/dot``.
        case regular
        /// 9 pt — beside a heading or a hero value.
        case large

        var diameter: CGFloat {
            switch self {
            case .compact: IconSize.dot - 1
            case .regular: IconSize.dot
            case .large: IconSize.dot + 1
            }
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size.diameter, height: size.diameter)
            .accessibilityHidden(true)
    }
}
