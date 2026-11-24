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
    func `A curve still running past now keeps the uniform scale into the future`() {
        // Dosed an hour ago, a twelve-hour curve: the eleven hours ahead of
        // now are active and cost their uniform height, far past the future
        // cap; only the margin after the curve is the live edge's own run.
        let dose = now.addingTimeInterval(-minutes(60))
        let curveEnd = dose.addingTimeInterval(minutes(720))
        let start = dose.addingTimeInterval(-minutes(5))
        let end = curveEnd.addingTimeInterval(minutes(30))
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
        #expect(abs(map.height(from: now, to: curveEnd) - 660 * ppm) < 0.5)
        #expect(660 * ppm > TimelineTimeMap.futureCap(pointsPerMinute: ppm))
        // The same hour reads the same height either side of now.
        let hourBefore = map.height(from: now.addingTimeInterval(-minutes(60)), to: now)
        let hourAfter = map.height(from: now, to: now.addingTimeInterval(minutes(60)))
        #expect(abs(hourBefore - hourAfter) < 0.5)
        // The empty margin past the curve keeps the live edge's floor.
        #expect(map.height(from: curveEnd, to: end) >= TimelineTimeMap.liveEdgeMinimumHeight - 0.01)
    }

    @Test
    func `Empty future time stays capped and floored`() {
        let dose = now.addingTimeInterval(-minutes(600))
        let start = dose.addingTimeInterval(-minutes(5))
        let longEnd = now.addingTimeInterval(minutes(1_000))
        let longMap = TimelineTimeMap(
            start: start,
            end: longEnd,
            now: now,
            slices: [.init(bottomTime: start, topTime: longEnd, breakAbove: false, minimumHeight: 0)],
            anchors: [dose],
            activeIntervals: [DateInterval(start: dose, duration: minutes(120))],
            pointsPerMinute: ppm,
            compressGaps: true,
        )
        #expect(longMap.height(from: now, to: longEnd) <= TimelineTimeMap.futureCap(pointsPerMinute: ppm) + 0.5)

        let shortEnd = now.addingTimeInterval(minutes(10))
        let shortMap = TimelineTimeMap(
            start: start,
            end: shortEnd,
            now: now,
            slices: [.init(bottomTime: start, topTime: shortEnd, breakAbove: false, minimumHeight: 0)],
            anchors: [dose],
            activeIntervals: [],
            pointsPerMinute: ppm,
            compressGaps: true,
        )
        #expect(abs(shortMap.height(from: now, to: shortEnd) - TimelineTimeMap.liveEdgeMinimumHeight) < 0.01)
    }

    @Test
    func `A curve running to the strip's edge still leaves the live edge its floor`() {
        // Active from before now to the very edge, ten minutes ahead: no empty
        // future segment exists, and the floor still holds.
        let dose = now.addingTimeInterval(-minutes(60))
        let start = dose.addingTimeInterval(-minutes(5))
        let end = now.addingTimeInterval(minutes(10))
        let map = TimelineTimeMap(
            start: start,
            end: end,
            now: now,
            slices: [.init(bottomTime: start, topTime: end, breakAbove: false, minimumHeight: 0)],
            anchors: [dose],
            activeIntervals: [DateInterval(start: dose, end: end)],
            pointsPerMinute: ppm,
            compressGaps: true,
        )
        #expect(map.height(from: now, to: end) >= TimelineTimeMap.liveEdgeMinimumHeight - 0.01)
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

    @Test
    func `Compression off shortens an empty run longer than three days`() {
        let past = now.addingTimeInterval(-86_400)
        let farFuture = now.addingTimeInterval(730 * 86_400)
        let start = past.addingTimeInterval(-minutes(5))
        let map = TimelineTimeMap(
            start: start,
            end: farFuture,
            now: now,
            slices: [.init(bottomTime: start, topTime: farFuture, breakAbove: false, minimumHeight: 0)],
            anchors: [past, farFuture],
            activeIntervals: [],
            pointsPerMinute: ppm,
            compressGaps: false,
        )
        #expect(map.height(from: now, to: farFuture) <= TimelineTimeMap.uncompressedRunCap(pointsPerMinute: ppm) + 0.5)
        #expect(map.totalHeight < 5 * 1_440 * ppm)
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

    // MARK: - Every input gets a map

    @Test
    func `A log dated entirely ahead of now still maps`() {
        // The launch crash loop: the only dose sits two hours ahead and draws
        // no curve, so the strip's oldest moment (five minutes before it)
        // lay past its live edge (ten minutes past now), every breakpoint was
        // filtered out, and the first lookup read `times[0]` of an empty array.
        let dose = now.addingTimeInterval(minutes(120))
        let start = dose.addingTimeInterval(-minutes(5))
        let end = now.addingTimeInterval(minutes(10))
        let map = TimelineTimeMap(
            start: start,
            end: end,
            now: now,
            slices: [.init(bottomTime: Calendar.current.startOfDay(for: dose), topTime: end, breakAbove: false, minimumHeight: 80)],
            anchors: [dose],
            activeIntervals: [],
            pointsPerMinute: ppm,
            compressGaps: true,
        )
        #expect(!map.times.isEmpty)
        #expect(map.reversedY(end).isFinite)
        #expect(map.reversedY(dose).isFinite)
        #expect(map.totalHeight >= 0)
    }

    @Test
    func `A map with no breakpoints answers zero instead of trapping`() {
        let nan = Date(timeIntervalSinceReferenceDate: .nan)
        let map = TimelineTimeMap(
            start: nan,
            end: nan,
            now: now,
            slices: [],
            anchors: [],
            activeIntervals: [],
            pointsPerMinute: ppm,
            compressGaps: true,
        )
        #expect(map.times.isEmpty)
        #expect(map.totalHeight == 0)
        #expect(map.forwardY(now) == 0)
        #expect(map.reversedY(now) == 0)
        #expect(map.height(from: now, to: now.addingTimeInterval(60)) == 0)
    }

    @Test
    func `A single breakpoint maps every moment to zero height`() {
        let map = TimelineTimeMap(
            start: now,
            end: now,
            now: now,
            slices: [],
            anchors: [],
            activeIntervals: [],
            pointsPerMinute: ppm,
            compressGaps: true,
        )
        #expect(map.times.count == 1)
        #expect(map.forwardY(now.addingTimeInterval(-60)) == 0)
        #expect(map.forwardY(now.addingTimeInterval(60)) == 0)
    }

    @Test @MainActor
    func `The strip's live edge never falls short of the newest dose`() {
        // No curve, dose two hours ahead: the edge follows the dose, so the
        // strip's oldest moment always lies below it.
        let ahead = now.addingTimeInterval(minutes(120))
        let end = TimelineStripBuilder.stripEnd(now: now, modeledCurves: [], newestDose: ahead)
        #expect(end > ahead.addingTimeInterval(-minutes(5)))
        // A dose two days ahead with a curve: the one-day future cap yields to it.
        let farAhead = now.addingTimeInterval(2 * 86_400)
        let farEnd = TimelineStripBuilder.stripEnd(
            now: now,
            modeledCurves: [DateInterval(start: farAhead, duration: minutes(240))],
            newestDose: farAhead,
        )
        #expect(farEnd > farAhead)
        // A past log keeps the usual edge: ten minutes past now.
        let pastEnd = TimelineStripBuilder.stripEnd(now: now, modeledCurves: [], newestDose: now.addingTimeInterval(-minutes(60)))
        #expect(pastEnd == now.addingTimeInterval(minutes(10)))
    }

    @Test @MainActor
    func `A dose days ahead holds the edge open to its curve's end`() {
        // Dosed three days ahead, a six-hour curve: the whole curve is on the
        // strip, plus the usual margin.
        let ahead = now.addingTimeInterval(3 * 86_400)
        let curve = DateInterval(start: ahead, duration: minutes(360))
        let end = TimelineStripBuilder.stripEnd(now: now, modeledCurves: [curve], newestDose: ahead)
        #expect(end == curve.end.addingTimeInterval(minutes(30)))
        // A week-long body-load tail from that dose stops a day past the dose.
        let tail = DateInterval(start: ahead, duration: 7 * 86_400)
        let tailEnd = TimelineStripBuilder.stripEnd(now: now, modeledCurves: [tail], newestDose: ahead)
        #expect(tailEnd == ahead.addingTimeInterval(86_400))
        // A dose already taken keeps the one-day cap past now.
        let taken = DateInterval(start: now.addingTimeInterval(-minutes(60)), duration: 7 * 86_400)
        let takenEnd = TimelineStripBuilder.stripEnd(now: now, modeledCurves: [taken], newestDose: taken.start)
        #expect(takenEnd == now.addingTimeInterval(86_400))
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

    // MARK: - Compressed runs and slice floors

    @Test
    func `Squeezed empty time is reported as one run and active time never is`() {
        let dose = now.addingTimeInterval(-12 * 86_400)
        let curveEnd = dose.addingTimeInterval(minutes(720))
        let start = dose.addingTimeInterval(-minutes(5))
        let end = now.addingTimeInterval(minutes(10))
        let map = TimelineTimeMap(
            start: start, end: end, now: now,
            slices: [.init(bottomTime: start, topTime: end, breakAbove: false, minimumHeight: 0)],
            anchors: [dose, dose.addingTimeInterval(4 * 86_400)],
            activeIntervals: [DateInterval(start: dose, end: curveEnd)],
            pointsPerMinute: ppm, compressGaps: true,
        )
        // The anchor four days in splits the empty stretch in two; both halves
        // are squeezed and merge into one run, from the curve's end to now.
        #expect(map.compressedRuns == [DateInterval(start: curveEnd, end: now)])
        #expect(!map.compressedRuns.contains { $0.intersects(DateInterval(start: dose, end: curveEnd.addingTimeInterval(-1))) })
    }

    @Test
    func `Empty time short enough to keep its scale is not reported`() {
        let dose = now.addingTimeInterval(-minutes(90))
        let start = dose.addingTimeInterval(-minutes(5))
        let end = now.addingTimeInterval(minutes(10))
        let map = TimelineTimeMap(
            start: start, end: end, now: now,
            slices: [.init(bottomTime: start, topTime: end, breakAbove: false, minimumHeight: 0)],
            anchors: [dose],
            activeIntervals: [DateInterval(start: dose, duration: minutes(30))],
            pointsPerMinute: ppm, compressGaps: true,
        )
        #expect(map.compressedRuns.isEmpty)
    }

    @Test
    func `A slice grown to fit its cards takes the room from its empty time`() {
        // Two hours active, then an hour empty before now; the cards need far
        // more than the slice's height. The active hours keep their uniform
        // height and the empty hour absorbs the rest.
        let dose = now.addingTimeInterval(-minutes(180))
        let curveEnd = dose.addingTimeInterval(minutes(120))
        let start = dose.addingTimeInterval(-minutes(5))
        let end = now.addingTimeInterval(minutes(10))
        let map = TimelineTimeMap(
            start: start, end: end, now: now,
            slices: [.init(bottomTime: start, topTime: end, breakAbove: false, minimumHeight: 1_200)],
            anchors: [dose, dose.addingTimeInterval(minutes(40))],
            activeIntervals: [DateInterval(start: dose, end: curveEnd)],
            pointsPerMinute: ppm, compressGaps: true,
        )
        #expect(map.totalHeight >= 1_200 - 0.5)
        #expect(abs(map.height(from: dose, to: curveEnd) - 120 * ppm) < 0.5)
        let first = map.height(from: dose, to: dose.addingTimeInterval(minutes(40)))
        let second = map.height(from: dose.addingTimeInterval(minutes(40)), to: dose.addingTimeInterval(minutes(80)))
        #expect(abs(first - second) < 0.5)
    }

    @Test
    func `A slice active throughout grows evenly`() {
        // Now lies an hour past the slice, so none of it is future time.
        let dose = now.addingTimeInterval(-minutes(120))
        let start = dose
        let end = now
        let map = TimelineTimeMap(
            start: start, end: end, now: now.addingTimeInterval(minutes(60)),
            slices: [.init(bottomTime: start, topTime: end, breakAbove: false, minimumHeight: 600)],
            anchors: [dose.addingTimeInterval(minutes(30))],
            activeIntervals: [DateInterval(start: start, end: end)],
            pointsPerMinute: ppm, compressGaps: true,
        )
        #expect(abs(map.totalHeight - 600) < 0.5)
        let short = map.height(from: dose, to: dose.addingTimeInterval(minutes(30)))
        let long = map.height(from: dose.addingTimeInterval(minutes(30)), to: end)
        #expect(abs(long - 3 * short) < 0.5)
    }
}
