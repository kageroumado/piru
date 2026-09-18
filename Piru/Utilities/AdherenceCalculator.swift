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
    /// A dose satisfies a med when the substance identity AND the route match
    /// (Specs/meds-reminders-redesign.md, boundary semantics) — the same
    /// substance by another route is deliberately a plain journal entry, not
    /// adherence credit. Identity joins by ``DoseEntry/identityKey`` with a
    /// lowercased-name fallback, so a PSID-resolved item still credits a
    /// legacy name-only dose (and vice versa) exactly as the old name join did.
    static func entryMatches(entry: DoseEntry, item: DailyDoseItem) -> Bool {
        matches(
            entryKey: entry.identityKey, entryName: entry.substance, entryRoute: entry.route,
            itemKey: item.identityKey, itemName: item.substance, itemRoute: item.route,
        )
    }

    /// The matching core over plain values, shared by the `@Model`
    /// ``entryMatches(entry:item:)`` and the `Sendable`-snapshot streak scan.
    /// Delegates to ``MedSchedule`` (Shared/) so the Today's Meds widget joins
    /// doses to meds with the exact same rule.
    nonisolated static func matches(
        entryKey: String, entryName: String, entryRoute: RouteOfAdministration,
        itemKey: String, itemName: String, itemRoute: RouteOfAdministration,
    ) -> Bool {
        MedSchedule.matches(
            entryKey: entryKey, entryName: entryName, entryRoute: entryRoute,
            itemKey: itemKey, itemName: itemName, itemRoute: itemRoute,
        )
    }

    /// Whether a prescription item is due on a given date, based on its frequency and start date.
    static func isDue(_ item: DailyDoseItem, on date: Date) -> Bool {
        isDue(startDate: item.startDate, frequency: item.frequency, frequencyDays: item.frequencyDays, on: date)
    }

    /// The scheduling core over plain values, shared by the `@Model` `isDue`
    /// above and the `Sendable`-snapshot streak scan. `nonisolated` so the
    /// off-main year pass can call it. Delegates to ``MedSchedule`` (Shared/)
    /// so the Today's Meds widget computes "due today" with the same rule.
    nonisolated static func isDue(startDate: Date, frequency: DoseFrequency, frequencyDays: [Int], on date: Date) -> Bool {
        MedSchedule.isDue(startDate: startDate, frequency: frequency, frequencyDays: frequencyDays, on: date)
    }

    static func adherence(
        for date: Date,
        entries: [DoseEntry],
        dailyItems: [DailyDoseItem],
    ) -> DayAdherence {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        let dayEntries = entries.filter { $0.timestamp >= dayStart && $0.timestamp < dayEnd }

        // Filter to only items due on this date. As-needed (PRN) meds carry
        // no expectation and are never counted (or marked missed).
        let dueItems = dailyItems.filter { !$0.isAsNeeded && isDue($0, on: date) }

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
        for item in dueItems {
            // A multi-time med expects one dose slot per reminder time.
            let itemExpected = max(1, item.reminderTimesMinutes.count)
            let hits = dayEntries.count { entryMatches(entry: $0, item: item) }
            let itemTaken = min(hits, itemExpected)
            itemResults.append(ItemAdherence(item: item, takenCount: itemTaken, totalCount: itemExpected))
            matched += itemTaken
            expected += itemExpected

            let times = item.reminderTimesMinutes
            guard !times.isEmpty else { splittable = false; continue }
            let morningSlots = times.count { $0 < noonMinutes }
            let eveningSlots = times.count - morningSlots
            let itemDoses = dayEntries.filter { entryMatches(entry: $0, item: item) }
            let morningHits = itemDoses.count { minutesOfDay($0.timestamp, calendar: calendar) < noonMinutes }
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

    /// Noon, as minutes from midnight — the seam the day's halves are cut at.
    /// A local clock hour, not a claim about anyone's morning.
    static let noonMinutes = 12 * 60

    private static func minutesOfDay(_ date: Date, calendar: Calendar) -> Int {
        calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }

    static func currentStreak(adherenceData: [DayAdherence]) -> Int {
        streak(fromDays: adherenceData.map { (date: $0.date, status: $0.status) })
    }

    /// The streak walk over `(date, status)` pairs — the part of the adherence
    /// computation `currentStreak(adherenceData:)` actually reads. Factored out
    /// (and `nonisolated`) so the off-main year scan shares the exact same logic.
    nonisolated static func streak(fromDays days: [(date: Date, status: AdherenceStatus)]) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

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
    }

    /// Per-day adherence **status** over Sendable snapshots — all the streak
    /// needs. Mirrors ``adherence(for:entries:dailyItems:)``'s status derivation
    /// without materializing the non-`Sendable` `DayAdherence`/`ItemAdherence`.
    nonisolated static func dayStatus(for date: Date, entries: [EntrySnapshot], items: [DailyItemSnapshot]) -> AdherenceStatus {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        let dayEntries = entries.filter { $0.timestamp >= dayStart && $0.timestamp < dayEnd }
        return dayStatus(for: date, dayEntries: dayEntries, items: items)
    }

    /// ``dayStatus(for:entries:items:)`` over entries already narrowed to the
    /// day — the year walk buckets once and calls this per day, instead of
    /// scanning the whole year's entries 366 times.
    nonisolated static func dayStatus(for date: Date, dayEntries: [EntrySnapshot], items: [DailyItemSnapshot]) -> AdherenceStatus {
        let dueItems = items.filter {
            !$0.isAsNeeded && isDue(startDate: $0.startDate, frequency: $0.frequency, frequencyDays: $0.frequencyDays, on: date)
        }
        guard !dueItems.isEmpty else { return .noData }

        var matched = 0
        var expected = 0
        for item in dueItems {
            let hits = dayEntries.count {
                matches(
                    entryKey: $0.identityKey, entryName: $0.substance, entryRoute: $0.route,
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
    ) -> Int {
        let calendar = Calendar.current
        guard let start = calendar.date(byAdding: .day, value: -dayCount, to: now) else { return 0 }
        let entriesByDay = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.timestamp) }
        var days: [(date: Date, status: AdherenceStatus)] = []
        var day = start
        while day <= now {
            let dayEntries = entriesByDay[calendar.startOfDay(for: day)] ?? []
            days.append((date: day, status: dayStatus(for: day, dayEntries: dayEntries, items: items)))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return streak(fromDays: days)
    }
}
