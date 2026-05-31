import SwiftUI

enum WidgetColors {
    /// Light mode: soft pink (#F57896), Dark mode: hot pink (#FF2D6F)
    static let accent = Color(red: 0.96, green: 0.47, blue: 0.59)

    static let backgroundGradientTop = Color(red: 0.06, green: 0.04, blue: 0.08)
    static let backgroundGradientBottom = Color(red: 0.10, green: 0.05, blue: 0.10)
}

struct WidgetBackground: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
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
    }
}
