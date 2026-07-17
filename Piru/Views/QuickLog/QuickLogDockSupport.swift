import SwiftUI
import UIKit

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
    var generation = 0
    /// Logical height the in-flight ramp is heading to — marks "a ramp owns
    /// the sheet right now" and anchors chained retargets.
    var rampLogicalTarget: CGFloat?
    /// Numeric value of the *resting* selection (`nil` at `.medium`/`.large`),
    /// maintained by the dock's `detentChanged` — which sees every settle,
    /// drag or programmatic — so a move can anchor its frame animation even
    /// after ``compactValue`` has been re-minted for the new target.
    var restingLogicalHeight: CGFloat? = QuickLogDockMetrics.peekHeight

    /// Memoized handle to the UIKit view controller presenting the dock —
    /// resolved once by ``SheetHostProbe`` when the content lands in a window.
    let host = SheetHostBox()
    /// Display-link driver for the frame-level sheet resize.
    let frameAnimator = DisplayLinkAnimator()
    /// The mutable custom detent driving the ramp.
    let rampDetent = MutableSheetDetent()
}

// MARK: - Display-link animator

/// Eases a scalar from one value to another with a callback per display
/// frame — the driver for the dock's frame-level sheet resize. Vsync-locked
/// (a `Task.sleep` loop adds scheduler wake latency and visibly stutters)
/// and eased against `targetTimestamp`, i.e. computed for the frame being
/// *presented*.
@MainActor
final class DisplayLinkAnimator: NSObject {
    private var displayLink: CADisplayLink?
    private var startTimestamp: CFTimeInterval?
    private var start: CGFloat = 0
    private var end: CGFloat = 0
    private var duration: Double = 0.32
    private var tick: ((CGFloat) -> Void)?
    private var completion: (() -> Void)?

    func run(
        from start: CGFloat,
        to end: CGFloat,
        duration: Double = 0.32,
        tick: @escaping (CGFloat) -> Void,
        completion: @escaping () -> Void,
    ) {
        cancel()
        self.start = start
        self.end = end
        self.duration = duration
        self.tick = tick
        self.completion = completion
        startTimestamp = nil
        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func cancel() {
        displayLink?.invalidate()
        displayLink = nil
        tick = nil
        completion = nil
    }

    @objc
    private func step(_ link: CADisplayLink) {
        // First callback anchors the timeline so the animation never skips
        // ahead by however late the link started.
        let reference = startTimestamp ?? link.timestamp
        if startTimestamp == nil { startTimestamp = reference }
        let progress = min(1, (link.targetTimestamp - reference) / duration)
        let eased = 1 - pow(1 - progress, 3)
        tick?(start + (end - start) * eased)
        if progress >= 1 {
            let completion = completion
            cancel()
            completion?()
        }
    }
}

// MARK: - Mutable ramp detent

/// A UIKit custom detent whose resolved height reads a mutable value — the
/// supported mechanism for continuously resizing a sheet (the pattern Apple
/// documents for keyboard-tracking sheets): update `height`, call
/// `invalidateDetents()`, and the controller re-resolves and lays out
/// through its own full resize path.
@MainActor
final class MutableSheetDetent {
    static let identifier = UISheetPresentationController.Detent.Identifier("dev.yumeji.piru.dock-ramp")

    var height: CGFloat = 0

    /// The UIKit detent. Lazy so the resolver can weakly capture `self`; the
    /// resolver runs on the main thread as part of sheet layout.
    private(set) lazy var detent: UISheetPresentationController.Detent = .custom(identifier: Self.identifier) { [weak self] context in
        MainActor.assumeIsolated {
            guard let self else { return context.maximumDetentValue }
            return min(self.height, context.maximumDetentValue)
        }
    }
}

// MARK: - Sheet host access

/// Memoized handle to the UIKit view controller presenting the dock sheet.
///
/// Resolved once when the dock content first lands in a window — the
/// controller never changes for the presented sheet's lifetime — so the dock
/// can drive `UISheetPresentationController.animateChanges` (which SwiftUI
/// doesn't expose) without re-walking the responder chain per move. Weak:
/// the box must not keep a dismissed sheet's controller alive.
@MainActor
final class SheetHostBox {
    weak var viewController: UIViewController?

    /// The dock sheet's presentation controller — `sheetPresentationController`
    /// resolves through the nearest presented ancestor, which for a view
    /// inside the dock's content is the dock sheet itself.
    var sheetController: UISheetPresentationController? {
        viewController?.sheetPresentationController
    }
}

/// Zero-size leaf that captures the dock's presenting view controller into a
/// ``SheetHostBox`` via the responder chain, once, on first window entry.
struct SheetHostProbe: UIViewRepresentable {
    let box: SheetHostBox

    func makeUIView(context _: Context) -> ProbeView {
        ProbeView(box: box)
    }
    func updateUIView(_: ProbeView, context _: Context) {}

    final class ProbeView: UIView {
        private let box: SheetHostBox

        init(box: SheetHostBox) {
            self.box = box
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            nil
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil, box.viewController == nil else { return }
            var responder: UIResponder? = next
            while let current = responder {
                if let viewController = current as? UIViewController {
                    box.viewController = viewController
                    return
                }
                responder = current.next
            }
        }
    }
}

/// Minimal context for resolving `.height` detents' values when matching the
/// UIKit detents SwiftUI minted (their identifiers are opaque; their resolved
/// heights are exact).
final class SheetDetentResolutionContext: NSObject, UISheetPresentationControllerDetentResolutionContext {
    let containerTraitCollection: UITraitCollection
    let maximumDetentValue: CGFloat

    init(containerTraitCollection: UITraitCollection, maximumDetentValue: CGFloat) {
        self.containerTraitCollection = containerTraitCollection
        self.maximumDetentValue = maximumDetentValue
    }
}
