import Foundation

nonisolated enum AdherenceStatus {
    case complete
    case partial
    case missed
    case noData
}

struct ItemAdherence: Identifiable {
    let item: DailyDoseItem
    /// Dose slots satisfied vs expected today — a multi-time med expects one
    /// slot per reminder time, so "1 of 2" is representable per item.
    let takenCount: Int
    let totalCount: Int
    var taken: Bool {
        takenCount >= totalCount
    }

    var id: String {
        item.substance + String(item.sortOrder)
    }
}

struct DayAdherence: Identifiable {
    /// A day whose scheduled doses fall on both sides of noon, counted per
    /// half. A single circle can say "you missed one"; two halves say *which
    /// end of the day* went missing, which is the fact a two-a-day routine
    /// actually turns on.
    struct Halves: Equatable, Hashable {
        let morningTaken: Int
        let morningTotal: Int
        let eveningTaken: Int
        let eveningTotal: Int

        var morning: AdherenceStatus {
            Self.status(taken: morningTaken, total: morningTotal)
        }

        var evening: AdherenceStatus {
            Self.status(taken: eveningTaken, total: eveningTotal)
        }

        /// What a day reads as when its halves differ — which end of the day
        /// went unlogged, and whether the other end was logged in part — or
        /// `nil` when both halves stand the same, and the day's own status
        /// says it.
        var mismatchDescription: LocalizedStringResource? {
            switch (morning, evening) {
            case (.complete, .partial), (.complete, .missed): "Evening dose not logged"
            case (.partial, .complete), (.missed, .complete): "Morning dose not logged"
            case (.partial, .missed): "Morning partly logged, evening not logged"
            case (.missed, .partial): "Morning not logged, evening partly logged"
            default: nil
            }
        }

        private static func status(taken: Int, total: Int) -> AdherenceStatus {
            if total == 0 { return .noData }
            if taken >= total { return .complete }
            return taken > 0 ? .partial : .missed
        }
    }

    let date: Date
    let status: AdherenceStatus
    let takenCount: Int
    let totalCount: Int
    let items: [ItemAdherence]
    /// The day split at noon, or `nil` when the split would say nothing: a
    /// routine that lives entirely in one half of the day, or one whose meds
    /// carry no reminder times to place them by.
    var halves: Halves?
    var id: Date {
        date
    }
}

enum AdherenceCalculator {
    /// A dose satisfies a med when the substance identity AND the route match —
    /// the same
    /// substance by another route is deliberately a plain journal entry, not
    /// adherence credit. Identity joins by ``DoseEntry/identityKey`` with a
    /// lowercased-name fallback, so a PSID-resolved item still credits a
    /// name-only dose, and vice versa.
    ///
    /// A med saved as a combination product is satisfied by the product: one
    /// pick logs an entry per component, all carrying its name, so only the
    /// lead component's entry counts, and taking the product twice reads as
    /// two doses rather than two per component.
    ///
    /// `products` is ``CustomSubstanceStore/productMeds``; a loop over many
    /// entries reads it once and passes it in.
    static func entryMatches(
        entry: DoseEntry, item: DailyDoseItem,
        products: [String: MedSchedule.ProductMed] = CustomSubstanceStore.shared.productMeds,
    ) -> Bool {
        MedSchedule.matches(
            entryKey: entry.identityKey, entryName: entry.substance, entryCombination: entry.combinationName,
            entryRoute: entry.route,
            itemKey: item.identityKey, itemName: item.substance, itemRoute: item.route, products: products,
        )
    }

    /// Whether a prescription item is due on a given date, based on its frequency and start date.
    static func isDue(_ item: DailyDoseItem, on date: Date) -> Bool {
        isDue(
            startDate: item.startDate, frequency: item.frequency, frequencyDays: item.frequencyDays,
            intervalDays: item.frequencyIntervalDays, on: date,
        )
    }

    /// The scheduling core over plain values, shared by the `@Model` `isDue`
    /// above and the `Sendable`-snapshot streak scan. `nonisolated` so the
    /// off-main year pass can call it. Delegates to ``MedSchedule`` (Shared/)
    /// so the Today's Meds widget computes "due today" with the same rule.
    nonisolated static func isDue(
        startDate: Date, frequency: DoseFrequency, frequencyDays: [Int], intervalDays: Int, on date: Date,
    ) -> Bool {
        MedSchedule.isDue(
            startDate: startDate, frequency: frequency, frequencyDays: frequencyDays,
            intervalDays: intervalDays, on: date,
        )
    }

