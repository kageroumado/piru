import Foundation

/// One dose as a Grouped-view row prints it: its own copy of the fields the
/// row reads and the id a tap opens, taken from the `DoseEntry` while the
/// Journal derives.
///
/// A row never holds the `DoseEntry`: the Journal's buckets outlive a commit
/// by one debounced regroup, and a deleted dose's attributes trap on read.
nonisolated struct JournalEntryRow: Identifiable, Hashable, Sendable {
    /// ``DoseEntry/id``.
    let id: UUID
    let timestamp: Date
    /// The name the dose was logged under.
    let substance: String
    let productName: String?
    let isomer: String?
    let releaseForm: String?
    let saltForm: String?
    let displayNameSnapshot: String?
    /// ``DoseEntry/amountDisplay``.
    let amountDisplay: String
    let unit: String
    let route: RouteOfAdministration

    @MainActor
    init(_ entry: DoseEntry) {
        id = entry.id
        timestamp = entry.timestamp
        substance = entry.substance
        productName = entry.productName
        isomer = entry.isomer
        releaseForm = entry.releaseForm
        saltForm = entry.saltForm
        displayNameSnapshot = entry.displayNameSnapshot
        amountDisplay = entry.amountDisplay
        unit = entry.unit
        route = entry.route
    }

    /// ``DoseEntry/namesAForm`` for this dose.
    var namesAForm: Bool {
        let namesIsomer = (isomer?.isEmpty == false) && isomer != "0"
        return namesIsomer || DoseEntry.namesUnmodeledForm(releaseForm: releaseForm)
    }

    /// The dose's title, as ``DoseTitle/resolve(for:)`` gives it for the entry.
    @MainActor
    var title: String {
        DoseTitle.resolve(
            substance: substance, productName: productName,
            namesForm: namesAForm, isomer: isomer, releaseForm: releaseForm,
            saltForm: saltForm, snapshot: displayNameSnapshot,
        )
    }
}
