import SwiftUI

// The pair-generated counterpart to "Also Active".
//
// Cocaethylene and ethylphenidate are not metabolites of cocaine and
// methylphenidate — they are metabolites of *cocaine plus alcohol* and
// *methylphenidate plus alcohol*. So they are deliberately excluded from the
// per-substance fold (``SubstanceDetailModel/foldActiveMetabolites(from:)``
// skips every row carrying a `conditional_combination_id`) and surface only
// here, where the co-drug can be seen in the same session and named in the
// copy. One fact, one place; before this the two features disagreed on screen.

/// Resolves the combination metabolites forming around one logged dose, off the
/// render path.
///
/// The lookups are `SubstanceLibrary` reads (batch-cached, but still SQL on a
/// cold cache), so they run once from the owner's `.task` rather than per body
/// pass — the same reason ``ActiveMetaboliteEntryModel`` exists.
@Observable
@MainActor
final class CombinationMetaboliteEntryModel {
    private(set) var formations: [CombinationMetabolite.Formation] = []
    private var loadedEntry: UUID?

    func load(entry: DoseEntry) {
        guard loadedEntry != entry.id else { return }
        loadedEntry = entry.id
        guard let siblings = entry.session?.doses else {
            formations = []
            return
        }
        let focus = CombinationMetabolite.Onboard(
            name: entry.substance,
            interval: Self.onboardWindow(for: entry),
        )
        let peers = siblings
            .filter { $0.id != entry.id }
            .map {
                CombinationMetabolite.Onboard(name: $0.substance, interval: Self.onboardWindow(for: $0))
            }
        formations = CombinationMetabolite.formed(
            overlapping: focus, with: peers, catalog: SubstanceStore.shared.combinationMetabolites(),
        )
    }

    /// How long a dose counts as onboard, mirroring
    /// ``InteractionChecker/activeEntries(from:)``'s tiering exactly — acute
    /// duration first, then five half-lives (~97 % eliminated), then a 24 h
    /// fallback for a substance we carry no kinetics for. Reusing that ladder
    /// keeps "are these two in me at once" answering the same way here as it
    /// does for interactions, and it covers the forms that draw no curve at all
    /// (a Concerta dose resolves no ``ActiveSubstanceState``, but its
    /// methylphenidate is still onboard).
    static func onboardWindow(for entry: DoseEntry) -> DateInterval {
        let fallback: TimeInterval = 24 * 3_600
        guard let substance = SubstanceLibrary.lookup(entry.substance) else {
            return DateInterval(start: entry.timestamp, duration: fallback)
        }
        if let duration = substance.duration(for: entry.route), duration.estimatedTotalMinutes > 0 {
            return DateInterval(start: entry.timestamp, duration: duration.estimatedTotalMinutes * 60)
        }
        if let halfLife = substance.halfLifeMinutes, halfLife > 0 {
            return DateInterval(start: entry.timestamp, duration: halfLife * 5 * 60)
        }
        return DateInterval(start: entry.timestamp, duration: fallback)
    }
}

/// "Formed With" — the section under "Also Active" that names a species this
/// dose makes only because something else was onboard at the same time.
struct CombinationMetaboliteEntrySection: View {
    let formations: [CombinationMetabolite.Formation]

    var body: some View {
        if !formations.isEmpty {
            section
        }
    }

    private var section: some View {
        Section {
            ForEach(formations) { formation in
                CombinationMetaboliteBanner(formation: formation)
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            }
        } header: {
            Label("Formed With", systemImage: "arrow.triangle.merge")
        } footer: {
            Text("A third compound your body makes from this dose and something else in the session — not from either alone.")
        }
    }
}
