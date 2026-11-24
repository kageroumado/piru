import Foundation
import Testing
@testable import Piru

/// Pins the axis choices of the Modeled Tolerance and Ceiling Effect charts: the value ladder, the
/// round time steps, the span the charts share, and the dates the near-baseline line prints.
@Suite("Tolerance chart scale")
@MainActor
struct ToleranceChartScaleTests {
    // MARK: - Value axis

    private struct ValueCase {
        let peak: Double
        let top: Double
        let ticks: [Double]
    }

    private static let valueCases: [ValueCase] = [
        ValueCase(peak: 0, top: 20, ticks: [0, 10, 20]),
        ValueCase(peak: 12, top: 20, ticks: [0, 10, 20]),
        ValueCase(peak: 20, top: 20, ticks: [0, 10, 20]),
        ValueCase(peak: 27, top: 30, ticks: [0, 10, 20, 30]),
        ValueCase(peak: 31, top: 40, ticks: [0, 20, 40]),
        ValueCase(peak: 45, top: 50, ticks: [0, 25, 50]),
        ValueCase(peak: 55, top: 60, ticks: [0, 20, 40, 60]),
        ValueCase(peak: 75, top: 80, ticks: [0, 20, 40, 60, 80]),
        ValueCase(peak: 97, top: 100, ticks: [0, 25, 50, 75, 100]),
        ValueCase(peak: 140, top: 100, ticks: [0, 25, 50, 75, 100]),
    ]

    @Test(arguments: 0 ..< 10)
    func `The value axis is the lowest rung that holds the peak`(index: Int) {
        let c = Self.valueCases[index]
        let axis = ToleranceChartScale.valueAxis(peakPercent: c.peak)
        #expect(axis.top == c.top)
        #expect(axis.ticks == c.ticks)
    }

    @Test(arguments: Array(stride(from: 0.0, through: 100, by: 0.5)))
    func `Every value axis holds its peak and the near-baseline line and labels its top`(peak: Double) {
        let axis = ToleranceChartScale.valueAxis(peakPercent: peak)
        #expect(axis.top >= peak)
        #expect(axis.top > ToleranceRow.nearBaselineSeverity * 100)
        #expect(axis.ticks.first == 0)
        #expect(axis.ticks.last == axis.top)
        #expect(axis.ticks.count <= 5)
    }

    // MARK: - Time axis

    private struct TimeCase {
        let spanDays: Double
        let axis: ToleranceChartScale.TimeAxis
    }

    private static func timeCase(_ spanDays: Double, _ unit: ToleranceChartScale.TimeUnit, _ step: Int, _ intervals: Int) -> TimeCase {
        TimeCase(spanDays: spanDays, axis: ToleranceChartScale.TimeAxis(unit: unit, step: step, intervals: intervals))
    }

    private static let timeCases: [TimeCase] = [
        timeCase(0, .hours, 1, 1),
        timeCase(5.0 / 24, .hours, 1, 5),
        timeCase(6.5 / 24, .hours, 2, 4),
        timeCase(15.0 / 24, .hours, 3, 5),
        timeCase(21.0 / 24, .hours, 6, 4),
        timeCase(30.0 / 24, .hours, 6, 5),
        timeCase(44.0 / 24, .hours, 12, 4),
        timeCase(2, .hours, 12, 4),
        timeCase(2.2, .days, 1, 3),
        timeCase(4.4, .days, 1, 5),
        timeCase(7, .days, 2, 4),
        timeCase(9, .days, 2, 5),
        timeCase(12, .days, 2, 6),
        timeCase(13.3, .weeks, 1, 2),
        timeCase(17.6, .weeks, 1, 3),
        timeCase(49, .weeks, 2, 4),
        timeCase(56, .weeks, 2, 4),
        timeCase(180, .weeks, 8, 4),
    ]

    @Test(arguments: 0 ..< 18)
    func `The time axis counts in round steps of one unit`(index: Int) {
        let c = Self.timeCases[index]
        #expect(ToleranceChartScale.timeAxis(spanDays: c.spanDays) == c.axis)
    }

