import Foundation
import Testing
@testable import Piru

/// The correlation pass over "did it work?" answers: one variable at a time,
/// and never below the floor where a single bad week would write the headline.
@Suite("FeltPatterns")
@MainActor
struct FeltPatternsTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func day(
        _ index: Int, hour: Double, amount: Double = 10, unit: String = "mg",
        isWeekend: Bool = false, caffeine: Bool = false, asExpected: Bool,
    ) -> FeltPatternsModel.RatedDay {
        FeltPatternsModel.RatedDay(
            day: Date(timeIntervalSince1970: Double(index) * 86_400),
            substance: "Methylphenidate",
            doseHour: hour,
            amount: amount,
            unit: unit,
            isWeekend: isWeekend,
            hadCaffeineBefore: caffeine,
            wasAsExpected: asExpected,
        )
    }

    @Test
    func `The median is where this person's own days sit`() {
        #expect(FeltPatternsModel.median([1, 2, 3]) == 2)
        #expect(FeltPatternsModel.median([1, 2, 3, 4]) == 2.5)
        #expect(FeltPatternsModel.median([]) == nil)
    }

    @Test
    func `A split under the floor on either side is not reported`() {
        // Four early days and six late ones: the early side is short.
        var rows = (0 ..< 4).map { day($0, hour: 7, asExpected: true) }
        rows += (4 ..< 10).map { day($0, hour: 11, asExpected: false) }
        let splits = FeltPatternsModel.splits(from: rows, calendar: calendar)
        #expect(!splits.contains { $0.variable == .doseHour })
    }

    @Test
    func `A split with enough on both sides reports the counts it saw`() {
        var rows = (0 ..< 6).map { day($0, hour: 7, asExpected: true) }
        rows += (6 ..< 12).map { day($0, hour: 11, asExpected: false) }
        let splits = FeltPatternsModel.splits(from: rows, calendar: calendar)
        let hour = try? #require(splits.first { $0.variable == .doseHour })
        #expect(hour?.low.days == 6)
        #expect(hour?.low.asExpected == 6)
        #expect(hour?.high.days == 6)
        #expect(hour?.high.asExpected == 0)
        #expect(hour?.gap == 1)
    }

    @Test
    func `Amounts in different units are never compared`() {
        var rows = (0 ..< 6).map { day($0, hour: 9, amount: 5, unit: "mg", asExpected: true) }
        rows += (6 ..< 12).map { day($0, hour: 9, amount: 20, unit: "µg", asExpected: false) }
        let splits = FeltPatternsModel.splits(from: rows, calendar: calendar)
        #expect(!splits.contains { $0.variable == .amount })
    }

    @Test
    func `Two substances are never mixed into one comparison`() {
        var rows = (0 ..< 6).map { day($0, hour: 7, asExpected: true) }
        rows += (6 ..< 12).map { index -> FeltPatternsModel.RatedDay in
            var row = day(index, hour: 11, asExpected: false)
            row = FeltPatternsModel.RatedDay(
                day: row.day, substance: "Lorazepam", doseHour: row.doseHour,
                amount: row.amount, unit: row.unit, isWeekend: row.isWeekend,
                hadCaffeineBefore: row.hadCaffeineBefore, wasAsExpected: row.wasAsExpected,
            )
            return row
        }
        let splits = FeltPatternsModel.splits(from: rows, calendar: calendar)
        // Each substance has only six days of its own and no second side.
        #expect(splits.isEmpty)
    }

    @Test
    func `A caffeine split reads both sides when both are lived`() {
        var rows = (0 ..< 6).map { day($0, hour: 9, caffeine: true, asExpected: false) }
        rows += (6 ..< 12).map { day($0, hour: 9, caffeine: false, asExpected: true) }
        let splits = FeltPatternsModel.splits(from: rows, calendar: calendar)
        let caffeine = try? #require(splits.first { $0.variable == .caffeine })
        #expect(caffeine?.high.days == 6)
        #expect(caffeine?.low.asExpected == 6)
    }
}
