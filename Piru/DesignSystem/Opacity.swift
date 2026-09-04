import SwiftUI

extension Theme {
    /// The app's alpha ladder.
    ///
    /// Alpha in this app is load-bearing for contrast, so the steps are named by
    /// the job they do rather than by their value — picking "a bit more visible"
    /// by nudging a number is how small copy ends up under WCAG AA.
    enum Opacity {
        /// 0.08 — a separator or a barely-there fill that reads as texture.
        static let hairline: Double = 0.08

        /// 0.10 — the tint a mark color is drawn on when the **same** color is
        /// the foreground (the ``CapsuleChip`` grammar: route pills, dose-strength
        /// chips, severity badges).
        ///
        /// Never raise it. A color on a tint of itself asymptotes around 4.5:1 in
        /// dark mode regardless of lightness, so a heavier tint fails the WCAG AA
        /// gate; every `text` variant in `design-system/color/` is derived against
        /// this exact alpha. Use ``tintActive`` only where the foreground is a
        /// *different* color — white or `.primary` — never the fill's own.
        static let tint: Double = 0.10

        /// 0.18 — a selected or active fill under a foreground of a different
        /// color (white, `.primary`). Not for a color on a tint of itself.
        static let tintActive: Double = 0.18

        /// 0.25 — an emphasized fill or a stroke that must read as deliberate.
        static let emphasis: Double = 0.25

        /// 0.4 — a disabled or de-emphasized non-text mark.
        static let muted: Double = 0.4

        /// 0.5 — a half-strength mark: a gridline, a trailing curve segment.
        static let dimmed: Double = 0.5

        /// 0.8 — nearly opaque; a scrim or an almost-solid overlay.
        static let strong: Double = 0.8
    }
}
