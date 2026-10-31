import Foundation
import SwiftData
import Testing
@testable import Piru

/// A dose's day, its morning-or-evening, and the med slot it ticks, read on
/// the clock it was logged by: the Day Starts At hour (`Calendar.journalDay`),
/// the zone each dose was logged in (`DoseEntry.timeZoneIdentifier`), and the
/// slot it was checked off for (`DoseEntry.medSlotMinutes`).
@Suite("Dose time zones and journal days")
@MainActor
struct DoseTimeZoneTests {
    // MARK: - Fixtures

    private static let paris = "Europe/Paris"
    private static let tokyo = "Asia/Tokyo"

    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    /// The instant `hour:minute` on 2026-10-`day` reads on `zone`'s wall clock.
    private func instant(day: Int, hour: Int, minute: Int = 0, in zone: String) -> Date {
        calendar(zone).date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    /// The journal-day key for 2026-10-`day` in `zone`'s calendar.
    private func dayKey(_ day: Int, in zone: String) -> Date {
        calendar(zone).date(from: DateComponents(year: 2026, month: 10, day: day))!
    }

    private func entry(_ substance: String = "Testine", at timestamp: Date, zone: String?, slot: Int? = nil) -> DoseEntry {
        DoseEntry(substance: substance, amount: 10, timestamp: timestamp, timeZoneIdentifier: zone, medSlotMinutes: slot)
    }

    private func item(times: [Int]) -> DailyDoseItem {
        DailyDoseItem(
            substance: "Testine", amount: 10, unit: "mg", route: .oral,
            startDate: .distantPast, reminderTimesMinutes: times,
        )
    }

    // MARK: - The dose's own clock

    @Test
    func `A Paris morning dose is a morning on its Paris day when read in Tokyo`() {
        let tokyo = calendar(Self.tokyo)
        let dose = instant(day: 12, hour: 8, in: Self.paris)
        // Tokyo's own clock says 15:00.
        #expect(tokyo.component(.hour, from: dose) == 15)
        #expect(tokyo.journalDay(for: dose, loggedIn: Self.paris, boundaryHour: 4) == dayKey(12, in: Self.tokyo))
        #expect(tokyo.journalMinutes(for: dose, loggedIn: Self.paris, boundaryHour: 4) == 8 * 60)
    }

    @Test
    func `A Paris evening stays on its own day where Tokyo is already the next morning`() {
        let tokyo = calendar(Self.tokyo)
        let dose = instant(day: 12, hour: 23, in: Self.paris)
        #expect(tokyo.journalDay(for: dose, boundaryHour: 4) == dayKey(13, in: Self.tokyo))
        #expect(tokyo.journalDay(for: dose, loggedIn: Self.paris, boundaryHour: 4) == dayKey(12, in: Self.tokyo))
    }

    @Test
    func `No zone, or an unknown one, reads the dose on the calendar's own clock`() {
        let tokyo = calendar(Self.tokyo)
        let dose = instant(day: 12, hour: 23, in: Self.paris)
        let plain = tokyo.journalDay(for: dose, boundaryHour: 4)
        #expect(tokyo.journalDay(for: dose, loggedIn: nil, boundaryHour: 4) == plain)
        #expect(tokyo.journalDay(for: dose, loggedIn: "Mars/Olympus", boundaryHour: 4) == plain)
    }

    @Test
    func `The hours after midnight before Day Starts At belong to the evening before`() {
        let paris = calendar(Self.paris)
        let late = instant(day: 13, hour: 0, minute: 30, in: Self.paris)
        #expect(paris.journalDay(for: late, loggedIn: Self.paris, boundaryHour: 4) == dayKey(12, in: Self.paris))
        #expect(paris.journalMinutes(for: late, loggedIn: Self.paris, boundaryHour: 4) == 24 * 60 + 30)
        // A midnight start puts it on its own date, early in the morning.
        #expect(paris.journalDay(for: late, loggedIn: Self.paris, boundaryHour: 0) == dayKey(13, in: Self.paris))
        #expect(paris.journalMinutes(for: late, loggedIn: Self.paris, boundaryHour: 0) == 30)
    }

    @Test
    func `A slot before the boundary hour is the last of its journal day`() {
        #expect(Calendar.journalMinutes(ofSlot: 2 * 60, boundaryHour: 4) == 26 * 60)
        #expect(Calendar.journalMinutes(ofSlot: 8 * 60, boundaryHour: 4) == 8 * 60)
        #expect(Calendar.journalMinutes(ofSlot: 2 * 60, boundaryHour: 0) == 2 * 60)

        let paris = calendar(Self.paris)
        let night = paris.date(ofSlot: 2 * 60, inJournalDay: dayKey(12, in: Self.paris), boundaryHour: 4)
        #expect(night == instant(day: 13, hour: 2, in: Self.paris))
        let morning = paris.date(ofSlot: 8 * 60, inJournalDay: dayKey(12, in: Self.paris), boundaryHour: 4)
        #expect(morning == instant(day: 12, hour: 8, in: Self.paris))
    }

    @Test
    func `The fetch window holds a day's doses from either edge of the world`() throws {
        let paris = calendar(Self.paris)
        let window = paris.doseFetchWindow(forJournalDay: dayKey(12, in: Self.paris), boundaryHour: 4)
        for zone in ["Pacific/Kiritimati", "Pacific/Pago_Pago"] {
            let zoned = calendar(zone)
            let first = try #require(zoned.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 4)))
            let last = try #require(zoned.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 3, minute: 59)))
            #expect(first >= window.start && first < window.end, "\(zone) day start")
            #expect(last >= window.start && last < window.end, "\(zone) day end")
        }
    }

    // MARK: - Logging writes the zone

    @Test
    func `A dose records the zone it was logged in`() {
        let dose = DoseEntry(substance: "Caffeine", amount: 100)
        #expect(dose.timeZoneIdentifier == TimeZone.current.identifier)
        #expect(dose.medSlotMinutes == nil)
    }

    @Test
    func `A med checked off for a slot carries the slot`() {
        let med = item(times: [8 * 60, 20 * 60])
        let dose = DoseEntry.medication(med, at: .now, slotMinutes: 8 * 60)
        #expect(dose.medSlotMinutes == 8 * 60)
        #expect(dose.timeZoneIdentifier == TimeZone.current.identifier)
    }

    @Test
    func `A watch dose keeps the watch's zone, and an older watch's the phone's`() throws {
        let payload = WatchDosePayload(
            id: UUID(), substance: "Caffeine", amount: 80, unit: "mg", route: "oral",
            timestamp: .now, timeZoneIdentifier: Self.tokyo,
        )
        #expect(WatchDoseReceiver.makeEntry(from: payload).timeZoneIdentifier == Self.tokyo)

        // A payload from a build without the field decodes with none.
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any])
        json.removeValue(forKey: "timeZoneIdentifier")
        let older = try JSONDecoder().decode(WatchDosePayload.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(older.timeZoneIdentifier == nil)
        #expect(WatchDoseReceiver.makeEntry(from: older).timeZoneIdentifier == TimeZone.current.identifier)
    }

