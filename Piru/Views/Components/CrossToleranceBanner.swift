import SwiftUI

/// One-line predicted **cross-tolerance** summary, surfaced at log time when a substance's receptor
/// class is already tolerant from recent use of substances that hit the same target
/// (`Specs/pharmacology-axis-meta-plan.md`, Stage 4a). Calm, informational styling — this is a
/// "it may feel weaker because of recent use" note, not a danger warning. Shown only for classes whose
/// availability axis is a valid effect multiplier (the tolerance engine refuses it for stimulants).
struct CrossToleranceBanner: View {
    let readout: CrossToleranceReadout

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "chart.line.downtrend.xyaxis")
                .foregroundStyle(.secondary)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text("Reduced response predicted — ~\(readout.responsePercent)% of rested.")
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            Spacer(minLength: 0)
        }
    }

    private var subtitle: String {
        let className = String(localized: readout.receptorClass.displayName)
        let confidence = String(localized: readout.confidence.label)
        if readout.contributors.isEmpty {
            return String(localized: "Shared \(className) tolerance · predicted (model, \(confidence)).")
        }
        let names = ListFormatter.localizedString(byJoining: readout.contributors)
        return String(localized: "Shared \(className) tolerance from \(names) · predicted (model, \(confidence)).")
    }
}
