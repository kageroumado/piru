import Foundation
import SwiftData
import SwiftUI

/// What the "did it work?" answers line up with, across the log.
///
/// The note stays a record — it shows the word that was entered and nothing
/// derived from it. Everything interpretive is here, which is what Insights
/// already is: Adherence, Usage and Patterns all read the log and draw
/// conclusions from it while the log itself stays a record.
///
/// **This is correlation from one person with no control.** A pattern here is a
/// thing to notice, never a reason; the screen says so once, plainly, and the
/// copy never turns an observation into an instruction.
@MainActor
@Observable
final class FeltPatternsModel {
    /// A day counts on one side or the other only once, and a side reports
    /// only with this many days on it. Below the floor, one bad week writes
    /// the headline. Stated in the screen's own copy as well as here.
    nonisolated static let minimumPerSide = 5

    /// What a split is cut on. One variable at a time — a pattern built from
    /// two at once is a pattern found by looking, not by the log.
    nonisolated enum Variable: String, CaseIterable {
        case doseHour
        case amount
        case weekday
        case caffeine
    }

    /// One day's answer for one substance: the mean of that day's ratings,
    /// read as "about right or better" against "less than usual".
    nonisolated struct RatedDay {
        let day: Date
        let substance: String
        let doseHour: Double
        let amount: Double
        let unit: String
        let isWeekend: Bool
        let hadCaffeineBefore: Bool
        /// `true` when the day's mean rating is `about right` or `more`.
        let wasAsExpected: Bool
    }

    nonisolated struct Tally {
        var days = 0
        var asExpected = 0

        var fraction: Double {
            days == 0 ? 0 : Double(asExpected) / Double(days)
        }
    }

    nonisolated struct Split: Identifiable {
        let substance: String
        let variable: Variable
        let lowLabel: String
        let highLabel: String
        let low: Tally
        let high: Tally

        var id: String {
            "\(substance)|\(variable.rawValue)"
        }

        /// How far apart the two sides read, in percentage points.
        var gap: Double {
            abs(low.fraction - high.fraction)
        }
    }

    private(set) var splits: [Split] = []
    private(set) var ratedDayCount = 0
    private(set) var substanceCount = 0
    private(set) var isLoaded = false

    /// A gap smaller than this is two sides reading the same; it is listed as
    /// no difference rather than dressed up as one.
    nonisolated static let notableGap = 0.20

    var notable: [Split] {
        splits.filter { $0.gap >= Self.notableGap }
    }

    var flat: [Split] {
        splits.filter { $0.gap < Self.notableGap }
    }

    func recompute(sessions: [Session], entries: [DoseEntry], calendar: Calendar = .current) {
        let days = Self.ratedDays(sessions: sessions, entries: entries, calendar: calendar)
        ratedDayCount = days.count
        substanceCount = Set(days.map(\.substance)).count
        splits = Self.splits(from: days, calendar: calendar).sorted { $0.gap > $1.gap }
        isLoaded = true
    }

    // MARK: - Joining notes to the dose that anchored them

    /// One row per (day, substance) that carries a rating.
    ///
    /// A note is attributed to the dose in its session that most recently
    /// preceded it; a note with no dose before it in its session has nothing to
    /// be a rating *of* and is skipped.
    static func ratedDays(
        sessions: [Session], entries: [DoseEntry], calendar: Calendar,
    ) -> [RatedDay] {
        let caffeineTimes = entries
            .filter { SubstanceLibrary.lookup($0.substance)?.name.lowercased() == "caffeine" }
            .map(\.timestamp)
            .sorted()

        // key: day + substance → the ratings and the anchoring dose
        var buckets: [String: (day: Date, dose: DoseEntry, ratings: [Int])] = [:]
        for session in sessions {
            let doses = session.orderedDoses
            guard !doses.isEmpty else { continue }
            for note in session.orderedNotes {
                guard let rating = note.worked else { continue }
                guard let dose = doses.last(where: { $0.timestamp <= note.timestamp }) else { continue }
                guard let substance = SubstanceLibrary.lookup(dose.substance)?.name else { continue }
                let day = calendar.startOfDay(for: dose.timestamp)
                let key = "\(day.timeIntervalSince1970)|\(substance.lowercased())"
                if var bucket = buckets[key] {
                    bucket.ratings.append(rating)
                    buckets[key] = bucket
                } else {
                    buckets[key] = (day: day, dose: dose, ratings: [rating])
                }
            }
        }

        return buckets.values.compactMap { bucket in
            guard let substance = SubstanceLibrary.lookup(bucket.dose.substance)?.name else { return nil }
            let mean = Double(bucket.ratings.reduce(0, +)) / Double(bucket.ratings.count)
            let hour = Double(calendar.component(.hour, from: bucket.dose.timestamp))
                + Double(calendar.component(.minute, from: bucket.dose.timestamp)) / 60
            let weekday = calendar.component(.weekday, from: bucket.dose.timestamp)
            let hadCaffeine = caffeineTimes.contains {
                let delta = bucket.dose.timestamp.timeIntervalSince($0)
                return delta >= 0 && delta <= 3_600
            }
            return RatedDay(
                day: bucket.day,
                substance: substance,
                doseHour: hour,
                amount: bucket.dose.amount,
                unit: bucket.dose.unit,
                isWeekend: weekday == 1 || weekday == 7,
                hadCaffeineBefore: hadCaffeine,
                wasAsExpected: mean >= 0,
            )
        }
    }

