import SwiftUI

/// **Also Active** — the metabolites doing some of the work.
///
/// Lives on the main detail screen at every disclosure tier. It used to sit
/// inside ``PharmacologySections``, which is hidden below the Pharma Nerd tier —
/// so the reader least likely to already know that something *other than what
/// they took* is producing the effect was the one who never saw it.
///
/// Deliberately not collapsible: it's usually one card, and folding it re-buries
/// the thing being surfaced.
struct AlsoActiveSection: View {
    let substance: Substance
    let model: SubstanceDetailModel
    /// Opens the glossary entry for metabolism from the section header's ⓘ.
    let onGlossary: (PharmacologyGlossarySheet.Topic) -> Void

    @Environment(\.appNavigator) private var navigator

    /// The metabolites worth a section — the ones that outlive the dose. See
    /// ``ActiveMetabolite/earnsOwnSection(parentHalfLifeMinutes:parentDurationMinutes:)``;
    /// the rest stay in the Metabolism disclosure rather than being promoted to a
    /// headline that implies news.
    private var durationChangingMetabolites: [ActiveMetabolite] {
        model.activeMetabolites.filter {
            $0.earnsOwnSection(
                parentHalfLifeMinutes: substance.halfLifeMinutes,
                parentDurationMinutes: substance.longestRouteDurationMinutes,
            )
        }
    }

    var body: some View {
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