    // MARK: - Adherence follows the journal day

    @Test
    func `With a 4 AM start, a 00:30 dose counts toward the day before`() {
        let paris = calendar(Self.paris)
        let med = item(times: [22 * 60])
        let dose = entry(at: instant(day: 13, hour: 0, minute: 30, in: Self.paris), zone: Self.paris)
        let monday = AdherenceCalculator.adherence(
            for: dayKey(12, in: Self.paris), entries: [dose], dailyItems: [med], calendar: paris, boundaryHour: 4,
        )
        let tuesday = AdherenceCalculator.adherence(
            for: dayKey(13, in: Self.paris), entries: [dose], dailyItems: [med], calendar: paris, boundaryHour: 4,
        )
        #expect(monday.status == .complete)
        #expect(tuesday.status == .missed)

        let midnightStart = AdherenceCalculator.adherence(
            for: dayKey(13, in: Self.paris), entries: [dose], dailyItems: [med], calendar: paris, boundaryHour: 0,
        )
        #expect(midnightStart.status == .complete)
    }

    @Test
    func `The noon split is noon of the journal day, so after midnight is still evening`() {
        let paris = calendar(Self.paris)
        let med = item(times: [8 * 60, 23 * 60])
        let doses = [
            entry(at: instant(day: 12, hour: 9, in: Self.paris), zone: Self.paris),
            entry(at: instant(day: 13, hour: 1, in: Self.paris), zone: Self.paris),
        ]
        let day = AdherenceCalculator.adherence(
            for: dayKey(12, in: Self.paris), entries: doses, dailyItems: [med], calendar: paris, boundaryHour: 4,
        )
        #expect(day.halves == DayAdherence.Halves(morningTaken: 1, morningTotal: 1, eveningTaken: 1, eveningTotal: 1))
    }

