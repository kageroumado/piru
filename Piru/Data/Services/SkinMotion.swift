#if os(iOS)
    import CoreMotion
#endif
import Observation
import SwiftUI

/// Device tilt for the decoration layer's parallax — the window into the
/// aquarium. Reports how far the phone is tilted from where it is *usually
/// held*: gravity is low-pass filtered into a resting reference so holding
/// the phone at any angle is neutral and only a change moves the scene.
/// Runs only while a decorated skin is showing with decorations on and
/// Reduce Motion off; otherwise the tilt is zero and no updates are requested.
@Observable
@MainActor
final class SkinMotion {
    static let shared = SkinMotion()

    /// -1 … 1 on each axis, 0 at rest. **Not observed**: it changes 30 times
    /// a second, and a view that tracked it would re-render every live
    /// backdrop on every tick on top of its own clock — which is exactly what
    /// hung the phone. The backdrop reads it inside its timeline closure, so
    /// each frame just picks up the latest value.
    @ObservationIgnored private(set) var tilt: CGPoint = .zero

    private var rest: (x: Double, y: Double)?
    private var users = 0
    #if os(iOS)
        private let manager = CMMotionManager()
    #endif

    /// Balanced by ``release()``. A backdrop calls this on appear. A Mac
    /// has no tilt; the scene stays still there.
    ///
    /// The accelerometer alone, at 20 Hz: the parallax only needs gravity's
    /// direction, and the fused `deviceMotion` feed keeps the gyroscope
    /// powered for the whole time a decorated skin is on screen. Gravity is
    /// separated from hand motion by the low-pass in ``ingest(x:y:)``.
    func retain() {
        users += 1
        #if os(iOS)
            guard users == 1, manager.isAccelerometerAvailable, !manager.isAccelerometerActive else { return }
            manager.accelerometerUpdateInterval = 1 / 20
            manager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
                guard let self, let a = data?.acceleration else { return }
                MainActor.assumeIsolated { self.ingest(x: a.x, y: a.y) }
            }
        #endif
    }

    func release() {
        users = max(0, users - 1)
        guard users == 0 else { return }
        #if os(iOS)
            manager.stopAccelerometerUpdates()
        #endif
        rest = nil
        gravity = nil
        tilt = .zero
    }

    /// Raw acceleration smoothed into a gravity estimate (≈0.15 s to settle),
    /// so a footstep or a tap reads as a nudge, not a lurch.
    private var gravity: (x: Double, y: Double)?

    private func ingest(x rawX: Double, y rawY: Double) {
        let g = gravity.map { (x: $0.x + (rawX - $0.x) * 0.3, y: $0.y + (rawY - $0.y) * 0.3) } ?? (x: rawX, y: rawY)
        gravity = g
        let x = g.x, y = g.y
        guard let rest else {
            rest = (x, y)
            return
        }
        // Slow reference (≈3 s to settle), fast signal.
        let ax = rest.x + (x - rest.x) * 0.012
        let ay = rest.y + (y - rest.y) * 0.012
        self.rest = (ax, ay)
        let dx = min(1, max(-1, (x - ax) * 3.2))
        let dy = min(1, max(-1, (y - ay) * 3.2))
        let next = CGPoint(x: tilt.x + (dx - tilt.x) * 0.25, y: tilt.y + (dy - tilt.y) * 0.25)
        if abs(next.x - tilt.x) > 0.002 || abs(next.y - tilt.y) > 0.002 { tilt = next }
    }
}
