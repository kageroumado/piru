import OSLog
import SwiftUI
import UIKit

// MARK: - Dock geometry probe

/// Measures where the dock's search bar actually lands relative to the sheet's
/// glass platter, and logs the two whenever they disagree.
///
/// The "search bar shears out of its floating platter" reports (TestFlight
/// 2.2 (30) through 2.2 (33)) all show the same thing: the platter is drawn in
/// the right place, the system grabber sits on its top edge, and the dock's
/// content column is ~38pt higher than it should be — clipped flat by the
/// platter at the smallest detent, merely overlapping the grabber at the taller
/// ones. Screenshots can't say *why*, because the two quantities that matter
/// are invisible: the presented view's safe-area insets, and the frame of the
/// platter, which for a `presentationBackground(.clear)` sheet is a companion
/// `CALayer` beside the presented view's layer rather than part of it.
///
/// This leaf reads both. Mounted as the search field's background, its own
/// frame *is* the field's frame, so the comparison is direct.
///
/// Cost: one responder/superview walk per layout pass of a zero-size view, and
/// a log line only when the rounded numbers change. Nothing here mutates the
/// hierarchy — it is a read-only instrument.
struct DockGeometryProbe: View {
    /// The dock's memoized presentation handle, for the selected detent's
    /// identifier — the label that makes a log line readable.
    let host: SheetHostBox

    /// A `GeometryReader` is what makes this fire at all: the search bar's
    /// *size* is identical in every detent, so `layoutSubviews` on a plain
    /// hosted view runs once and never again — only the bar's **position**
    /// moves. The reader re-evaluates on either, and re-evaluates inside this
    /// background subtree without touching the dock's own body.
    var body: some View {
        GeometryReader { proxy in
            ProbeRepresentable(host: host, barFrame: proxy.frame(in: .global))
        }
    }
}

private struct ProbeRepresentable: UIViewRepresentable {
    let host: SheetHostBox
    let barFrame: CGRect

    func makeUIView(context _: Context) -> DockGeometryProbe.ProbeView {
        DockGeometryProbe.ProbeView(host: host)
    }

    /// Requests a layout pass rather than measuring here: at `updateUIView`
    /// time UIKit has not yet positioned the bar for this update, so reading
    /// its frame now returns the *previous* position while the presented view
    /// already reports the new one — a phantom shear of exactly the height
    /// delta. Measuring from `layoutSubviews` puts both reads in the same pass.
    func updateUIView(_ view: DockGeometryProbe.ProbeView, context _: Context) {
        view.setNeedsLayout()
    }
}

extension DockGeometryProbe {
    final class ProbeView: UIView {
        private static let log = Logger(subsystem: "dev.yumeji.piru", category: "dock-geometry")

        private let host: SheetHostBox
        /// Detent name + rounded overhang of the last line emitted.
        ///
        /// Deliberately *not* the frames: a detent ramp re-lays the sheet out
        /// every display frame, so keying on position would log a hundred lines
        /// per drag. Overhang is an invariant — it should not move at all as the
        /// sheet resizes — so keying on it collapses a whole ramp to one line
        /// and still catches the instant it breaks.
        private var lastKey: String?

        init(host: SheetHostBox) {
            self.host = host
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            nil
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            report()
        }

        // MARK: Measurement

