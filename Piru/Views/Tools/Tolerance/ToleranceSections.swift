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
                Label("Nothing to show yet", systemImage: "checkmark.circle")
                    .sectionLabel()
                Text("Log a few doses and your predicted tolerance shows up here. Anything you haven't taken recently counts as no tolerance.")
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
                    Label("Can't predict yet", systemImage: "questionmark.circle")
                        .sectionLabel()
                    Text("Logged, but missing the pharmacokinetics the model needs — so it's blind here, which is not the same as no tolerance. \(toleranceListPhrase(names)).")
                        .captionSecondary()
                }
                .padding(.vertical, Spacing.xs)
            }
        }
    }
}
