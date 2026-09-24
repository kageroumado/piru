import SwiftUI

/// Advances a counter whenever the timeline's "now" has moved far enough to
/// redraw: on returning to the foreground after at least
/// ``foregroundThreshold`` away, and every ``interval`` while the scene stays
/// active. The strip lays out "now" — the Now line, the axis's live edge, each
/// bubble's phase — when it is built, so the strip's rebuild key carries this
/// counter; without it, a strip reopened hours later still shows the moment it
/// was built.
///
/// A pinned `-piruNow` clock never advances, so the tick holds still for it.
struct TimelineClockTick: ViewModifier {
    @Binding var tick: Int
    @Environment(\.scenePhase) private var scenePhase
    @State private var lastTick = Date.now

    private static let interval: Duration = .seconds(5 * 60)
    private static let foregroundThreshold: TimeInterval = 60

    func body(content: Content) -> some View {
        content.task(id: scenePhase) {
            guard scenePhase == .active, DebugClock.override == nil else { return }
            if Date.now.timeIntervalSince(lastTick) >= Self.foregroundThreshold {
                advance()
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.interval)
                guard !Task.isCancelled else { return }
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