    @Test(arguments: Array(stride(from: 0.05, through: 200, by: 0.37)))
    func `Every time axis covers its span, ends on a labeled tick and keeps its labels few`(spanDays: Double) {
        let axis = ToleranceChartScale.timeAxis(spanDays: spanDays)
        let ticks = axis.tickDays
        #expect(axis.endDays >= spanDays - 1e-9)
        #expect(ticks.first == 0)
        #expect(ticks.last == axis.endDays)
        #expect(ticks.count == axis.intervals + 1)
        #expect(ticks.count <= 7)
        // Each tick prints a whole count of the axis's unit, a whole step past the one before.
        #expect(ticks.map { axis.count(atDays: $0) } == (0 ... axis.intervals).map { $0 * axis.step })
        // The end is the first whole step at or past the span.
        #expect(axis.endDays - Double(axis.step) * axis.unit.days < spanDays || axis.intervals == 1)
    }

    @Test
    func `A coarse axis carries unlabeled gridlines between its ticks`() {
        let twoWeeks = ToleranceChartScale.timeAxis(spanDays: 13.3)
        #expect(twoWeeks.minorGridDays == [1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 12, 13])
        let nineDays = ToleranceChartScale.timeAxis(spanDays: 9)
        #expect(nineDays.minorGridDays == [1, 3, 5, 7, 9])
        let day = ToleranceChartScale.timeAxis(spanDays: 1)
        #expect(day.minorGridDays.map { ($0 * 24).rounded() } == [3, 9, 15, 21])
        #expect(ToleranceChartScale.timeAxis(spanDays: 4.4).minorGridDays.isEmpty)
    }

    // MARK: - Shared span

    @Test
    func `The span puts the latest near-baseline point at four fifths of the axis`() {
        let span = ToleranceChartScale.spanMinutes(
            nearBaselineMinutes: [8 * 1_440, 600, 0], fadeMinutes: [30 * 1_440, 900, 100],
        )
        #expect(abs(span - 10 * 1_440) < 1e-6)
    }

    @Test
    func `A mechanism with no near-baseline point takes the longest span`() {
        let span = ToleranceChartScale.spanMinutes(nearBaselineMinutes: [600, nil], fadeMinutes: [900, 0])
        #expect(span == ToleranceChartScale.maximumSpanMinutes)
    }

    @Test
    func `Mechanisms already near baseline are plotted across their fade`() {
        let span = ToleranceChartScale.spanMinutes(nearBaselineMinutes: [0, 0], fadeMinutes: [3 * 1_440, 1_000])
        #expect(span == 3 * 1_440)
    }