    /// The journal day each undated med's schedule opens on, for
    /// ``adherence(for:entries:dailyItems:calendar:boundaryHour:scheduleOpens:)``.
    ///
    /// A med saved in the app carries the day it was added as its start date.
    /// An imported one, or one saved before meds had a start date, carries
    /// ``Foundation/Date/distantPast``, and read literally that makes every day
    /// before its first dose a missed one. Such a med opens on the day of the
    /// first dose that satisfies it, or today when none has been logged: the
    /// days before that hold no record either way.
    ///
    /// `entries` is the whole journal. Meds with a start date are left out;
    /// their schedule opens where ``isDue(_:on:)`` already says.
    static func scheduleOpens(
        for dailyItems: [DailyDoseItem],
        entries: [DoseEntry],
        now: Date = .now,
        calendar: Calendar = .current,
        boundaryHour: Int = Calendar.sessionDayBoundaryHour,
    ) -> [ObjectIdentifier: Date] {
        let undated = dailyItems.filter { $0.startDate == .distantPast && !$0.isAsNeeded }
        guard !undated.isEmpty else { return [:] }
        let products = CustomSubstanceStore.shared.productMeds
        let today = calendar.journalDay(for: now, boundaryHour: boundaryHour)
        let matchers = undated.map { MedMatcher($0, products: products) }
        // One pass over the journal for every med, oldest end first: the
        // journal arrives newest first, so a med meets its first dose early
        // and every later dose is passed over on its timestamp alone. Among
        // doses at one instant, the one nearest the front of `entries` wins.
        var first: [(entry: DoseEntry, timestamp: Date)?] = Array(repeating: nil, count: matchers.count)
        for entry in entries.reversed() {
            let timestamp = entry.timestamp
            var dose = MedMatcher.Dose(entry)
            for index in matchers.indices {
                if let current = first[index], current.timestamp < timestamp { continue }
                if matchers[index].matches(&dose) {
                    first[index] = (entry, timestamp)
                }
            }
        }
        var opens: [ObjectIdentifier: Date] = [:]
        for (item, found) in zip(undated, first) {
            let firstDay = found?.entry.journalDay(in: calendar, boundaryHour: boundaryHour)
            opens[ObjectIdentifier(item)] = min(firstDay ?? today, today)
        }
        return opens
    }

    /// A med's side of ``entryMatches(entry:item:products:)``, read off the
    /// `@Model` once for a scan over a whole journal: every `DailyDoseItem`
    /// property is a SwiftData getter, and reading them per dose costs more
    /// than the comparison itself. Matches exactly as ``MedSchedule/matches(entryKey:entryName:entryCombination:entryRoute:itemKey:itemName:itemRoute:products:)``.
    struct MedMatcher {
        private let product: MedSchedule.ProductMed?
        private let key: String
        private let name: String
        private let route: RouteOfAdministration

        init(_ item: DailyDoseItem, products: [String: MedSchedule.ProductMed]) {
            name = item.substance
            product = products[name.lowercased()]
            key = item.identityKey
            route = item.route
        }

        /// A dose's side, each field read from the `@Model` the first time a
        /// med asks for it.
        struct Dose {
            let entry: DoseEntry
            private var routeValue: RouteOfAdministration?
            private var nameValue: String?
            private var keyValue: String?

            init(_ entry: DoseEntry) {
                self.entry = entry
            }

            mutating func route() -> RouteOfAdministration {
                if let routeValue { return routeValue }
                let value = entry.route
                routeValue = value
                return value
            }

            mutating func name() -> String {
                if let nameValue { return nameValue }
                let value = entry.substance
                nameValue = value
                return value
            }

            mutating func key() -> String {
                if let keyValue { return keyValue }
                let value = entry.identityKey
                keyValue = value
                return value
            }
        }

