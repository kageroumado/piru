import Foundation

/// Settings ▸ Journal ▸ Hidden Classes: whole substance classes kept out of
/// the Journal's history (Days, Timeline, Grouped, and the pushed timeline
/// screen). The entries stay recorded — Search, Insights, My Meds, Active Now
/// and exports read the full log. A Quiet med is grouped under Supplements in
/// My Meds, so the Supplements switch also hides the doses logged from one,
/// whatever their class. The rule follows the dose, not the med: it is the
/// dose's own ``DoseEntry/isBackgroundMed``, stamped when it was logged, the
/// same flag the curves read. A med made Quiet later leaves its earlier doses
/// showing, and a med made not Quiet leaves its earlier doses hidden.
enum JournalVisibility {
    static let suite = AppIdentity.appGroup
    static let hidesSupplementsKey = "journalHidesSupplements"
    static let hidesMedsKey = "journalHidesMeds"

    /// The Library families each switch covers, by ``LibraryFamily/id``. Read
    /// from the taxonomy so a class that moves between families moves here too.
    private static let supplementFamilies: Set<String> = ["supplement"]
    private static let medFamilies: Set<String> = ["peptide", "mind", "pharmaceutical", "other"]

    static func hiddenCategories(supplements: Bool, meds: Bool) -> Set<SubstanceCategory> {
        var families = Set<String>()
        if supplements { families.formUnion(supplementFamilies) }
        if meds { families.formUnion(medFamilies) }
        guard !families.isEmpty else { return [] }
        return Set(LibraryFamily.all.filter { families.contains($0.id) }.flatMap(\.categories))
    }

    /// Whether `entry`, in `category`, is kept out of the Journal. `.supplement`
    /// is in `hidden` exactly when the Supplements switch is on, and a dose
    /// logged from a Quiet med counts as a supplement there.
    static func hides(_ entry: DoseEntry, category: SubstanceCategory, hiding hidden: Set<SubstanceCategory>) -> Bool {
        hidden.contains(category) || (hidden.contains(.supplement) && entry.isBackgroundMed)
    }

    /// `entries` without the hidden classes, each resolved the way the Journal
    /// resolves a category (an unknown substance is `.other`). A dict hit per
    /// distinct substance over the batch projection, so the caller awaits
    /// `SubstanceStore.shared.ensureAllLoaded()` first.
    static func visible(_ entries: [DoseEntry], hiding hidden: Set<SubstanceCategory>) -> [DoseEntry] {
        guard !hidden.isEmpty else { return entries }
        var categories: [String: SubstanceCategory] = [:]
        return entries.filter { entry in
            let category: SubstanceCategory
            if let known = categories[entry.substance] {
                category = known
            } else {
                category = SubstanceLibrary.lookup(entry.substance)?.category ?? .other
                categories[entry.substance] = category
            }
            return !hides(entry, category: category, hiding: hidden)
        }
    }
}
