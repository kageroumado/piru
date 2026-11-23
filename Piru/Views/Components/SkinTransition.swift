import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif

/// The change from one skin to the next: the screen as it was stays up for a
/// moment as a picture, and the new skin opens through it in a circle that
/// grows from the last place the screen was touched.
///
/// A skin change re-renders every skinned view at once, in one frame. Under
/// the picture that frame is never seen arriving, and the reveal runs in the
/// render server, so it stays smooth while the app is busy drawing.
@MainActor
enum SkinTransition {
    /// Where the screen was last touched, in window coordinates. The root's
    /// touch observer keeps it current.
    static var lastTouch: CGPoint?

    /// Runs `change`, which puts another skin on the app, and reveals the
    /// result. With no window to picture, the change simply happens.
    static func perform(_ change: () -> Void) {
        #if canImport(UIKit)
            // A change that arrives mid-reveal cuts straight over: a picture
            // taken now would hold the reveal's first frame, the old skin whole.
            if let current {
                finish(current)
                change()
                return
            }
            guard !isCapturing, let window = keyWindow,
                  let picture = window.snapshotView(afterScreenUpdates: false)
            else {
                change()
                return
            }
            picture.frame = window.bounds
            picture.isUserInteractionEnabled = false
            window.addSubview(picture)
            current = picture
            change()
            if UIAccessibility.isReduceMotionEnabled {
                fade(picture)
            } else {
                open(picture, from: lastTouch ?? CGPoint(x: window.bounds.midX, y: window.bounds.midY))
            }
        #else
            change()
        #endif
    }

    #if canImport(UIKit)
        private static var current: UIView?

        /// A screenshot taken mid-reveal would show two skins at once.
        private static var isCapturing: Bool {
            #if DEBUG
                ScreenshotTour.isRequested
            #else
                false
            #endif
        }

        private enum Timing {
            static let reveal: CFTimeInterval = 0.55
            static let fade: TimeInterval = 0.25
            /// The circle the reveal starts from: a point would open with a jump.
            static let startRadius: CGFloat = 12
        }

        private static var keyWindow: UIWindow? {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow)
        }

        /// Cuts a growing circle out of the picture, centered on `origin`, until
        /// the circle covers the window.
        private static func open(_ picture: UIView, from origin: CGPoint) {
            let bounds = picture.bounds
            let reach = [
                CGPoint(x: bounds.minX, y: bounds.minY), CGPoint(x: bounds.maxX, y: bounds.minY),
                CGPoint(x: bounds.minX, y: bounds.maxY), CGPoint(x: bounds.maxX, y: bounds.maxY),
            ].map { hypot($0.x - origin.x, $0.y - origin.y) }.max() ?? bounds.height

            func hole(radius: CGFloat) -> CGPath {
                let path = UIBezierPath(rect: bounds)
                path.append(UIBezierPath(ovalIn: CGRect(x: origin.x - radius, y: origin.y - radius, width: radius * 2, height: radius * 2)))
                return path.cgPath
            }

            let mask = CAShapeLayer()
            mask.fillRule = .evenOdd
            mask.path = hole(radius: reach)
            picture.layer.mask = mask

            let reveal = CABasicAnimation(keyPath: "path")
            reveal.fromValue = hole(radius: Timing.startRadius)
            reveal.toValue = mask.path
            reveal.duration = Timing.reveal
            reveal.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            CATransaction.begin()
            CATransaction.setCompletionBlock { finish(picture) }
            mask.add(reveal, forKey: "reveal")
            CATransaction.commit()
        }

        private static func fade(_ picture: UIView) {
            UIView.animate(withDuration: Timing.fade) {
                picture.alpha = 0
            } completion: { _ in
                finish(picture)
            }
        }

        private static func finish(_ picture: UIView) {
            picture.removeFromSuperview()
            if current === picture { current = nil }
        }
    #endif
}