        func matches(_ dose: inout Dose) -> Bool {
            if let product {
                return MedSchedule.productMatches(
                    entryName: dose.name(), entryCombination: dose.entry.combinationName, product: product,
                )
            }
            guard dose.route() == route else { return false }
            return MedSchedule.identityMatches(keyA: dose.key(), nameA: dose.name(), keyB: key, nameB: name)
        }

        func matches(_ entry: DoseEntry) -> Bool {
            var dose = Dose(entry)
            return matches(&dose)
        }
    }

    /// One journal day's adherence. `date` names the day (any instant on its
    /// calendar date; pass ``Foundation/Calendar/journalDay(for:boundaryHour:)``
    /// of an instant to ask about the day that instant falls in), and a dose
    /// counts toward it when its own journal day, read on the clock of the zone
    /// it was logged in, is that day.
    ///
    /// `scheduleOpens` is ``scheduleOpens(for:entries:now:calendar:boundaryHour:)``:
    /// a med listed there is due only from its day on.
    static func adherence(
        for date: Date,
        entries: [DoseEntry],
        dailyItems: [DailyDoseItem],
        calendar: Calendar = .current,
        boundaryHour: Int = Calendar.sessionDayBoundaryHour,
        scheduleOpens: [ObjectIdentifier: Date] = [:],
    ) -> DayAdherence {
        let day = calendar.startOfDay(for: date)
        let dayEntries = entries.filter { $0.journalDay(in: calendar, boundaryHour: boundaryHour) == day }

        // Filter to only items due on this date. As-needed (PRN) meds carry
        // no expectation and are never counted (or marked missed).
        let dueItems = dailyItems.filter { item in
            guard !item.isAsNeeded, isDue(item, on: day) else { return false }
            guard let opens = scheduleOpens[ObjectIdentifier(item)] else { return true }
            return day >= opens
        }

        guard !dueItems.isEmpty else {
            return DayAdherence(date: date, status: .noData, takenCount: 0, totalCount: 0, items: [])
        }

        var itemResults: [ItemAdherence] = []
        var matched = 0
        var expected = 0
        // The same counting again, split at noon. It stays a separate tally
        // rather than a sum of halves: an item with no reminder times has a
        // slot but no hour to file it under, and one such item takes the whole
        // day's split away (see `splittable` below) without disturbing the
        // headline count.
        var morningTaken = 0, morningTotal = 0, eveningTaken = 0, eveningTotal = 0
        var splittable = true
        let products = CustomSubstanceStore.shared.productMeds
        for item in dueItems {
            // A multi-time med expects one dose slot per reminder time.
            let itemExpected = max(1, item.reminderTimesMinutes.count)
            let matcher = MedMatcher(item, products: products)
            let itemDoses = dayEntries.filter { matcher.matches($0) }
            let hits = itemDoses.count
            let itemTaken = min(hits, itemExpected)
            itemResults.append(ItemAdherence(item: item, takenCount: itemTaken, totalCount: itemExpected))
            matched += itemTaken
            expected += itemExpected

            // Both sides are read on the journal-day scale, so with a 4 AM
            // start a 01:00 dose or slot is the end of the evening, and each
            // dose by the clock of the zone it was logged in. A dose counts by
            // when it was taken even when it was checked off for a slot
            // (``DoseEntry/medSlotMinutes``): an 8:00 dose taken at 15:00 is
            // not an on-time morning dose.
            let times = item.reminderTimesMinutes
            guard !times.isEmpty else { splittable = false; continue }
            let morningSlots = times.count { Calendar.journalMinutes(ofSlot: $0, boundaryHour: boundaryHour) < noonMinutes }
            let eveningSlots = times.count - morningSlots
            let morningHits = itemDoses.count { $0.journalMinutes(in: calendar, boundaryHour: boundaryHour) < noonMinutes }
            morningTotal += morningSlots
            eveningTotal += eveningSlots
            morningTaken += min(morningHits, morningSlots)
            eveningTaken += min(itemDoses.count - morningHits, eveningSlots)
        }

        let status: AdherenceStatus = if matched == expected {
            .complete
        } else if matched > 0 {
            .partial
        } else {
            .missed
        }

        let halves: DayAdherence.Halves? = splittable && morningTotal > 0 && eveningTotal > 0
            ? DayAdherence.Halves(
                morningTaken: morningTaken, morningTotal: morningTotal,
                eveningTaken: eveningTaken, eveningTotal: eveningTotal,
            )
            : nil

        return DayAdherence(
            date: date, status: status, takenCount: matched, totalCount: expected,
            items: itemResults, halves: halves,
        )
    }

