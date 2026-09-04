import SwiftData
import SwiftUI

/// The adherence figures ``AdherenceView`` renders: the displayed month, today,
/// and the current streak.
///
/// The month pass groups a whole journal by day and calls
/// ``AdherenceCalculator/adherence(for:entries:dailyItems:)`` once per day, so it
/// runs on an explicit refresh — a dose logged, or the user paging the calendar —
/// rather than on every `body` evaluation.
@Observable
@MainActor
final class AdherenceModel {
    /// The displayed month, day by day, in calendar order.
    private(set) var monthAdherence: [DayAdherence] = []

    /// The same days keyed by `startOfDay` so each calendar cell is an O(1)
    /// lookup instead of a linear scan — the grid is O(days²) per body pass
    /// without it.
    private(set) var monthAdherenceByDay: [Date: DayAdherence] = [:]

    /// Today's adherence, computed independently of the displayed month so the
    /// Today strip survives browsing back through the calendar.
    private(set) var today: DayAdherence?

    private(set) var streak: Int = 0

    let calendar = Calendar.current

    /// Share of scheduled doses taken across the displayed month, counting only
    /// days that had something due and have already happened.
    var adherenceRate: Double {
        let actionable = monthAdherence.filter { $0.status != .noData && $0.date <= .now }
        let totalDue = actionable.reduce(0) { $0 + $1.totalCount }
        guard totalDue > 0 else { return 0 }
        let totalTaken = actionable.reduce(0) { $0 + $1.takenCount }
        return Double(totalTaken) / Double(totalDue)
    }

    func recompute(
        entries: [DoseEntry],
        dailyItems: [DailyDoseItem],
        month: Date,
        container: ModelContainer,
    ) async {
        recomputeMonth(entries: entries, dailyItems: dailyItems, month: month)
        today = AdherenceCalculator.adherence(for: .now, entries: entries, dailyItems: dailyItems)
        await refreshStreak(dailyItems: dailyItems, container: container)
    }

    func recomputeMonth(entries: [DoseEntry], dailyItems: [DailyDoseItem], month: Date) {
        var entriesByDay: [Date: [DoseEntry]] = [:]
        for entry in entries {
            let day = calendar.startOfDay(for: entry.timestamp)
            entriesByDay[day, default: []].append(entry)
        }

        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: month))!
        let range = calendar.range(of: .day, in: .month, for: start)!

        var data: [DayAdherence] = []
        var byDay: [Date: DayAdherence] = [:]
        for dayOffset in range {
            let date = calendar.date(byAdding: .day, value: dayOffset - 1, to: start)!
            let dayStart = calendar.startOfDay(for: date)
            let adherence = AdherenceCalculator.adherence(for: date, entries: entriesByDay[dayStart] ?? [], dailyItems: dailyItems)
            data.append(adherence)
            byDay[dayStart] = adherence
        }

        monthAdherence = data
        monthAdherenceByDay = byDay
    }

    private func refreshStreak(dailyItems: [DailyDoseItem], container: ModelContainer) async {
        guard !dailyItems.isEmpty else {
            streak = 0
            return
        }
        streak = await AdherenceStreakFetcher.currentStreak(container: container)
    }
}
