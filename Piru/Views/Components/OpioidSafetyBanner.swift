import SwiftUI

/// Reset-after-break overdose warning for a μ-opioid about to be logged (`Specs/pharmacology-axis-meta-
/// plan.md`, Stage 5 opioid safety axis). Shown **only** when ``ToleranceStore/opioidResetRisk`` fires —
/// the user built real tolerance, took a break, and it has recovered — so this is not a recurring
/// lecture but the one warning that matters, in the genuine relapse window.
///
/// The copy follows the spec's epistemic-empathy law: written for someone who does not already know,
/// specific to their logged situation, calm not panicked, leading with the survivable facts —
/// (1) the reset is the actual killer, (2) hypoxia is sudden loss of consciousness with no warning
/// window, (3) you cannot use naloxone on yourself, so don't use alone.
struct OpioidSafetyBanner: View {
    let risk: OpioidResetRisk

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "lungs.fill")
                    .foregroundStyle(.red)
                    .font(.title3)
                Text("Your tolerance has dropped")
                    .font(.subheadline.weight(.semibold))
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(situationLine)
                    .font(.callout)
                Text("If a dose is too much, you don't feel it coming — breathing just stops and you black out with no warning. There's no moment where you notice and react.")
                    .font(.callout)
                Text("And you can't use naloxone (Narcan) on yourself once that happens. Have someone with you who can, keep naloxone where they can reach it, and start much lower than your old dose.")
                    .font(.callout)
            }
            .foregroundStyle(.primary)

            Text(footer)
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
        }
        .padding(.vertical, 4)
    }

    private var situationLine: String {
        let pct = risk.currentResponsePercent
        return String(localized: "After about a \(risk.breakDays)-day break your opioid tolerance has fallen to roughly \(pct)% of full — close to none. A dose that felt fine before the break can stop your breathing now. This is the most common way people overdose.")
    }

    private var footer: String {
        let confidence = String(localized: risk.confidence.label)
        return String(localized: "Predicted from your logged use (model, \(confidence)).")
    }
}