    @Test
    func `A slot before Day Starts At is an evening slot`() {
        let paris = calendar(Self.paris)
        let med = item(times: [8 * 60, 2 * 60])
        let day = AdherenceCalculator.adherence(
            for: dayKey(12, in: Self.paris), entries: [], dailyItems: [med], calendar: paris, boundaryHour: 4,
        )
        #expect(day.halves?.morningTotal == 1)
        #expect(day.halves?.eveningTotal == 1)
    }

    @Test
    func `Logged in Paris at 08:00 and viewed in Tokyo, it is still that day's morning dose`() {
        let tokyo = calendar(Self.tokyo)
        let med = item(times: [8 * 60, 20 * 60])
        let dose = entry(at: instant(day: 12, hour: 8, in: Self.paris), zone: Self.paris)
        let day = AdherenceCalculator.adherence(
            for: dayKey(12, in: Self.tokyo), entries: [dose], dailyItems: [med], calendar: tokyo, boundaryHour: 4,
        )
        #expect(day.takenCount == 1)
        #expect(day.halves?.morning == .complete)
        #expect(day.halves?.evening == .missed)

        // Without its zone the same instant is a 15:00 Tokyo dose.
        let zoneless = entry(at: dose.timestamp, zone: nil)
        let read = AdherenceCalculator.adherence(
            for: dayKey(12, in: Self.tokyo), entries: [zoneless], dailyItems: [med], calendar: tokyo, boundaryHour: 4,
        )
        #expect(read.halves?.morning == .missed)
        #expect(read.halves?.evening == .complete)
    }

    @Test
    func `A Paris evening dose stays on its Paris day in the Tokyo calendar`() {
        let tokyo = calendar(Self.tokyo)
        let med = item(times: [22 * 60])
        let dose = entry(at: instant(day: 12, hour: 22, in: Self.paris), zone: Self.paris)
        let own = AdherenceCalculator.adherence(
            for: dayKey(12, in: Self.tokyo), entries: [dose], dailyItems: [med], calendar: tokyo, boundaryHour: 4,
        )
        let next = AdherenceCalculator.adherence(
            for: dayKey(13, in: Self.tokyo), entries: [dose], dailyItems: [med], calendar: tokyo, boundaryHour: 4,
        )
        #expect(own.status == .complete)
        #expect(next.status == .missed)
    }

    @Test
    func `A late dose checked off for the morning slot counts by when it was taken`() {
        // Kiri's rule: an 8:00 dose taken after noon is not an on-time
        // morning dose. "Just now" at 15:00 ticks the 8:00 slot in the
        // checklist, and the calendar's halves read it as an afternoon dose.
        let paris = calendar(Self.paris)
        let med = item(times: [8 * 60, 20 * 60])
        let late = entry(at: instant(day: 12, hour: 15, in: Self.paris), zone: Self.paris, slot: 8 * 60)
        let day = AdherenceCalculator.adherence(
            for: dayKey(12, in: Self.paris), entries: [late], dailyItems: [med], calendar: paris, boundaryHour: 4,
        )
        #expect(day.takenCount == 1)
        #expect(day.halves?.morning == .missed)
        #expect(day.halves?.evening == .complete)
    }

    @Test
    func `The streak walks journal days`() throws {
        let calendar = Calendar.current
        let now = Date.now
        let today = calendar.journalDay(for: now, boundaryHour: 4)
        // A dose at 00:30 after each of the last three days, logged here.
        let doses = try (1 ... 3).map { back in
            let day = try #require(calendar.date(byAdding: .day, value: -back, to: today))
            let after = calendar.date(ofSlot: 30, inJournalDay: day, boundaryHour: 4)
            return AdherenceCalculator.EntrySnapshot(
                substance: "Testine", identityKey: "testine", route: .oral, timestamp: after,
                timeZoneIdentifier: TimeZone.current.identifier,
            )
        }
        let start = try #require(calendar.date(byAdding: .day, value: -3, to: today))
        let items = [AdherenceCalculator.DailyItemSnapshot(
            substance: "Testine", identityKey: "testine", route: .oral, expectedPerDay: 1, isAsNeeded: false,
            startDate: start, frequency: .daily, frequencyDays: [],
        )]
        let streak = AdherenceCalculator.currentStreak(
            spanningDays: 10, endingAt: now, entries: doses, items: items, boundaryHour: 4,
        )
        #expect(streak == 3)
    }

