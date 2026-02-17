import Foundation

enum AdherenceStatus {
    case complete
    case partial
    case missed
    case noData
}

struct DayAdherence: Identifiable {
    let date: Date
    let status: AdherenceStatus
    let takenCount: Int
    let totalCount: Int
    var id: Date { date }
}

enum AdherenceCalculator {

    static func entryMatches(entry: DoseEntry, item: DailyDoseItem) -> Bool {
        entry.substance.lowercased() == item.substance.lowercased()
    }

    static func adherence(
        for date: Date,
        entries: [DoseEntry],
        dailyItems: [DailyDoseItem]
    ) -> DayAdherence {
        guard !dailyItems.isEmpty else {
            return DayAdherence(date: date, status: .noData, takenCount: 0, totalCount: 0)
        }

        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        let dayEntries = entries.filter { $0.timestamp >= dayStart && $0.timestamp < dayEnd }

        var matched = 0
        for item in dailyItems {
            if dayEntries.contains(where: { entryMatches(entry: $0, item: item) }) {
                matched += 1
            }
        }

        let status: AdherenceStatus
        if matched == dailyItems.count {
            status = .complete
        } else if matched > 0 {
            status = .partial
        } else {
            status = .missed
        }

        return DayAdherence(date: date, status: status, takenCount: matched, totalCount: dailyItems.count)
    }

    static func currentStreak(adherenceData: [DayAdherence]) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let sorted = adherenceData
            .filter { $0.date < today }
            .sorted { $0.date > $1.date }

        var streak = 0
        for (index, day) in sorted.enumerated() {
            let expectedDate = calendar.date(byAdding: .day, value: -(index + 1), to: today)!
            guard calendar.isDate(day.date, inSameDayAs: expectedDate),
                  day.status == .complete || day.status == .partial else { break }
            streak += 1
        }

        if let todayData = adherenceData.first(where: { calendar.isDate($0.date, inSameDayAs: today) }),
           todayData.status == .complete || todayData.status == .partial {
            streak += 1
        }

        return streak
    }
}
