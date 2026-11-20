import SwiftUI

/// The route-of-administration badge — a fixed-per-route tinted capsule ("oral")
/// that reads identically everywhere it appears: one place owns the casing,
/// padding, and font for every call site.
///
/// Casing is **lowercase** to match the row's sibling chips (the strength
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

        var chipSize: CapsuleChipSize {
            switch self {
            case .compact: .compact
            case .regular: .hero
            }
        }
    }

    var body: some View {
        // The label takes the gated text variant, the fill the accent.
        Text(String(localized: route.localizedName).lowercased())
            .capsuleChip(text: route.tintTextColor, fill: route.tintColor, size: size.chipSize)
    }
}
