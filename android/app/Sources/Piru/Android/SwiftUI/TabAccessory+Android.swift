// The iOS tab-bar bottom accessory, which holds Piru's Log button and live-session pill.
// Compose's navigation bar has no accessory slot, so the content floats just above the bar,
// always in its expanded placement: the Material bar does not minimize on scroll.

import SwiftUI

enum TabViewBottomAccessoryPlacement: Equatable {
    case expanded
    case inline
}

extension EnvironmentValues {
    @Entry var tabViewBottomAccessoryPlacement: TabViewBottomAccessoryPlacement? = .expanded
}

extension View {
    /// Height of the Material navigation bar the accessory sits above.
    private static var navigationBarClearance: CGFloat { 88 }

    func tabViewBottomAccessory(@ViewBuilder content: () -> some View) -> some View {
        let accessory = content()
        return overlay(alignment: .bottom) {
            accessory
                .frame(height: 52)
                // iOS's glass bar: gray on a dark page (a shadow cannot show on black),
                // near-white on a light one, edged by a hairline.
                .background(Capsule().fill(.androidThickMaterial))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                .padding(.horizontal, 16)
                .padding(.bottom, Self.navigationBarClearance)
        }
    }
}
