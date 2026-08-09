import SwiftUI

/// Reference card listing what the clinical-trial literature says about interventions during
/// benzodiazepine discontinuation — both the things that worked and, more usefully, the things
/// that didn't. Pure reference content: no recommendation, no model, no personalization.
/// Source: NAV26 §8.3 (Navarrete et al. 2026, Int J Mol Sci 27:1430).
struct InterventionLedgerView: View {
    var body: some View {
        List {
            Group {
                Section {
                    Text("Clinical trial evidence for interventions during benzodiazepine discontinuation. Each row is what the study found — not a recommendation.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryLabel)
                }

                Section("Supported by evidence") {
                    ForEach(Self.supported) { entry in
                        InterventionRow(entry: entry)
                    }
                }

                Section("Not supported by evidence") {
                    Text("This half is the more useful half.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)

                    ForEach(Self.notSupported) { entry in
                        InterventionRow(entry: entry)
                    }
                }

                Section {
                    Text("Not medical advice. Benzodiazepine discontinuation can be medically dangerous — these are research findings, not a plan.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                }

                Section {
                    Link(destination: URL(string: "https://doi.org/10.3390/ijms27031430")!) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Navarrete F, et al. Benzodiazepine Dependence: Clinical and Molecular Aspects, Preventive Strategies and Therapeutic Approaches. Int J Mol Sci. 2026;27(3):1430.")
                                .font(.caption2)
                                .foregroundStyle(Theme.secondaryLabel)
                            Text("doi:10.3390/ijms27031430")
                                .font(.caption2)
                                .foregroundStyle(.tint)
                        }
                    }
                }
            }
            .listRowBackground(CardBackground())
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .appNavigationBar("Discontinuation Evidence")
    }
}

// MARK: - Row view

private struct InterventionRow: View {
    let entry: InterventionEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.name)
                .font(.subheadline.weight(.semibold))

            Text(entry.finding)
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)

            if let detail = entry.detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Data

private struct InterventionEntry: Identifiable {
    let name: LocalizedStringResource
    let finding: LocalizedStringResource
    let detail: LocalizedStringResource?

    var id: String {
        String(localized: name)
    }
}

private extension InterventionLedgerView {
    static let supported: [InterventionEntry] = [
        InterventionEntry(
            name: "CBT + gradual taper",
            finding: "The strongest result in the literature. Discontinuation significantly higher than taper alone at both 3 months and 6–12 months.",
            detail: "Meta-analysis",
        ),
        InterventionEntry(
            name: "Gradual taper",
            finding: "About two-thirds discontinue short-term; roughly one-third sustain long-term. Consensus rate: 25% reduction per week over 4–6 weeks.",
            detail: "Clinical consensus",
        ),
        InterventionEntry(
            name: "Imipramine",
            finding: "Taper success 82.6% vs 37.5% placebo.",
            detail: "RCT, n = 107",
        ),
        InterventionEntry(
            name: "Carbamazepine",
            finding: "More patients BZD-free at week 5; lower withdrawal incidence and anxiety in elderly.",
            detail: "3 RCTs",
        ),
        InterventionEntry(
            name: "Pregabalin",
            finding: "Safe and effective for tapering off long-term use; improved sleep.",
            detail: "1 RCT (n = 106) + open study (n = 282)",
        ),
        InterventionEntry(
            name: "Valproate",
            finding: "79% abstinent at 5 weeks post-taper vs placebo. No effect at 12 weeks.",
            detail: "RCT, n = 78",
        ),
        InterventionEntry(
            name: "Flumazenil",
            finding: "Reversed withdrawal scores and craving vs oxazepam taper and placebo. Inpatient IV only — dangerous in chronic users (precipitated withdrawal).",
            detail: "2 trials",
        ),
    ]

    static let notSupported: [InterventionEntry] = [
        InterventionEntry(
            name: "Melatonin",
            finding: "One small positive trial (n = 34); two larger negative trials (n = 80, n = 38 at 1-year follow-up). Improved sleep quality without improving discontinuation.",
            detail: nil,
        ),
        InterventionEntry(
            name: "Long-acting benzo switch",
            finding: "Insufficient evidence to support the efficacy of this strategy — despite being the standard move and the core of the Ashton method.",
            detail: nil,
        ),
        InterventionEntry(
            name: "Gabapentin",
            finding: "No difference vs placebo.",
            detail: "n = 19, underpowered",
        ),
        InterventionEntry(
            name: "Lithium",
            finding: "More than 60% discontinuation in both arms; no difference.",
            detail: "n = 244",
        ),
        InterventionEntry(
            name: "Progesterone",
            finding: "No difference on withdrawal severity, anxiety, or drug-free status.",
            detail: "n = 40",
        ),
        InterventionEntry(
            name: "Magnesium aspartate",
            finding: "No difference on any endpoint.",
            detail: "n = 144",
        ),
        InterventionEntry(
            name: "Ondansetron",
            finding: "No effect on taper rate, withdrawal severity, or anxiety.",
            detail: "n = 108",
        ),
        InterventionEntry(
            name: "Buspirone",
            finding: "Four small trials with contradictory results.",
            detail: nil,
        ),
        InterventionEntry(
            name: "Propranolol",
            finding: "Reduced symptom severity in completers; no effect on dropout rate or incidence.",
            detail: nil,
        ),
    ]
}
