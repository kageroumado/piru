import SwiftUI

/// Recursively renders the navigator's `sheetStack` by attaching one
/// `.sheet(item:)` modifier per depth level. Each level binds to its own
/// stack index so SwiftUI's identity-preserving sheet diffing works normally.
///
/// We cap the visible depth at ``maxDepth`` to avoid pathological deep stacks
/// that iOS doesn't render reliably anyway.
struct SheetStackPresenter: ViewModifier {
    @Bindable var navigator: AppNavigator

    func body(content: Content) -> some View {
        content.modifier(SheetLayer(navigator: navigator, depth: 0))
    }
}

/// A single layer of the sheet stack. Each layer reads its own depth, presents
/// the sheet at that depth (if any), and recurses one level deeper inside the
/// presented content.
private struct SheetLayer: ViewModifier {
    @Bindable var navigator: AppNavigator
    let depth: Int

    func body(content: Content) -> some View {
        if depth >= AppNavigator.maxSheetDepth {
            content
        } else {
            content.sheet(item: binding) { route in
                SheetRouteView(route: route)
                    .modifier(SheetLayer(navigator: navigator, depth: depth + 1))
                    .environment(\.appNavigator, navigator)
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
    func sheetStackPresenter(_ navigator: AppNavigator) -> some View {
        modifier(SheetStackPresenter(navigator: navigator))
    }
}
