import SwiftUI

/// One selectable branded formulation with its authored duration-of-effect
/// envelope — "Concerta" (~11 h), "Adderall XR" (~11 h). Sourced from
/// `product_durations` via ``SubstanceLibrary/productDuration(for:)``; only
/// products that carry an envelope become options.
struct BrandedDurationOption: Identifiable {
    /// The product name, also the identity — a proper noun, not localized.
    let name: String
    let isExtendedRelease: Bool
    let duration: DurationProfile

    var id: String {
        name
    }

    /// The envelope's total-duration figure ("~11h"), the formulation's headline.
    var totalText: String? {
        duration.total.map { DoseEffectsCard.compactDuration($0) }
    }

    /// The onset figure ("~1h"), shown as the envelope's lead-in.
    var onsetText: String? {
        duration.onset.map { DoseEffectsCard.compactDuration($0) }
    }
}

/// The **Branded formulations** section of the substance detail screen: a picker
/// that redraws the Dose & Duration curve with a specific product's envelope
/// (Concerta's manufacturer ~11 h in place of methylphenidate's own IR curve),
/// while the dose ladder stays the substance's own — doses are not branded here.
///
/// Shown only when the substance has ≥1 branded product with an authored
/// duration. `selection` is the chosen product name, or `nil` for the base
/// substance (the default), which draws the substance's own curve.
struct BrandedFormulationsSection: View {
    let options: [BrandedDurationOption]
    @Binding var selection: String?
    var accent: Color = Theme.accent

    var body: some View {
        Section {
            row(
                title: Text("Substance default", comment: "Branded formulations: the base substance, no brand"),
                subtitle: nil,
                envelope: nil,
                isSelected: selection == nil,
            ) {
                selection = nil
            }
            ForEach(options) { option in
                row(
                    title: Text(verbatim: option.name),
                    subtitle: option.isExtendedRelease
                        ? Text("Extended-release", comment: "Branded formulations: the extended-release form")
                        : Text("Immediate-release", comment: "Branded formulations: the immediate-release form"),
                    envelope: envelopeText(option),
                    isSelected: selection == option.name,
                ) {
                    selection = option.name
                }
            }
        } header: {
            Text("Branded formulations")
        } footer: {
            Text("Doses stay the substance's own — only the duration curve changes.", comment: "Branded formulations: clarifies the dose ladder is unaffected")
        }
    }

    /// "~1h → ~11h" (onset → total), or whichever bound the envelope carries.
    private func envelopeText(_ option: BrandedDurationOption) -> String? {
        switch (option.onsetText, option.totalText) {
        case let (onset?, total?): "\(onset) → \(total)"
        case let (nil, total?): total
        case let (onset?, nil): onset
        case (nil, nil): nil
        }
    }

    private func row(
        title: Text,
        subtitle: Text?,
        envelope: String?,
        isSelected: Bool,
        select: @escaping () -> Void,
    ) -> some View {
        Button(action: select) {
            HStack(spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    title
                        .font(.piru(.body, weight: .medium))
                        .foregroundStyle(Color.primary)
                    if let subtitle {
                        subtitle
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                }
                Spacer(minLength: Spacing.md)
                if let envelope {
                    Text(envelope)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.secondaryLabel)
                }
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(accent)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
