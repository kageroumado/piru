import SwiftUI

/// The "Safety" umbrella — the screen's how-not-to-hurt-yourself block, gathering
/// what used to be four separate sections into one card below the pharmacology
/// and beside Prescribing: notable **combinations**, **water & heat** guidance,
/// label **contraindications**, and myth **corrections**. Each sub-block still
/// self-hides on absent data, and the whole section disappears when a compound
/// carries none of it. Placement gates (`.combinations` / `.water` /
/// `.misconceptions`) are honored per sub-block so a tier that hides one still
/// shows the rest.
struct SafetySection: View {
    let substance: Substance
    let policy: DisclosurePolicy
    let accent: Color
    @Binding var cautionsExpanded: Bool

    private func placement(_ section: DetailSection) -> SectionPlacement {
        policy.placement(for: section, displayClass: substance.displayClass)
    }

    private var showsCombinations: Bool {
        placement(.combinations) == .inline && !substance.combinations.isEmpty
    }

    private var showsWater: Bool {
        placement(.water) == .inline && substance.waterHeat != nil
    }

    /// Non-boxed contraindications; boxed warnings stay with Prescribing.
    private var cautions: [Contraindication] {
        substance.contraindications.filter { !$0.isBoxedWarning }
    }

    private var showsMisconceptions: Bool {
        placement(.misconceptions) == .inline && !substance.misconceptions.isEmpty
    }

    private var isEmpty: Bool {
        !showsCombinations && !showsWater && cautions.isEmpty && !showsMisconceptions
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
                    if !cautions.isEmpty {
                        ContraindicationsDisclosure(cautions: cautions, isExpanded: $cautionsExpanded)
                    }
                    if showsMisconceptions {
                        subheading("Common misconceptions")
                        MythBustList(misconceptions: substance.misconceptions, accent: accent)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Safety")
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    /// The sub-label above each block — smaller and quieter than the "Safety"
    /// section header so the four kinds of content read as members of one group.
    private func subheading(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .textCase(.uppercase)
            .tracking(0.5)
            .foregroundStyle(Theme.secondaryLabel)
    }
}

/// Contraindications & cautions.
///
/// The list folds **only when folding hides something** — that is, only past
/// `displayLimit`, which is also the point where a "+N more" appears. Since
/// label prose became a normalized flag each row is one short line, and 98% of
/// substances fit; folding those put a tap in front of six words and cost more
/// header than it saved body. Same rule the session-review interactions use:
/// below the threshold there is nothing to gain by folding.
///
/// Rows are *not* line-clamped. A contraindication cut mid-clause ("risk of
/// hypertensive cri…") is worse than a long one, and `displayLimit` already
/// keeps the card from turning into a drug monograph.
private struct ContraindicationsDisclosure: View {
    let cautions: [Contraindication]
    @Binding var isExpanded: Bool

    private let displayLimit = 6

    var body: some View {
        if cautions.count <= displayLimit {
            VStack(alignment: .leading, spacing: 8) {
                header
                rows
            }
        } else {
            DisclosureGroup(isExpanded: $isExpanded) {
                rows.padding(.top, 6)
            } label: {
                header
            }
            .tint(Theme.secondaryLabel)
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(cautions.prefix(displayLimit), id: \.self) { caution in
                Text(caution.display)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if cautions.count > displayLimit {
                Text("+\(cautions.count - displayLimit) more")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Contraindications & Cautions")
                .font(.footnote.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(Theme.secondaryLabel)
            Text(verbatim: "\(cautions.count)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.secondaryLabel)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Theme.secondaryLabel.opacity(0.12), in: Capsule())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
