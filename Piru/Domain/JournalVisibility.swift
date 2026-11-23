import Foundation

/// Settings ▸ Journal ▸ Hidden Classes: whole substance classes kept out of
/// the Journal's history (Days, Timeline, Grouped, and the pushed timeline
/// screen). The entries stay recorded — Search, Insights, My Meds, Active Now
/// and exports read the full log.
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

    /// `entries` without the hidden classes, each resolved the way the Journal
    /// resolves a category (an unknown substance is `.other`). A dict hit per
    /// distinct substance over the batch projection, so the caller awaits
    /// `SubstanceStore.shared.ensureAllLoaded()` first.
    static func visible(_ entries: [DoseEntry], hiding hidden: Set<SubstanceCategory>) -> [DoseEntry] {
        guard !hidden.isEmpty else { return entries }
        var isHidden: [String: Bool] = [:]
        return entries.filter { entry in
            if let known = isHidden[entry.substance] { return !known }
            let hides = hidden.contains(SubstanceLibrary.lookup(entry.substance)?.category ?? .other)
            isHidden[entry.substance] = hides
            return !hides
        }
    }
}
