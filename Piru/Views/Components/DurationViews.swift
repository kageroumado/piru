import SwiftUI

/// A single legible bar that shows the *shape* of the experience — how the
/// phases divide the timeline proportionally by their typical length. No text
/// legend: the rows beneath carry the same colors and spell each phase out.
struct DurationTimelineBar: View {
    let duration: DurationProfile

    private var segments: [(phase: ExperiencePhase, minutes: Double)] {
        ExperiencePhase.allCases.compactMap { phase in
            guard let range = phase.range(in: duration) else { return nil }
            return (phase, range.midpoint)
        }
    }

    private var totalMinutes: Double {
        segments.reduce(0) { $0 + $1.minutes }
    }

    var body: some View {
        if !segments.isEmpty {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        let fraction = totalMinutes > 0
                            ? segment.minutes / totalMinutes
                            : 1.0 / Double(segments.count)
                        segment.phase.color
                            .frame(width: geo.size.width * fraction)
                    }
                }
            }
            .frame(height: 8)
            .clipShape(Capsule())
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Duration Phase Rows

/// The labeled per-phase rows that accompany a ``DurationTimelineBar``,
/// styled to match ``DoseRangeRows`` so the Dosage and Duration cards read as
/// siblings. Each row flattens into its own list cell (gaining the standard
/// hairline separators); ``total`` is emphasised as the summary line.
struct DurationPhaseRows: View {
    let duration: DurationProfile

    var body: some View {
        ForEach(ExperiencePhase.allCases, id: \.self) { phase in
            if let range = phase.range(in: duration) {
                row(phase.label, value: range.displayString, color: phase.color)
            }
        }
        if let total = duration.total {
            HStack {
                Text("Total")
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Spacer()
                Text(total.displayString)
                    .monospacedDigit()
                    .fontWeight(.semibold)
            }
            .font(.subheadline)
        }
    }

    private func row(_ label: LocalizedStringResource, value: String, color: Color) -> some View {
        HStack {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(label)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .font(.subheadline)
    }
}

// MARK: - Dose Range Rows

/// Composes the redesigned duration card: a legible timeline bar over spacious
/// per-phase rows. Emitted as flattened siblings (no wrapping `VStack`) so the
/// rows pick up the enclosing list's separators, exactly like the Dosage card.
struct DurationInfoView: View {
    let duration: DurationProfile

    var body: some View {
        DurationTimelineBar(duration: duration)
            .padding(.vertical, 6)
        DurationPhaseRows(duration: duration)
    }
}

// MARK: - Route Dosing Card
