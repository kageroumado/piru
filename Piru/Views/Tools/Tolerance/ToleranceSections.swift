import SwiftUI

/// The "Predicted" provenance banner at the top of the tool.
struct ToleranceBanner: View {
    let isWeightEstimated: Bool

    /// Model + body-weight provenance folded into one sentence (the weight clause only when it's the
    /// population default, so a user who set their own weight doesn't see the nudge).
    private var subtitle: LocalizedStringResource {
        isWeightEstimated
            ? "Model estimates from your dose log, assuming a \(Int(UserProfileStore.defaultWeightKg)) kg body weight — set yours in Settings."
            : "Model estimates from your dose log and your body weight."
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label("Predicted", systemImage: "exclamationmark.triangle.fill")
                    .sectionLabel()
                    .foregroundStyle(.cautionText)
                Text(subtitle)
                    .captionSecondary()
            }
            .padding(.vertical, Spacing.xs)
        }
    }
}

/// The "How tolerance works" navigation row.
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
