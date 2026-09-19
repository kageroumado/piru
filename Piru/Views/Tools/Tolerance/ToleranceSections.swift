import SwiftUI

/// The "How tolerance works" navigation row, the last row of the tool.
struct ToleranceHowItWorksCard: View {
    var body: some View {
        Section {
            NavigationLink {
                ToleranceExplainerView()
            } label: {
                Label("How tolerance works", systemImage: "book")
            }
        }
    }
}

/// Shown when nothing is logged (or nothing scores) — the model has nothing to plot.
struct ToleranceEmptyState: View {
    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Label("Nothing to show yet", systemImage: "chart.line.flattrend.xyaxis")
                    .sectionLabel()
                Text("Log a few doses and the modeled tolerance shows up here. The model sees only what is logged, so an empty screen says nothing about your actual tolerance.")
                    .captionSecondary()
            }
            .padding(.vertical, Spacing.xs)
        }
    }
}

/// Surfaces logged substances the model can't score (missing PK), so a class never silently reads
/// "rested" (the heavy-kratom → "Opioids recovered" trap).
struct ToleranceIncompleteDataSection: View {
    let names: [String]

    var body: some View {
        if !names.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Label("Not modeled", systemImage: "questionmark.circle")
                        .sectionLabel()
                    Text("Logged, but the model has no data for these, so they are left out: \(toleranceListPhrase(names)).")
                        .captionSecondary()
                }
                .padding(.vertical, Spacing.xs)
            }
        }
    }
}
