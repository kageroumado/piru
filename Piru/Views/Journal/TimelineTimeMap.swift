import CoreGraphics
import Foundation

/// The vertical timeline's global time → height map: ascending breakpoint
/// times with cumulative heights, uniform points-per-minute everywhere except
/// where the strip is deliberately squeezed. Pure geometry so the compression
/// rules are testable without a store.
///
/// Three kinds of stretch:
/// - **Active time** — any span where a curve is still above ~5 % of its own
///   peak — always keeps the uniform scale. Compression squeezes only dead
///   time, never the inside of a curve.
/// - **Dead time** in the past is capped per segment (`gapCap`), so an empty
///   night costs a bounded strip; the hour ticks bunching together is the
///   compression cue.
/// - **Skipped whole days** between two dosed days collapse to one fixed
///   ``breakHeight`` run that draws no axis — a visible break, not a ruler.
///
/// The segment past now carries the active curves' tails and has its own,
/// far roomier cap, so the live edge stays near the top of the strip.
nonisolated struct TimelineTimeMap {
    /// One day slice's span on the strip, plus the room its cards need.
    struct Slice {
        let bottomTime: Date
        let topTime: Date
        /// `true` when whole days are skipped between this slice's top and
        /// the next newer slice — the span between them is a break.
        let breakAbove: Bool
        /// Height the slice's cards need; an undersized slice has its largest
        /// segment stretched to fit them.
        let minimumHeight: CGFloat
    }

    /// Ascending breakpoint times.
    let times: [Date]
    /// Cumulative height at each breakpoint; `ys[0] == 0`.
    let ys: [CGFloat]

    var totalHeight: CGFloat {
        ys[ys.count - 1]
    }

    /// The empty run standing in for skipped days.
    static let breakHeight: CGFloat = 24
    /// Point floor for the segment past now, at any zoom: keeps the "Now"
    /// tag below the day tag in the gutter and clear of the axis arrowhead.
    static let liveEdgeMinimumHeight: CGFloat = 52
    /// Point floor for any past segment, so two breakpoints never coincide.
    static let pastMinimumHeight: CGFloat = 2

    /// Cap on one dead-time segment, in points, at the given resolution.
    static func gapCap(pointsPerMinute ppm: CGFloat) -> CGFloat {
        max(90, 45 * ppm)
    }

    /// Cap on the segment past now.
    static func futureCap(pointsPerMinute ppm: CGFloat) -> CGFloat {
        max(240, 240 * ppm)
    }

    /// - Parameters:
    ///   - start: the strip's oldest moment.
    ///   - end: the strip's newest moment (the live edge).
    ///   - now: the current time; segments at or after it are the future.
    ///   - slices: every day slice, in any order.
    ///   - anchors: extra breakpoints — the card groups' representative times.
    ///   - activeIntervals: spans where some curve is still above threshold.
    ///   - pointsPerMinute: the uniform resolution.
    ///   - compressGaps: `false` for a stable 1:1 scale everywhere.
    init(
        start: Date,
        end: Date,
        now: Date,
        slices: [Slice],
        anchors: [Date],
        activeIntervals: [DateInterval],
        pointsPerMinute ppm: CGFloat,
        compressGaps: Bool,
    ) {
        let gapCap: CGFloat = compressGaps ? Self.gapCap(pointsPerMinute: ppm) : .infinity
        let futureCap: CGFloat = compressGaps ? Self.futureCap(pointsPerMinute: ppm) : .infinity
        let active = Self.merged(activeIntervals)

        var eventTimes: Set<Date> = [start, end, now]
        var breakStarts: Set<Date> = []
        for slice in slices {
            eventTimes.insert(slice.bottomTime)
            eventTimes.insert(slice.topTime)
            if slice.breakAbove, compressGaps {
                breakStarts.insert(slice.topTime)
            }
        }
        for anchor in anchors {
            eventTimes.insert(anchor)
        }
        for interval in active {
            eventTimes.insert(interval.start)
            eventTimes.insert(interval.end)
        }
        let times = eventTimes.sorted().filter { $0 >= start && $0 <= end }

        var heights: [CGFloat] = []
        heights.reserveCapacity(max(times.count - 1, 0))
        var activeIndex = 0
        for i in 0 ..< max(times.count - 1, 0) {
            let segmentStart = times[i]
            let segmentEnd = times[i + 1]
            if breakStarts.contains(segmentStart) {
                heights.append(Self.breakHeight)
                continue
            }
            let minutes = CGFloat(segmentEnd.timeIntervalSince(segmentStart) / 60)
            if segmentStart >= now {
                heights.append(max(min(minutes * ppm, futureCap), Self.liveEdgeMinimumHeight))
                continue
            }
            // Advance past intervals that ended before this segment; the
            // merged list is sorted and disjoint, so the walk is one pass.
            while activeIndex < active.count, active[activeIndex].end <= segmentStart {
                activeIndex += 1
            }
            let isActive = activeIndex < active.count && active[activeIndex].start < segmentEnd
            let cap = isActive ? .infinity : gapCap
            heights.append(max(min(minutes * ppm, cap), Self.pastMinimumHeight))
        }

        // Slice floors: stretch the largest segment inside an undersized
        // slice so its cards fit without spilling into the next day.
        for slice in slices {
            guard let lo = times.firstIndex(where: { $0 >= slice.bottomTime }),
                  let hi = times.lastIndex(where: { $0 <= slice.topTime }),
                  hi > lo else { continue }
            let sliceHeight = heights[lo ..< hi].reduce(0, +)
            if sliceHeight < slice.minimumHeight,
               let biggest = (lo ..< hi).max(by: { heights[$0] < heights[$1] }) {
                heights[biggest] += slice.minimumHeight - sliceHeight
            }
        }

        var ys: [CGFloat] = [0]
        ys.reserveCapacity(times.count)
        for h in heights {
            ys.append(ys[ys.count - 1] + h)
        }
        self.times = times
        self.ys = ys
    }

    /// Height between two moments on the strip (`from` older than `to`).
    func height(from older: Date, to newer: Date) -> CGFloat {
        forwardY(newer) - forwardY(older)
    }

    /// Cumulative height from the strip's start up to `t`, interpolating
    /// within a segment.
    func forwardY(_ t: Date) -> CGFloat {
        if t <= times[0] { return 0 }
        if t >= times[times.count - 1] { return totalHeight }
        var lo = 0
        var hi = times.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if times[mid] <= t { lo = mid } else { hi = mid }
        }
        let span = times[hi].timeIntervalSince(times[lo])
        let f = span > 0 ? t.timeIntervalSince(times[lo]) / span : 0
        return ys[lo] + (ys[hi] - ys[lo]) * CGFloat(f)
    }

    /// Reversed lookup — the strip's top is the newest moment, so later
    /// time → smaller y.
    func reversedY(_ t: Date) -> CGFloat {
        totalHeight - forwardY(t)
    }

    /// Sorted, disjoint union of `intervals`.
    static func merged(_ intervals: [DateInterval]) -> [DateInterval] {
        let sorted = intervals.filter { $0.duration > 0 }.sorted { $0.start < $1.start }
        var result: [DateInterval] = []
        for interval in sorted {
            if let last = result.last, interval.start <= last.end {
                result[result.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                result.append(interval)
            }
        }
        return result
    }
}
