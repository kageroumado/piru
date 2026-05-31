import Foundation

enum AdherenceStatus {
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
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let start = calendar.startOfDay(for: item.startDate)

        // Not due before the prescription start date
        guard day >= start else { return false }

        switch item.frequency {
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
            return item.frequencyDays.contains(weekday)
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
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        // Filter to only days that had items due (skip .noData days)
        let actionable = adherenceData
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
                if let gapDay = adherenceData.first(where: { calendar.isDate($0.date, inSameDayAs: check) }),
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
}