        /// Called both from layout and from the SwiftUI side on every geometry
        /// change. The bar's frame is read back out of UIKit rather than taken
        /// from the `GeometryReader`, so it carries the same transform the
        /// presented view does — the pill treatment scales the whole sheet
        /// ~0.89, and comparing a scaled rect against an unscaled one would
        /// invent a shear that isn't there.
        func report() {
            guard let window, bounds.height > 0,
                  let presented = presentedView()
            else { return }
            let bar = convert(bounds, to: window)
            let presentedFrame = presented.convert(presented.bounds, to: window)
            let platter = platterFrame(in: window)

            // The number the bug is about: how far the field's top sits below
            // the top of the sheet it lives in. Healthy is the dock's 16pt top
            // padding times whatever the pill treatment is scaling by — 14.2 at
            // peek on a 17 Pro Max, 16.0 unscaled at large. Negative means the
            // field has climbed out of its platter, the reported defect.
            let overhang = bar.minY - presentedFrame.minY

            // **Measured against the platter, which is the surface the report is
            // actually about.** The presented view and the platter are not the
            // same rect: with `presentationBackground(.clear)` the platter is a
            // sibling `CALayer`, and UIKit compresses a too-tall sheet by putting
            // a *scale transform* on it (see `QuickLogDock`'s own notes, and the
            // lldb-verified residual-transform corruption). Both rects here are
            // read post-transform, so if the platter and the presented view get
            // different transforms the field visibly leaves the platter while
            // `overhang` stays perfectly healthy. That is the blind spot that let
            // three rounds of reports produce no log line: the platter frame was
            // computed and printed but never compared.
            let platterOverhang = platter.map { bar.minY - $0.minY }
            let sheared = overhang < 0 || (platterOverhang.map { $0 < 0 } ?? false)

            let detent = detentLabel()
            // The platter's own origin joins the key. Keyed on `detent|overhang`
            // alone, a platter that moved while the overhang held constant — the
            // exact signature of the transform mechanism above — emitted no line
            // at all.
            let key = """
            \(detent)|\(String(format: "%.1f", overhang))\
            |\(String(format: "%.1f", platterOverhang ?? .nan))\
            |\(String(format: "%.1f", platter?.minY ?? .nan))
            """
            guard key != lastKey else { return }
            lastKey = key

            // Everything below only runs when the invariant or the detent has
            // actually moved — the layer walk and string building stay off the
            // per-frame path of a resize.
            let insets = presented.safeAreaInsets
            let line = """
            detent=\(detent) bar=\(rect(bar)) presented=\(rect(presentedFrame)) \
            platter=\(platter.map(rect) ?? "?") \
            safe=(t\(round(insets.top)) b\(round(insets.bottom))) \
            klg=\(round(window.keyboardLayoutGuide.layoutFrame.height)) \
            overhang=\(String(format: "%.1f", overhang)) \
            platterOverhang=\(platterOverhang.map { String(format: "%.1f", $0) } ?? "?")
            """

            // A sheared dock is the defect itself, so it is logged at a level
            // that persists without a live Console attached — the only way to
            // read it back off a TestFlight device. Healthy transitions stay
            // debug-level chatter for a streaming session.
            if sheared {
                Self.log.error("SHEARED \(line, privacy: .public)")
            } else {
                Self.log.debug("\(line, privacy: .public)")
            }
        }

        /// The sheet's presented view — the ancestor owned by the view
        /// controller the dock's content is hosted in.
        private func presentedView() -> UIView? {
            host.viewController?.view
        }

        /// Frame of the system's glass platter, in window space.
        ///
        /// With `presentationBackground(.clear)` the platter is not in the view
        /// hierarchy at all: it is a sibling `CALayer` of the presented view's
        /// layer, inside the presentation host's multi-layer container (found by
        /// lldb bisection when the platter first had to be hidden; see the
        /// retired `SheetPlatterHider`). So the walk is: up the superviews to the
        /// drop-shadow ancestor UIKit wraps the presentation in, then across its
        /// layer's siblings, taking the largest one that is not our own branch.
        private func platterFrame(in window: UIWindow) -> CGRect? {
            var ancestor: UIView? = superview
            var shadowHost: UIView?
            while let view = ancestor {
                if String(describing: type(of: view)).contains("DropShadow") {
                    shadowHost = view
                    break
                }
                ancestor = view.superview
            }
            guard let shadowHost,
                  let siblings = shadowHost.layer.superlayer?.sublayers
            else { return nil }
            let candidates = siblings
                .filter { $0 !== shadowHost.layer && $0.frame.height > 0 }
                .map { layer -> CGRect in
                    guard let container = shadowHost.layer.superlayer else { return layer.frame }
                    return window.layer.convert(layer.frame, from: container)
                }
            return candidates.max { $0.height < $1.height }
        }

        private func detentLabel() -> String {
            host.sheetController?.selectedDetentIdentifier?.rawValue ?? "?"
        }

        private func rect(_ frame: CGRect) -> String {
            String(format: "(%.0f,%.1f,%.0f,%.1f)", frame.minX, frame.minY, frame.width, frame.height)
        }

        private func round(_ value: CGFloat) -> String {
            String(format: "%.1f", value)
        }
    }
}
