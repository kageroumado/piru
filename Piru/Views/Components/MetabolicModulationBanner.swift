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

            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            Spacer(minLength: 0)
        }
    }

    private var headline: String {
        if effect.origin == .selfEdge {
            return String(localized: "Repeated \(effect.substrate) doses build up faster than the dose suggests.")
        }
        let modulator = String(localized: effect.modulatorName)
        return effect.raisesLevels
            ? String(localized: "\(modulator) may raise \(effect.substrate) levels (\(effect.enzyme.displayName)).")
            : String(localized: "\(modulator) may lower \(effect.substrate) levels (\(effect.enzyme.displayName)).")
    }

    private var subtitle: String {
        let confidence = String(localized: effect.confidence.label)
        let note = String(localized: effect.note)
        return String(localized: "\(note) · predicted (model, \(confidence)).")
    }
}
