import SwiftUI

struct VolumetricDosingDisclaimer: View {
    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text("Extremely Potent Substance")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                Text("Active in microgram (µg) quantities — 1/1000th of a milligram. Volumetric dosing is required at all times for safe and accurate measurement. Never attempt to measure doses by eye or with standard scales.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
            }
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }
}

/// Shown for plant entries dosed in active-compound content (unit like "mg THC"):
/// the ladder is molecule mg, not plant weight, so explain the conversion.
struct THCContentNote: View {
    var body: some View {
        Label {
            Text("Doses are milligrams of THC. Flower needed ≈ desired THC ÷ the strain's %THC (e.g. 3 mg ÷ 18% ≈ 0.02 g). Smoking loses 50–80% to combustion, so real flower amounts run higher.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
        } icon: {
            Image(systemName: "leaf")
                .foregroundStyle(.secondary)
        }
    }
}

/// Softer guidance for low-milligram substances: a precise scale matters, but
/// they're not active in microgram quantities so the stronger banner would mislead.
struct PreciseScaleNote: View {
    var body: some View {
        Label {
            Text("Dosed in low milligrams — use a precise milligram scale (0.001 g resolution). Hard to measure accurately by eye or with kitchen scales.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
        } icon: {
            Image(systemName: "scalemass")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Experience Phase
