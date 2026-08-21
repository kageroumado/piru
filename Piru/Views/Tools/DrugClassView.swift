import SwiftUI

/// **Tools ▸ Education ▸ Drug Classes** — the pharmacological families, and what
/// the members of each share.
///
/// This content lived on the substance screen for one build and did not belong
/// there: it is four paragraphs of pharmacology about a *family*, which is a
/// good read and a bad interruption between a dose ladder and a safety card.
/// It sits with the rest of the educational material, and each substance links
/// to its own family from a single row.
struct DrugClassListView: View {
    @State private var classes: [SubstanceStore.ClassContextSummary] = []

    var body: some View {
        List {
            ForEach(classes) { item in
                NavigationLink(value: PushRoute.drugClass(slug: item.slug)) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: item.title)
                            .font(.body)
                        if let subtitle = item.subtitle {
                            Text(verbatim: subtitle)
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryLabel)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .task {
            if classes.isEmpty { classes = SubstanceStore.shared.classContexts() }
        }
        .overlay {
            if classes.isEmpty {
                ContentUnavailableView("No Classes", systemImage: "square.stack.3d.up")
            }
        }
    }
}

/// One class: what its members share, who they are, and the studies behind it.
struct DrugClassDetailView: View {
    let slug: String

    @State private var context: SubstanceStore.ClassContext?
    @Environment(\.appNavigator) private var navigator

    var body: some View {
        List {
            if let context {
                if let subtitle = context.subtitle {
                    Section {
                        Text(verbatim: subtitle)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                }
                paragraph("Shared mechanism", context.sharedMechanism)
                paragraph("Shared kinetics", context.sharedPharmacokinetics)
                paragraph("Shared safety profile", context.sharedSafety)
                paragraph("Structure and activity", context.sarSummary)
                members(context.siblings)
                references(context.references)
            }
        }
        .navigationTitle(Text(verbatim: context?.title ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if context == nil { context = SubstanceStore.shared.classContext(slug: slug) }
        }
    }

    @ViewBuilder
    private func paragraph(_ title: LocalizedStringResource, _ text: String?) -> some View {
        if let text, !text.isEmpty {
            Section {
                // Authored per class in the curated research data, so it ships
                // in English regardless of locale — `verbatim` keeps it out of
                // the catalog rather than minting untranslatable keys.
                Text(verbatim: text)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
            } header: {
                Text(title)
            }
        }
    }

    @ViewBuilder
    private func members(_ names: [String]) -> some View {
        if !names.isEmpty {
            Section {
                ForEach(names, id: \.self) { name in
                    NavigationLink(value: PushRoute.substance(name: name)) {
                        Text(verbatim: name)
                    }
                }
            } header: {
                Text("^[\(names.count) substance](inflect: true)")
            }
        }
    }

    @ViewBuilder
    private func references(_ refs: [SubstanceStore.ClassContext.Reference]) -> some View {
        if !refs.isEmpty {
            Section {
                ForEach(refs) { ref in
                    sourceLine(
                        slug: "peer-review-primary",
                        detail: ref.title,
                        doi: ref.doi,
                        pmid: ref.pmid,
                        accent: Theme.accent,
                    )
                    .font(.caption)
                }
            } header: {
                Text("References")
            }
        }
    }
}
