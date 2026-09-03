import Foundation

/// One trailing info line under the My Meds card's slot rows — a fact worth a
/// glance, never an instruction (Specs/journal-home-rework.md §3).
enum MyMedsInfoLine: Hashable {
    /// A tracked supply projected to run out inside ``MyMedsInfo/restockHorizonDays``.
    case restock(name: String, daysLeft: Int, itemID: UUID)
    /// The next timed slot today while nothing is due right now.
    case nextDue(name: String, minutes: Int)
    /// A slot that ended yesterday still unlogged — neutral history, dismissible.
    case missedYesterday(MissedYesterdayNotice)
}

/// What yesterday's `missed` occurrences add up to. `slotMinutes` names the
/// slot when exactly one was missed; `count` > 1 collapses them.
struct MissedYesterdayNotice: Hashable {
    let names: [String]
    let slotMinutes: Int?
    let count: Int
    /// ``MissedNoticeDismissals/dayKey(for:calendar:)`` of the missed day.
    let dayKey: String

    var name: String {
        names.first ?? ""
    }
}

/// The pure selection behind the card's info lines: which candidates exist and
/// which two of them show. Every input is a value so the choice is testable
/// without a store.
enum MyMedsInfo {
    /// At most this many lines under the slot rows.
    static let maxLines = 2
    /// A supply projected to last fewer days than this earns a restock line.
    static let restockHorizonDays = 14.0

    /// One tracked supply's projection, as the inventory service reports it.
    struct SupplyProjection: Equatable {
        let name: String
        let daysLeft: Double
        let itemID: UUID
    }

    /// One checklist slot reduced to what next-due needs.
    struct SlotSummary: Equatable {
        let name: String
        let minutes: Int?
        let pending: Bool
    }

    /// Priority order restock → next due → missed yesterday, capped at
    /// ``maxLines``. A dismissed missed notice is dropped before capping.
    static func select(
        restock: MyMedsInfoLine?,
        nextDue: MyMedsInfoLine?,
        missed: MyMedsInfoLine?,
        missedDismissed: Bool,
    ) -> [MyMedsInfoLine] {
        var lines: [MyMedsInfoLine] = []
        if let restock { lines.append(restock) }
        if let nextDue { lines.append(nextDue) }
        if let missed, !missedDismissed { lines.append(missed) }
        return Array(lines.prefix(maxLines))
    }

    /// The soonest-to-run-out supply under the horizon, or `nil` when every
    /// tracked med has more than two weeks left. Days are floored so "6 days
    /// left" never promises a seventh.
    static func restock(from projections: [SupplyProjection]) -> MyMedsInfoLine? {
        guard let soonest = projections
            .filter({ $0.daysLeft < restockHorizonDays })
            .min(by: { $0.daysLeft < $1.daysLeft })
        else { return nil }
        return .restock(name: soonest.name, daysLeft: max(0, Int(soonest.daysLeft.rounded(.down))), itemID: soonest.itemID)
    }

    /// The earliest pending timed slot still ahead of `nowMinutes`, only while
    /// no pending slot has already come due — a due slot is the rows' job, and
    /// the line would otherwise point past it.
    static func nextDue(slots: [SlotSummary], nowMinutes: Int) -> MyMedsInfoLine? {
        let pending = slots.filter(\.pending)
        let dueNow = pending.contains { ($0.minutes ?? 0) <= nowMinutes }
        guard !dueNow else { return nil }
        guard let next = pending
            .compactMap({ slot in slot.minutes.map { (name: slot.name, minutes: $0) } })
            .filter({ $0.minutes > nowMinutes })
            .min(by: { $0.minutes < $1.minutes })
        else { return nil }
        return .nextDue(name: next.name, minutes: next.minutes)
    }

    /// Yesterday's missed slots folded into one notice, keyed by the missed
    /// day so a dismissal outlives relaunches but expires with the day.
    static func missedYesterday(
        missed: [(name: String, slotMinutes: Int?)],
        yesterday: Date,
        calendar: Calendar = .current,
    ) -> MyMedsInfoLine? {
        guard let first = missed.first else { return nil }
        return .missedYesterday(MissedYesterdayNotice(
            names: missed.map(\.name),
            slotMinutes: missed.count == 1 ? first.slotMinutes : nil,
            count: missed.count,
            dayKey: MissedNoticeDismissals.dayKey(for: yesterday, calendar: calendar),
        ))
    }
}

/// The ✕ on a missed-yesterday line, remembered per missed day so the notice
/// never returns for that day. Stored as a small set of ISO day keys in the
/// app-group defaults, pruned so it never grows past a month of dismissals.
enum MissedNoticeDismissals {
    static let defaultsKey = "myMedsMissedNoticeDismissedDays"
    static let retainedCount = 31

    /// "2026-08-31" in the calendar's own time zone — the same key on every
    /// launch regardless of when in the day it's computed.
    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func isDismissed(_ dayKey: String, in defaults: UserDefaults) -> Bool {
        (defaults.stringArray(forKey: defaultsKey) ?? []).contains(dayKey)
    }

    static func dismiss(_ dayKey: String, in defaults: UserDefaults) {
        var keys = defaults.stringArray(forKey: defaultsKey) ?? []
        guard !keys.contains(dayKey) else { return }
        keys.append(dayKey)
        if keys.count > retainedCount {
            keys.removeFirst(keys.count - retainedCount)
        }
        defaults.set(keys, forKey: defaultsKey)
    }
}
