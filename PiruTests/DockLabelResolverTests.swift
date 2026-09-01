import Foundation
import Testing
@testable import Piru

@Suite("DockLabelResolver")
@MainActor
struct DockLabelResolverTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// A fixed instant at the given hour, in the test calendar.
    private func date(hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: hour, minute: minute))!
    }

    private func context(hour: Int = 12, minute: Int = 0) -> DockLabelContext {
        DockLabelContext(now: date(hour: hour, minute: minute), calendar: calendar)
    }

    // MARK: Ordering

    @Test("Empty list resolves to the unavailable dash")
    func emptyList() {
        #expect(DockLabel.resolve([], in: context()) == DockLabel.unavailable)
    }

    @Test("The first applicable label wins, in list order")
    func firstApplicableWins() {
        let labels: [DockLabel] = [.due, .text("Log a dose"), .text("Second")]
        #expect(DockLabel.resolve(labels, in: context()) == "Log a dose")

        var ctx = context()
        ctx.dueMedNames = ["Memantine", "Lisdexamfetamine"]
        #expect(DockLabel.resolve(labels, in: ctx) == "2 due")
    }

    @Test("Nothing applicable falls through to the dash")
    func nothingApplicable() {
        let labels: [DockLabel] = [.due, .timer(.sinceLastDose), .timed("Morning", startHour: 7, endHour: 10)]
        #expect(DockLabel.resolve(labels, in: context(hour: 15)) == DockLabel.unavailable)
    }

    @Test("Blank text never applies")
    func blankText() {
        #expect(DockLabel.text("   ").resolved(in: context()) == nil)
        #expect(DockLabel.resolve([.text(""), .text("Fallback")], in: context()) == "Fallback")
    }

    // MARK: Due

    @Test("One due med is named; more are counted")
    func dueNaming() {
        var ctx = context()
        ctx.dueMedNames = ["Memantine"]
        #expect(DockLabel.due.resolved(in: ctx) == "Memantine due")
        ctx.dueMedNames = ["Memantine", "Bupropion", "Vitamin D"]
        #expect(DockLabel.due.resolved(in: ctx) == "3 due")
        ctx.dueMedNames = []
        #expect(DockLabel.due.resolved(in: ctx) == nil)
    }

    // MARK: Timed

    @Test("Timed text applies inside its hours, end exclusive")
    func timedWindow() {
        let label = DockLabel.timed("Morning meds?", startHour: 7, endHour: 10)
        #expect(label.resolved(in: context(hour: 6, minute: 59)) == nil)
        #expect(label.resolved(in: context(hour: 7)) == "Morning meds?")
        #expect(label.resolved(in: context(hour: 9, minute: 59)) == "Morning meds?")
        #expect(label.resolved(in: context(hour: 10)) == nil)
    }

    @Test("A range ending before it starts wraps past midnight")
    func timedWrap() {
        let label = DockLabel.timed("Night", startHour: 22, endHour: 6)
        #expect(label.resolved(in: context(hour: 23)) == "Night")
        #expect(label.resolved(in: context(hour: 2)) == "Night")
        #expect(label.resolved(in: context(hour: 6)) == nil)
        #expect(label.resolved(in: context(hour: 12)) == nil)
    }

    @Test("Equal hours mean all day")
    func timedAllDay() {
        let label = DockLabel.timed("Always", startHour: 8, endHour: 8)
        #expect(label.resolved(in: context(hour: 3)) == "Always")
        #expect(label.resolved(in: context(hour: 20)) == "Always")
    }

    // MARK: Timers

    @Test("Since-last-dose counts elapsed time, then expires after a day")
    func sinceLastDose() {
        var ctx = context(hour: 14, minute: 14)
        #expect(DockTimer.sinceLastDose.resolved(in: ctx) == nil)

        ctx.lastDose = DockDoseRef(name: "Memantine", timestamp: date(hour: 12))
        #expect(DockTimer.sinceLastDose.resolved(in: ctx) == "2h 14m since Memantine")

        ctx.lastDose = DockDoseRef(name: "Memantine", timestamp: date(hour: 12).addingTimeInterval(-3 * 24 * 60 * 60))
        #expect(DockTimer.sinceLastDose.resolved(in: ctx) == nil)
    }

    @Test("Until-next-med counts down and never applies once passed")
    func untilNextMed() {
        var ctx = context(hour: 9)
        #expect(DockTimer.untilNextMed.resolved(in: ctx) == nil)

        ctx.nextMed = DockMedRef(name: "Memantine", at: date(hour: 12))
        #expect(DockTimer.untilNextMed.resolved(in: ctx) == "Next: Memantine in 3h")

        ctx.nextMed = DockMedRef(name: "Memantine", at: date(hour: 8))
        #expect(DockTimer.untilNextMed.resolved(in: ctx) == nil)
    }

    @Test("Default list keeps today's behavior")
    func defaults() {
        let labels = DockLabel.defaultLabels
        #expect(DockLabel.resolve(labels, in: context()) == "Log a dose")
        var ctx = context()
        ctx.dueMedNames = ["Memantine"]
        #expect(DockLabel.resolve(labels, in: ctx) == "Memantine due")
    }
}
