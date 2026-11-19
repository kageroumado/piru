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
    ///
    /// `intervalDays` is the item's own N for ``DoseFrequency/everyNDays``
    /// (``DailyDoseItem/frequencyIntervalDays``); the fixed-offset cadences
    /// ignore it.
    static func isDue(
        startDate: Date, frequency: DoseFrequency, frequencyDays: [Int], intervalDays: Int, on date: Date,
    ) -> Bool {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let start = calendar.startOfDay(for: startDate)

        // Not due before the prescription start date
        guard day >= start else { return false }

        switch frequency {
        case .daily:
            return true

        case .everyOtherDay, .weekly, .biweekly, .everyNDays:
            let interval = frequency.intervalDays(custom: intervalDays) ?? 1
            let days = calendar.dateComponents([.day], from: start, to: day).day ?? 0
            return days.isMultiple(of: interval)

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

    /// A med saved as a combination product, by the names its doses carry. One
    /// pick logs an entry per component, each with ``DoseEntry/combinationName``
    /// set to `name`, so only the `lead` component's entry counts: taking the
    /// product twice reads as two doses, not two per component.
    struct ProductMed: Sendable, Hashable {
        let name: String
        /// The first component's staged (library-canonical) name.
        let lead: String
    }

    /// The App Group defaults key of the product-med map the app mirrors for
    /// its widgets and off-main scans: JSON of `[lowercased med name: [name,
    /// lead]]`, keyed by the product's name and its label. A JSON string
    /// because Android's `UserDefaults` stores no dictionaries.
    static let productMedMapKey = "piru.productMeds.v1"

    /// The product-med map as the mirror stores it.
    static func encodeProductMeds(_ map: [String: ProductMed]) -> String? {
        guard let data = try? JSONEncoder().encode(map.mapValues { [$0.name, $0.lead] }) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// The mirrored product meds, keyed by lowercased name. Read once per
    /// scan or timeline, never per entry.
    static func productMeds(in defaults: UserDefaults? = UserDefaults(suiteName: AppIdentity.appGroup)) -> [String: ProductMed] {
        guard let json = defaults?.string(forKey: productMedMapKey),
              let raw = try? JSONDecoder().decode([String: [String]].self, from: Data(json.utf8))
        else { return [:] }
        return raw.compactMapValues { pair in
            pair.count == 2 ? ProductMed(name: pair[0], lead: pair[1]) : nil
        }
    }

    /// ``matches(entryKey:entryName:entryRoute:itemKey:itemName:itemRoute:)``
    /// for a med that may be a combination product: when `itemName` names one
    /// in `products`, the dose must be that product's lead-component entry,
    /// whatever its route.
    static func matches(
        entryKey: String, entryName: String, entryCombination: String?, entryRoute: RouteOfAdministration,
        itemKey: String, itemName: String, itemRoute: RouteOfAdministration,
        products: [String: ProductMed],
    ) -> Bool {
        if let product = products[itemName.lowercased()] {
            return productMatches(entryName: entryName, entryCombination: entryCombination, product: product)
        }
        return matches(
            entryKey: entryKey, entryName: entryName, entryRoute: entryRoute,
            itemKey: itemKey, itemName: itemName, itemRoute: itemRoute,
        )
    }

    /// Whether an entry is a dose of `product`: its lead-component entry, or
    /// one entry under the product's own name (what the widget's Take button
    /// and the watch log, having no catalog to split it by).
    static func productMatches(entryName: String, entryCombination: String?, product: ProductMed) -> Bool {
        guard let entryCombination else { return entryName.caseInsensitiveCompare(product.name) == .orderedSame }
        guard entryCombination.caseInsensitiveCompare(product.name) == .orderedSame else { return false }
        return product.lead.caseInsensitiveCompare(entryName) == .orderedSame
    }

    /// Whether two substance references name the same drug: their identity
    /// keys agree, or their names do. This is the one identity join every
    /// "already taken today" surface runs — the quick-log chips, the adherence
    /// calendar, the widget, and the My Meds checklist's occurrence records —
    /// so a dose can never read as taken on one screen and missing on another.
    ///
    /// The name arm covers both ends of PSID resolution: it credits a dose
    /// logged before its substance resolved to an id, and a dose
    /// whose PSID family was re-pinned after the med was scheduled, where both
    /// sides carry ids that no longer agree.
    static func identityMatches(keyA: String?, nameA: String, keyB: String?, nameB: String) -> Bool {
        if let keyA, let keyB, !keyA.isEmpty, !keyB.isEmpty, keyA == keyB { return true }
        return nameA.lowercased() == nameB.lowercased()
    }
}
