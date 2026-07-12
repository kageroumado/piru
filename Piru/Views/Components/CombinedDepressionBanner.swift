import SwiftUI

/// One-line combined CNS/respiratory-depression summary, surfaced wherever a depressant stack warns
/// at log time (`Specs/pharmacology-axis-meta-plan.md`, Stage 3b). The danger signal is *when* the
/// combined depression peaks — "peaks around 02:30" — rather than "two depressant tags co-exist". The
/// rich timeline + curve live in ``InteractionTimelineView``; this is the at-a-glance form.
struct CombinedDepressionBanner: View {
    let result: CombinedDepressionResult

    var body: some View {
        let color = result.band?.labelColor ?? Theme.secondaryLabel
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lungs.fill")
                .foregroundStyle(color)
                .font(.title3)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Combined respiratory depression peaks around \(result.peakDate.formatted(date: .omitted, time: .shortened)).")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
        }
    }

    private var subtitle: String {
        let confidence = String(localized: result.confidence.label)
        guard let level = result.levelLabel else {
            return String(localized: "Predicted combined depression · \(confidence).")
        }
        return String(localized: "\(String(localized: level)) combined depression · predicted (model, \(confidence)).")
    }
}
