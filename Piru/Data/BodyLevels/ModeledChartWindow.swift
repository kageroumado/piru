import Foundation

/// The span a modeled-level chart (In Your Body, Receptor Load) draws for a range. It is the whole
/// range when the log reaches back that far, and otherwise starts just before the first logged
/// dose, so a log younger than the range fills the chart's width rather than its last pixels.
/// "All" always starts at the first dose.
struct ModeledChartWindow: Equatable {
    let start: Date
    let end: Date

    /// Room left before the first dose so its rise is not drawn against the axis: a tenth of the
    /// log's age, between half an hour and a day.
    private static let marginBounds: ClosedRange<TimeInterval> = 1_800 ... 86_400

    /// Below this length the axis names hours rather than dates.
    static let hourAxisLimit: TimeInterval = 2 * 86_400

    /// - Parameter reach: how far back from `now` the model behind the chart replays the log, for a
    ///   model that stops short of the first dose; the window starts no earlier than that.
    init(range: UsageTimeRange, firstDose: Date?, now: Date, reach: TimeInterval? = nil) {
        end = now
        let opens = Self.start(range: range, firstDose: firstDose, now: now)
        start = reach.map { max(opens, now.addingTimeInterval(-$0)) } ?? opens
    }

    private static func start(range: UsageTimeRange, firstDose: Date?, now: Date) -> Date {
        let rangeStart = range.days.map { now.addingTimeInterval(-Double($0) * 86_400) }
        guard let firstDose, firstDose < now else {
            return rangeStart ?? now.addingTimeInterval(-365 * 86_400)
        }
        let age = now.timeIntervalSince(firstDose)
        let margin = min(max(age / 10, marginBounds.lowerBound), marginBounds.upperBound)
        let logStart = firstDose.addingTimeInterval(-margin)
        return rangeStart.map { max($0, logStart) } ?? logStart
    }

    var length: TimeInterval {
        end.timeIntervalSince(start)
    }

    var span: ClosedRange<Date> {
        start ... end
    }

    /// The x-axis label format: hours across a day or two, dates beyond.
    var axisFormat: Date.FormatStyle {
        Self.axisFormat(for: span)
    }

    /// The x-axis ticks: whole hours across a day or two, `nil` (the chart's own
    /// date ticks) beyond.
    var axisTicks: [Date]? {
        Self.hourTicks(in: span)
    }

    /// Hours across a day or two, dates beyond; a span that holds no whole hour
    /// takes its labels from the chart's own ticks, so they carry minutes.
    static func axisFormat(for span: ClosedRange<Date>) -> Date.FormatStyle {
        if hourTicks(in: span) == nil, span.upperBound.timeIntervalSince(span.lowerBound) < hourAxisLimit {
            return .dateTime.hour().minute()
        }
        return span.upperBound.timeIntervalSince(span.lowerBound) < hourAxisLimit
            ? .dateTime.hour()
            : .dateTime.month(.abbreviated).day()
    }

    /// Whole hours inside `span`, at most five, at a stride of 1, 2, 3, 4, 6 or 12 hours, so each
    /// label names a different hour; `nil` for a span of two days or more, or one holding no whole hour.
    static func hourTicks(in span: ClosedRange<Date>, calendar: Calendar = .current) -> [Date]? {
        let length = span.upperBound.timeIntervalSince(span.lowerBound)
        guard length > 0, length < hourAxisLimit,
              let firstHour = calendar.dateInterval(of: .hour, for: span.lowerBound)?.end
        else { return nil }
        let hours = length / 3_600
        let stride = [1, 2, 3, 4, 6, 12].first { hours / Double($0) <= 5 } ?? 12
        var ticks: [Date] = []
        var tick = firstHour
        // Align multi-hour strides to the clock: 6 PM, not 5 PM, on a 3-hour stride.
        while calendar.component(.hour, from: tick) % stride != 0 {
            tick = tick.addingTimeInterval(3_600)
        }
        while tick <= span.upperBound {
            ticks.append(tick)
            tick = tick.addingTimeInterval(Double(stride) * 3_600)
        }
        return ticks.isEmpty ? nil : ticks
    }

    /// Receptor Load's sample spacing: about 300 samples across a week or less, so a session of a
    /// few hours keeps its shape, then coarser as the span widens so a year is not a comb.
    var receptorLoadStep: TimeInterval {
        switch length {
        case ..<(8 * 86_400): max(120, length / 336)
        case ..<(31 * 86_400): 3 * 3_600
        case ..<(91 * 86_400): 6 * 3_600
        case ..<(366 * 86_400): 12 * 3_600
        default: max(12 * 3_600, length / 1_000)
        }
    }
}
