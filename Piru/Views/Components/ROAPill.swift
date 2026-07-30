import SwiftUI

/// The route-of-administration badge — a fixed-per-route tinted capsule ("oral")
/// that reads identically everywhere it appears. Extracted so the casing, padding,
/// and font can't drift between call sites (they had: the dose row lowercased at
/// `.caption2`/8·3, while the detail hero and the Journal active-session row
/// capitalized at `.caption`/10·5).
///
/// Casing is unified **lowercase** to match the row's sibling chips (the strength
/// tier "common"/"sub-threshold" and the interaction-severity chip), so route,
/// strength, and severity read as one lowercase badge grammar. Size is
/// configurable for dense rows vs. standalone hero placements.
struct ROAPill: View {
    let route: RouteOfAdministration
    var size: Size = .compact

    enum Size {
        /// Dense dose rows — sits alongside the strength chip.
        case compact
        /// Standalone placements: the entry-detail hero, the active-session row.
        case regular

        var font: Font {
            switch self {
            case .compact: .caption2.weight(.semibold)
            case .regular: .caption.weight(.semibold)
            }
        }

        var horizontalPadding: CGFloat {
            self == .compact ? 8 : 10
        }

        var verticalPadding: CGFloat {
            self == .compact ? 3 : 5
        }
    }

    var body: some View {
        Text(String(localized: route.localizedName).lowercased())
            .font(size.font)
            .lineLimit(1)
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            // 0.10, not the 0.16 this used to be: at 0.16 a colour on a tint of
            // itself asymptotes around 4.5:1 in dark mode whatever its
            // lightness, so every route failed there and no hue retune could fix
            // it. The label takes the gated text variant, the fill the accent.
            .background(route.tintColor.opacity(0.10), in: Capsule())
            .foregroundStyle(route.tintTextColor)
    }
}
