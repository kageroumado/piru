import SwiftUI

/// The "Safety" umbrella — the screen's how-not-to-hurt-yourself block, gathering
/// what used to be four separate sections into one card below the pharmacology
/// notable **combinations**, **water & heat** guidance, and myth
/// **corrections**. Each sub-block still
/// self-hides on absent data, and the whole section disappears when a compound
/// carries none of it. Placement gates (`.combinations` / `.water` /
/// `.misconceptions`) are honored per sub-block so a tier that hides one still
/// shows the rest.
struct SafetySection: View {
    let substance: Substance
    let policy: DisclosurePolicy
    let accent: Color

    private func placement(_ section: DetailSection) -> SectionPlacement {
        policy.placement(for: section, displayClass: substance.displayClass)
    }

    private var showsCombinations: Bool {
        placement(.combinations) == .inline && !substance.combinations.isEmpty
    }

    private var showsWater: Bool {
        placement(.water) == .inline && substance.waterHeat != nil
    }

    private var showsMisconceptions: Bool {
        placement(.misconceptions) == .inline && !substance.misconceptions.isEmpty
    }

    private var isEmpty: Bool {
        !showsCombinations && !showsWater && !showsMisconceptions
    }

    var body: some View {
        if !isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 18) {
                    if showsCombinations {
                        subheading("Combinations")
                        CombinationsList(combinations: substance.combinations)
                    }
                    if showsWater, let water = substance.waterHeat {
                        subheading("Water & heat")
                        WaterHeatCard(guidance: water)
                    }
                    if showsMisconceptions {
                        subheading("Common misconceptions")
                        MythBustList(misconceptions: substance.misconceptions, accent: accent)
                    }
                }
                .padding(.vertical, Spacing.xs)
            } header: {
                Text("Safety")
                    .sectionLabel()
            }
        }
    }

    /// The sub-label above each block — smaller and quieter than the "Safety"
    /// section header so the kinds of content read as members of one group.
    private func subheading(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .textCase(.uppercase)
            .tracking(0.5)
            .foregroundStyle(Theme.secondaryLabel)
    }
}
