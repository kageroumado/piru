import Foundation

/// The med-scheduling and dose↔med matching cores, shared between the app's
/// `AdherenceCalculator` (which delegates here) and the Today's Meds widget —
/// so the widget's notion of "due today" and "already taken" can never drift
/// from the app's.
///
/// `nonisolated` throughout: the app target builds with default MainActor
/// isolation and calls these from off-main scans; the widget target calls them
/// from timeline providers and App Intents.
nonisolated enum MedSchedule {
    /// Whether a scheduled item is due on `date`, given its frequency and start
    /// date. See ``DoseFrequency`` for the cadence semantics.
    static func isDue(startDate: Date, frequency: DoseFrequency, frequencyDays: [Int], on date: Date) -> Bool {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let start = calendar.startOfDay(for: startDate)

        // Not due before the prescription start date
        guard day >= start else { return false }

        switch frequency {
        case .daily:
            return true

        case .everyOtherDay:
            let days = calendar.dateComponents([.day], from: start, to: day).day ?? 0
            return days.isMultiple(of: 2)

        case .weekly:
            let days = calendar.dateComponents([.day], from: start, to: day).day ?? 0
            return days.isMultiple(of: 7)

        case .biweekly:
            let days = calendar.dateComponents([.day], from: start, to: day).day ?? 0
            return days.isMultiple(of: 14)

        case .monthly:
            let startDay = calendar.component(.day, from: start)
            let checkDay = calendar.component(.day, from: day)
            // Match same day-of-month, accounting for shorter months
            if checkDay == startDay { return true }
            // Handle months shorter than the start day (e.g., start=31, Feb=28)
            guard let daysInMonth = calendar.range(of: .day, in: .month, for: day)?.count else { return false }
            return startDay > daysInMonth && checkDay == daysInMonth

        case .specificDays:
            let weekday = calendar.component(.weekday, from: day)
            return frequencyDays.contains(weekday)
        }
    }

    /// Whether a logged dose satisfies a scheduled med: the substance identity
    /// AND the route must match (the same substance by another route is
    /// deliberately a plain journal entry, not adherence credit).
    static func matches(
        entryKey: String, entryName: String, entryRoute: RouteOfAdministration,
        itemKey: String, itemName: String, itemRoute: RouteOfAdministration,
    ) -> Bool {
        guard entryRoute == itemRoute else { return false }
        return identityMatches(keyA: entryKey, nameA: entryName, keyB: itemKey, nameB: itemName)
    }

    /// Whether two substance references name the same drug: their identity
    /// keys agree, or their names do. This is the one identity join every
    /// "already taken today" surface runs — the quick-log chips, the adherence
    /// calendar, the widget, and the My Meds checklist's occurrence records —
    /// so a dose can never read as taken on one screen and missing on another.
    ///
    /// The name arm is load-bearing on both ends of PSID resolution: it credits
    /// a legacy dose logged before its substance resolved to an id, and a dose
    /// whose PSID family was re-pinned after the med was scheduled, where both
    /// sides carry ids that no longer agree.
    static func identityMatches(keyA: String?, nameA: String, keyB: String?, nameB: String) -> Bool {
        if let keyA, let keyB, !keyA.isEmpty, !keyB.isEmpty, keyA == keyB { return true }
        return nameA.lowercased() == nameB.lowercased()
    }
}
