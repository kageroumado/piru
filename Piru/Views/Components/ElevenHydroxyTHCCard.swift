import SwiftUI

/// 11-OH-THC readout for cannabis, shown only on oral
/// entries (edibles, oils, capsules; the caller gates it). First-pass metabolism converts much of the
/// swallowed Δ9-THC to 11-hydroxy-THC, which enters the brain more readily and binds CB1 more strongly
/// than the parent (Kᵢ ≈ 0.37 nM vs ≈ 25 nM). That is why an edible feels stronger per milligram than
/// the same dose smoked, comes on slowly and lasts far longer; the practical point is the slow-onset
/// redose trap. Qualitative by the house labeling rule: the affinity gap is cited, but felt potency is
/// never reduced to a single multiple.
struct ElevenHydroxyTHCCard: View {
    var body: some View {
        Section {
            HStack(alignment: .top, spacing: Spacing.lg) {
                Image(systemName: "clock.badge.exclamationmark")
                    .foregroundStyle(.cautionAccent)
                    .font(.piru(.title3))
                    .padding(.top, Spacing.xxs)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("11-OH-THC")
                        .sectionLabel()

                    Text("Swallowed THC passes through your liver first, which turns much of it into 11-hydroxy-THC, an active by-product that reaches the brain more easily and binds the CB1 receptor far more strongly than THC itself. That's why an edible tends to feel stronger, milligram for milligram, than the same amount smoked.")
                        .captionSecondary()

                    Text("Edibles also come on slowly, usually 30 minutes to 2 hours, and last much longer, often 6–10 hours. That slow start is the redose trap: more taken before the first dose has arrived stacks into a far stronger, longer experience than intended.")
                        .captionSecondary()
                }
                .accessibilityElement(children: .combine)
            }
            .padding(.vertical, Spacing.xxs)
        } header: {
            Text("11-OH-THC (Edibles)")
        } footer: {
            Text("Based on first-pass metabolism of oral THC · educational. Onset and duration vary with dose, product, and tolerance.")
        }
    }
}
