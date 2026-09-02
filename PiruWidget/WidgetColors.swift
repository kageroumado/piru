import SwiftUI

/// Widget colours follow the app's skin. The widget cannot see `SkinStore`,
/// but `Skin.current` falls back to the persisted choice in the app group,
/// and the app reloads widget timelines whenever the skin changes.
enum WidgetColors {
    /// The skin's text-safe accent — the same symbol the app's `Theme.accent`
    /// resolves to, so a widget never drifts from the app.
    static var accent: Color { Skin.current.accent }

    static let backgroundGradientTop = Color(red: 0.06, green: 0.04, blue: 0.08)
    static let backgroundGradientBottom = Color(red: 0.10, green: 0.05, blue: 0.10)
}

struct WidgetBackground: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        switch Skin.current {
        case .piru:
            if colorScheme == .dark {
                LinearGradient(
                    colors: [
                        WidgetColors.backgroundGradientTop,
                        WidgetColors.backgroundGradientBottom,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing,
                )
            } else {
                Color(.systemBackground)
            }
        case let skin:
            skin.background
        }
    }
}
