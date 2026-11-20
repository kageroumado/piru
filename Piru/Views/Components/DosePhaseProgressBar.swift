import SwiftUI

/// The live "where is this dose in its arc" readout: a phase-tinted progress bar
/// over a phase label + "{elapsed} in · {remaining} left". Shared by the dose
/// detail hero and the Journal's active-session hero so the two read identically.
///
/// Renders only while the dose is within its modeled window (`start ..< end`);
/// outside that range the caller decides what to show (e.g. "Effects ended").
struct DosePhaseProgressBar: View {
    let state: ActiveSubstanceState
    let now: Date
    var style: Style = .full

    /// How much of the readout to draw.
    enum Style {
        /// The 6 pt bar over the dotted phase word and "{elapsed} in · {remaining} left".
        case full
        /// The phase word over a 3 pt bar, sized to sit at the trailing edge of a
        /// timeline bubble — the same fill and phase color, no clock text.
        case compact
    }

    var body: some View {
        let start = state.doseTimestamp
        let end = start.addingTimeInterval(state.totalMinutes * 60)
        let elapsedMinutes = now.timeIntervalSince(start) / 60
        let fraction = state.totalMinutes > 0 ? min(1, max(0, elapsedMinutes / state.totalMinutes)) : 0
        let phase = DosePhase.at(state, elapsedMinutes: elapsedMinutes)

        switch style {
        case .full:
            fullReadout(phase: phase, fraction: fraction, start: start, end: end)
        case .compact:
            compactReadout(phase: phase, fraction: fraction)
        }
    }

    private func bar(phase: DosePhase, fraction: Double, height: CGFloat) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(phase.color.opacity(Theme.Opacity.tint))
                Capsule()
                    .fill(phase.color)
                    .frame(width: max(0, geo.size.width * fraction))
            }
        }
        .frame(height: height)
    }

    private func compactReadout(phase: DosePhase, fraction: Double) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(phase.name)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(phase.labelColor)
                .lineLimit(1)
            bar(phase: phase, fraction: fraction, height: 3)
                .frame(width: 40)
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }

    private func fullReadout(phase: DosePhase, fraction: Double, start: Date, end: Date) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            bar(phase: phase, fraction: fraction, height: 6)

            HStack(spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    Circle()
                        .fill(phase.color)
                        .frame(width: 6, height: 6)
                    Text(phase.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(phase.labelColor)
                }
                Spacer(minLength: 8)
                Text("\(now.timeIntervalSince(start).durationHM) in \u{00B7} \(end.timeIntervalSince(now).durationHM) left")
                    .captionSecondary()
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }
}