    // MARK: - The checklist honors the slot a dose was checked off for

    private func plan(entries: [RoutineOccurrenceService.EntrySnapshot], slots: [Int?], boundaryHour: Int = 4) -> [Int?: UUID] {
        let due = [RoutineOccurrenceService.ItemSnapshot(substance: "Testine", substanceUID: nil, route: .oral, slots: slots)]
        let plan = RoutineOccurrenceService.plan(
            dueItems: due, occurrences: [], expired: [], entries: entries,
            calendar: calendar(Self.paris), boundaryHour: boundaryHour,
        )
        return Dictionary(uniqueKeysWithValues: plan.inserts.compactMap { insert in
            insert.satisfyingEntryID.map { (insert.slotMinutes, $0) }
        })
    }

    private func snapshot(at timestamp: Date, slot: Int? = nil) -> RoutineOccurrenceService.EntrySnapshot {
        RoutineOccurrenceService.EntrySnapshot(
            id: UUID(), substance: "Testine", substanceUID: nil, route: .oral, timestamp: timestamp,
            timeZoneIdentifier: Self.paris, medSlotMinutes: slot,
        )
    }

    @Test
    func `Just now for the 8:00 slot ticks 8:00, not the nearer 20:00`() {
        let late = snapshot(at: instant(day: 12, hour: 15, in: Self.paris), slot: 8 * 60)
        let claims = plan(entries: [late], slots: [8 * 60, 20 * 60])
        #expect(claims[8 * 60] == late.id)
        #expect(claims[20 * 60] == nil)
    }

    @Test
    func `An untagged dose still takes the nearest slot`() {
        let dose = snapshot(at: instant(day: 12, hour: 15, in: Self.paris))
        let claims = plan(entries: [dose], slots: [8 * 60, 20 * 60])
        #expect(claims[20 * 60] == dose.id)
        #expect(claims[8 * 60] == nil)
    }

    @Test
    func `A tagged dose takes its slot even when an earlier untagged dose is nearer to it`() {
        let early = snapshot(at: instant(day: 12, hour: 9, in: Self.paris))
        let tagged = snapshot(at: instant(day: 12, hour: 15, in: Self.paris), slot: 8 * 60)
        let claims = plan(entries: [early, tagged], slots: [8 * 60, 20 * 60])
        #expect(claims[8 * 60] == tagged.id)
        #expect(claims[20 * 60] == early.id)
    }

    @Test
    func `After midnight a dose is nearest the late-evening slot`() {
        let dose = snapshot(at: instant(day: 13, hour: 1, in: Self.paris))
        let claims = plan(entries: [dose], slots: [8 * 60, 23 * 60])
        #expect(claims[23 * 60] == dose.id)
    }

    // MARK: - A late tap asks; a due-now one doesn't

    @Test
    func `A slot asks when it was taken only once it is well past its time`() {
        let med = item(times: [8 * 60])
        let slot = MyMedsCard.MedSlot(
            med: DailyMedSnapshot(med), itemID: med.persistentModelID, time: 8 * 60, index: 0, state: .pending,
        )
        #expect(!slot.isLate(at: 7 * 60, boundaryHour: 4))
        #expect(slot.isDue(at: 8 * 60 + 30, boundaryHour: 4))
        #expect(!slot.isLate(at: 8 * 60 + 30, boundaryHour: 4))
        #expect(slot.isLate(at: 15 * 60, boundaryHour: 4))

        let anytime = MyMedsCard.MedSlot(
            med: DailyMedSnapshot(med), itemID: med.persistentModelID, time: nil, index: 0, state: .pending,
        )
        #expect(!anytime.isLate(at: 15 * 60, boundaryHour: 4))
        let taken = MyMedsCard.MedSlot(
            med: DailyMedSnapshot(med), itemID: med.persistentModelID, time: 8 * 60, index: 0, state: .taken,
        )
        #expect(!taken.isLate(at: 15 * 60, boundaryHour: 4))
    }
}
