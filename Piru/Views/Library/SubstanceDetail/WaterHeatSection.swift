import SwiftUI

/// The water/heat block — per-substance thermoregulation and hydration guidance.
/// Only relevant for substances that raise body temperature or alter fluid
/// balance (empathogens, stimulants). Rendered inside the ``SafetySection`` card
/// under a "Water & heat" sub-heading; the caller gates on `nil`.
/// See ``WaterHeatGuidance``.
struct WaterHeatCard: View {
    let guidance: WaterHeatGuidance

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Spacer(minLength: 0)
                EditorialPill(
                    label: Text(guidance.headline),
                    foreground: Theme.accent,
                    background: Theme.accent.opacity(Theme.Opacity.tint),
                )
                .accessibilityLabel(Text("Guideline: \(guidance.headline)"))
            }
            Text(bodyText)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var bodyText: AttributedString {
        (try? AttributedString(markdown: guidance.body)) ?? AttributedString(guidance.body)
    }
}
