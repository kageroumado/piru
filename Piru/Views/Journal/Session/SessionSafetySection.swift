import SwiftUI

/// The session's interaction warnings plus the heart-rate summary when vitals
/// are on.
///
/// Findings that have earned an interruption are inline; the quiet ones fold
/// behind a count — but only once there are enough of them for folding to buy
/// anything. See ``partitionedForReview``. This is where the quiet ones live:
/// the QuickLog dock dropped interactions entirely, because a dock is for
/// recording what has already been taken and a warning there arrives after the
/// decision it would inform. Rows echo the dose/cumulative rows: a leading glyph (the
/// severity triangle in place of the color dot) + the involved substances in
/// normal text, with the severity level as a tinted chip on the right — the only
/// colored element. Warnings produced by the same rule are grouped so a
/// stimulant-stack session doesn't repeat one sentence five times.
struct SessionSafetySection: View {
    let interactions: [InteractionResult]
    /// Measured exposure changes between two things logged here. Rendered under
    /// the class warnings and visually apart from them: these carry a number and
    /// a citation and no severity, and dressing them in the severity ladder
    /// would manufacture the one thing a reader leans on hardest.
    var pkFindings: [PKInteractionFinding] = []
    let hrSummary: HRSummary?

    @State private var showsQuiet = false

    private var split: (shown: [InteractionResult], folded: [InteractionResult]) {
        interactions.partitionedForReview()
    }

    private var hasContent: Bool {
        !interactions.isEmpty || !pkFindings.isEmpty || hrSummary != nil
    }

    var body: some View {
        if hasContent {
            Section {
                let partition = split
                ForEach(grouped(partition.shown)) { group in
                    interactionRow(group)
                }
                if !partition.folded.isEmpty {
                    DisclosureGroup(isExpanded: $showsQuiet) {
                        ForEach(grouped(partition.folded)) { group in
                            interactionRow(group)
                        }
                    } label: {
                        Text("^[\(partition.folded.count) more combination](inflect: true)")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                }
                ForEach(pkFindings) { finding in
                    PKInteractionRow(hit: finding.hit)
                }
                if let hrSummary {
                    hrSummaryRow(hrSummary)
                }
            } header: {
                if !interactions.isEmpty || !pkFindings.isEmpty {
                    Text("Interactions")
                }
            }
        }
    }

    // MARK: - Interaction rows

    private func interactionRow(_ group: InteractionGroup) -> some View {
        NavigationLink {
            InteractionTimelineView(
                substanceA: group.navigationSubstanceA,
                substanceB: group.navigationSubstanceB,
                severity: group.severity,
                mechanism: group.description,
            )
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(group.pairs.enumerated()), id: \.offset) { index, pair in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(pair)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if index == 0 {
                            Spacer(minLength: 8)
                            Image(systemName: group.severity == .dangerous
                                ? group.mechanism.filledIconName : group.mechanism.iconName)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(group.severity.labelColor)
                                .accessibilityHidden(true)
                            Text(String(localized: group.severity.label).lowercased())
                                .capsuleChip(text: group.severity.labelColor, fill: group.severity.color)
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
        .buttonStyle(.plain)
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
                // Both figures above describe the session as it happened, workout included —
                // so say when a workout is in them, or the peak reads as something a dose did.
                if summary.workoutMinutes > 0 {
                    Text("Includes \(summary.workoutMinutes) min of workout — the dose rows leave it out")
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
        let id: String
        let severity: InteractionSeverity
        let mechanism: InteractionMechanism
        let description: String
        let pairs: [String]
        let substanceAs: [String]
        let substanceBs: [String]

        var navigationSubstanceA: String {
            substanceAs.first ?? ""
        }

        var navigationSubstanceB: String {
            substanceBs.first ?? ""
        }
    }

    /// Collapse warnings produced by the same rule into one row that lists
    /// every involved pair. Ordered most-severe first; within a severity,
    /// first-seen order is preserved.
    ///
    /// Keyed on the rule's class pair, not its prose: several distinct rules
    /// share boilerplate ("Additive CNS depression — increased sedation and
    /// impairment."), and folding those together asserts one cause where there
    /// are two. A hand-made result carries no rule key and falls back to its
    /// text, which for those is the only identity there is.
    private func grouped(_ warnings: [InteractionResult]) -> [InteractionGroup] {
        var order: [String] = []
        var pairs: [String: [String]] = [:]
        var substanceAs: [String: [String]] = [:]
        var substanceBs: [String: [String]] = [:]
        var severities: [String: InteractionSeverity] = [:]
        var mechanisms: [String: InteractionMechanism] = [:]
        var descriptions: [String: String] = [:]
        for warning in warnings {
            let key = warning.ruleKey.isEmpty ? warning.description : warning.ruleKey
            descriptions[key] = descriptions[key] ?? warning.description
            if pairs[key] == nil {
                order.append(key)
                severities[key] = warning.severity
                mechanisms[key] = warning.mechanism
            }
            pairs[key, default: []].append("\(warning.substanceA) + \(warning.substanceB)")
            substanceAs[key, default: []].append(warning.substanceA)
            substanceBs[key, default: []].append(warning.substanceB)
            if let existing = severities[key], warning.severity.rawValue > existing.rawValue {
                severities[key] = warning.severity
            }
        }
        return order
            .map { key in
                InteractionGroup(
                    id: key,
                    severity: severities[key] ?? .caution,
                    mechanism: mechanisms[key] ?? .generic,
                    description: descriptions[key] ?? "",
                    pairs: pairs[key] ?? [],
                    substanceAs: substanceAs[key] ?? [],
                    substanceBs: substanceBs[key] ?? [],
                )
            }
            .sorted { $0.severity.rawValue > $1.severity.rawValue }
    }
}
