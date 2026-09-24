import SwiftUI

/// Advances a counter once every ``interval`` of wall-clock time, so the
/// timeline's "now" follows the clock. The strip lays out "now" — the Now line,
/// the axis's live edge, each bubble's phase — when it is built, so the strip's
/// rebuild key carries this counter; without it, a strip reopened hours later
/// still shows the moment it was built.
///
/// The cadence is measured from the last tick, never from when the view
/// appeared: `.task` restarts on every reappearance — a tab switch, a pop back —
/// and each tick is a full strip rebuild, so a return that lands inside the
/// interval waits out the remainder rather than ticking. A foreground after a long absence
/// ticks at once, because the interval has already passed.
///
/// A pinned `-piruNow` clock never advances, so the tick holds still for it.
struct TimelineClockTick: ViewModifier {
    @Binding var tick: Int
    @Environment(\.scenePhase) private var scenePhase
    @State private var lastTick = Date.now

    private static let interval: TimeInterval = 5 * 60

    func body(content: Content) -> some View {
        content.task(id: scenePhase) {
            guard scenePhase == .active, DebugClock.override == nil else { return }
            while !Task.isCancelled {
                let remaining = Self.interval - Date.now.timeIntervalSince(lastTick)
                if remaining > 0 {
                    try? await Task.sleep(for: .seconds(remaining))
                    guard !Task.isCancelled else { return }
                }
                advance()
            }
        }
    }

    private func advance() {
        lastTick = .now
        tick += 1
    }
}

extension View {
    /// Bumps `tick` whenever the timeline's baked-in "now" goes stale; see
    /// ``TimelineClockTick``.
    func timelineClockTick(_ tick: Binding<Int>) -> some View {
        modifier(TimelineClockTick(tick: tick))
    }
}
