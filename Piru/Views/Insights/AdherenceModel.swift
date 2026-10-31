import SwiftData
import SwiftUI

/// The adherence figures ``AdherenceView`` renders: the displayed month and
/// today.
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

    /// The same days keyed by journal day (the start of the calendar date
    /// each is named after) so each calendar cell is an O(1)
    /// lookup instead of a linear scan — the grid is O(days²) per body pass
    /// without it.
    private(set) var monthAdherenceByDay: [Date: DayAdherence] = [:]

    /// Today's adherence, computed independently of the displayed month so the
    /// Today strip survives browsing back through the calendar.
    private(set) var today: DayAdherence?

    let calendar = Calendar.current

    /// The displayed month's days that had something due and have already
    /// happened — the only ones a count can honestly be taken over.
    private var actionableDays: [DayAdherence] {
        let today = calendar.journalDay(for: .now)
        return monthAdherence.filter { $0.status != .noData && $0.date <= today }
    }

    /// Scheduled doses taken so far this month, and how many were scheduled.
    var monthDosesTaken: Int {
        actionableDays.reduce(0) { $0 + $1.takenCount }
    }

    var monthDosesDue: Int {
        actionableDays.reduce(0) { $0 + $1.totalCount }
    }

    func recompute(entries: [DoseEntry], dailyItems: [DailyDoseItem], month: Date) {
        recomputeMonth(entries: entries, dailyItems: dailyItems, month: month)
        let boundaryHour = Calendar.sessionDayBoundaryHour
        today = AdherenceCalculator.adherence(
            for: calendar.journalDay(for: .now, boundaryHour: boundaryHour), entries: entries, dailyItems: dailyItems,
            boundaryHour: boundaryHour,
        )
    }

    func recomputeMonth(entries: [DoseEntry], dailyItems: [DailyDoseItem], month: Date) {
        // Bucketed by each dose's own journal day, read on the clock of the
        // zone it was logged in — the same test `adherence(for:)` applies.
        let boundaryHour = Calendar.sessionDayBoundaryHour
        var entriesByDay: [Date: [DoseEntry]] = [:]
        for entry in entries {
            entriesByDay[entry.journalDay(in: calendar, boundaryHour: boundaryHour), default: []].append(entry)
        }

        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: month))!
        let range = calendar.range(of: .day, in: .month, for: start)!

        var data: [DayAdherence] = []
        var byDay: [Date: DayAdherence] = [:]
        for dayOffset in range {
            let date = calendar.date(byAdding: .day, value: dayOffset - 1, to: start)!
            let dayStart = calendar.startOfDay(for: date)
            let adherence = AdherenceCalculator.adherence(
                for: dayStart, entries: entriesByDay[dayStart] ?? [], dailyItems: dailyItems, boundaryHour: boundaryHour,
            )
            data.append(adherence)
            byDay[dayStart] = adherence
        }

        monthAdherence = data
        monthAdherenceByDay = byDay
    }
}