    @Test
    func `The span stays between six hours and eight weeks`() {
        #expect(ToleranceChartScale.spanMinutes(nearBaselineMinutes: [20], fadeMinutes: [40]) == 360)
        #expect(ToleranceChartScale.spanMinutes(nearBaselineMinutes: [], fadeMinutes: []) == 360)
        #expect(
            ToleranceChartScale.spanMinutes(nearBaselineMinutes: [300 * 1_440], fadeMinutes: [0])
                == ToleranceChartScale.maximumSpanMinutes,
        )
    }

    // MARK: - Near-baseline date

    private static let paris = TimeZone(identifier: "Europe/Paris") ?? .gmt

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = paris
        return calendar
    }

    /// Monday 23 November 2026, 19:16 in Paris.
    private static let now = Date(timeIntervalSince1970: 1_795_457_760)

    private static func text(_ minutesAhead: Double, locale: String, timeZone: TimeZone = paris) -> String {
        ToleranceBaselineDate.text(
            for: now.addingTimeInterval(minutesAhead * 60),
            precision: ToleranceBaselineDate.precision(minutesAhead: minutesAhead),
            locale: Locale(identifier: locale), calendar: calendar, timeZone: timeZone,
        )
        // Foundation separates the clock from AM/PM with a narrow no-break space.
        .replacingOccurrences(of: "\u{202F}", with: " ")
    }

    @Test
    func `A point under a day away prints the weekday and the nearest hour`() {
        // 19:16 + 14 h 10 min = 09:26 on Tuesday, nearest hour 09:00.
        #expect(Self.text(850, locale: "en_GB") == "Tue 09:00")
        #expect(Self.text(850, locale: "en_US") == "Tue 9:00 AM")
        // 19:16 + 100 min = 20:56, nearest hour 21:00.
        #expect(Self.text(100, locale: "en_GB") == "Mon 21:00")
    }

    @Test
    func `The nearest hour is taken on the reader's clock`() throws {
        // Kolkata is UTC+5:30: 23:46 there, plus 30 min is 00:16 on Tuesday, nearest hour 00:00.
        let kolkata = try #require(TimeZone(identifier: "Asia/Kolkata"))
        #expect(Self.text(30, locale: "en_GB", timeZone: kolkata) == "Tue 00:00")
    }

    @Test
    func `A point days away prints the weekday, day and month`() {
        #expect(Self.text(3 * 1_440, locale: "en_GB") == "Thu 26 Nov")
        #expect(Self.text(3 * 1_440, locale: "en_US") == "Thu, Nov 26")
        #expect(Self.text(11 * 1_440, locale: "fr_FR") == "ven. 4 déc.")
    }

    @Test
    func `A point over half a year away prints the month and year`() {
        #expect(Self.text(200 * 1_440, locale: "en_GB") == "Jun 2027")
        #expect(Self.text(200 * 1_440, locale: "en_US") == "Jun 2027")
    }

    @Test
    func `Precision steps from the hour to the day to the month`() {
        #expect(ToleranceBaselineDate.precision(minutesAhead: 1_439) == .hour)
        #expect(ToleranceBaselineDate.precision(minutesAhead: 1_440) == .day)
        #expect(ToleranceBaselineDate.precision(minutesAhead: 180 * 1_440 - 1) == .day)
        #expect(ToleranceBaselineDate.precision(minutesAhead: 180 * 1_440) == .month)
    }

    // MARK: - The near-baseline point on a row

    private static func row(
        _ receptorClass: ReceptorClasses.ReceptorClass, sAcute: Double, sAdaptive: Double, occupancy: Double = 0.6,
    ) -> ToleranceRow {
        ToleranceRow(
            snapshot: ClassTolerance(
                receptorClass: receptorClass,
                sAcute: sAcute, sAdaptive: sAdaptive, sDeep: 0, sSynthesis: 0,
                chronicExposure: 0, representativeOccupancy: occupancy,
                confidence: .medium, subTargets: [], contributors: [],
                safetyShiftFactor: nil, safetyEndpointKind: nil,
            ),
            params: ReceptorClasses.parameters(for: receptorClass),
        )
    }

    @Test
    func `Near baseline is the rested boundary of the tolerance buckets`() {
        let boundary = 1 - ToleranceRow.nearBaselineSeverity
        #expect(ToleranceBucket(responseFraction: boundary) == .rested)
        #expect(ToleranceBucket(responseFraction: boundary - 0.001) == .mild)
        #expect(ToleranceRow.minimumCardSeverity == ToleranceRow.nearBaselineSeverity)
    }

    @Test(arguments: [ReceptorClasses.ReceptorClass.adenosine, .catecholamineStimulant, .muOpioid, .gaba])
    func `The curve reads near baseline at the minute the row names`(receptorClass: ReceptorClasses.ReceptorClass) throws {
        let row = Self.row(receptorClass, sAcute: 0.3, sAdaptive: 0.6)
        #expect(row.snapshot.severity > ToleranceRow.nearBaselineSeverity)
        let minutes = try #require(row.minutesToNearBaseline)
        #expect(minutes > 0)
        #expect(abs(row.tolerancePercent(afterMinutes: minutes) - ToleranceRow.nearBaselineSeverity * 100) < 0.01)
        #expect(row.tolerancePercent(afterMinutes: minutes * 0.9) > ToleranceRow.nearBaselineSeverity * 100)
        #expect(abs(row.tolerancePercent(afterMinutes: 0) - row.snapshot.severity * 100) < 1e-9)
    }

    @Test
    func `A row already near baseline names no wait`() {
        let row = Self.row(.adenosine, sAcute: 0.02, sAdaptive: 0.03)
        #expect(row.snapshot.severity < ToleranceRow.nearBaselineSeverity)
        #expect(row.minutesToNearBaseline == 0)
    }

    @Test
    func `The curve starts at the current level, ends at the window and never rises`() {
        let row = Self.row(.catecholamineStimulant, sAcute: 0.5, sAdaptive: 0.4)
        let points = row.recoveryCurve(overMinutes: 14 * 1_440)
        #expect(points.first?.day == 0)
        #expect(abs((points.last?.day ?? 0) - 14) < 1e-9)
        #expect(abs((points.first?.percent ?? 0) - row.snapshot.severity * 100) < 1e-9)
        #expect(zip(points, points.dropFirst()).allSatisfy { $0.percent >= $1.percent && $0.day < $1.day })
    }

    @Test
    func `One frame holds every plotted row's level and near-baseline point`() throws {
        let rows = [
            Self.row(.adenosine, sAcute: 0.3, sAdaptive: 0.6),
            Self.row(.catecholamineStimulant, sAcute: 0.5, sAdaptive: 0.1),
        ]
        let frame = ToleranceChartFrame(rows: rows)
        for row in rows {
            #expect(frame.value.top >= row.snapshot.severity * 100)
            let crossing = try #require(row.minutesToNearBaseline) / 1_440
            #expect(crossing < frame.time.endDays)
        }
    }

    @Test
    func `A band too narrow to see is left off the bar`() {
        let row = Self.row(.adenosine, sAcute: 0.001, sAdaptive: 0.6)
        #expect(row.bands.map(\.id) == [1])
        #expect(row.bands.allSatisfy { $0.widthFraction >= ToleranceRow.minimumBandWidth })
    }

    // MARK: - Ceiling Effect ticks

    @Test
    func `Whole multiples reach every point in six labels or fewer`() {
        #expect(CeilingChartScale.wholeMultiples(from: 1, through: 6) == [1, 2, 3, 4, 5, 6])
        #expect(CeilingChartScale.wholeMultiples(from: 1, through: 4) == [1, 2, 3, 4])
        #expect(CeilingChartScale.wholeMultiples(from: 1, through: 8) == [1, 2, 4, 6, 8])
        #expect(CeilingChartScale.wholeMultiples(from: 1, through: 7) == [1, 2, 4, 6, 8])
        #expect(CeilingChartScale.wholeMultiples(from: 1, through: 0.4) == [1])
        #expect(CeilingChartScale.wholeMultiples(from: 1, through: 12) == [1, 5, 10, 15])
        for last in stride(from: 0.5, through: 300, by: 0.5) {
            let ticks = CeilingChartScale.wholeMultiples(from: 1, through: last)
            #expect(ticks.count <= 6)
            #expect((ticks.last ?? 0) >= last)
        }
    }

    @Test
    func `Concentration charts tick in round hours and end on a tick inside the window`() {
        let half = CeilingChartScale.timeTicks(windowMinutes: 780)
        #expect(half.ticks == [0, 3, 6, 9, 12])
        #expect(half.usesDays == false)
        #expect(half.endMinutes == 720)

        let day = CeilingChartScale.timeTicks(windowMinutes: 1_440)
        #expect(day.ticks == [0, 6, 12, 18, 24])
        #expect(day.endMinutes == 1_440)

        let week = CeilingChartScale.timeTicks(windowMinutes: 5 * 1_440)
        #expect(week.ticks == [0, 1, 2, 3, 4, 5])
        #expect(week.usesDays)
    }
}
