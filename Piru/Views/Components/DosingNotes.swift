import SwiftUI

struct VolumetricDosingDisclaimer: View {
    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Extremely Potent Substance")
                    .sectionLabel()
                    .foregroundStyle(.dangerText)
                Text("Active in micrograms — a thousandth of a milligram. Always measure volumetrically. You cannot dose this by eye.")
                    .captionSecondary()
            }
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.dangerAccent)
                .accessibilityHidden(true)
        }
    }
}

/// Shown for plant entries dosed in active-compound content (unit like "mg THC"):
/// the ladder is molecule mg, not plant weight, so explain the conversion.
struct THCContentNote: View {
    var body: some View {
        Label {
            Text("Doses are milligrams of THC. Flower needed ≈ desired THC ÷ the strain's %THC (e.g. 3 mg ÷ 18% ≈ 0.02 g). Smoking loses 50–80% to combustion, so real flower amounts run higher.")
                .captionSecondary()
        } icon: {
            Image(systemName: "leaf")
                .foregroundStyle(Theme.secondaryLabel)
                .accessibilityHidden(true)
        }
    }
}

/// Softer guidance for low-milligram substances: a precise scale matters, but
/// they're not active in microgram quantities so the stronger banner would mislead.
struct PreciseScaleNote: View {
    var body: some View {
        Label {
            Text("Dosed in low milligrams — use a milligram scale (0.001 g). Can't be measured by eye or kitchen scale.")
                .captionSecondary()
        } icon: {
            Image(systemName: "scalemass")
                .foregroundStyle(Theme.secondaryLabel)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Experience Phase
