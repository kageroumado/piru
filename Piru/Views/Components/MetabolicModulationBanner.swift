import SwiftUI

/// One-line predicted **metabolic-modulation** note, surfaced at log time when something onboard (a
/// co-active drug, a profile flag like smoking, the per-dose grapefruit flag, or the substance's own
/// auto-modulation) changes how fast the dose is cleared — and therefore its levels
/// (`Specs/pharmacology-axis-meta-plan.md`, Stage 4c). Calm, informational styling: this is a
/// "levels run higher/lower" note, not a danger warning. Direction and qualitative strength only — never
/// a fabricated fold-change.
struct MetabolicModulationBanner: View {
    let effect: MetabolicModulation.Effect

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: effect.raisesLevels ? "arrow.up.right.circle" : "arrow.down.right.circle")
                .foregroundStyle(.secondary)
                .font(.title3)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(headline)
                    .font(.subheadline.weight(.semibold))
                Text(effect.note)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
                HStack(spacing: 6) {
                    ConfidenceBadge(tier: effect.confidence)
                    Text("Predicted")
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
        }
    }

    /// The enzyme is deliberately omitted from the headline — the note below already names it
    /// ("inhibits intestinal CYP3A4 …"), so repeating "(CYP3A4)" in the title is redundant. So is the
    /// substrate: we're on its own card, "raise levels" can only mean this drug's levels. No trailing
    /// period — these read as labels, not sentences.
    private var headline: String {
        if effect.origin == .selfEdge {
            return String(localized: "Repeated doses build up faster than the dose suggests")
        }
        let modulator = String(localized: effect.modulatorName)
        return effect.raisesLevels
            ? String(localized: "\(modulator) may raise levels")
            : String(localized: "\(modulator) may lower levels")
    }
}
