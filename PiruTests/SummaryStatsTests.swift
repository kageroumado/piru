import Foundation
import Testing
@testable import Piru

/// The pure clinical/patterns aggregation. Operates on Sendable snapshots (no
/// SwiftData), so it tests in isolation.
@Suite("SummaryStats")
struct SummaryStatsTests {
    /// UTC + a midnight-aligned anchor so day boundaries are exact and DST-free.
    /// Reports run with `dayBoundaryHour: 0` (plain calendar days) unless a
    /// test is about the Day Starts At hour.
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private let base = Date(timeIntervalSince1970: 1_699_920_000) // 2023-11-14 00:00:00 UTC

    private func substance(_ name: String, _ currency: ExposureCurrency) -> SummarySubstance {
        SummarySubstance(name: name, displayName: name, tint: P3Color(red: 0.917, green: 0.200, blue: 0.139), unit: "mg", currency: currency)
    }

    private func day(_ n: Int) -> Date {
        base.addingTimeInterval(Double(n) * 86_400)
    }

    // MARK: Holidays

    @Test
    func `Days used, longest break, and current break`() {
        // 30-day window; used on days 0, 1, 2, then 10, then nothing after.
        let subs = [substance("X", .milligrams)]
        let usedDays = [0, 1, 2, 10]
        let doses = usedDays.map { SummaryDose(substanceIndex: 0, timestamp: day($0).addingTimeInterval(3_600), exposure: 5, ke: nil, ka: nil) }
        let report = SummaryStats.report(substances: subs, doses: doses, start: day(0), end: day(29), calendar: cal, dayBoundaryHour: 0)
        let h = report.holidays
        #expect(h.totalDays == 30)
        #expect(h.daysUsed == 4)
        #expect(h.daysOff == 26)
        // Gap between day 10 and the window end (day 29) is 19 unused days — the longest.
        #expect(h.longestBreakDays == 19)
        #expect(h.currentBreakDays == 19)
    }

    /// With a 4 AM day start, a 22:00 dose and a 02:00 dose after it are one day used.
    @Test
    func `Days used count journal days`() {
        let subs = [substance("X", .milligrams)]
        let doses = [day(1).addingTimeInterval(22 * 3_600), day(2).addingTimeInterval(2 * 3_600)]
            .map { SummaryDose(substanceIndex: 0, timestamp: $0, exposure: 5, ke: nil, ka: nil) }
        let journal = SummaryStats.report(substances: subs, doses: doses, start: day(0).addingTimeInterval(12 * 3_600), end: day(4), calendar: cal, dayBoundaryHour: 4)
        #expect(journal.holidays.daysUsed == 1)
        let calendarDays = SummaryStats.report(substances: subs, doses: doses, start: day(0).addingTimeInterval(12 * 3_600), end: day(4), calendar: cal, dayBoundaryHour: 0)
        #expect(calendarDays.holidays.daysUsed == 2)
    }

    // MARK: Exposure

    @Test
    func `Cumulative total, peak day, and daily mean`() throws {
        let subs = [substance("Oxy", .mme)]
        // Three doses: two on day 0 (30 + 15 MME), one on day 4 (45 MME).
        let doses = [
            SummaryDose(substanceIndex: 0, timestamp: day(0).addingTimeInterval(3_600), exposure: 30, ke: nil, ka: nil),
            SummaryDose(substanceIndex: 0, timestamp: day(0).addingTimeInterval(7_200), exposure: 15, ke: nil, ka: nil),
            SummaryDose(substanceIndex: 0, timestamp: day(4).addingTimeInterval(3_600), exposure: 45, ke: nil, ka: nil),
        ]
        let report = SummaryStats.report(substances: subs, doses: doses, start: day(0), end: day(9), calendar: cal, dayBoundaryHour: 0)
        let e = try #require(report.exposure.first)
        #expect(e.total == 90)
        #expect(e.peakDay == 45) // day 0 summed to 45; day 4 also 45 — tie
        #expect(e.cumulative.map(\.total) == [30, 45, 90])
        // window is day0..day9 → ~9 days; dailyMean ≈ 90/9 = 10 (allow float slop)
        #expect(abs(e.dailyMean - 10) < 0.5)
        // Peak-day MME surfaces for the CDC band comparison.
        #expect(report.opioidPeakDayMME == 45)
    }

