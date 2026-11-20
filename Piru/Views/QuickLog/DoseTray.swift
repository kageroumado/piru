import SwiftUI

// MARK: - Metrics

/// Geometry for the tray's content, shared with the dock sheet that hosts it.
enum DoseTrayMetrics {
    /// Height of the Log button — literally the dock's pinned search field
    /// height, so the two read as one control system at every Dynamic Type
    /// size.
    static var controlHeight: CGFloat {
        QuickLogDockMetrics.fieldHeight
    }
    /// Corner radius of the grouped cards inside the dock, matching the
    /// system inset-grouped list.
    static let cardCornerRadius: CGFloat = 26
}

// MARK: - Motion-aware morphs

/// The tray's expand/collapse matched-geometry pairing, dropped under Reduce
/// Motion: without the pairing the row⇄editor swap plays as SwiftUI's default
/// crossfade (the elements fade in place while the card resizes), instead of
/// text and pills flying between layouts. Removing just the *animation* is not
/// enough — matched geometry with no animation still snaps elements across the
/// card mid-swap.
private struct TrayMorphEffect: ViewModifier {
    let id: String
    let namespace: Namespace.ID
    /// Whether this side of the pair defines the geometry the other adopts.
    let isSource: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.matchedGeometryEffect(id: id, in: namespace, isSource: isSource)
        }
    }
}

extension View {
    /// `matchedGeometryEffect` for the tray's row⇄editor morph pairs,
    /// degrading to a plain crossfade under Reduce Motion.
    ///
    /// Exactly one side of each pair must be the source: two views claiming one
    /// id in one namespace is undefined behavior, and it reads as a
    /// snap-then-settle on expansion. The collapsed row is the source because it
    /// is the state the tray sits in.
    func trayMorph(id: String, in namespace: Namespace.ID, isSource: Bool = true) -> some View {
        modifier(TrayMorphEffect(id: id, namespace: namespace, isSource: isSource))
    }
}
