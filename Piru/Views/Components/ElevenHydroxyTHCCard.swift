import SwiftUI

/// 11-OH-THC readout for the cannabis vertical (`Specs/pharmacology-axis-meta-plan.md`, Stage 5).
/// Shown **only** on **oral** cannabis entries (edibles, oils, capsules) — gated by the caller — where
/// first-pass hepatic metabolism is the dominant story: swallowed Δ9-THC is largely converted to
/// 11-hydroxy-THC, an active metabolite that crosses into the brain more readily and binds CB1
/// markedly more strongly than the parent (flagship data: 11-OH-THC Kᵢ ≈ 0.37 nM vs THC ≈ 25 nM). That
/// is why an edible feels stronger per milligram than the same dose smoked, comes on slowly, and lasts
/// far longer. The actionable harm-reduction point is the slow-onset redose trap. Qualitative and
/// educational — the metabolite's higher receptor affinity is real and cited, but felt potency is never
/// reduced to a single multiple (house labeling rule).
struct ElevenHydroxyTHCCard: View {
    var body: some View {
        Section {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "clock.badge.exclamationmark")
                    .foregroundStyle(.orange)
                    .font(.title3)
                    .padding(.top, 2)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    Text("11-OH-THC")
                        .font(.subheadline.weight(.semibold))

                    Text("Swallowed THC passes through your liver first, which turns much of it into 11-hydroxy-THC — an active by-product that reaches the brain more easily and binds the CB1 receptor far more strongly than THC itself. That's why an edible tends to feel stronger, milligram for milligram, than the same amount smoked.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)

                    Text("Edibles also come on slowly — usually 30 minutes to 2 hours — and last much longer, often 6–10 hours. That slow start is the redose trap: wait at least 2 hours before taking more, or you can stack a far stronger, longer dose than you meant to.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                }
                .accessibilityElement(children: .combine)
            }
            .padding(.vertical, 2)
        } header: {
            Text("11-OH-THC (edibles)")
        } footer: {
            Text("Based on first-pass metabolism of oral THC · educational. Onset and duration vary with dose, product, and tolerance.")
        }
    }
}
