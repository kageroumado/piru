import SwiftUI

/// The "Water & heat" section — a per-substance thermoregulation and hydration
/// guidance card. Only relevant for substances that raise body temperature or
/// alter fluid balance (empathogens, stimulants). Self-hides when nil.
/// See ``WaterHeatGuidance``.
struct WaterHeatSection: View {
    let guidance: WaterHeatGuidance?

    var body: some View {
        if let guidance {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    Text(guidance.headline)
                        .font(.system(.title3, design: .rounded, weight: .heavy))
                        .foregroundStyle(Theme.accent)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minWidth: 70, alignment: .leading)
                        .accessibilityLabel(Text("Guideline: \(guidance.headline)"))
                    Text(body(guidance))
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            } header: {
                Label("Water & heat", systemImage: "drop.fill")
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    private func body(_ guidance: WaterHeatGuidance) -> AttributedString {
        (try? AttributedString(markdown: guidance.body)) ?? AttributedString(guidance.body)
    }
}
