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

                Section(TaperIntervention.Verdict.supported.sectionTitle) {
                    ForEach(interventions(.supported)) { entry in
                        InterventionRow(entry: entry)
                    }
                }

                Section(TaperIntervention.Verdict.notSupported.sectionTitle) {
                    Text("This half is the more useful half.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)

                    ForEach(interventions(.notSupported)) { entry in
                        InterventionRow(entry: entry)
                    }
                }

                Section {
                    Label {
                        Text("Research findings, not medical advice. Benzodiazepine discontinuation can be medically dangerous.")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryLabel)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
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

    private func interventions(_ verdict: TaperIntervention.Verdict) -> [TaperIntervention] {
        SubstanceStore.shared.taperInterventions().filter { $0.verdict == verdict }
    }
}

// MARK: - Row view

private struct InterventionRow: View {
    let entry: TaperIntervention

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.kind.name)
                .font(.subheadline.weight(.semibold))

            Text(entry.kind.finding)
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
