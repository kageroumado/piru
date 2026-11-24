import Foundation
import SwiftData
import Testing
@testable import Piru

/// The strip marks a dose's phase boundaries only while no other dose's
/// effect window overlaps its own. Each slice reads the doses near it by
/// binary search over the log's states; these pin that the marks it finds
/// are the ones a scan of every dose would find.
@MainActor
@Suite("Timeline strip milestones", .serialized)
struct TimelineStripMilestoneTests {
    private let substance = "Caffeine"

    private func makeContext() throws -> (ModelContext, ModelContainer) {
        let container = try ModelContainer(
            for: Schema(PiruSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none),
        )
        return (ModelContext(container), container)
    }

    /// 09:00 on the day `daysAgo` before today, plus `minutes`.
    private func time(daysAgo: Int, minutes: Double = 0) -> Date {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: DebugClock.now))!
        return day.addingTimeInterval(9 * 3_600 + minutes * 60)
    }

    private func dose(_ timestamp: Date, in context: ModelContext) -> DoseEntry {
        let entry = DoseEntry(substance: substance, amount: 100, unit: "mg", timestamp: timestamp)
        context.insert(entry)
        return entry
    }

    private func layouts(_ entries: [DoseEntry]) throws -> [TimelineDayLayout] {
        var builder = try #require(TimelineStripBuilder(
            entries: entries,
            colors: [],
            colorMap: [:],
            zoom: 1,
            compressGaps: true,
            style: TimelineDayLayout.Style(showsAxis: true, bubbleStyle: .full, pkMode: false),
        ))
        return (0 ..< builder.sliceCount).map { builder.layout(sliceAt: $0) }
    }

    private func doseKey(_ state: ActiveSubstanceState) -> String {
        "\(state.substanceName)|\(Int(state.doseTimestamp.timeIntervalSince1970))"
    }

    @Test
    func `A dose alone in its window is marked, two overlapping doses are not`() async throws {
        await SubstanceStore.shared.ensureAllLoaded()
        let (context, container) = try makeContext()
        defer { withExtendedLifetime(container) {} }
        let lone = dose(time(daysAgo: 10), in: context)
        let first = dose(time(daysAgo: 5), in: context)
        let second = dose(time(daysAgo: 5, minutes: 30), in: context)

        let states = [lone, first, second].compactMap { ActiveSubstanceState.from(entry: $0, tint: .neutral) }
        try #require(states.count == 3, "Caffeine resolves duration data from the bundled catalog")

        let marked = try Set(layouts([second, first, lone]).flatMap(\.milestones).map(\.doseKey))
        #expect(marked.contains(doseKey(states[0])))
        #expect(!marked.contains(doseKey(states[1])))
        #expect(!marked.contains(doseKey(states[2])))
    }

    @Test
    func `Every marked dose is alone in its window, over a long log`() async throws {
        await SubstanceStore.shared.ensureAllLoaded()
        let (context, container) = try makeContext()
        defer { withExtendedLifetime(container) {} }
        // Ninety days: a lone morning dose on most, a redose on every third,
        // a dose three hours on on every fifth.
        var entries: [DoseEntry] = []
        for day in 1 ... 90 {
            entries.append(dose(time(daysAgo: day), in: context))
            if day.isMultiple(of: 3) { entries.append(dose(time(daysAgo: day, minutes: 45), in: context)) }
            if day.isMultiple(of: 5) { entries.append(dose(time(daysAgo: day, minutes: 180), in: context)) }
        }
        entries.sort { $0.timestamp > $1.timestamp }

        let states = entries.compactMap { ActiveSubstanceState.from(entry: $0, tint: .neutral) }
        try #require(states.count == entries.count)
        func window(_ state: ActiveSubstanceState) -> DateInterval {
            DateInterval(start: state.doseTimestamp, duration: max(state.totalMinutes, 1) * 60)
        }
        let alone = Set(states.filter { state in
            !states.contains { other in
                other.doseTimestamp != state.doseTimestamp && window(other).intersects(window(state))
            }
        }.map(doseKey))

        let marked = try Set(layouts(entries).flatMap(\.milestones).map(\.doseKey))
        #expect(!marked.isEmpty)
        #expect(marked.isSubset(of: alone))
        // Days 1, 2 and 4 hold one dose each, nowhere near another.
        for day in [1, 2, 4] {
            let state = try #require(states.first { $0.doseTimestamp == time(daysAgo: day) })
            #expect(marked.contains(doseKey(state)))
        }
    }
}
