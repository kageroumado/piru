import SwiftUI
import UIKit

enum Theme {
    /// Soft pink in light mode, hot pink in dark mode
    static let accent = Color("AccentColor")

    /// Darker secondary label for improved readability
    static let secondaryLabel: Color = Color(UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.65, green: 0.65, blue: 0.68, alpha: 1)
        } else {
            return UIColor(red: 0.48, green: 0.48, blue: 0.50, alpha: 1)
        }
    })

    // MARK: - OLED Dark Mode Backgrounds

    /// Main background: pure black in dark mode, system white in light mode
    static let background: Color = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0, green: 0, blue: 0, alpha: 1)
            : .systemBackground
    })

    /// Card/surface background: very dark gray in dark mode
    static let cardBackground: Color = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.067, green: 0.067, blue: 0.067, alpha: 1)
            : .secondarySystemGroupedBackground
    })

    /// Grouped background: slightly off-black in dark mode
    static let groupedBackground: Color = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.039, green: 0.039, blue: 0.039, alpha: 1)
            : .systemGroupedBackground
    })

    /// Input field background
    static let inputBackground: Color = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
            : .systemGray6
    })
}

// MARK: - Theme View Modifiers

struct ThemedBackground<S: Shape>: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    let shape: S

    func body(content: Content) -> some View {
        if colorScheme == .dark {
            content.background(Theme.cardBackground, in: shape)
        } else {
            content.background(.ultraThinMaterial, in: shape)
        }
    }
}

extension View {
    func themeCard(cornerRadius: CGFloat = 16) -> some View {
        modifier(ThemedBackground(shape: RoundedRectangle(cornerRadius: cornerRadius)))
    }

    func themeCapsule() -> some View {
        modifier(ThemedBackground(shape: Capsule()))
    }
}
