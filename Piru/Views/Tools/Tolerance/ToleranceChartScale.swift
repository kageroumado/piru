import Foundation

/// Axis choices for the Modeled Tolerance charts. Pure functions of a peak or a span, so every chart
/// on the screen reads against one frame and each choice is testable without a view.
nonisolated enum ToleranceChartScale {
    // MARK: - Value axis

    /// The value axis of a tolerance chart, in percent of a usual dose's effect.
    struct ValueAxis: Equatable {
        /// The top of the plot.
        let top: Double
        /// The labeled gridlines, from 0 to ``top``.
        let ticks: [Double]
    }

    /// Tops the value axis may take, each with the step between its gridlines.
    private static let valueLadder: [(top: Double, step: Double)] = [
        (20, 10), (30, 10), (40, 20), (50, 25), (60, 20), (80, 20), (100, 25),
    ]

    /// The value axis for curves that peak at `peakPercent`: the lowest rung that holds the peak, so the
    /// plot is mostly data and its top gridline carries a round label. The lowest rung is 20%, which
    /// keeps the 10% near-baseline line inside every plot.
    static func valueAxis(peakPercent: Double) -> ValueAxis {
        let peak = max(0, min(100, peakPercent))
        let rung = valueLadder.first { peak <= $0.top } ?? (top: 100, step: 25)
        return ValueAxis(top: rung.top, ticks: Array(stride(from: 0, through: rung.top, by: rung.step)))
    }

    // MARK: - Time axis

    /// The one unit a time axis counts in.
    enum TimeUnit: Equatable {
        case hours
        case days
        case weeks

        /// The unit's length in days.
        var days: Double {
            switch self {
            case .hours: 1.0 / 24
            case .days: 1
            case .weeks: 7
            }
        }
    }

    /// A time axis from "now": `intervals` steps of `step` units each, ending on a labeled tick.
    struct TimeAxis: Equatable {
        let unit: TimeUnit
        /// Units between neighboring ticks.
        let step: Int
        /// Steps from now to the end of the axis.
        let intervals: Int

        /// The end of the axis, in days from now.
        var endDays: Double {
            Double(step * intervals) * unit.days
        }

        /// Every tick from now (0) to the end, in days.
        var tickDays: [Double] {
            (0 ... intervals).map { Double(step * $0) * unit.days }
        }

        /// Unlabeled gridlines between the ticks, in days: every day on an axis of single weeks or of
        /// two-day steps, every half step on an axis of 6 or 12 hours, so a coarse axis still reads to
        /// the day or the quarter day.
        var minorGridDays: [Double] {
            let parts = switch (unit, step) {
            case (.weeks, 1): 7
            case (.days, 2), (.hours, 6), (.hours, 12): 2
            default: 1
            }
            guard parts > 1 else { return [] }
            let minor = Double(step) * unit.days / Double(parts)
            return (0 ... intervals * parts).filter { $0 % parts != 0 }.map { Double($0) * minor }
        }

        /// The count the tick at `days` prints, in this axis's unit ("12" for the 12 h tick).
        func count(atDays days: Double) -> Int {
            Int((days / unit.days).rounded())
        }
    }

    /// Longest span counted in hours, and the longest counted in whole days.
    private static let hoursLimitDays = 2.0
    private static let daysLimitDays = 12.0

    /// Most steps an axis takes: at phone width, six keep the last two labels apart when the last one
    /// ends at the plot's edge.
    private static let maxIntervals = 6

    /// A time axis covering `spanDays` in steps a person counts in: hours up to two days, whole days up
    /// to twelve, weeks beyond. The step is the smallest of the unit's round steps that keeps the labels
    /// apart at phone width, and the end is rounded up to a whole step.
    static func timeAxis(spanDays: Double) -> TimeAxis {
        let span = max(spanDays, TimeUnit.hours.days)
        if span <= hoursLimitDays {
            return axis(span: span, unit: .hours, steps: [1, 2, 3, 6, 12])
        }
        if span <= daysLimitDays {
            return axis(span: span, unit: .days, steps: [1, 2])
        }
        return axis(span: span, unit: .weeks, steps: [1, 2, 4, 8, 13, 26])
    }

    private static func axis(span: Double, unit: TimeUnit, steps: [Int]) -> TimeAxis {
        let units = span / unit.days
        func intervals(_ step: Int) -> Int {
            max(1, Int((units / Double(step) - 1e-9).rounded(.up)))
        }
        let step = steps.first { intervals($0) <= maxIntervals } ?? steps[steps.count - 1]
        return TimeAxis(unit: unit, step: step, intervals: intervals(step))
    }

    // MARK: - Shared span

    /// Shortest and longest span the charts take, in minutes: six hours, and eight weeks.
    static let minimumSpanMinutes: Double = 6 * 60
    static let maximumSpanMinutes: Double = 56 * 1_440

    /// Share of the span the latest near-baseline crossing sits at, so its mark has plot on both sides.
    private static let crossingPosition = 0.8

    /// The span every chart on the screen shares, in minutes. It reaches past the latest point at which
    /// a plotted mechanism reads near baseline, so each crossing is on screen; a mechanism with no such
    /// point inside the forecast (`nil`) takes the longest span. When every mechanism already reads near
    /// baseline, the span is the longest of `fadeMinutes`, the time each takes to fade out.
    ///
    /// `settleMinutes` carries, for each projected (scheduled-med) class, when its curve settles — so the
    /// span also reaches far enough for the settling to be on screen. A projection still rising at the
    /// projection horizon passes that horizon here and pins the span to its maximum.
    static func spanMinutes(
        nearBaselineMinutes: [Double?], fadeMinutes: [Double], settleMinutes: [Double] = [],
    ) -> Double {
        let settleBasis = settleMinutes.map { $0 / crossingPosition }.max() ?? 0
        guard !nearBaselineMinutes.contains(where: { $0 == nil }) else {
            return min(max(settleBasis, maximumSpanMinutes), maximumSpanMinutes)
        }
        let latest = nearBaselineMinutes.compactMap(\.self).max() ?? 0
        let decayBasis = latest > 0 ? latest / crossingPosition : fadeMinutes.max() ?? 0
        return min(max(max(decayBasis, settleBasis), minimumSpanMinutes), maximumSpanMinutes)
    }
}

