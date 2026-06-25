import Foundation

nonisolated enum AdherenceStatus {
    case complete
    case partial
    case missed
    case noData
}

struct ItemAdherence: Identifiable {
    let item: DailyDoseItem
    let taken: Bool
    var id: String {
        item.substance + String(item.sortOrder)
    }
}

struct DayAdherence: Identifiable {
    let date: Date
    let status: AdherenceStatus
    let takenCount: Int
    let totalCount: Int
    let items: [ItemAdherence]
    var id: Date {
        date
    }
}

enum AdherenceCalculator {
    static func entryMatches(entry: DoseEntry, item: DailyDoseItem) -> Bool {
        entry.substance.lowercased() == item.substance.lowercased()
    }

    /// Whether a prescription item is due on a given date, based on its frequency and start date.
    static func isDue(_ item: DailyDoseItem, on date: Date) -> Bool {
        isDue(startDate: item.startDate, frequency: item.frequency, frequencyDays: item.frequencyDays, on: date)
    }

    /// The scheduling core over plain values, shared by the `@Model` `isDue`
    /// above and the `Sendable`-snapshot streak scan. `nonisolated` so the
    /// off-main year pass can call it.
    nonisolated static func isDue(startDate: Date, frequency: DoseFrequency, frequencyDays: [Int], on date: Date) -> Bool {
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
            return days % 2 == 0

        case .weekly:
            let weeks = calendar.dateComponents([.day], from: start, to: day).day ?? 0
            return weeks % 7 == 0

        case .biweekly:
            let days = calendar.dateComponents([.day], from: start, to: day).day ?? 0
            return days % 14 == 0

        case .monthly:
            let startDay = calendar.component(.day, from: start)
            let checkDay = calendar.component(.day, from: day)
            // Match same day-of-month, accounting for shorter months
            if checkDay == startDay { return true }
            // Handle months shorter than the start day (e.g., start=31, Feb=28)
            let daysInMonth = calendar.range(of: .day, in: .month, for: day)!.count
            return startDay > daysInMonth && checkDay == daysInMonth

        case .specificDays:
            let weekday = calendar.component(.weekday, from: day)
            return frequencyDays.contains(weekday)
        }
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

        // Filter to only items due on this date
        let dueItems = dailyItems.filter { isDue($0, on: date) }

        guard !dueItems.isEmpty else {
            return DayAdherence(date: date, status: .noData, takenCount: 0, totalCount: 0, items: [])
        }

        var itemResults: [ItemAdherence] = []
        var matched = 0
        for item in dueItems {
            let taken = dayEntries.contains { entryMatches(entry: $0, item: item) }
            itemResults.append(ItemAdherence(item: item, taken: taken))
            if taken { matched += 1 }
        }

        let status: AdherenceStatus = if matched == dueItems.count {
            .complete
        } else if matched > 0 {
            .partial
        } else {
            .missed
        }

        return DayAdherence(date: date, status: status, takenCount: matched, totalCount: dueItems.count, items: itemResults)
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
            var check = calendar.date(byAdding: .day, value: -1, to: cursor)!
            var gapOk = true
            while check > dayStart {
                if let gapDay = days.first(where: { calendar.isDate($0.date, inSameDayAs: check) }),
                   gapDay.status == .missed {
                    gapOk = false
                    break
                }
                check = calendar.date(byAdding: .day, value: -1, to: check)!
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
        let timestamp: Date
    }

    /// Sendable snapshot of a daily item's scheduling/matching fields.
    struct DailyItemSnapshot {
        let substance: String
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

        let dueItems = items.filter { isDue(startDate: $0.startDate, frequency: $0.frequency, frequencyDays: $0.frequencyDays, on: date) }
        guard !dueItems.isEmpty else { return .noData }

        var matched = 0
        for item in dueItems where dayEntries.contains(where: { $0.substance.lowercased() == item.substance.lowercased() }) {
            matched += 1
        }
        if matched == dueItems.count { return .complete }
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
        var days: [(date: Date, status: AdherenceStatus)] = []
        var day = start
        while day <= now {
            days.append((date: day, status: dayStatus(for: day, entries: entries, items: items)))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return streak(fromDays: days)
    }
}
