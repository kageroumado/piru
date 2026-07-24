import SwiftUI

// "Also Active" on a *dose* rather than on a catalog entry.
//
// The library card answers "what does this substance turn into". This answers
// the same question about something the user actually took, which is where it
// matters: the person reading a dose detail wants to know whether the thing
// still working is the thing they swallowed. It sits beside In Your Body for
// that reason — that card says how much is left, this one says of what.
//
// Deliberately **not** gated on ``DisclosurePolicy``. The library surface is,
// because it lives among reference tables; this is not reference data. Someone
// tracking an SSRI never opens the pharmacology tier and is exactly who needs
// to hear that a metabolite outlives the dose — gating it to `.pharmaNerd`
// showed it only to the readers who already knew.

/// Loads the metabolite rows for one dose off the render path.
///
/// A `@MainActor` GRDB query in `body` would re-run on every invalidation of a
/// screen that also drives a live timeline, so the fetch happens once and the
/// view reads a plain array.
///
/// The owner drives ``load(substanceName:)`` from a section that is **always**
/// present. A `.task` hung on this section instead would never fire: its
/// content is empty until the load completes, and SwiftUI does not run the
/// lifecycle of a modifier attached to a view that produces no rows — so it
/// would wait on a load that was waiting on it.
@Observable
@MainActor
final class ActiveMetaboliteEntryModel {
    private(set) var metabolites: [ActiveMetabolite] = []
    private var loadedSubstance: String?

    func load(substanceName: String) {
        guard loadedSubstance != substanceName else { return }
        loadedSubstance = substanceName
        let rows = SubstanceStore.shared.metabolism(forSubstanceName: substanceName)
        metabolites = SubstanceDetailModel.foldActiveMetabolites(from: rows)
    }
}

struct ActiveMetaboliteEntrySection: View {
    let metabolites: [ActiveMetabolite]
    let substance: Substance
    let accent: Color

    @Environment(\.appNavigator) private var navigator

    /// See ``ActiveMetabolite/earnsOwnSection(parentHalfLifeMinutes:parentDurationMinutes:)``
    /// — only a metabolite that outlives the dose gets this surface.
    private var shown: [ActiveMetabolite] {
        metabolites.filter {
            $0.earnsOwnSection(
                parentHalfLifeMinutes: substance.halfLifeMinutes,
                parentDurationMinutes: substance.longestRouteDurationMinutes,
            )
        }
    }

    var body: some View {
        if !shown.isEmpty {
            section
        }
    }

    private var section: some View {
        Section {
            ForEach(shown) { metabolite in
                ActiveMetaboliteCard(
                    metabolite: metabolite,
                    parentName: substance.displayTitle,
                    parentHalfLifeMinutes: substance.halfLifeMinutes,
                    accent: accent,
                    parentDurationMinutes: substance.longestRouteDurationMinutes,
                    onOpenSubstance: { navigator.push(.substance(name: $0)) },
                )
                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        } header: {
            Label("Also Active", systemImage: "arrow.trianglehead.branch")
        } footer: {
            Text("What your body makes from this dose. Not a measured level.")
        }
    }
}
