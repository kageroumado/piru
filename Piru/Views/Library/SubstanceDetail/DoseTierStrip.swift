import SwiftUI

// MARK: - Tier strip model

/// The five dose tiers resolved for display: a short value (unit stripped, for the
/// disc strip), a full value (with unit, for the big readout), the tier name, and
/// which tier is the "reference" (Common, or the nearest present tier).
struct DoseTierStripModel {
    struct Tier: Identifiable {
        let id: Int // 0 threshold … 4 heavy
        let name: LocalizedStringKey
        let shortValue: String?
        let fullValue: String?
    }

    let tiers: [Tier]
    let selectedID: Int

    private static let names: [LocalizedStringKey] = ["Threshold", "Light", "Common", "Strong", "Heavy"]

    init(doses: DoseRange, unit: String) {
        let full = EffectsIntensityModel.bandDoseText(from: doses, unit: unit)
        tiers = (0 ... 4).map { index in
            let value = full[index]
            return Tier(
                id: index,
                name: Self.names[index],
                shortValue: value.map { Self.stripUnit($0, unit: unit) },
                fullValue: value,
            )
        }
        // Reference tier: Common if present, else the nearest present tier to it.
        let present = tiers.filter { $0.fullValue != nil }.map(\.id)
        selectedID = present.contains(2) ? 2 : (present.min(by: { abs($0 - 2) < abs($1 - 2) }) ?? 2)
    }

    var selected: (name: LocalizedStringKey, fullValue: String)? {
        tier(selectedID)
    }

    /// The named tier, if it carries a value — a tier the source didn't supply
    /// has nothing to headline, so the caller keeps whatever it was showing.
    func tier(_ id: Int) -> (name: LocalizedStringKey, fullValue: String)? {
        guard let tier = tiers.first(where: { $0.id == id }), let value = tier.fullValue else { return nil }
        return (tier.name, value)
    }

    private static func stripUnit(_ text: String, unit: String) -> String {
        text.replacingOccurrences(of: " \(unit)", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Tier disc strip

/// Five equal columns — a filled disc that grows and warms across the tiers, the
/// short value, and the uppercase tier name. The selected (reference) column is
/// tinted with the accent so it reads as "this is the number above."
struct DoseTierStrip: View {
    let tiers: DoseTierStripModel
    /// Which column reads as "this is the number above" — owned by the parent so
    /// tapping a disc can retarget the headline.
    var selectedID: Int?
    var accent: Color = Theme.accent
    /// Tapping a tier that has a value. Tiers the source left empty aren't
    /// selectable: there is no number to promote.
    var onSelect: ((Int) -> Void)?

    /// Disc diameters per tier — a single glyph family that grows threshold→heavy.
    private static let diameters: [CGFloat] = [7, 10, 13, 15, 18]
    /// The gauge's ramp, threshold gray → heavy red. One of three encodings of
    /// dose intensity that have been folded into the shared `dose` scale; this
    /// one's hues were the ones kept, since it was the most deliberately
    /// designed of the three.
    private static let colors: [Color] = [
        .Dose.Threshold.accent, .Dose.Light.accent, .Dose.Common.accent,
        .Dose.Strong.accent, .Dose.Heavy.accent,
    ]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tiers.tiers) { tier in
                let isSelected = tier.id == (selectedID ?? tiers.selectedID)
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(Self.colors[tier.id])
                            .frame(width: Self.diameters[tier.id], height: Self.diameters[tier.id])
                    }
                    .frame(height: 18)
                    Text(tier.shortValue ?? "—")
                        .font(.footnote.weight(isSelected ? .bold : .semibold).monospacedDigit())
                        .foregroundStyle(tier.shortValue == nil ? Theme.secondaryLabel : Color.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(tier.name)
                        .font(.system(size: 8, weight: .bold))
                        .textCase(.uppercase)
                        .tracking(0.3)
                        .foregroundStyle(Theme.secondaryLabel)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .padding(.horizontal, 2)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSelected ? accent.opacity(0.12) : Color(.tertiarySystemFill)),
                )
                // The value + name Texts combine into "Threshold, 30" without a
                // custom label (which would mint a generic "%@, %@" catalog key);
                // the selected tier reads as selected via the trait.
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityAddTraits(tier.fullValue != nil ? .isButton : [])
                // `contentShape` so the whole column is the target, not just the
                // glyphs — and so the tap is consumed here rather than falling
                // through to the enclosing disclosure, which is what made tapping
                // a dose tier expand "All phases" instead.
                .contentShape(RoundedRectangle(cornerRadius: 10))
                .onTapGesture {
                    guard tier.fullValue != nil else { return }
                    onSelect?(tier.id)
                }
            }
        }
    }
}
