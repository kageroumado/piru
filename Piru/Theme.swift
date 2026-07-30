import SwiftUI
import UIKit

enum Theme {
    /// Soft pink in light mode, hot pink in dark mode
    static let accent = Color("AccentColor")

    /// Yellow that stays legible as text/icon on a light surface — pure yellow
    /// is unreadable on white, so it darkens to amber in light mode while
    /// keeping its yellow identity in dark mode. Used for the "Common" dose
    /// level and "Caution" interaction severity labels.
    static let legibleYellow: Color = .init(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? .systemYellow
            : UIColor(red: 0.52, green: 0.39, blue: 0.0, alpha: 1)
    })

    /// De-emphasized body text. ~566 call sites, so this accessor stays even
    /// though the value now comes from the asset catalog.
    ///
    /// The old hand-rolled pair (`#7A7A80` / `#A6A6AD`) was half right. Its
    /// light value genuinely beat the system colour — 3.89:1 against system's
    /// 2.17:1 — but **still failed WCAG AA**, which the original audit missed by
    /// computing against pure white instead of the measured `#f5f5f5` card. Its
    /// dark value was simply worse than the system's (7.79 vs 9.97).
    ///
    /// Now `#6E6E73` light (4.65:1) and the system's own `#BCBCC4` dark
    /// (9.97:1). Gated by `ColorContrastTests`.
    static let secondaryLabel = Color.Text.secondary

    // MARK: - OLED Dark Mode Backgrounds

    /// Main background: pure black in dark mode, system white in light mode
    static let background: Color = .init(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0, green: 0, blue: 0, alpha: 1)
            : .systemBackground
    })

    /// Card/surface background: very dark gray in dark mode, subtle off-white in light mode
    static let cardBackground: Color = .init(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.067, green: 0.067, blue: 0.067, alpha: 1)
            : .systemGray6
    })

    /// Grouped background: slightly off-black in dark mode
    static let groupedBackground: Color = .init(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.039, green: 0.039, blue: 0.039, alpha: 1)
            : .systemGroupedBackground
    })

    /// Input field background
    static let inputBackground: Color = .init(UIColor { traits in
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

/// The app's standard card fill as a standalone view — the same scheme-adaptive
/// treatment ``themeCard`` applies (`.ultraThinMaterial` in light, a soft solid
/// in dark), for `listRowBackground` and other spots that need the fill directly.
/// Replaces the bare `Theme.cardBackground` (a cold `systemGray6` in light) so
/// grouped Lists match the rest of the app.
struct CardBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if colorScheme == .dark {
            Theme.cardBackground
        } else {
            Rectangle().fill(.ultraThinMaterial)
        }
    }
}

extension View {
    /// Default corner radius `22` matches the system grouped-list / Library card
    /// rounding (the 16 the app shipped with read too boxy next to them).
    func themeCard(cornerRadius: CGFloat = 22) -> some View {
        modifier(ThemedBackground(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)))
    }

    /// Conditionally apply the card background — for rows that live inside a
    /// shared grouped container, where the container draws the background and the
    /// row should not.
    @ViewBuilder
    func themeCard(enabled: Bool, cornerRadius: CGFloat = 16) -> some View {
        if enabled {
            themeCard(cornerRadius: cornerRadius)
        } else {
            self
        }
    }

    func themeCapsule() -> some View {
        modifier(ThemedBackground(shape: Capsule()))
    }
}
