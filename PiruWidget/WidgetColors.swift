import SwiftUI

enum WidgetColors {
    /// The app's asset-catalog `AccentColor`, resolved from the real colorset.
    ///
    /// This used to be a hand-transcribed `UIColor { traits }` copy, because the
    /// widget target could not see `Assets.xcassets` while it lived under
    /// `Piru/`. The catalog now lives in `Shared/`, which is a synchronized
    /// group of all three targets, so the duplicate is gone. The transcription
    /// was colorimetrically correct — this removes the drift risk, not a bug —
    /// and reading the colorset also picks up its Display-P3 components, which
    /// the sRGB literals could not represent.
    static let accent = Color("AccentColor")

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