    /// Standard defaults: whether the adherence calendar draws a day's morning
    /// and evening as separate halves. Off, each day is one circle and a dose
    /// logged at any hour counts toward it, which suits logging after the fact.
    static let splitsDayKey = "adherenceSplitsDay"

    /// Noon of the journal day, as minutes from the midnight that opens it —
    /// the seam the day's halves are cut at. A local clock hour, not a claim
    /// about anyone's morning.
    static let noonMinutes = 12 * 60

    /// The moment a reminder slot (minutes from midnight) falls at in the
    /// journal day named `day` — what a dose logged "at its slot time" is
    /// stamped with, so a morning dose recorded in the afternoon still lands in
    /// the morning half. Set by wall-clock hour rather than added as seconds
    /// from midnight, which is an hour off on a daylight-saving day.
    static func slotDate(
        minutes: Int, on day: Date, calendar: Calendar = .current,
        boundaryHour: Int = Calendar.sessionDayBoundaryHour,
    ) -> Date {
        calendar.date(ofSlot: minutes, inJournalDay: day, boundaryHour: boundaryHour)
    }

    static func currentStreak(adherenceData: [DayAdherence], now: Date = .now) -> Int {
        streak(fromDays: adherenceData.map { (date: $0.date, status: $0.status) }, now: now)
    }

    /// The streak walk over `(date, status)` pairs keyed by journal day — the
    /// part of the adherence computation `currentStreak(adherenceData:)`
    /// actually reads. Factored out (and `nonisolated`) so the off-main year
    /// scan shares the exact same logic.
    nonisolated static func streak(
        fromDays days: [(date: Date, status: AdherenceStatus)],
        now: Date = .now,
        boundaryHour: Int = Calendar.sessionDayBoundaryHour,
    ) -> Int {
        let calendar = Calendar.current
        let today = calendar.journalDay(for: now, boundaryHour: boundaryHour)

        // Filter to only days that had items due (skip .noData days)
        let actionable = days
            .filter { $0.status != .noData }
            .sorted { $0.date > $1.date }

        let past = actionable.filter { $0.date < today }
        var streak = 0

        // Walk backwards through actionable days — a .missed breaks the streak,
        // but date gaps are OK if the gap days were all .noData
        var cursor = today
        for day in past {
            // Verify no missed days exist between cursor and this day
            let dayStart = calendar.startOfDay(for: day.date)
            // Check all calendar days between this day and cursor for missed items
            guard var check = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            var gapOk = true
            while check > dayStart {
                if let gapDay = days.first(where: { calendar.isDate($0.date, inSameDayAs: check) }),
                   gapDay.status == .missed {
                    gapOk = false
                    break
                }
                guard let previous = calendar.date(byAdding: .day, value: -1, to: check) else {
                    gapOk = false
                    break
                }
                check = previous
            }
            guard gapOk else { break }

            guard day.status == .complete || day.status == .partial else { break }
            streak += 1
            cursor = dayStart
        }

        if let todayData = actionable.first(where: { calendar.isDate($0.date, inSameDayAs: today) }),
           todayData.status == .complete || todayData.status == .partial {
            streak += 1
        }

        return streak
    }

    // MARK: - Off-main year scan (Sendable snapshots)

    /// Sendable snapshot of a dose's matching fields for the off-main streak scan.
    struct EntrySnapshot {
        let substance: String
        let identityKey: String
        let route: RouteOfAdministration
        let timestamp: Date
        /// ``DoseEntry/combinationName``: the product this dose was one component of.
        var combinationName: String?
        /// ``DoseEntry/timeZoneIdentifier``: the zone the dose was logged in.
        var timeZoneIdentifier: String?
    }

