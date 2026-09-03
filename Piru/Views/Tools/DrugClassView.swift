import SwiftUI

/// **The classes under one Library family** — the stimulants split into
/// cathinones, amphetamines, dopamine reuptake inhibitors and the rest.
///
/// Reached from that family's substance list rather than from a flat A–Z, so a
/// reader meets the grouping where they were already browsing. Ordered by how
/// many members each class has, which stands in for both specificity and
/// familiarity: the rare groups fall to the bottom on their own.
struct DrugClassGroupView: View {
    let category: SubstanceCategory

    @State private var classes: [SubstanceStore.ClassContextSummary] = []

    var body: some View {
        List {
            // No summary card and no large title: the reader arrived by tapping
            // a card that said both, one screen ago. Repeating them puts two
            // identical paragraphs a swipe apart and pushes the list — the
            // reason for the screen — below the fold.
            Section {
                ForEach(classes) { item in
                    NavigationLink(value: PushRoute.drugClass(slug: item.slug)) {
                        ClassRow(item: item, accent: category.color)
                    }
                }
            }
            .listRowBackground(CardBackground())
        }
        .insetGroupedListStyle()
        .themedPage()
        .navigationTitle(Text(category.browseTitle))
        .inlineNavigationTitle()
        .task {
            if classes.isEmpty { classes = SubstanceStore.shared.classContexts(in: category) }
        }
    }
}

/// One class in the group list: the name, what it covers, and how many
/// substances are in it.
struct ClassRow: View {
    let item: SubstanceStore.ClassContextSummary
    let accent: Color

    var body: some View {
        HStack(spacing: Spacing.lg) {
            LegendDot(color: accent, size: .large)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                // `verbatim`: a class name is data, read from the research
                // write-up, not a catalog key.
                Text(verbatim: item.title)
                    .font(.body)
                if let subtitle = item.subtitle {
                    Text(verbatim: subtitle)
                        .captionSecondary()
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            Text(verbatim: "\(item.memberCount)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.secondaryLabel)
        }
        .padding(.vertical, Spacing.xxs)
    }
}

/// One class: what its members share, who they are, and the studies behind it.
///
/// Laid out like the substance screen rather than as a wall of prose — a title
/// block with the family it belongs to, then each shared property as its own
/// card under its own heading.
struct DrugClassDetailView: View {
    let slug: String

    @State private var context: SubstanceStore.ClassContext?

    private var accent: Color {
        context?.category?.color ?? Theme.accent
    }

    var body: some View {
        List {
            if let context {
                header(context)
                paragraph("Shared mechanism", context.sharedMechanism)
                paragraph("Shared kinetics", context.sharedPharmacokinetics)
                paragraph("Shared safety profile", context.sharedSafety)
                paragraph("Structure and activity", context.sarSummary)
                members(context.siblings)
                references(context.references)
            }
        }
        .insetGroupedListStyle()
        .themedPage()
        .navigationTitle(Text(verbatim: context?.title ?? ""))
        .inlineNavigationTitle()
        .task {
            if context == nil { context = SubstanceStore.shared.classContext(slug: slug) }
        }
    }

    /// The title block. Carries the name at display weight and the family chip,
    /// so the screen opens with what this *is* rather than with a paragraph.
    private func header(_ context: SubstanceStore.ClassContext) -> some View {
        Section {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text(verbatim: context.title)
                    .font(.title2.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                if let category = context.category {
                    Text(category.browseTitle)
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(accent)
                }
                if let subtitle = context.subtitle {
                    Text(verbatim: subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, Spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .listRowBackground(CardBackground())
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
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, Spacing.xxs)
            } header: {
                Text(title)
            }
            .listRowBackground(CardBackground())
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
            .listRowBackground(CardBackground())
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
                        accent: accent,
                    )
                    .font(.caption)
                }
            } header: {
                Text("References")
            }
            .listRowBackground(CardBackground())
        }
    }
}

/// **Tools ▸ Education ▸ Drug Classes** — every class, grouped by family.
///
/// The same screens the Library reaches, from the other direction: this is the
/// entrance for someone reading *about* drug classes rather than looking one up
/// from a substance they already have in mind. Each family's classes sit under
/// its own header, so the list reads as a taxonomy instead of an A–Z.
struct DrugClassListView: View {
    @State private var groups: [(category: SubstanceCategory, classes: [SubstanceStore.ClassContextSummary])] = []

    var body: some View {
        List {
            ForEach(groups, id: \.category) { group in
                Section {
                    ForEach(group.classes) { item in
                        NavigationLink(value: PushRoute.drugClass(slug: item.slug)) {
                            ClassRow(item: item, accent: group.category.color)
                        }
                    }
                } header: {
                    Text(group.category.browseTitle)
                }
                .listRowBackground(CardBackground())
            }
        }
        .insetGroupedListStyle()
        .themedPage()
        .task {
            guard groups.isEmpty else { return }
            // Families ordered by how many classes they hold, so the ones with
            // something to browse lead.
            groups = Dictionary(grouping: SubstanceStore.shared.classContexts()) { $0.category }
                .compactMap { category, classes in
                    category.map { (category: $0, classes: classes) }
                }
                .sorted { $0.classes.count > $1.classes.count }
        }
        .overlay {
            if groups.isEmpty {
                ContentUnavailableView("No Classes", systemImage: "square.stack.3d.up")
            }
        }
    }
}
