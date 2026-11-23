import SwiftUI

/// The route-of-administration badge — a fixed-per-route tinted capsule ("oral")
/// that reads identically everywhere it appears: one place owns the padding and
/// font for every call site.
///
/// The case is the chip's (``ChipLabel``): lowercase on a dense row, like its
/// sibling strength and severity chips, capitalized at the hero size. Size is
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
        Text(route.localizedName)
            .capsuleChip(text: route.tintTextColor, fill: route.tintColor, size: size.chipSize)
    }
}
