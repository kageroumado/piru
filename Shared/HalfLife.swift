import Foundation

/// A substance's elimination half-life as its source states it: one number, or the range the
/// source gives.
///
/// Sources mostly do not know a half-life to one number. "4 to 26 hours" is what the
/// literature says about clozapine, and picking 12 hours out of that was how this database
/// came to print a precision nobody measured. So the range is stored and shown, and the
/// engines — which need a single number to exponentiate — take ``representative``.
///
/// **``representative`` is the only place that number is chosen.** Call sites ask for it;
/// none of them re-derives it from the bounds, because two call sites deriving it two ways is
/// the bug this type exists to prevent.
nonisolated struct HalfLife: Hashable, Codable, Sendable {
    /// The number the engines run on: the value the source states, or, for a source that
    /// states only a range, that range's geometric mean.
    let minutes: Double
    /// The range the source states, when it states one. `nil` for a point value.
    let rangeMinutes: ClosedRange<Double>?

    /// The geometric mean of a range — its midpoint on the log scale that exponential
    /// elimination actually runs on, so it sits the same number of half-lives from each end.
    /// An arithmetic mean of 4 and 26 hours (15 h) is nearly four half-lives from the low end
    /// and barely half of one from the high end.
    static func geometricMean(of range: ClosedRange<Double>) -> Double {
        (range.lowerBound * range.upperBound).squareRoot()
    }

    init(minutes: Double, rangeMinutes: ClosedRange<Double>? = nil) {
        self.minutes = minutes
        self.rangeMinutes = rangeMinutes
    }

    /// A half-life known only as a range.
    init(rangeMinutes range: ClosedRange<Double>) {
        minutes = Self.geometricMean(of: range)
        rangeMinutes = range
    }

    /// Builds from the database's three columns, which carry a point value and, when the
    /// source gave a range, its two ends. A range whose ends are missing or inverted is
    /// dropped rather than guessed at.
    init?(minutes: Double?, lower: Double?, upper: Double?) {
        var range: ClosedRange<Double>?
        if let lower, let upper, lower > 0, lower < upper {
            range = lower ... upper
        }
        if let minutes, minutes > 0 {
            self.init(minutes: minutes, rangeMinutes: range)
        } else if let range {
            self.init(rangeMinutes: range)
        } else {
            return nil
        }
    }

    /// The single number every engine and projection uses.
    ///
    /// Precedence: a number the source states wins, and the geometric mean of the range is
    /// what stands in when the source states only a range. ``minutes`` already holds that
    /// choice — the pipeline derives it the same way when it writes the row, so the database
    /// column and this property can never disagree — and ``geometricMean(of:)`` is the one
    /// definition both sides apply.
    var representative: Double { minutes }

    var isRange: Bool { rangeMinutes != nil }

    /// `"20–33 h"` for a range, `"6 h"` for a point value: what every surface shows.
    ///
    /// Both ends are rendered through the same scale, so a range never reads "90 min – 2 h".
    /// The scale is the one the *low* end asks for, because that is the end a coarser unit
    /// would flatten: 47–150 hours reads "47–150 h", where days would make its low end "2".
    var displayText: String {
        guard let rangeMinutes else { return Self.scalarText(minutes) }
        let unit = Self.unit(for: rangeMinutes.lowerBound)
        let low = Self.number(rangeMinutes.lowerBound, in: unit)
        let high = Self.number(rangeMinutes.upperBound, in: unit)
        return unit.label("\(low)–\(high)")
    }

    /// The unit a half-life of this size reads best in.
    nonisolated enum Unit: Sendable {
        case minutes
        case hours
        case days

        /// A number (or range of numbers) with this unit after it. The key carries the number
        /// so the unit is translated as a duration: a bare "min" key is the catalog's
        /// "minimum" (the custom-substance range field), and reads 最小 in Chinese.
        func label(_ number: String) -> String {
            switch self {
            case .minutes: String(localized: "\(number) min", comment: "A duration in minutes")
            case .hours: String(localized: "\(number) h", comment: "A duration in hours")
            case .days: String(localized: "\(number) days", comment: "A duration in days")
            }
        }
    }

    static func unit(for minutes: Double) -> Unit {
        if minutes < 60 { return .minutes }
        return minutes >= 48 * 60 ? .days : .hours
    }

    /// One end of a range, in a unit chosen for the whole range, rounded to one decimal so a
    /// clean value keeps its clean form ("3 h", not "3.0 h").
    static func number(_ minutes: Double, in unit: Unit) -> String {
        let value: Double = switch unit {
        case .minutes: minutes
        case .hours: (minutes / 6).rounded() / 10
        case .days: (minutes / 144).rounded() / 10
        }
        return value == value.rounded()
            ? String(Int(value.rounded()))
            : String(format: "%.1f", value)
    }

    /// One half-life as text, in the unit it reads best in: `"14 h"`, `"45 min"`, `"3.1 days"`.
    static func scalarText(_ minutes: Double) -> String {
        let unit = unit(for: minutes)
        return unit.label(number(minutes, in: unit))
    }
}
