import SwiftUI

/// Predicted **combination-metabolite** note — surfaced when two onboard substances react to form a
/// third active species (`Specs/pharmacology-axis-meta-plan.md`, Stage 4d). The only v1 case is
/// cocaethylene (cocaine + alcohol). Caution styling (not calm, not hard-danger): the combination puts
/// real extra strain on the heart and liver, but the copy explicitly defuses the "18–25× sudden death"
/// myth the evidence run rejected. Always "predicted (model, confidence)", never a fabricated number.
struct CombinationMetaboliteBanner: View {
    let formation: CombinationMetabolite.Formation

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.lg) {
            Image(systemName: "heart.text.square")
                .foregroundStyle(.cautionAccent)
                .font(.title3)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(formation.displayName)
                    .sectionLabel()
                Text(formation.formationNote)
                    .captionSecondary()
                Text(caution)
                    .captionSecondary()
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
        }
    }

    private var caution: String {
        let note = String(localized: formation.cautionNote)
        let confidence = String(localized: formation.confidence.label)
        return String(localized: "\(note) · predicted (model, \(confidence)).")
    }
}
