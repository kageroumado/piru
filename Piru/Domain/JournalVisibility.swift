import Foundation

/// Settings ▸ Journal ▸ Hidden Classes: whole substance classes kept out of
/// the Journal's history (Days, Timeline, Grouped, and the pushed timeline
/// screen). The entries stay recorded — Search, Insights, My Meds, Active Now
/// and exports read the full log. A Quiet med is grouped under Supplements in
/// My Meds, so the Supplements switch also hides every dose of a med that is
/// Quiet now, whatever its class. It is the med's state, read at the time: a
/// dose logged before the med went Quiet is hidden with it, and comes back when
/// the med stops being Quiet. The dose's own ``DoseEntry/isBackgroundMed`` is
/// not read here — it keeps the graphs and sessions as logged.
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

    /// The identities (``DailyDoseItem/identityKey``) of the My Meds items that
    /// are Quiet now, when the Supplements switch is on; empty otherwise.
    static func hiddenQuietMeds(supplements: Bool, items: [DailyDoseItem]) -> Set<String> {
        guard supplements else { return [] }
        return Set(items.filter(\.isQuiet).map(\.identityKey))
    }

    /// Whether `entry`, in `category`, is kept out of the Journal: its class is
    /// hidden, or it is a dose of a Quiet med (`quietMeds`, matched on
    /// ``DoseEntry/identityKey``).
    static func hides(_ entry: DoseEntry, category: SubstanceCategory, hiding hidden: Set<SubstanceCategory>, quietMeds: Set<String> = []) -> Bool {
        hidden.contains(category) || (!quietMeds.isEmpty && quietMeds.contains(entry.identityKey))
    }

    /// `entries` without the hidden classes, each resolved the way the Journal
    /// resolves a category (an unknown substance is `.other`). A dict hit per
    /// distinct substance over the batch projection, so the caller awaits
    /// `SubstanceStore.shared.ensureAllLoaded()` first.
    static func visible(_ entries: [DoseEntry], hiding hidden: Set<SubstanceCategory>, quietMeds: Set<String> = []) -> [DoseEntry] {
        guard !hidden.isEmpty || !quietMeds.isEmpty else { return entries }
        var categories: [String: SubstanceCategory] = [:]
        return entries.filter { entry in
            let category: SubstanceCategory
            if let known = categories[entry.substance] {
                category = known
            } else {
                category = SubstanceLibrary.lookup(entry.substance)?.category ?? .other
                categories[entry.substance] = category
            }
            return !hides(entry, category: category, hiding: hidden, quietMeds: quietMeds)
        }
    }
}