/// The date a mechanism reads near baseline, printed no finer than the model can place it.
nonisolated enum ToleranceBaselineDate {
    /// How finely a date is printed.
    enum Precision: Equatable {
        /// Weekday and clock time to the minute: the scrubbed instant on an hours axis.
        case minute
        /// Weekday and clock time rounded to the hour: a point under a day away.
        case hour
        /// Weekday, day and month.
        case day
        /// Month and year: a point months away.
        case month
    }

    /// The precision for a point `minutesAhead` of now: the hour inside a day, the day inside half a
    /// year, the month beyond.
    static func precision(minutesAhead: Double) -> Precision {
        switch minutesAhead {
        case ..<1_440: .hour
        case ..<(180 * 1_440): .day
        default: .month
        }
    }

    /// `date` in the reader's locale at `precision`: "Tue 21:00", "Thu 26 Nov", "Mar 2027".
    static func text(
        for date: Date, precision: Precision,
        locale: Locale = .current, calendar: Calendar = .current, timeZone: TimeZone = .current,
    ) -> String {
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone)
        switch precision {
        case .minute:
            return date.formatted(style.weekday(.abbreviated).hour().minute())
        case .hour:
            return roundedToHour(date, in: timeZone).formatted(style.weekday(.abbreviated).hour().minute())
        case .day:
            return date.formatted(style.weekday(.abbreviated).day().month(.abbreviated))
        case .month:
            return date.formatted(style.month(.abbreviated).year())
        }
    }

    /// `date` moved to the nearest full hour on `timeZone`'s clock.
    private static func roundedToHour(_ date: Date, in timeZone: TimeZone) -> Date {
        let offset = Double(timeZone.secondsFromGMT(for: date))
        let local = date.timeIntervalSinceReferenceDate + offset
        return Date(timeIntervalSinceReferenceDate: (local / 3_600).rounded() * 3_600 - offset)
    }
}
