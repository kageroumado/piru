import SwiftUI

/// The session's interaction warnings, shown in full (they used to hide behind a
/// collapsed disclosure at the bottom of the screen — folding the last section
/// saved no space, it just hid the warning), plus the heart-rate summary when
/// vitals are on. Rows carry no leading icon and use the dose/cumulative rows'
/// type scale so the whole screen reads as one family; severity is conveyed by
/// the tinted "Unsafe:"/"Caution:" heading.
struct SessionSafetySection: View {
    let interactions: [InteractionResult]
    let hrSummary: HRSummary?

    var body: some View {
        if !interactions.isEmpty || hrSummary != nil {
            Section {
                ForEach(interactions.enumerated(), id: \.offset) { _, warning in
                    interactionRow(warning)
                }
                if let hrSummary {
                    hrSummaryRow(hrSummary)
                }
            }
        }
    }

    private func interactionRow(_ warning: InteractionResult) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text("\(warning.severity.label): \(warning.substanceA) + \(warning.substanceB)")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(warning.severity.labelColor)
                if warning.source != .classRule {
                    Text(warning.source.label)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(warning.severity.color.opacity(0.15), in: Capsule())
                        .foregroundStyle(warning.severity.labelColor)
                }
            }
            Text(warning.description)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func hrSummaryRow(_ summary: HRSummary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text("Heart rate")
                    .font(.body.weight(.semibold))
                Text("avg \(summary.average) · peak \(summary.peak) bpm")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondaryLabel)
            }
            if let resting = summary.resting {
                Text(
                    summary.average > resting + 3
                        ? "Elevated vs your resting \(resting) bpm"
                        : "In line with your resting \(resting) bpm",
                )
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
