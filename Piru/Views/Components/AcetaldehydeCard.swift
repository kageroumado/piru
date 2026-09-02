import SwiftUI

/// Acetaldehyde readout for the alcohol vertical (`Specs/pharmacology-axis-meta-plan.md`, Stage 5 /
/// Foundation B). Shown **only** when the user has self-reported the ALDH2 "alcohol flush" variant *and*
/// the entry is alcohol — gated by the caller. ALDH2 carriers clear acetaldehyde, the first and toxic
/// by-product of ethanol, slowly, so it accumulates and lingers: the flush itself is the toxicity, and
/// acetaldehyde is an IARC Group 1 carcinogen whose dose-dependent throat/oesophageal-cancer risk is
/// markedly higher in flush-reactive drinkers. Honest and qualitative — a dose-scaled load band and the
/// mechanism, never a fabricated µM number (house labeling rule).
struct AcetaldehydeCard: View {
    /// Grams of ethanol in this dose, when it can be read as a mass (drives the qualitative load band).
    let gramsEthanol: Double?

    /// Qualitative acetaldehyde-exposure band — scales with the ethanol oxidised, which all passes
    /// through ADH to acetaldehyde. Ordinal only; never presented as a concentration.
    ///
    /// **These cut points do not belong in `concentration_effects`,** which
    /// `Specs/pharma-data-in-swift.md` names as their target. That table holds
    /// measured concentration→effect rows; these are counts of standard drinks
    /// with an ordinal word attached, and filing them there would give a display
    /// ladder the authority of a measurement — the same fabricated-µM claim the
    /// card's own doc comment refuses one line up.
    ///
    /// The band is safe to show as a traffic light here, where a daily-total one
    /// would not be (see the deleted CDC MME bands), because it grades the *dose*
    /// against a mechanism that has no threshold rather than grading the reader
    /// against an authority's line — and the copy beside it says exactly that:
    /// there is no amount that clears as cleanly as it does for others.
    enum Load {
        case elevated
        case high
        case veryHigh

        init(standardDrinks: Double) {
            switch standardDrinks {
            case ..<1.5: self = .elevated
            case ..<3.5: self = .high
            default: self = .veryHigh
            }
        }

        var label: LocalizedStringKey {
            switch self {
            case .elevated: "Elevated"
            case .high: "High"
            case .veryHigh: "Very high"
            }
        }

        var tint: Color {
            switch self {
            case .elevated: .yellow
            case .high: .orange
            case .veryHigh: .red
            }
        }
    }

    private var load: Load? {
        guard let grams = gramsEthanol, grams > 0 else { return nil }
        return Load(standardDrinks: ByVolumeDosing.standardDrinks(grams: grams))
    }

    var body: some View {
        Section {
            HStack(alignment: .top, spacing: Spacing.lg) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.cautionAccent)
                    .font(.title3)
                    .padding(.top, Spacing.xxs)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack {
                        Text("Acetaldehyde")
                            .sectionLabel()
                        Spacer(minLength: 8)
                        if let load {
                            Text(load.label)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(load.tint)
                                .padding(.horizontal, Spacing.md)
                                .padding(.vertical, 3)
                                .background(load.tint.opacity(Theme.Opacity.tint), in: Capsule())
                        }
                    }

                    Text("Your ALDH2 variant clears acetaldehyde — the first, toxic by-product of alcohol — slowly, so it builds up and lingers. That build-up *is* the flush, racing heart, and nausea, and it's a Group 1 carcinogen (IARC): for flush-reactive drinkers each drink carries more long-term throat and oesophageal cancer risk. Less alcohol means less acetaldehyde — there's no amount that clears as cleanly as it does for others.")
                        .captionSecondary()

                    Text("Avoid mixing alcohol with metronidazole or certain other antibiotics — they block this same step and can make even a small drink severe.")
                        .captionSecondary()
                }
                .accessibilityElement(children: .combine)
            }
            .padding(.vertical, Spacing.xxs)
        } header: {
            Text("Acetaldehyde (ALDH2)")
        } footer: {
            Text("Based on your self-reported alcohol flush · educational.")
        }
    }
}
