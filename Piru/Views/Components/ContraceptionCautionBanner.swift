import SwiftUI

/// A small, calm heads-up shown on the detail page of a CYP3A4 *inducer* (modafinil, rifampicin,
/// carbamazepine, St John's Wort…): by speeding up clearance of the estrogen/progestin in systemic
/// hormonal contraception, it can lower their levels enough to reduce contraceptive efficacy.
///
/// It is only relevant to people using hormonal birth control, so it is phrased as a brief note rather
/// than an alarm — but it is shown to *everyone* viewing the substance, because the app has no user-sex
/// profile to gate on and this is a commonly-overlooked, on-the-label interaction worth not burying.
struct ContraceptionCautionBanner: View {
    /// The inducer catalog entry — carries the enzyme name for honest, specific framing.
    let inducer: MetabolicModulation.Modulator

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "pills.circle")
                .foregroundStyle(.orange)
                .font(.title3)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("May reduce hormonal birth-control efficacy")
                    .font(.subheadline.weight(.semibold))
                Text("Induces \(inducer.enzyme.displayName), which clears the hormones in the combined pill, patch, ring, implant and hormonal IUD — lowering their levels. Anyone relying on hormonal contraception should consider a backup method. Often noted on the label, but easy to miss.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
        }
    }
}
