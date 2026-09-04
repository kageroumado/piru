import SwiftUI

// MARK: - Duration Phase Rows

/// The labeled per-phase duration rows. Each row flattens into its own list
/// cell (gaining the standard hairline separators); ``total`` is emphasized as
/// the summary line.
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
            HStack(spacing: Spacing.sm) {
                LegendDot(color: color)
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

// MARK: - Route Dosing Card
