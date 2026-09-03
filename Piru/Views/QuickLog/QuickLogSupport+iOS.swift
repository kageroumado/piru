import SwiftUI
import UIKit

// MARK: - Cover Accessibility Unmasker

/// Restores VoiceOver access to the dock sheet at undimmed detents.
///
/// UIKit marks the quick-log cover's `UITransitionView` `accessibilityViewIsModal`
/// (it's a full-screen modal), and VoiceOver ignores every *sibling* of a modal
/// view — which includes the always-presented dock sheet's own transition view
/// whenever the dock is non-modal (peek/compact/medium, i.e. whenever
/// `presentationBackgroundInteraction` leaves it undimmed). Net effect: at rest
/// the search field, staged doses, and Log Dose are invisible to assistive tech;
/// at `.large` the dock's transition view turns modal itself, wins as topmost,
/// and the situation flips (verified via lldb: both transition views, flag by
/// detent). The full-screen presentation already removes the Journal underneath
/// from the hierarchy, so the cover's modal flag protects nothing — clearing it
/// exposes cover content and dock together, while the dock's *own* modal flag
/// still correctly masks the cover at `.large`.
///
/// Public-API superview walk from a hosted leaf, same pattern as the (retired)
/// `SheetPlatterHider`. Re-asserted from `layoutSubviews` because UIKit can
/// re-apply the flag across presentation transitions.
struct CoverAccessibilityUnmasker: UIViewRepresentable {
    func makeUIView(context _: Context) -> UnmaskView {
        UnmaskView()
    }
    func updateUIView(_: UnmaskView, context _: Context) {}

    final class UnmaskView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            unmask()
            // The presentation transition can set the flag after this view
            // lands in the window — re-check once the current turn settles.
            DispatchQueue.main.async { [weak self] in self?.unmask() }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            unmask()
        }

        private func unmask() {
            var ancestor = superview
            while let view = ancestor {
                if view.accessibilityViewIsModal {
                    view.accessibilityViewIsModal = false
                    UIAccessibility.post(notification: .layoutChanged, argument: nil)
                    break
                }
                ancestor = view.superview
            }
        }
    }
}