    // MARK: Escalation

    @Test
    func `Rising dose is detected; flat is steady`() throws {
        // Rising: 6 doses over 40 days, first third ~10, last third ~30.
        let rising = [10.0, 11, 20, 22, 30, 31].enumerated().map { i, v in
            SummaryDose(substanceIndex: 0, timestamp: day(i * 8).addingTimeInterval(3_600), exposure: v, ke: nil, ka: nil)
        }
        var report = SummaryStats.report(substances: [substance("X", .milligrams)], doses: rising, start: day(0), end: day(41), calendar: cal, dayBoundaryHour: 0)
        var s = try #require(report.escalation.first)
        #expect(s.direction == .rising)
        #expect(s.change > 0.15)

        // Flat: same dose throughout.
        let flat = (0 ..< 6).map { i in
            SummaryDose(substanceIndex: 0, timestamp: day(i * 8).addingTimeInterval(3_600), exposure: 20, ke: nil, ka: nil)
        }
        report = SummaryStats.report(substances: [substance("X", .milligrams)], doses: flat, start: day(0), end: day(41), calendar: cal, dayBoundaryHour: 0)
        s = try #require(report.escalation.first)
        #expect(s.direction == .steady)
    }

    @Test
    func `Too few doses or too short a span yields no escalation stat`() {
        // Only 4 doses — below the minimum.
        let few = (0 ..< 4).map { i in
            SummaryDose(substanceIndex: 0, timestamp: day(i * 10).addingTimeInterval(3_600), exposure: Double(10 + i * 10), ke: nil, ka: nil)
        }
        let report = SummaryStats.report(substances: [substance("X", .milligrams)], doses: few, start: day(0), end: day(41), calendar: cal, dayBoundaryHour: 0)
        #expect(report.escalation.isEmpty)
    }

    // MARK: Overlap

    @Test
    func `Simultaneously active substances accrue overlap hours`() throws {
        // Two substances dosed at the same time, both with a multi-hour curve.
        let ke = PKModel.ke(fromHalfLifeMinutes: 240)
        let ka = PKModel.defaultKa(ke: ke)
        let subs = [substance("A", .milligrams), substance("B", .milligrams)]
        let doses = [
            SummaryDose(substanceIndex: 0, timestamp: day(1), exposure: 100, ke: ke, ka: ka),
            SummaryDose(substanceIndex: 1, timestamp: day(1), exposure: 100, ke: ke, ka: ka),
        ]
        let report = SummaryStats.report(substances: subs, doses: doses, start: day(0), end: day(3), calendar: cal, dayBoundaryHour: 0)
        let o = try #require(report.overlaps.first)
        #expect(o.hours > 2) // both active together for several hours after the shared dose
        #expect(Set([o.a, o.b]) == Set([0, 1]))
    }

    @Test
    func `Non-overlapping doses accrue no overlap`() {
        let ke = PKModel.ke(fromHalfLifeMinutes: 120) // ~2h half-life, clears well within a day
        let ka = PKModel.defaultKa(ke: ke)
        let subs = [substance("A", .milligrams), substance("B", .milligrams)]
        let doses = [
            SummaryDose(substanceIndex: 0, timestamp: day(0), exposure: 100, ke: ke, ka: ka),
            SummaryDose(substanceIndex: 1, timestamp: day(2), exposure: 100, ke: ke, ka: ka),
        ]
        let report = SummaryStats.report(substances: subs, doses: doses, start: day(0), end: day(3), calendar: cal, dayBoundaryHour: 0)
        #expect(report.overlaps.isEmpty)
    }
}
