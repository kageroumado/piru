import CoreGraphics
import Foundation
import Testing
@testable import Piru

@Suite("TimelineTimeMap")
struct TimelineTimeMapTests {
    private let ppm: CGFloat = 1.4
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func minutes(_ m: Double) -> TimeInterval {
        m * 60
    }

    // MARK: - Active spans keep the uniform scale

    @Test
    func `A long curve after a lone dose is never compressed`() {
        // One dose twelve days ago whose curve runs twelve hours, then dead
        // time up to now: the twelve active hours cost exactly their uniform
        // height while the days after them collapse to one capped gap.
        let dose = now.addingTimeInterval(-12 * 86_400)
        let curveEnd = dose.addingTimeInterval(minutes(720))
        let start = dose.addingTimeInterval(-minutes(5))
        let end = now.addingTimeInterval(minutes(10))
        let map = TimelineTimeMap(
            start: start,
            end: end,
            now: now,
            slices: [.init(bottomTime: start, topTime: end, breakAbove: false, minimumHeight: 0)],
            anchors: [dose],
            activeIntervals: [DateInterval(start: dose, end: curveEnd)],
            pointsPerMinute: ppm,
            compressGaps: true,
        )

        let uncompressed = 720 * ppm
        #expect(abs(map.height(from: dose, to: curveEnd) - uncompressed) < 0.5)
        // Every hour inside the curve keeps its share too — compression
        // never squeezes the inside of a curve.
        let hourIn = dose.addingTimeInterval(minutes(360))
        #expect(abs(map.height(from: hourIn, to: hourIn.addingTimeInterval(minutes(60))) - 60 * ppm) < 0.5)
        // The dead stretch after the curve is one capped gap.
        #expect(map.height(from: curveEnd, to: now) <= TimelineTimeMap.gapCap(pointsPerMinute: ppm) + 0.5)
    }

    @Test
    func `A dose with no curve still compresses the time after it`() {
        let dose = now.addingTimeInterval(-3 * 86_400)
        let start = dose.addingTimeInterval(-minutes(5))
        let end = now.addingTimeInterval(minutes(10))
        let map = TimelineTimeMap(
            start: start,
            end: end,
            now: now,
            slices: [.init(bottomTime: start, topTime: end, breakAbove: false, minimumHeight: 0)],
            anchors: [dose],
            activeIntervals: [],
            pointsPerMinute: ppm,
            compressGaps: true,
        )
        #expect(map.height(from: dose, to: now) <= TimelineTimeMap.gapCap(pointsPerMinute: ppm) + 0.5)
    }

    @Test
    func `Overlapping curves merge into one active span`() {
        let first = now.addingTimeInterval(-minutes(600))
        let second = first.addingTimeInterval(minutes(120))
        let start = first.addingTimeInterval(-minutes(5))
        let end = now.addingTimeInterval(minutes(10))
        let map = TimelineTimeMap(
            start: start,
            end: end,
            now: now,
            slices: [.init(bottomTime: start, topTime: end, breakAbove: false, minimumHeight: 0)],
            anchors: [first, second],
            activeIntervals: [
                DateInterval(start: first, duration: minutes(180)),
                DateInterval(start: second, duration: minutes(180)),
            ],
            pointsPerMinute: ppm,
            compressGaps: true,
        )
        // first → second + 180 min is one continuous active span of 300 min.
        #expect(abs(map.height(from: first, to: second.addingTimeInterval(minutes(180))) - 300 * ppm) < 0.5)
    }

    @Test
    func `Compression off keeps every span at the uniform scale`() {
        let dose = now.addingTimeInterval(-2 * 86_400)
        let start = dose.addingTimeInterval(-minutes(5))
        let end = now.addingTimeInterval(minutes(10))
        let map = TimelineTimeMap(
            start: start,
            end: end,
            now: now,
            slices: [.init(bottomTime: start, topTime: end, breakAbove: true, minimumHeight: 0)],
            anchors: [dose],
            activeIntervals: [],
            pointsPerMinute: ppm,
            compressGaps: false,
        )
        #expect(abs(map.height(from: dose, to: now) - 2 * 1_440 * ppm) < 0.5)
    }

    // MARK: - Breaks

    @Test
    func `Skipped days between two slices cost exactly the break height`() {
        let older = now.addingTimeInterval(-10 * 86_400)
        let olderTop = older.addingTimeInterval(minutes(300))
        let newerBottom = now.addingTimeInterval(-minutes(600))
        let start = older.addingTimeInterval(-minutes(5))
        let end = now.addingTimeInterval(minutes(10))
        let map = TimelineTimeMap(
            start: start,
            end: end,
            now: now,
            slices: [
                .init(bottomTime: newerBottom, topTime: end, breakAbove: false, minimumHeight: 0),
                .init(bottomTime: start, topTime: olderTop, breakAbove: true, minimumHeight: 0),
            ],
            anchors: [older, newerBottom.addingTimeInterval(minutes(60))],
            activeIntervals: [DateInterval(start: older, end: olderTop)],
            pointsPerMinute: ppm,
            compressGaps: true,
        )
        #expect(abs(map.height(from: olderTop, to: newerBottom) - TimelineTimeMap.breakHeight) < 0.01)
        // The slice below the break is untouched by it.
        #expect(abs(map.height(from: older, to: olderTop) - 300 * ppm) < 0.5)
    }

    // MARK: - Lookup

    @Test
    func `Reversed y runs from the newest moment at the top`() {
        let dose = now.addingTimeInterval(-minutes(120))
        let start = dose.addingTimeInterval(-minutes(5))
        let end = now.addingTimeInterval(minutes(10))
        let map = TimelineTimeMap(
            start: start,
            end: end,
            now: now,
            slices: [.init(bottomTime: start, topTime: end, breakAbove: false, minimumHeight: 0)],
            anchors: [dose],
            activeIntervals: [DateInterval(start: dose, end: now)],
            pointsPerMinute: ppm,
            compressGaps: true,
        )
        #expect(map.reversedY(end) == 0)
        #expect(map.reversedY(start) == map.totalHeight)
        #expect(map.reversedY(dose) > map.reversedY(now))
    }

    @Test
    func `Merged intervals are sorted and disjoint`() {
        let t0 = now
        let merged = TimelineTimeMap.merged([
            DateInterval(start: t0.addingTimeInterval(minutes(100)), duration: minutes(50)),
            DateInterval(start: t0, duration: minutes(60)),
            DateInterval(start: t0.addingTimeInterval(minutes(30)), duration: minutes(60)),
        ])
        #expect(merged.count == 2)
        #expect(merged[0] == DateInterval(start: t0, duration: minutes(90)))
        #expect(merged[1] == DateInterval(start: t0.addingTimeInterval(minutes(100)), duration: minutes(50)))
    }
}
