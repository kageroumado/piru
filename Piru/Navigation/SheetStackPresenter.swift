import SwiftUI

/// Identifiers for the sheet zoom transition. The journal's floating add button
/// and the day-detail's add button each tag themselves with their *own* id
/// (distinct ids avoid the undefined behaviour of two `matchedTransitionSource`s
/// sharing one id in the same namespace — the journal tab stays alive behind
/// other tabs, so both would otherwise register at once). The launching button
/// records which id it is via ``AppNavigator/sheetZoomSourceID`` so the depth-0
/// sheet zooms out of the button that was actually tapped.
///
/// The session accessory deliberately has no id here: iOS hosts it in a separate
/// context where a zoom can't anchor, so its sheets present as a normal slide-up.
enum QuickLogTransition {
    static let floatingID = "quickLog.zoom.floating"
    static let dayDetailID = "quickLog.zoom.dayDetail"
}

extension EnvironmentValues {
    /// The quick-log zoom namespace, published by `ContentView` so add buttons
    /// living outside it (e.g. the day/session detail's floating button) can tag
    /// themselves as a `matchedTransitionSource` and grow into the sheet too.
    @Entry var quickLogZoomNamespace: Namespace.ID?
}

/// Recursively renders the navigator's `sheetStack` by attaching one
/// `.sheet(item:)` modifier per depth level. Each level binds to its own
/// stack index so SwiftUI's identity-preserving sheet diffing works normally.
///
/// We cap the visible depth at ``maxDepth`` to avoid pathological deep stacks
/// that iOS doesn't render reliably anyway.
struct SheetStackPresenter: ViewModifier {
    @Bindable var navigator: AppNavigator
    /// Namespace for the quick-log zoom transition, shared with the add-button
    /// sources in `ContentView`. The depth-0 quick-log sheet uses it to grow
    /// out of the tapped button rather than sliding up from the bottom.
    var quickLogZoom: Namespace.ID?

    func body(content: Content) -> some View {
        content.modifier(SheetLayer(navigator: navigator, depth: 0, quickLogZoom: quickLogZoom))
    }
}

/// A single layer of the sheet stack. Each layer reads its own depth, presents
/// the sheet at that depth (if any), and recurses one level deeper inside the
/// presented content.
private struct SheetLayer: ViewModifier {
    @Bindable var navigator: AppNavigator
    let depth: Int
    var quickLogZoom: Namespace.ID?

    func body(content: Content) -> some View {
        if depth >= AppNavigator.maxSheetDepth {
            content
        } else {
            content.sheet(item: binding) { route in
                SheetRouteView(route: route)
                    .modifier(SheetLayer(navigator: navigator, depth: depth + 1, quickLogZoom: quickLogZoom))
                    .environment(\.appNavigator, navigator)
                    .sheetZoomTransition(
                        depth: depth,
                        sourceID: navigator.sheetZoomSourceID,
                        in: quickLogZoom,
                    )
            }
        }
    }

    /// Binds the sheet at this depth. Setting `nil` from the system (swipe
    /// down, tap outside) dismisses the top sheet by trimming the stack.
    private var binding: Binding<SheetRoute?> {
        Binding(
            get: { navigator.sheetStack.indices.contains(depth) ? navigator.sheetStack[depth] : nil },
            set: { newValue in
                if newValue == nil {
                    // System dismissed the sheet at this depth — trim the
                    // stack to here, discarding any deeper sheets (they're
                    // gone because their host went away).
                    navigator.truncateSheetStack(to: depth)
                }
            },
        )
    }
}

extension View {
    /// Presents `navigator.sheetStack` as nested sheets. Attach at the root of
    /// the scene above the tab view; do not attach multiple times in the
    /// hierarchy.
    ///
    /// Pass `quickLogZoom` to let depth-0 sheets grow out of their launching
    /// control via a zoom transition (the control must be tagged with
    /// `matchedTransitionSource(id:in:)` using a `QuickLogTransition` id).
    func sheetStackPresenter(_ navigator: AppNavigator, quickLogZoom: Namespace.ID? = nil) -> some View {
        modifier(SheetStackPresenter(navigator: navigator, quickLogZoom: quickLogZoom))
    }

    /// Applies the zoom transition to a presented sheet, but only at the top
    /// level (`depth == 0`) and only when the launch recorded a `sourceID` —
    /// that's the only case with an on-screen `matchedTransitionSource` to grow
    /// from. Nested or deep-linked sheets (no `sourceID`) slide up by default.
    @ViewBuilder
    fileprivate func sheetZoomTransition(
        depth: Int,
        sourceID: String?,
        in namespace: Namespace.ID?,
    ) -> some View {
        if depth == 0, let namespace, let sourceID {
            navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            self
        }
    }
}
