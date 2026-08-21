import SwiftUI

/// **The class** — what this substance shares with the rest of its family.
///
/// Earns its place on the long tail, where a research chemical has almost no
/// data of its own and everything worth knowing is a property of the family: a
/// 2C-x nobody has studied still inherits the class's kinetics, its safety
/// profile and the SAR that says where in the series it sits. The four bodies
/// are folded and self-hiding, so a class with only a mechanism shows one.
struct ClassContextSection: View {
    let substance: Substance
    let model: SubstanceDetailModel

    @State private var isExpanded = false
    @Environment(\.appNavigator) private var navigator

    private var accent: Color {
        substance.category.color
    }

    var body: some View {
        if let context = model.classContext, context.hasBody {
            CollapsibleSection(title: Text(verbatim: context.title), isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    if let subtitle = context.subtitle {
                        Text(verbatim: subtitle)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    body(context)
                    if !context.siblings.isEmpty {
                        siblings(context.siblings)
                    }
                    if !context.references.isEmpty {
                        references(context.references)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private func body(_ context: SubstanceStore.ClassContext) -> some View {
        paragraph("Shared mechanism", context.sharedMechanism)
        paragraph("Shared kinetics", context.sharedPharmacokinetics)
        paragraph("Shared safety profile", context.sharedSafety)
        paragraph("Structure and activity", context.sarSummary)
    }

    @ViewBuilder
    private func paragraph(_ title: LocalizedStringResource, _ text: String?) -> some View {
        if let text, !text.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                // Authored per class in the curated research data, so it ships
                // in English regardless of locale — `verbatim` keeps it out of
                // the catalog rather than minting untranslatable keys.
                Text(verbatim: text)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The other members, as chips that open them. The point of naming a class
    /// is being able to walk to its neighbours.
    ///
    /// A `Button` that pushes rather than a `NavigationLink`: inside a List row
    /// each link draws its own disclosure chevron, and twelve chips came with
    /// twelve chevrons wedged between them.
    private func siblings(_ names: [String]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Also in this class")
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
            FlowLayout(spacing: 6) {
                ForEach(names, id: \.self) { name in
                    Button {
                        navigator.push(.substance(name: name))
                    } label: {
                        Text(verbatim: name)
                            .font(.caption)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(accent.opacity(0.10), in: Capsule())
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func references(_ refs: [SubstanceStore.ClassContext.Reference]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(refs.prefix(4)) { ref in
                sourceLine(
                    slug: "peer-review-primary",
                    detail: ref.title,
                    doi: ref.doi,
                    pmid: ref.pmid,
                    accent: accent,
                )
                .font(.caption2)
            }
            if refs.count > 4 {
                Text("^[\(refs.count - 4) more reference](inflect: true)")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryLabel)
            }
        }
    }
}

extension SubstanceStore.ClassContext {
    /// Whether there is anything to show. A membership row with no research
    /// bodies behind it is a label, not a section.
    var hasBody: Bool {
        [sharedMechanism, sharedPharmacokinetics, sharedSafety, sarSummary]
            .contains { $0?.isEmpty == false }
    }
}
