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

    /// Phase bands, mirroring the timeline graph's hues so the bar reads
    /// coherently with a curve drawn near it.
    enum Phase {
        case onset
        case comeup
        case peak
        case offset
        case after

        /// Mark colour — the bar fill and the dot. Gated at the 3:1 non-text
        /// floor. Text uses ``labelColor``.
        var color: Color {
            switch self {
            case .onset: .Phase.Onset.accent
            case .comeup: .Phase.Comeup.accent
            case .peak: .Phase.Peak.accent
            case .offset: .Phase.Offset.accent
            case .after: .Phase.Afterglow.accent
            }
        }

        /// Legible text variant. The phase label sits on a capsule filled with
        /// this phase's own colour at 18% — the self-tint pattern — where the
        /// old hex ramp measured 1.73–2.71:1 in light mode. This clears AA
        /// against both that fill and the bare card.
        var labelColor: Color {
            switch self {
            case .onset: .Phase.Onset.text
            case .comeup: .Phase.Comeup.text
            case .peak: .Phase.Peak.text
            case .offset: .Phase.Offset.text
            case .after: .Phase.Afterglow.text
            }
        }

        var name: LocalizedStringResource {
            switch self {
            case .onset: "Onset"
            case .comeup: "Come-up"
            case .peak: "Peak"
            case .offset: "Offset"
            case .after: "Afterglow"
            }
        }
    }

    static func phase(_ state: ActiveSubstanceState, elapsedMinutes: Double) -> Phase {
        if elapsedMinutes <= state.onsetEndMinutes { .onset } else if elapsedMinutes <= state.comeupEndMinutes { .comeup } else if elapsedMinutes <= state.peakEndMinutes { .peak } else if elapsedMinutes <= state.offsetEndMinutes { .offset } else { .after }
    }

    var body: some View {
        let start = state.doseTimestamp
        let end = start.addingTimeInterval(state.totalMinutes * 60)
        let elapsedMinutes = now.timeIntervalSince(start) / 60
        let fraction = state.totalMinutes > 0 ? min(1, max(0, elapsedMinutes / state.totalMinutes)) : 0
        let phase = Self.phase(state, elapsedMinutes: elapsedMinutes)

        VStack(alignment: .leading, spacing: 7) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(phase.color.opacity(0.18))
                    Capsule()
                        .fill(phase.color)
                        .frame(width: max(0, geo.size.width * fraction))
                }
            }
            .frame(height: 6)

            HStack(spacing: 6) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(phase.color)
                        .frame(width: 6, height: 6)
                    Text(phase.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(phase.labelColor)
                }
                Spacer(minLength: 8)
                Text("\(now.timeIntervalSince(start).durationHM) in \u{00B7} \(end.timeIntervalSince(now).durationHM) left")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }
}
