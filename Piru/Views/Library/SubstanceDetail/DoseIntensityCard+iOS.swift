import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// The pan that drives the glass selector.
///
/// Attached to the small grab handle riding the selected band, so it only ever
/// receives touches that land on the handle — the rest of the card scrolls. It
/// fires `onGrab(true)` on touch-down for immediate lift feedback (a pan
/// otherwise waits for movement, and the grab should read the instant the finger
/// lands), and once dragging, the recognizer tracks the finger anywhere on the
/// arc — including the near-vertical ends that broke direction-based schemes.
final class GrabPanRecognizer: UIPanGestureRecognizer {
    var onGrabChange: (Bool) -> Void = { _ in }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        onGrabChange(true)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        onGrabChange(false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        onGrabChange(false)
    }
}

struct ArcPan: UIGestureRecognizerRepresentable {
    var coordSpace: String
    var onGrab: (Bool) -> Void
    var onMove: (CGPoint) -> Void

    func makeCoordinator(converter _: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> GrabPanRecognizer {
        let recognizer = GrabPanRecognizer()
        recognizer.onGrabChange = onGrab
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: GrabPanRecognizer, context _: Context) {
        recognizer.onGrabChange = onGrab
    }

    func handleUIGestureRecognizerAction(_ recognizer: GrabPanRecognizer, context: Context) {
        // The handle is positioned away from the gauge origin, so read the touch
        // in the gauge's named space rather than the handle's local space.
        switch recognizer.state {
        case .began, .changed: onMove(context.converter.location(in: .named(coordSpace)))
        default: break
        }
    }

    /// Makes the enclosing scroll view wait for this recognizer to fail before it
    /// scrolls, so an on-handle drag wins even when it moves vertically (the arc's
    /// ends). Touches off the handle never reach this recognizer, so the rest of
    /// the card scrolls untouched.
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(
            _: UIGestureRecognizer,
            shouldBeRequiredToFailBy other: UIGestureRecognizer,
        ) -> Bool {
            other is UIPanGestureRecognizer && other.view is UIScrollView
        }
    }
}