    // MARK: - The splits

    nonisolated static func splits(from days: [RatedDay], calendar: Calendar) -> [Split] {
        var out: [Split] = []
        for (substance, rows) in Dictionary(grouping: days, by: \.substance) {
            out += hourSplit(substance: substance, rows: rows, calendar: calendar).map { [$0] } ?? []
            out += amountSplit(substance: substance, rows: rows).map { [$0] } ?? []
            out += weekdaySplit(substance: substance, rows: rows).map { [$0] } ?? []
            out += caffeineSplit(substance: substance, rows: rows).map { [$0] } ?? []
        }
        return out
    }

    /// Tally two groups, or nil when either is under the floor.
    private nonisolated static func tallied(
        substance: String, variable: Variable,
        lowLabel: String, highLabel: String,
        low: [RatedDay], high: [RatedDay],
    ) -> Split? {
        guard low.count >= minimumPerSide, high.count >= minimumPerSide else { return nil }
        func tally(_ rows: [RatedDay]) -> Tally {
            Tally(days: rows.count, asExpected: rows.count { $0.wasAsExpected })
        }
        return Split(
            substance: substance, variable: variable,
            lowLabel: lowLabel, highLabel: highLabel,
            low: tally(low), high: tally(high),
        )
    }

    /// The median, so the cut is where this person's own days actually sit
    /// rather than at an hour or a milligram someone picked.
    nonisolated static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    private nonisolated static func hourSplit(substance: String, rows: [RatedDay], calendar: Calendar) -> Split? {
        guard let cut = median(rows.map(\.doseHour)) else { return nil }
        let clock = hourLabel(cut, calendar: calendar)
        return tallied(
            substance: substance, variable: .doseHour,
            lowLabel: String(localized: "Before \(clock)"),
            highLabel: String(localized: "\(clock) or later"),
            low: rows.filter { $0.doseHour < cut },
            high: rows.filter { $0.doseHour >= cut },
        )
    }

    /// The cut as a clock time, in the reader's own format.
    nonisolated static func hourLabel(_ hour: Double, calendar: Calendar) -> String {
        var components = DateComponents()
        components.hour = Int(hour)
        components.minute = Int((hour - Double(Int(hour))) * 60)
        let date = calendar.date(from: components) ?? Date(timeIntervalSince1970: hour * 3_600)
        return date.formatted(date: .omitted, time: .shortened)
    }

    private nonisolated static func amountSplit(substance: String, rows: [RatedDay]) -> Split? {
        // Mixed units would compare numbers that are not the same quantity.
        let units = Set(rows.map(\.unit))
        guard units.count == 1, let unit = units.first else { return nil }
        guard let cut = median(rows.map(\.amount)), cut > 0 else { return nil }
        let cutText = "\(cut.doseFormatted) \(unit)"
        return tallied(
            substance: substance, variable: .amount,
            lowLabel: String(localized: "Under \(cutText)"),
            highLabel: String(localized: "\(cutText) or more"),
            low: rows.filter { $0.amount < cut },
            high: rows.filter { $0.amount >= cut },
        )
    }

    private nonisolated static func weekdaySplit(substance: String, rows: [RatedDay]) -> Split? {
        tallied(
            substance: substance, variable: .weekday,
            lowLabel: String(localized: "Weekdays"),
            highLabel: String(localized: "Weekends"),
            low: rows.filter { !$0.isWeekend },
            high: rows.filter(\.isWeekend),
        )
    }

    private nonisolated static func caffeineSplit(substance: String, rows: [RatedDay]) -> Split? {
        tallied(
            substance: substance, variable: .caffeine,
            lowLabel: String(localized: "No caffeine first"),
            highLabel: String(localized: "Caffeine within the hour"),
            low: rows.filter { !$0.hadCaffeineBefore },
            high: rows.filter(\.hadCaffeineBefore),
        )
    }
}

extension FeltPatternsModel.Variable {
    var title: LocalizedStringKey {
        switch self {
        case .doseHour: "Time of day"
        case .amount: "Amount"
        case .weekday: "Day of week"
        case .caffeine: "Caffeine before it"
        }
    }

    var icon: String {
        switch self {
        case .doseHour: "clock"
        case .amount: "scalemass"
        case .weekday: "calendar"
        case .caffeine: "cup.and.saucer"
        }
    }
}
