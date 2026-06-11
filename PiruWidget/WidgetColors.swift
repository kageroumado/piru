import SwiftUI
import UIKit

enum WidgetColors {
    /// Mirrors the app's asset-catalog `AccentColor` — soft pink (#F57896) in
    /// light mode, hot pink (#FF2D6F) in dark. The widget target doesn't
    /// include the app's `Assets.xcassets`, so the variants are built in code
    /// via a dynamic provider.
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1.00, green: 0.176, blue: 0.435, alpha: 1.0)
            : UIColor(red: 0.96, green: 0.470, blue: 0.590, alpha: 1.0)
    })

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
