import Foundation

extension StagedDose {
    /// The journal entry this staged dose commits as: the quick-log tray's Log
    /// button and the Log Dose shortcut both write through here.
    ///
    /// The tray-wide values come in as parameters, `nil` where the caller has
    /// none. `meal` lands on oral doses only, the stomach an oral dose waits
    /// in. Tags are trimmed and blank ones dropped. An unknown amount commits
    /// as ``DoseEntry/isUnknownDose`` with amount 0 and keeps no by-volume
    /// detail (volume, strength, drink name), since those describe an amount.
    func makeEntry(
        timestamp: Date,
        tags: [String] = [],
        meal: MealState? = nil,
        location: PickedLocation? = nil,
    ) -> DoseEntry {
        DoseEntry(
            substance: substanceName,
            amount: isUnknownAmount ? 0 : totalAmount,
            unit: unit,
            route: route,
            saltForm: saltForm,
            isomer: isomer,
            releaseForm: releaseForm,
            productName: productName,
            substanceUID: substanceUID,
            displayNameSnapshot: displayNameSnapshot,
            timestamp: timestamp,
            notes: note.isEmpty ? nil : note,
            tags: Self.cleanedTags(tags),
            isBackgroundMed: isBackgroundMed,
            locationName: location?.name,
            latitude: location?.latitude,
            longitude: location?.longitude,
            hadGrapefruit: hadGrapefruit ? true : nil,
            meal: route == .oral ? meal : nil,
            isUnknownDose: isUnknownAmount,
            volumeML: isUnknownAmount ? nil : volumeML,
            abv: isUnknownAmount ? nil : abv,
            drinkName: isUnknownAmount ? nil : drinkName,
            combinationName: combinationName,
            injectionSite: InjectionSite.applies(to: route) ? injectionSite : nil,
        )
    }

    /// `tags` trimmed of surrounding spaces, blanks dropped, order kept.
    static func cleanedTags(_ tags: [String]) -> [String] {
        tags.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
