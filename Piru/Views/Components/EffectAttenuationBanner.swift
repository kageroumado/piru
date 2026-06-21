import SwiftUI

/// One-line predicted **effect-attenuation** summary, surfaced at log time when a releaser is taken
/// while a reuptake blocker that competes for its transporter is onboard
/// (`Specs/pharmacology-axis-meta-plan.md`, Stage 3c). This is a *sign-flipped* readout — "it won't
/// work as well," not a danger warning — so it is styled deliberately calm (no alarm color), distinct
/// from the interaction-danger and combined-depression surfaces.
struct EffectAttenuationBanner: View {
    let result: EffectAttenuationResult

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.down.right.circle")
                .foregroundStyle(.secondary)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(result.attenuated) may feel weaker — \(blockerPhrase) blocks the \(transporterName) it needs to work.")
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            Spacer(minLength: 0)
        }
    }

    private var transporterName: String {
        String(localized: result.transporter.displayName)
    }

    private var blockerPhrase: String {
        ListFormatter.localizedString(byJoining: result.blockers)
    }

    private var subtitle: String {
        let confidence = String(localized: result.confidence.label)
        return String(localized: "Predicted ~\(result.reductionRangeText) reduced effect · predicted (model, \(confidence)). Reduced effect, not a danger warning.")
    }
}
