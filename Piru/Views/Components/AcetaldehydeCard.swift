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
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.title3)
                    .padding(.top, 2)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Acetaldehyde")
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: 8)
                        if let load {
                            Text(load.label)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(load.tint)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(load.tint.opacity(0.10), in: Capsule())
                        }
                    }

                    Text("Your ALDH2 variant clears acetaldehyde — the first, toxic by-product of alcohol — slowly, so it builds up and lingers. That build-up *is* the flush, racing heart, and nausea, and it's a Group 1 carcinogen (IARC): for flush-reactive drinkers each drink carries more long-term throat and oesophageal cancer risk. Less alcohol means less acetaldehyde — there's no amount that clears as cleanly as it does for others.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)

                    Text("Avoid mixing alcohol with metronidazole or certain other antibiotics — they block this same step and can make even a small drink severe.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                }
                .accessibilityElement(children: .combine)
            }
            .padding(.vertical, 2)
        } header: {
            Text("Acetaldehyde (ALDH2)")
        } footer: {
            Text("Based on your self-reported alcohol flush · educational, not a measured level.")
        }
    }
}
