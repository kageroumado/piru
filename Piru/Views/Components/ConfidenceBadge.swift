import SwiftUI

/// A compact pill that renders a ``ConfidenceTier`` next to a predicted pharmacology value
/// (Vd, Kᵢ/EC₅₀, tolerance forecast, …).
///
/// Reinforces the house rule that every modeled number is "predicted (model, confidence)", never
/// "measured": the color and glyph degrade from a sealed checkmark (literature-backed) to a warning
/// triangle (unverified class default), so a glance conveys how much to trust the figure.
struct ConfidenceBadge: View {
    let tier: ConfidenceTier

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .imageScale(.small)
            Text(tier.label)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.10), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tier.label)
    }

    private var color: Color {
        switch tier {
        case .high: .Confidence.High.text
        case .medium: .Confidence.Medium.text
        case .low: .Confidence.Low.text
        case .unverified: .Confidence.Unverified.text
        }
    }

    private var symbol: String {
        switch tier {
        case .high: "checkmark.seal.fill"
        case .medium: "checkmark.seal"
        case .low: "questionmark.circle"
        case .unverified: "exclamationmark.triangle"
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 8) {
        ForEach(ConfidenceTier.allCases, id: \.self) { ConfidenceBadge(tier: $0) }
    }
    .padding()
}
