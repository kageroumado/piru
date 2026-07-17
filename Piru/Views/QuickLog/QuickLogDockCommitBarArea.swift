import SwiftUI

// MARK: - Pinned commit bar

/// The bottom safe-area bar: chips + Log button. Content scrolls beneath it
/// with the soft edge effect.
///
/// The bar stays mounted at its intrinsic height for the dock's whole lifetime
/// and is only *faded* out while the tray is empty. Structurally removing it
/// (or collapsing it to zero height) unregisters the scroll pocket, and
/// re-registering a pocket on a live sheet corrupts UIKit's scroll-edge-effect
/// layout: the bottom effect view inflates to cover the entire scroll view (a
/// full-height blur that "erases" the content) with a touch blocker over
/// everything — the delete-last-dose → stage-again wedge. The bare face's
/// geometry is protected on the scroll view instead (see the frame in
/// ``QuickLogDock``).
struct DockCommitBarArea: View {
    var tray: DoseTrayModel
    var content: QuickLogContentModel
    let isBare: Bool
    @Binding var commitBarHeight: CGFloat
    let onCommit: () -> Void

    var body: some View {
        let visible = !tray.isEmpty && !isBare
        return TrayCommitBar(
            model: tray,
            content: content,
            onCommit: onCommit,
        )
        .padding(.horizontal, 16)
        // Intrinsic height always: when a drag squeezes the sheet below the
        // compact detent, the bar must clip rather than compress — a
        // compressed measurement re-minted the compact detent mid-gesture and
        // snapped the sheet to the wrong one.
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { newValue in
            guard abs(newValue - commitBarHeight) > 0.5 else { return }
            commitBarHeight = newValue
        }
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)
        .accessibilityHidden(!visible)
    }
}
