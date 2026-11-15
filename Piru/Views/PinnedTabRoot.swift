import SwiftUI

/// The root of a tab the user pinned in Settings ▸ Tabs: the screen exactly as
/// it renders when pushed, plus the app's overflow menu — with every stock tab
/// hidden, that menu is the only way back to Settings.
struct PinnedTabRoot: View {
    let screen: PinnedScreen

    var body: some View {
        if screen.ownsOverflowMenu {
            PushRouteView(route: screen.route)
        } else {
            PushRouteView(route: screen.route)
                .toolbar {
                    ToolbarItem(placement: .platformTopBarTrailing) {
                        AppOverflowMenu()
                    }
                }
        }
    }
}
