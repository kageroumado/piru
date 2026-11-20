import SwiftUI

/// **Also Active** — the metabolites doing some of the work.
///
/// Shown open at every tier, because the reader who never opens the pharmacology
/// cards is the one least likely to know a metabolite is doing the work.
///
/// Deliberately not collapsible: it's usually one card, and folding it re-buries
/// the thing being surfaced.
struct AlsoActiveSection: View {
    let substance: Substance
    let model: SubstanceDetailModel
    /// Opens the glossary entry for metabolism from the section header's ⓘ.
    let onGlossary: (PharmacologyGlossarySheet.Topic) -> Void

    @Environment(\.appNavigator) private var navigator

    var body: some View {
        let durationChangingMetabolites = model.durationChangingMetabolites(for: substance)
        if !durationChangingMetabolites.isEmpty {
            Section {
                ForEach(durationChangingMetabolites) { metabolite in
                    ActiveMetaboliteCard(
                        metabolite: metabolite,
                        parentName: substance.displayTitle,
                        parentHalfLifeMinutes: substance.halfLifeMinutes,
                        accent: substance.category.color,
                        parentDurationMinutes: substance.longestRouteDurationMinutes,
                        onOpenSubstance: { navigator.push(.substance(name: $0)) },
                    )
                    .listRowSeparator(.hidden)
                }
            } header: {
                HStack(spacing: Spacing.sm) {
                    Text("Also Active")
                    Button {
                        onGlossary(.metabolism)
                    } label: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("About metabolites", comment: "Glossary button"))
                }
            }
        }
    }
}
