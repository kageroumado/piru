import SwiftUI

// MARK: - Detent bookkeeping

/// Mutable registers for the dock's detent state machine — the fit-to-content
/// detent's minted value, the in-flight ramp target, the resting height, the
/// supersession generation, and the UIKit handles the transitions drive.
///
/// A plain class, deliberately **not** `@Observable` and not spread across
/// view `@State`: nothing in the dock's `body` renders from these, but as
/// `@State` every write invalidated the whole dock view — and one programmatic
/// detent move writes several of them (generation, compact value, ramp target,
/// resting height), so each transition re-ran the dock body a handful of times
/// for bookkeeping the UI never shows. Boxed, the writes are free; handlers
/// read the current values directly.
@MainActor
final class DockDetentBookkeeping {
    /// The current fit-to-content compact detent, kept alongside the view's
    /// detent set so detent-change handlers can recognize it by value.
    var compactDetent: PresentationDetent?
    /// The height ``compactDetent`` was minted at — refreshes are skipped for
    /// sub-6pt drift so transient re-measures (the commit bar animating a
    /// panel open, geometry settling) don't re-mint the detent mid-gesture.
    var compactValue: CGFloat = 0
    /// Invalidates deferred detent work (the UIKit selection hand-off and the
    /// member prune in `applyDetents`) when a newer change supersedes it.
    /// Settle callbacks are never invalidated with it — they wait in
    /// ``pendingSettled`` for whichever move lands.
    var generation = 0
    /// Work queued behind the sheet's next settle, across supersession.
    var pendingSettled = PendingSettleQueue()
    /// Logical height the in-flight ramp is heading to — marks "a ramp owns
    /// the sheet right now" and anchors chained retargets.
    var rampLogicalTarget: CGFloat?
    /// Numeric value of the *resting* selection (`nil` at `.medium`/`.large`),
    /// maintained by the dock's `detentChanged` — which sees every settle,
    /// drag or programmatic — so a move can anchor its frame animation even
    /// after ``compactValue`` has been re-minted for the new target.
    var restingLogicalHeight: CGFloat? = QuickLogDockMetrics.peekHeight

    #if canImport(UIKit)
        /// Memoized handle to the UIKit view controller presenting the dock —
        /// resolved once by ``SheetHostProbe`` when the content lands in a window.
        let host = SheetHostBox()
        /// Display-link driver for the frame-level sheet resize.
        let frameAnimator = DisplayLinkAnimator()
        /// The mutable custom detent driving the ramp.
        let rampDetent = MutableSheetDetent()
    #endif
}

/// Callbacks waiting for the sheet's next settle. A detent move can be
/// superseded before it lands — a newer `applyDetents` bumps the generation
/// and the older move's completion is dropped — so a callback is queued here
/// rather than bound to the move that registered it, and the move that
/// finally lands drains the whole queue in registration order. Work sequenced
/// behind a resize (revealing a freshly staged row once the sheet has grown
/// for it) therefore survives a second refresh landing mid-move, such as the
/// commit bar growing for an interaction warning.
struct PendingSettleQueue {
    private var callbacks: [() -> Void] = []

    var isEmpty: Bool {
        callbacks.isEmpty
    }

    mutating func enqueue(_ callback: (() -> Void)?) {
        guard let callback else { return }
        callbacks.append(callback)
    }

    /// Removes every queued callback and returns them in registration order.
    mutating func drain() -> [() -> Void] {
        defer { callbacks.removeAll() }
        return callbacks
    }
}

// iOS UIKit types (DisplayLinkAnimator, MutableSheetDetent, SheetHostBox,
// SheetHostProbe, SheetDetentResolutionContext) are in QuickLogDockSupport+iOS.swift.
