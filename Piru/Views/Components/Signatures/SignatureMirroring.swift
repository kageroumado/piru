import SwiftUI

extension View {
    /// Pin a hand-drawn signature plot to LTR so the view mirrors itself.
    ///
    /// The signature plots (efficacy axis, balance arc, ternary plot) place
    /// geometry with `Path`s and `.offset`, which SwiftUI's automatic RTL flip
    /// does not treat alike — offset-placed marks flip, path geometry does
    /// not, and a label that drifts off its mark is worse than not mirroring
    /// at all (verified on device in an RTL locale). So each plot reads
    /// `@Environment(\.layoutDirection)` for its own mirroring math and pins
    /// the drawn subtree to LTR with this modifier, keeping arcs, ticks, and
    /// labels flipping together as one decision.
    func signaturePlotPinnedToLTR() -> some View {
        environment(\.layoutDirection, .leftToRight)
    }
}
