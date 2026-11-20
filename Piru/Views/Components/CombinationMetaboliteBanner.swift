import SwiftUI

/// Predicted **combination-metabolite** note — surfaced when two onboard substances react to form a
/// third active species, such as cocaethylene
/// (cocaine + alcohol). Caution styling, between calm and danger: the combination puts real extra
/// strain on the heart and liver, and the copy defuses the "18–25× sudden death" myth the evidence
/// rejects. Always "predicted (model, confidence)", never a fabricated number.
struct CombinationMetaboliteBanner: View {
    let formation: CombinationMetabolite.Formation

    var body: some View {
        InfoBanner(icon: "heart.text.square", iconTint: .cautionAccent, title: Text(formation.displayName)) {
            Text(formation.formationNote)
                .captionSecondary()
            Text(caution)
                .captionSecondary()
        }
    }

    private var caution: String {
        let note = String(localized: formation.cautionNote)
        let confidence = String(localized: formation.confidence.label)
        return String(localized: "\(note) · modeled (\(confidence)).")
    }
}