    /// Sendable snapshot of a daily item's scheduling/matching fields.
    struct DailyItemSnapshot {
        let substance: String
        let identityKey: String
        let route: RouteOfAdministration
        /// `max(1, reminderTimesMinutes.count)` — dose slots expected per due day.
        let expectedPerDay: Int
        let isAsNeeded: Bool
        let startDate: Date
        let frequency: DoseFrequency
        let frequencyDays: [Int]
        /// ``DailyDoseItem/frequencyIntervalDays``, read for `.everyNDays`.
        var intervalDays: Int = DoseFrequency.defaultIntervalDays
        /// The combination product this med names, resolved when the snapshot
        /// is taken (``MedSchedule/productMeds(in:)``).
        var product: MedSchedule.ProductMed?
    }

    /// Per-day adherence **status** over Sendable snapshots — all the streak
    /// needs. Mirrors ``adherence(for:entries:dailyItems:)``'s status derivation
    /// without materializing the non-`Sendable` `DayAdherence`/`ItemAdherence`.
    nonisolated static func dayStatus(
        for date: Date, entries: [EntrySnapshot], items: [DailyItemSnapshot],
        boundaryHour: Int = Calendar.sessionDayBoundaryHour,
    ) -> AdherenceStatus {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let dayEntries = entries.filter {
            calendar.journalDay(for: $0.timestamp, loggedIn: $0.timeZoneIdentifier, boundaryHour: boundaryHour) == day
        }
        return dayStatus(for: day, dayEntries: dayEntries, items: items)
    }

    /// ``dayStatus(for:entries:items:)`` over entries already narrowed to the
    /// day — the year walk buckets once and calls this per day, instead of
    /// scanning the whole year's entries 366 times.
    nonisolated static func dayStatus(for date: Date, dayEntries: [EntrySnapshot], items: [DailyItemSnapshot]) -> AdherenceStatus {
        let dueItems = items.filter {
            !$0.isAsNeeded && isDue(
                startDate: $0.startDate, frequency: $0.frequency, frequencyDays: $0.frequencyDays,
                intervalDays: $0.intervalDays, on: date,
            )
        }
        guard !dueItems.isEmpty else { return .noData }

        var matched = 0
        var expected = 0
        for item in dueItems {
            let hits = dayEntries.count { entry in
                if let product = item.product {
                    return MedSchedule.productMatches(
                        entryName: entry.substance, entryCombination: entry.combinationName, product: product,
                    )
                }
                return MedSchedule.matches(
                    entryKey: entry.identityKey, entryName: entry.substance, entryRoute: entry.route,
                    itemKey: item.identityKey, itemName: item.substance, itemRoute: item.route,
                )
            }
            // Clamped here, not just at snapshot construction — a zero
            // expectation would otherwise make `matched == expected` read as
            // a false `.complete`.
            let itemExpected = max(1, item.expectedPerDay)
            matched += min(hits, itemExpected)
            expected += itemExpected
        }
        if matched == expected { return .complete }
        return matched > 0 ? .partial : .missed
    }

    /// Current streak over a span of days (default the past year), computed
    /// **off the main actor** from Sendable snapshots — the heavy part of the
    /// Insights adherence card. Equivalent to building each day's
    /// ``adherence(for:entries:dailyItems:)`` and calling
    /// ``currentStreak(adherenceData:)``, but without touching `@Model`s.
    nonisolated static func currentStreak(
        spanningDays dayCount: Int,
        endingAt now: Date,
        entries: [EntrySnapshot],
        items: [DailyItemSnapshot],
        boundaryHour: Int = Calendar.sessionDayBoundaryHour,
    ) -> Int {
        let calendar = Calendar.current
        let today = calendar.journalDay(for: now, boundaryHour: boundaryHour)
        guard let start = calendar.date(byAdding: .day, value: -dayCount, to: today) else { return 0 }
        let entriesByDay = Dictionary(grouping: entries) {
            calendar.journalDay(for: $0.timestamp, loggedIn: $0.timeZoneIdentifier, boundaryHour: boundaryHour)
        }
        var days: [(date: Date, status: AdherenceStatus)] = []
        var day = calendar.startOfDay(for: start)
        while day <= today {
            days.append((date: day, status: dayStatus(for: day, dayEntries: entriesByDay[day] ?? [], items: items)))
            day = calendar.journalDay(after: day)
        }
        return streak(fromDays: days, now: now, boundaryHour: boundaryHour)
    }
}
