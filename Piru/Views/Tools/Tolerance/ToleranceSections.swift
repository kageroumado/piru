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

/// Shown when the model has nothing to plot or list: an empty journal, or a journal whose doses the
/// replay leaves at zero (substances outside every modeled mechanism, or doses long faded).
struct ToleranceEmptyState: View {
    /// The journal holds entries, so the empty result is the replay's answer for them.
    let hasEntries: Bool

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Label(hasEntries ? "Nothing above baseline" : "Nothing to show yet", systemImage: "chart.line.flattrend.xyaxis")
                    .sectionLabel()
                Text(
                    hasEntries
                        ? "No logged dose still counts toward a mechanism this model follows. The model sees only what is logged, so an empty screen says nothing about your actual tolerance."
                        : "Log a few doses and the modeled tolerance shows up here. The model sees only what is logged, so an empty screen says nothing about your actual tolerance.",
                )
                .captionSecondary()
            }
            .padding(.vertical, Spacing.xs)
        }
    }
}

/// The mechanisms that read near baseline, folded into one line: each has a level to report and
/// nothing a card would add.
struct ToleranceNearBaselineSection: View {
    /// One entry per mechanism, its name and level ("Adenosine (caffeine) 4%"), highest first.
    let items: [String]

    var body: some View {
        if !items.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Label("Near baseline", systemImage: "chart.line.flattrend.xyaxis")
                        .sectionLabel()
                    Text("Under \(tolerancePercentText(ToleranceRow.nearBaselineSeverity * 100)) in the model now: \(toleranceListPhrase(items)).")
                        .captionSecondary()
                }
                .padding(.vertical, Spacing.xs)
            }
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
