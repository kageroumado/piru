import SwiftUI

/// **Drug Class** — which antidepressant class this is, shown against the others
/// so the acronym means something.
///
/// The card exists because the classes are the most-used and least-explained
/// words in this corner of pharmacology. Naming this drug's class alone would be
/// a dictionary entry; the family beside it is what makes it an answer, because
/// every class is defined by what the neighbouring ones do differently.
///
/// Gated on the compound being an antidepressant, not merely on carrying a class
/// tag. `NDRI` is tagged on methamphetamine and the cathinones, and `SNRI` on
/// tramadol — mechanistically right, and an antidepressant-class card on any of
/// them frames the compound as something it isn't.
struct DrugClassSection: View {
    let substance: Substance

    @State private var isExpanded = false

    private var ownClasses: [AntidepressantClass] {
        guard substance.category == .antidepressant
            || substance.extraBrowseCategories.contains(.antidepressant)
        else { return [] }
        return AntidepressantClass.resolve(tags: substance.tags)
    }

    var body: some View {
        if !ownClasses.isEmpty {
            let own = Set(ownClasses)
            CollapsibleSection(
                "Drug Class",
                isExpanded: $isExpanded,
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(ownClasses, id: \.self) { drugClass in
                        DrugClassRow(drugClass: drugClass, isThisDrug: true, accent: substance.category.color)
                    }
                    Divider()
                    Text("The rest of the family", comment: "Header above the sibling drug classes")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.secondaryLabel)
                    ForEach(AntidepressantClass.allCases.filter { !own.contains($0) }, id: \.self) { drugClass in
                        DrugClassRow(drugClass: drugClass, isThisDrug: false, accent: substance.category.color)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

/// One class: the acronym, what it expands to, and the line that separates it
/// from its neighbours. The substance's own class is tinted and marked; the rest
/// carry the same content at secondary weight, because the comparison is the
/// point and a collapsed sibling would defeat it.
private struct DrugClassRow: View {
    let drugClass: AntidepressantClass
    let isThisDrug: Bool
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                // `verbatim`: an acronym is not a catalog key.
                Text(verbatim: drugClass.acronym)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isThisDrug ? accent : Color.primary)
                Text(drugClass.expansion)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(drugClass.difference)
                .font(.caption)
                .foregroundStyle(isThisDrug ? Color.primary : Theme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(isThisDrug ? 8 : 0)
        .background {
            if isThisDrug {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.opacity(0.10))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isThisDrug ? [.isSelected] : [])
    }
}
