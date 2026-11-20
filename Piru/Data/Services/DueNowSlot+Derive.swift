import Foundation
import SwiftData

extension DueNowSlot {
    /// The due-now derivation, shared by the My Meds pills and the tab-bar
    /// accessory badge: for each non-PRN med due today, the earliest
    /// uncovered slot whose time is within ``dueSoonLeadMinutes`` (or already
    /// past) — "covered" assigns today's logged doses to the earliest slots
    /// first, mirroring MyMedsCard. Anytime meds (no set times) are due all
    /// day until taken and sort behind timed slots so an overdue 8:00 pill
    /// outranks the anytime vitamin.
    ///
    /// "Taken" is counted with ``AdherenceCalculator/entryMatches(entry:item:)``
    /// — the SAME matcher MyMedsCard uses (identity *or* name, same route), so
    /// the accessory and My Meds never disagree about what counts as taken: a
    /// dose's PSID can resolve differently than its schedule item, so a
    /// strict identity-only match would miss it. `todayEntries` is today's doses.
    ///
    /// Today is the journal day, and times are read on its clock
    /// (``Foundation/Calendar/journalMinutes(for:loggedIn:boundaryHour:)``).
    static func derive(
        items: [DailyDoseItem], todayEntries: [DoseEntry], now: Date = .now,
        boundaryHour: Int = Calendar.sessionDayBoundaryHour,
    ) -> [DueNowSlot] {
        guard !items.isEmpty else { return [] }
        let calendar = Calendar.current
        let today = calendar.journalDay(for: now, boundaryHour: boundaryHour)
        let nowMinutes = calendar.journalMinutes(for: now, loggedIn: nil, boundaryHour: boundaryHour)

        var slots: [DueNowSlot] = []
        for item in items where !item.isAsNeeded && AdherenceCalculator.isDue(item, on: today) {
            let (taken, times) = coverage(of: item, todayEntries: todayEntries, boundaryHour: boundaryHour)
            if times.isEmpty {
                guard taken == 0 else { continue }
                slots.append(DueNowSlot(id: "\(item.identityKey)|any", item: DailyMedSnapshot(item), slotMinutes: nil))
                continue
            }
            // The earliest uncovered slot, and only if its window has opened.
            guard taken < times.count else { continue }
            let slot = times[taken]
            guard Calendar.journalMinutes(ofSlot: slot, boundaryHour: boundaryHour) <= nowMinutes + dueSoonLeadMinutes else { continue }
            slots.append(DueNowSlot(id: "\(item.identityKey)|\(slot)", item: DailyMedSnapshot(item), slotMinutes: slot))
        }
        func order(_ slot: DueNowSlot) -> Int {
            slot.slotMinutes.map { Calendar.journalMinutes(ofSlot: $0, boundaryHour: boundaryHour) } ?? .max
        }
        return slots.sorted { (order($0), $0.item.sortOrder) < (order($1), $1.item.sortOrder) }
    }

    /// `item`'s set times in journal-day order, and how many of `todayEntries`
    /// count as taking it (``AdherenceCalculator/entryMatches(entry:item:)``).
    /// Today's doses cover the times in that order, so `times[taken...]` are
    /// the slots still open. Shared by ``derive(items:todayEntries:now:boundaryHour:)``
    /// and the dock label's next-med lookup.
    static func coverage(
        of item: DailyDoseItem, todayEntries: [DoseEntry], boundaryHour: Int,
    ) -> (taken: Int, times: [Int]) {
        let taken = todayEntries.count { AdherenceCalculator.entryMatches(entry: $0, item: item) }
        let times = item.reminderTimesMinutes.sorted {
            Calendar.journalMinutes(ofSlot: $0, boundaryHour: boundaryHour)
                < Calendar.journalMinutes(ofSlot: $1, boundaryHour: boundaryHour)
        }
        return (taken, times)
    }
}
