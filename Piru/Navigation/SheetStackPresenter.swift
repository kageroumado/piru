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
            // Two presentation containers share this depth: routes that want a
            // full-screen cover (quick log — Maps-style, with its own dock sheet
            // on top) and everything else as a regular sheet. The bindings are
            // mutually exclusive per route, so at most one presents at a time.
            //
            // The cover branch does NOT wrap the next layer: quick log keeps a
            // persistent dock sheet presented for its whole lifetime, which
            // occupies the cover's only presentation slot — a nested sheet
            // attached here could never present. The cover's content mounts the
            // next layer on the dock instead, via
            // ``hostsNestedNavigatorSheets(_:)``.
            content
                // The quick-log cover clears its transition view's
                // `accessibilityViewIsModal` (see `CoverAccessibilityUnmasker`)
                // so VoiceOver can reach the dock sheet at undimmed detents —
                // which un-hides this presenting layer as a side effect. Hide
                // it explicitly while a cover is up; regular sheets keep the
                // system's own modality handling.
                .accessibilityHidden(coverPresentedHere)
                .sheet(item: binding(fullScreen: false)) { route in
                    routeContent(route)
                        .modifier(SheetLayer(navigator: navigator, depth: depth + 1))
                }
                .fullScreenCover(item: binding(fullScreen: true)) { route in
                    // The cover's content re-mounts the next layer itself at a
                    // hardcoded depth 1 (see `hostsNestedNavigatorSheets`) —
                    // only correct while covers present at depth 0. Nothing
                    // structurally prevents a deeper cover, so fail loudly in
                    // debug if one ever appears.
                    //
                    // `let _ =` is load-bearing: this is a `ViewBuilder`, where a
                    // bare `_ =` is parsed as a view expression and fails to
                    // conform to `View`. The lint rule doesn't know that.
                    // swiftlint:disable:next redundant_discardable_let
                    let _ = assert(
                        depth == 0,
                        "fullScreenCover route at depth \(depth); hostsNestedNavigatorSheets hardcodes nested depth 1",
                    )
                    routeContent(route)
                }
        }
    }

    private func routeContent(_ route: SheetRoute) -> some View {
        SheetRouteView(route: route, depth: depth)
            .environment(\.appNavigator, navigator)
    }

    /// Whether the route at this depth is currently presented as a
    /// full-screen cover (drives the explicit accessibility hide above).
    private var coverPresentedHere: Bool {
        guard navigator.sheetStack.indices.contains(depth) else { return false }
        return navigator.sheetStack[depth].presentsAsFullScreenCover
    }

    /// Binds the route at this depth, filtered to one presentation style.
    /// Setting `nil` from the system (swipe down, tap outside) dismisses the
    /// top sheet by trimming the stack.
    private func binding(fullScreen: Bool) -> Binding<SheetRoute?> {
        Binding(
            get: {
                guard navigator.sheetStack.indices.contains(depth) else { return nil }
                let route = navigator.sheetStack[depth]
                return route.presentsAsFullScreenCover == fullScreen ? route : nil
            },
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

private extension SheetRoute {
    /// Routes presented as a `fullScreenCover` rather than a sheet. Quick log
    /// is full-screen so its staging dock can layer on top as the *only*
    /// detented sheet (Apple Maps model: browse behind, resizable dock over).
    var presentsAsFullScreenCover: Bool {
        if case .quickLog = self { return true }
        return false
    }
}

extension View {
    /// Mounts the navigator's nested sheet layers (depth ≥ 1) on this view.
    ///
    /// The quick-log cover presents a persistent dock sheet that occupies its
    /// only presentation slot, so `SheetLayer` deliberately does not wrap a
    /// cover's content with the next layer. The dock's content attaches this
    /// instead, so navigator sheets launched from quick log (Manage Routines,
    /// Edit Routine…) stack *on the dock*. Hardcodes depth 1 — quick log is
    /// only ever presented at depth 0.
    func hostsNestedNavigatorSheets(_ navigator: AppNavigator) -> some View {
        modifier(SheetLayer(navigator: navigator, depth: 1))
    }

    /// Presents `navigator.sheetStack` as nested sheets. Attach at the root of
    /// the scene above the tab view; do not attach multiple times in the
    /// hierarchy.
    ///
    func sheetStackPresenter(_ navigator: AppNavigator) -> some View {
        modifier(SheetStackPresenter(navigator: navigator))
    }
}
