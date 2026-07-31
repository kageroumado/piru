import SwiftUI

/// The session's interaction warnings, shown in full (they used to hide behind a
/// collapsed disclosure at the bottom of the screen), plus the heart-rate summary
/// when vitals are on. Rows echo the dose/cumulative rows: a leading glyph (the
/// severity triangle in place of the color dot) + the involved substances in
/// normal text, with the severity level as a tinted chip on the right — the only
/// colored element. Warnings that share the exact same explanation are grouped
/// so a stimulant-stack session doesn't repeat one sentence five times.
struct SessionSafetySection: View {
    let interactions: [InteractionResult]
    let hrSummary: HRSummary?

    var body: some View {
        if !interactions.isEmpty || hrSummary != nil {
            Section {
                ForEach(groupedInteractions) { group in
                    interactionRow(group)
                }
                if let hrSummary {
                    hrSummaryRow(hrSummary)
                }
            } header: {
                // The section doubles as the heart-rate summary's home when
                // vitals are on; "Interactions" only fits when there are some.
                if !interactions.isEmpty {
                    Text("Interactions")
                }
            }
        }
    }

    // MARK: - Interaction rows

    private func interactionRow(_ group: InteractionGroup) -> some View {
        // Mirrors a dose row: the severity glyph takes the color-dot's slot
        // (same 9pt size + 8pt gap, so the pairs line up with the dose/cumulative
        // titles), and the description sits flush with the row's leading edge —
        // where a dose row keeps its time/meta line — not indented under the pair.
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: group.severity == .dangerous ? "exclamationmark.triangle.fill" : "exclamationmark.triangle")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(group.severity.labelColor)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(group.pairs.enumerated()), id: \.offset) { index, pair in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(pair)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            if index == 0 {
                                Spacer(minLength: 8)
                                Text(String(localized: group.severity.label).lowercased())
                                    .capsuleChip(text: group.severity.labelColor, fill: group.severity.color)
                            }
                        }
                    }
                }
            }

            Text(group.description)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func hrSummaryRow(_ summary: HRSummary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "heart.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(VitalsPalette.heart)
                .accessibilityHidden(true)
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
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Grouping

    private struct InteractionGroup: Identifiable {
        let id: Int
        let severity: InteractionSeverity
        let description: String
        let pairs: [String]
    }

    /// Collapse warnings that share an identical explanation into one row that
    /// lists every involved pair. Ordered most-severe first; within a severity,
    /// first-seen order is preserved.
    private var groupedInteractions: [InteractionGroup] {
        var order: [String] = []
        var pairs: [String: [String]] = [:]
        var severities: [String: InteractionSeverity] = [:]
        for warning in interactions {
            let key = warning.description
            if pairs[key] == nil {
                order.append(key)
                severities[key] = warning.severity
            }
            pairs[key, default: []].append("\(warning.substanceA) + \(warning.substanceB)")
            // A shared explanation keeps its strongest severity.
            if let existing = severities[key], warning.severity.rawValue > existing.rawValue {
                severities[key] = warning.severity
            }
        }
        return order.enumerated()
            .map { index, key in
                InteractionGroup(id: index, severity: severities[key] ?? .caution, description: key, pairs: pairs[key] ?? [])
            }
            .sorted { $0.severity.rawValue > $1.severity.rawValue }
    }
}
