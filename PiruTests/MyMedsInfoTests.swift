import Foundation
import Testing
@testable import Piru

/// The My Meds card's info-line selection: which facts qualify and which two
/// of them show.
@Suite("MyMedsInfo")
struct MyMedsInfoTests {
    private let itemID = UUID()

    private var restockLine: MyMedsInfoLine {
        .restock(name: "Memantine", daysLeft: 6, itemID: itemID)
    }

    private var nextDueLine: MyMedsInfoLine {
        .nextDue(name: "Memantine", minutes: 21 * 60)
    }

    private var missedLine: MyMedsInfoLine {
        .missedYesterday(MissedYesterdayNotice(name: "Memantine", slotMinutes: 20 * 60, count: 1, dayKey: "2026-08-31"))
    }

    // MARK: Selection

    @Test
    func `Priority is restock, then next due, then missed — capped at two`() {
        let all = MyMedsInfo.select(restock: restockLine, nextDue: nextDueLine, missed: missedLine, missedDismissed: false)
        #expect(all == [restockLine, nextDueLine])

        let noRestock = MyMedsInfo.select(restock: nil, nextDue: nextDueLine, missed: missedLine, missedDismissed: false)
        #expect(noRestock == [nextDueLine, missedLine])

        let onlyMissed = MyMedsInfo.select(restock: nil, nextDue: nil, missed: missedLine, missedDismissed: false)
        #expect(onlyMissed == [missedLine])
    }

    @Test
    func `A dismissed missed notice is dropped, not merely pushed past the cap`() {
        let lines = MyMedsInfo.select(restock: nil, nextDue: nil, missed: missedLine, missedDismissed: true)
        #expect(lines.isEmpty)
    }

    @Test
    func `Nothing qualifying means no lines`() {
        #expect(MyMedsInfo.select(restock: nil, nextDue: nil, missed: nil, missedDismissed: false).isEmpty)
    }

    // MARK: Restock

    @Test
    func `Only supplies under the two-week horizon qualify, soonest first`() {
        let far = MyMedsInfo.SupplyProjection(name: "Vitamin D", daysLeft: 40, itemID: UUID())
        let soon = MyMedsInfo.SupplyProjection(name: "Memantine", daysLeft: 6.8, itemID: itemID)
        let sooner = MyMedsInfo.SupplyProjection(name: "Methylphenidate", daysLeft: 2.2, itemID: UUID())

        #expect(MyMedsInfo.restock(from: [far]) == nil)
        #expect(MyMedsInfo.restock(from: [far, soon]) == .restock(name: "Memantine", daysLeft: 6, itemID: itemID))
        if case let .restock(name, daysLeft, _)? = MyMedsInfo.restock(from: [far, soon, sooner]) {
            #expect(name == "Methylphenidate")
            #expect(daysLeft == 2)
        } else {
            Issue.record("expected the soonest supply")
        }
    }

    @Test
    func `Exactly fourteen days is outside the horizon`() {
        let edge = MyMedsInfo.SupplyProjection(name: "Memantine", daysLeft: 14, itemID: itemID)
        #expect(MyMedsInfo.restock(from: [edge]) == nil)
    }

    // MARK: Next due

    @Test
    func `The earliest later pending slot is next while nothing is due`() {
        let slots = [
            MyMedsInfo.SlotSummary(name: "Methylphenidate", minutes: 8 * 60, pending: false),
            MyMedsInfo.SlotSummary(name: "Melatonin", minutes: 22 * 60, pending: true),
            MyMedsInfo.SlotSummary(name: "Memantine", minutes: 21 * 60, pending: true),
        ]
        #expect(MyMedsInfo.nextDue(slots: slots, nowMinutes: 12 * 60) == .nextDue(name: "Memantine", minutes: 21 * 60))
    }

    @Test
    func `A slot already due suppresses the line — the rows own it`() {
        let slots = [
            MyMedsInfo.SlotSummary(name: "Methylphenidate", minutes: 8 * 60, pending: true),
            MyMedsInfo.SlotSummary(name: "Memantine", minutes: 21 * 60, pending: true),
        ]
        #expect(MyMedsInfo.nextDue(slots: slots, nowMinutes: 12 * 60) == nil)
    }

    @Test
    func `An anytime slot counts as due now; taken slots never count`() {
        let anytime = [
            MyMedsInfo.SlotSummary(name: "Vitamin D", minutes: nil, pending: true),
            MyMedsInfo.SlotSummary(name: "Memantine", minutes: 21 * 60, pending: true),
        ]
        #expect(MyMedsInfo.nextDue(slots: anytime, nowMinutes: 12 * 60) == nil)

        let allTaken = [MyMedsInfo.SlotSummary(name: "Memantine", minutes: 21 * 60, pending: false)]
        #expect(MyMedsInfo.nextDue(slots: allTaken, nowMinutes: 12 * 60) == nil)
    }

    // MARK: Missed yesterday

    @Test
    func `One miss names its slot; several collapse to a count`() throws {
        let yesterday = try #require(Calendar.current.date(from: DateComponents(year: 2_026, month: 8, day: 31)))
        let one = MyMedsInfo.missedYesterday(missed: [(name: "Memantine", slotMinutes: 20 * 60)], yesterday: yesterday)
        #expect(one == .missedYesterday(MissedYesterdayNotice(name: "Memantine", slotMinutes: 20 * 60, count: 1, dayKey: "2026-08-31")))

        let two = MyMedsInfo.missedYesterday(
            missed: [(name: "Memantine", slotMinutes: 20 * 60), (name: "Methylphenidate", slotMinutes: 8 * 60)],
            yesterday: yesterday,
        )
        if case let .missedYesterday(notice)? = two {
            #expect(notice.count == 2)
            #expect(notice.slotMinutes == nil)
        } else {
            Issue.record("expected a collapsed notice")
        }

        #expect(MyMedsInfo.missedYesterday(missed: [], yesterday: yesterday) == nil)
    }

    // MARK: Dismissals

    @Test
    func `A dismissed day stays dismissed and the store stays bounded`() throws {
        let name = "MyMedsInfoTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)

        #expect(!MissedNoticeDismissals.isDismissed("2026-08-31", in: defaults))
        MissedNoticeDismissals.dismiss("2026-08-31", in: defaults)
        MissedNoticeDismissals.dismiss("2026-08-31", in: defaults)
        #expect(MissedNoticeDismissals.isDismissed("2026-08-31", in: defaults))
        #expect(defaults.stringArray(forKey: MissedNoticeDismissals.defaultsKey)?.count == 1)

        for day in 1 ... 40 {
            MissedNoticeDismissals.dismiss(String(format: "2026-10-%02d", day), in: defaults)
        }
        let kept = defaults.stringArray(forKey: MissedNoticeDismissals.defaultsKey) ?? []
        #expect(kept.count == MissedNoticeDismissals.retainedCount)
        #expect(!kept.contains("2026-08-31"))
        #expect(kept.last == "2026-10-40")
    }

    @Test
    func `The day key is the calendar date, zero-padded`() throws {
        let date = try #require(Calendar.current.date(from: DateComponents(year: 2_026, month: 9, day: 1, hour: 23, minute: 59)))
        #expect(MissedNoticeDismissals.dayKey(for: date) == "2026-09-01")
    }
}
