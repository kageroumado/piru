import SwiftUI

/// One-line predicted **metabolic-modulation** note, surfaced at log time when something onboard (a
/// co-active drug, a profile flag like smoking, the per-dose grapefruit flag, or the substance's own
/// auto-modulation) changes how fast the dose is cleared — and therefore its levels.
/// Calm, informational styling: this is a
/// "levels run higher/lower" note, not a danger warning. Direction, qualitative strength and a
/// confidence tier only, never a fold-change.
struct MetabolicModulationBanner: View {
    let effect: MetabolicModulation.Effect

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(headline)
                .sectionLabel()
            Text(LocalizedStringKey(effect.userNote))
                .captionSecondary()
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let grading {
                Text(verbatim: grading)
                    .captionSecondary()
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// "Strong effect · High confidence", from whichever of the two the source grades.
    private var grading: String? {
        let parts = [
            effect.strength.map { String(localized: $0.label) },
            effect.confidence.map { String(localized: $0.label) },
        ].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The enzyme is deliberately omitted from the headline — the note below already names it
    /// ("inhibits intestinal CYP3A4 …"), so repeating "(CYP3A4)" in the title is redundant. So is the
    /// substrate: we're on its own card, "raise levels" can only mean this drug's levels. No trailing
    /// period — these read as labels, not sentences.
    private var headline: String {
        if effect.origin == .selfEdge {
            return String(localized: "Repeated doses build up faster than the dose suggests")
        }
        let modulator = String(localized: String.LocalizationValue(stringLiteral: effect.modulatorName))
        return effect.raisesLevels
            ? String(localized: "\(modulator) may raise levels")
            : String(localized: "\(modulator) may lower levels")
    }
}
