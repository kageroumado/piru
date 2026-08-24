import SwiftUI

/// A pushed deep-data page — the destination of the redesigned detail view's
/// "Show all" affordances (`PushRoute.substanceData`). It **reuses the existing
/// section views** (`ChemistrySection`, `SourcesSection`, `PharmacologySections`)
/// rather than re-implementing them, hosting them on their own screen instead of
/// inline.
///
/// The page always renders the substance's **full** data for its section,
/// independent of the user's disclosure tier — a deep link or a "Show all" tap
/// is a request to see everything, and the page must stay valid if the tier
/// changes while it's on the stack. So it loads its model at a fixed
/// `pharmaNerd` policy.
struct SubstanceDataPageView: View {
    let name: String
    let section: DataSection

    /// The reference pages show full data regardless of the user's chosen tier.
    private static let policy = DisclosurePolicy(profile: .pharmaNerd)

    @State private var model = SubstanceDetailModel()
    @State private var glossaryTopic: PharmacologyGlossarySheet.Topic?

    /// The full per-field record, upgraded in the `.task` — the first frame
    /// renders off the shell (mirrors `SubstanceDetailView`'s shell-first +
    /// upgrade pattern; the full resolve on the push's first frame was ~21 SQL).
    @State private var resolved: Substance?

    var body: some View {
        Group {
            if let substance = resolved ?? SubstanceLibrary.shell(name) ?? SubstanceLibrary.lookup(name) {
                List {
                    sections(for: substance)
                }
                .listStyle(.insetGrouped)
                .task(id: name) {
                    if let full = SubstanceLibrary.resolveFull(name) {
                        resolved = full
                    }
                    model.load(substanceName: substance.name, category: substance.category, policy: Self.policy)
                }
                .sheet(item: $glossaryTopic) { topic in
                    PharmacologyGlossarySheet(topic: topic)
                }
            } else {
                ContentUnavailableView(
                    "Substance Not Found",
                    systemImage: "questionmark.circle",
                    description: Text("“\(name)” isn’t in the library anymore. It may have been renamed or merged."),
                )
            }
        }
        .navigationTitle(Text(section.pageTitle))
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func sections(for substance: Substance) -> some View {
        switch section {
        case .chemistry:
            ChemistrySection(substance: substance, showsMechanism: true, initiallyExpanded: true)
        case .sources:
            SourcesSection(
                substance: substance,
                showsSources: true,
                contributions: model.sourceContributions,
                initiallyExpanded: true,
            )
        case .pharmacology:
            // Host the whole pharmacology cluster (mechanism · monoamine ·
            // receptor literature · PK · metabolism) at full tier so the deep
            // page reuses the canonical rendering — disclosures start expanded
            // at pharmaNerd — rather than duplicating its gating.
            PharmacologySections(
                substance: substance,
                model: model,
                policy: Self.policy,
                profile: .pharmaNerd,
                onGlossary: { glossaryTopic = $0 },
            )
        }
    }
}
