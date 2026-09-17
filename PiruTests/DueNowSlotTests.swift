import Foundation
import Testing
@testable import Piru

/// The shared "what should I take now?" derivation behind the quick-log My
/// Meds pills' due state and the tab-bar accessory badge.
@MainActor
@Suite("DueNowSlot")
struct DueNowSlotTests {
    /// Noon today — a fixed anchor so slot windows are deterministic.
    private var noon: Date {
        Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: .now)!
    }

    private func med(
        _ substance: String,
        times: [Int] = [],
        isAsNeeded: Bool = false,
        frequency: DoseFrequency = .daily,
        sortOrder: Int = 0,
    ) -> DailyDoseItem {
        DailyDoseItem(
            substance: substance, amount: 10, unit: "mg", sortOrder: sortOrder,
            frequency: frequency, reminderTimesMinutes: times,
            isAsNeeded: isAsNeeded,
        )
    }

    /// A logged dose that satisfies `item` — same substance name + route, as a
    /// tap in MyMedsCard produces. `substanceUID` lets a test give the dose a
    /// resolved identity the schedule item lacks (the desync repro below).
    private func dose(for item: DailyDoseItem, substanceUID: String? = nil) -> DoseEntry {
        DoseEntry(
            substance: item.substance, amount: item.amount, unit: item.unit, route: item.route,
            substanceUID: substanceUID, timestamp: noon,
        )
    }

    @Test
    func `A passed, uncovered slot is due`() {
        let slots = DueNowSlot.derive(items: [med("Sertraline", times: [480])], todayEntries: [], now: noon)
        #expect(slots.count == 1)
        #expect(slots.first?.slotMinutes == 480)
    }

    @Test
    func `A slot inside the lead window is due; beyond it is not`() {
        let soon = med("Sertraline", times: [12 * 60 + 30])
        let later = med("Melatonin", times: [22 * 60])
        let slots = DueNowSlot.derive(items: [soon, later], todayEntries: [], now: noon)
        #expect(slots.map(\.slotMinutes) == [12 * 60 + 30])
    }

    @Test
    func `Covered slots are skipped — earliest-first assignment`() {
        let twice = med("Methylphenidate", times: [480, 11 * 60])
        // One dose today covers the 8:00 slot; the 11:00 slot is uncovered and past.
        let one = DueNowSlot.derive(items: [twice], todayEntries: [dose(for: twice)], now: noon)
        #expect(one.map(\.slotMinutes) == [11 * 60])
        // Two doses cover both.
        let none = DueNowSlot.derive(items: [twice], todayEntries: [dose(for: twice), dose(for: twice)], now: noon)
        #expect(none.isEmpty)
    }

    @Test
    func `An anytime med is due all day until taken, and sorts behind timed slots`() {
        let vitamin = med("Vitamin D", sortOrder: 1)
        let ssri = med("Sertraline", times: [480])
        let slots = DueNowSlot.derive(items: [vitamin, ssri], todayEntries: [], now: noon)
        #expect(slots.map(\.slotMinutes) == [480, nil])
        let taken = DueNowSlot.derive(items: [vitamin], todayEntries: [dose(for: vitamin)], now: noon)
        #expect(taken.isEmpty)
    }

    @Test
    func `PRN meds and off-day schedules never appear`() throws {
        let prn = med("Ibuprofen", isAsNeeded: true)
        // Weekly med starting long ago on a different weekday than today —
        // pick a start date 3 days back so today is an off-day.
        let weekly = med("B12", times: [480], frequency: .weekly)
        weekly.startDate = try #require(Calendar.current.date(byAdding: .day, value: -3, to: noon))
        let slots = DueNowSlot.derive(items: [prn, weekly], todayEntries: [], now: noon)
        #expect(slots.isEmpty)
    }

    // MARK: My Meds pills

    @Test
    func `A group pill is due for the member whose slot opened, in that slot's own group`() {
        // 8:00 and 20:00: the morning slot is open at noon, the evening one is
        // not, so only the Morning pill wears the due state.
        let twice = med("Methylphenidate", times: [480, 20 * 60])
        let later = med("Melatonin", times: [22 * 60])
        let vitamin = med("Vitamin D")
        let content = QuickLogContentModel()
        let groups = content.makeDailyGroups(dailyDoseItems: [twice, later, vitamin], routines: [], now: noon)
        let byID = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })

        #expect(byID["morning"]?.due.map(\.item.substance) == ["Methylphenidate"])
        #expect(byID["morning"]?.dueSlotMinutes == 480)
        #expect(byID["evening"]?.isDue == false)
        #expect(byID["night"]?.isDue == false)
        // An anytime med is due all day, with no slot time to show.
        #expect(byID["anytime"]?.isDue == true)
        #expect(byID["anytime"]?.dueSlotMinutes == nil)
    }

    @Test
    func `Staging the due pill's member flips it to staged`() throws {
        let item = med("Sertraline", times: [480])
        let content = QuickLogContentModel()
        let group = try #require(content.makeDailyGroups(dailyDoseItems: [item], routines: [], now: noon).first)
        #expect(group.isDue)

        let tray = DoseTrayModel()
        #expect(group.isFullyStaged(in: tray.stagedCountsBySubstance()) == false)
        #expect(group.unstaged(in: tray.stagedCountsBySubstance()).count == 1)

        // The same path the pill's tap takes; the snapshot keys by the
        // resolved identity, which is what the pill must read it back under.
        tray.stage(dailyItem: item, colorLookup: [:])
        #expect(group.isFullyStaged(in: tray.stagedCountsBySubstance()))
        #expect(group.unstaged(in: tray.stagedCountsBySubstance()).isEmpty)
    }

    @Test
    func `A dose credits its med even when its PSID resolved differently (accessory desync)`() {
        // The reported bug: the accessory read "1 due" while My Meds showed
        // everything taken. A dose whose substanceUID resolved (identityKey
        // "mph-cid-4158") no longer matched a name-only schedule item
        // (identityKey "methylphenidate") under the old strict dict lookup, so
        // it was counted as un-taken. entryMatches's name fallback credits it.
        let item = med("Methylphenidate", times: [480])
        let resolved = dose(for: item, substanceUID: "MPH-CID-4158")
        #expect(resolved.identityKey != item.identityKey) // genuinely differing keys
        let slots = DueNowSlot.derive(items: [item], todayEntries: [resolved], now: noon)
        #expect(slots.isEmpty) // covered — not due
    }
}
