import SwiftUI

extension Theme {
    /// The app's corner-radius ladder.
    ///
    /// A fixed radius is a fallback, not the first choice: ``SwiftUI/View/themeCard(cornerRadius:)``
    /// derives its corner from the enclosing container via `ConcentricRectangle`
    /// and only falls back to a fixed minimum. These steps are for the shapes
    /// that cannot inherit — an inline `RoundedRectangle`, a stroke overlay, a
    /// clip shape on a leaf view.
    enum CornerRadius {
        /// 22 pt — the card rounding, matching the system grouped-list corner.
        static let card = Theme.cardCornerRadius
        /// 16 pt — a container that groups several cards or rows.
        static let container: CGFloat = 16
        /// 12 pt — a standalone panel or banner.
        static let medium: CGFloat = 12
        /// 10 pt — a shape nested one level inside a card.
        static let inner: CGFloat = 10
        /// 8 pt — a text field or other input fill.
        static let input: CGFloat = 8
        /// 3 pt — a chart bar cap or another mark-sized rounding.
        static let tiny: CGFloat = 3
    }
}
