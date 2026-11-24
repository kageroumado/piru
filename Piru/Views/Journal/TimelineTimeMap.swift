import CoreGraphics
import Foundation

/// The vertical timeline's global time → height map: ascending breakpoint
/// times with cumulative heights, uniform points-per-minute everywhere except
/// where the strip is deliberately squeezed. Pure geometry so the compression
/// rules are testable without a store.
///
/// Three kinds of stretch:
/// - **Active time** — any span the builder reports a curve still legibly
///   above baseline (``TimelineActivity/activeThreshold``) and not yet a
///   baseline of its own (``TimelineActivity/baselineMinutes``) — always
///   keeps the uniform scale. Compression squeezes only dead time, never the
///   inside of an event's curve.
/// - **Dead time** in the past is capped per segment (`gapCap`), so an empty
///   night costs a bounded strip. Each squeezed run is reported in
///   ``compressedRuns``, and the strip breaks its axis there.
/// - **Skipped whole days** between two dosed days collapse to one fixed
///   ``breakHeight`` run that draws no axis — a visible break, not a ruler.
///
/// Past now, active time keeps the uniform scale the same way, so a running
/// curve's decay reads at the scale it rose at. Only the empty future beyond
/// the last active end has its own, far roomier cap (and a point floor), so
/// the live edge stays near the top of the strip.
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

    /// Dead-time runs drawn shorter than the uniform scale, merged where they
    /// touch. The strip marks each with a break on its axis, so a squeezed
    /// stretch never reads as a short one.
    let compressedRuns: [DateInterval]

    var totalHeight: CGFloat {
        ys.last ?? 0
    }

    /// The empty run standing in for skipped days.
    static let breakHeight: CGFloat = 24
    /// Point floor for an empty segment past now, at any zoom: keeps the "Now"
    /// tag below the day tag in the gutter and clear of the axis arrowhead.
    static let liveEdgeMinimumHeight: CGFloat = 52
    /// Point floor for any past segment, so two breakpoints never coincide.
    static let pastMinimumHeight: CGFloat = 2

    /// Cap on one dead-time segment, in points, at the given resolution.
    static func gapCap(pointsPerMinute ppm: CGFloat) -> CGFloat {
        max(90, 45 * ppm)
    }

    /// Cap on an empty segment past now — future time no curve is active in.
    static func futureCap(pointsPerMinute ppm: CGFloat) -> CGFloat {
        max(240, 240 * ppm)
    }

    /// Cap on one empty segment with compression off: three days at the
    /// uniform scale. Shorter spans keep that scale exactly; a longer empty run
    /// (a dose dated years ahead or behind) would otherwise make a strip
    /// millions of points tall, which hangs the main thread laying it out.
    static func uncompressedRunCap(pointsPerMinute ppm: CGFloat) -> CGFloat {
        3 * 1_440 * ppm
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
        let uncompressedCap = Self.uncompressedRunCap(pointsPerMinute: ppm)
        let gapCap: CGFloat = compressGaps ? Self.gapCap(pointsPerMinute: ppm) : uncompressedCap
        let futureCap: CGFloat = compressGaps ? Self.futureCap(pointsPerMinute: ppm) : uncompressedCap
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
        // Bounds taken in either order: a strip whose oldest moment lies past
        // its live edge (every dose logged ahead of now) still gets a map. Only
        // a non-finite bound leaves `times` empty, and every lookup below
        // answers 0 for that rather than trapping.
        // Finiteness is checked explicitly: `Date`'s `>=` is "not less than",
        // so a NaN bound would otherwise admit every time.
        let lower = min(start, end)
        let upper = max(start, end)
        let boundsAreFinite = lower.timeIntervalSinceReferenceDate.isFinite && upper.timeIntervalSinceReferenceDate.isFinite
        let times = boundsAreFinite
            ? eventTimes.filter(\.timeIntervalSinceReferenceDate.isFinite).sorted().filter { $0 >= lower && $0 <= upper }
            : []

        var heights: [CGFloat] = []
        heights.reserveCapacity(max(times.count - 1, 0))
        var compressed: [DateInterval] = []
        var kinds: [SegmentKind] = []
        kinds.reserveCapacity(max(times.count - 1, 0))
        var activeIndex = 0
        for i in 0 ..< max(times.count - 1, 0) {
            let segmentStart = times[i]
            let segmentEnd = times[i + 1]
            if breakStarts.contains(segmentStart) {
                heights.append(Self.breakHeight)
                kinds.append(.skippedDays)
                continue
            }
            let minutes = CGFloat(segmentEnd.timeIntervalSince(segmentStart) / 60)
            // Advance past intervals that ended before this segment; the
            // merged list is sorted and disjoint, so the walk is one pass.
            while activeIndex < active.count, active[activeIndex].end <= segmentStart {
                activeIndex += 1
            }
            let isActive = activeIndex < active.count && active[activeIndex].start < segmentEnd
            kinds.append(isActive ? .active : .empty)
            // Active time keeps the uniform scale on both sides of now: a cap
            // inside a running curve would shear its decay flat at the Now line.
            if isActive {
                heights.append(max(minutes * ppm, Self.pastMinimumHeight))
                continue
            }
            let cap = segmentStart >= now ? futureCap : gapCap
            if minutes * ppm > cap {
                compressed.append(DateInterval(start: segmentStart, end: segmentEnd))
            }
            if segmentStart >= now {
                heights.append(max(min(minutes * ppm, futureCap), Self.liveEdgeMinimumHeight))
            } else {
                heights.append(max(min(minutes * ppm, gapCap), Self.pastMinimumHeight))
            }
        }

        // The live-edge floor holds for the whole future too: when active
        // time runs to the strip's edge there is no empty segment to carry it.
        if let firstFuture = times.firstIndex(where: { $0 >= now }), firstFuture < heights.count {
            let futureHeight = heights[firstFuture...].reduce(0, +)
            if futureHeight < Self.liveEdgeMinimumHeight {
                heights[heights.count - 1] += Self.liveEdgeMinimumHeight - futureHeight
            }
        }

        // Slice floors: an undersized slice grows until its cards fit without
        // spilling into the next day. The room goes to its largest empty
        // segment, so active time keeps the uniform scale; a slice active
        // throughout grows evenly, which keeps its curves in proportion.
        for slice in slices {
            let lo = Self.firstIndex(in: times) { $0 >= slice.bottomTime }
            let hi = Self.firstIndex(in: times) { $0 > slice.topTime } - 1
            guard lo < times.count, hi > lo else { continue }
            let sliceHeight = heights[lo ..< hi].reduce(0, +)
            guard sliceHeight < slice.minimumHeight else { continue }
            let deficit = slice.minimumHeight - sliceHeight
            if let emptiest = (lo ..< hi).filter({ kinds[$0] == .empty }).max(by: { heights[$0] < heights[$1] }) {
                heights[emptiest] += deficit
            } else {
                let active = (lo ..< hi).filter { kinds[$0] == .active }
                let activeHeight = active.reduce(0) { $0 + heights[$1] }
                guard activeHeight > 0 else { continue }
                for i in active {
                    heights[i] += deficit * heights[i] / activeHeight
                }
            }
        }

        var ys: [CGFloat] = [0]
        ys.reserveCapacity(times.count)
        for h in heights {
            ys.append(ys[ys.count - 1] + h)
        }
        self.times = times
        self.ys = ys
        compressedRuns = Self.merged(compressed)
    }

    /// Height between two moments on the strip (`from` older than `to`).
    func height(from older: Date, to newer: Date) -> CGFloat {
        forwardY(newer) - forwardY(older)
    }

    /// Cumulative height from the strip's start up to `t`, interpolating
    /// within a segment.
    func forwardY(_ t: Date) -> CGFloat {
        guard let first = times.first, let last = times.last else { return 0 }
        if t <= first { return 0 }
        if t >= last { return totalHeight }
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

    /// The first index of the ascending `times` at which `isAtOrPast` holds,
    /// or `times.count` when it never does — the slice floors look up every
    /// slice's span, so a linear scan per slice is quadratic in the log.
    private static func firstIndex(in times: [Date], where isAtOrPast: (Date) -> Bool) -> Int {
        var low = 0
        var high = times.count
        while low < high {
            let mid = (low + high) / 2
            if isAtOrPast(times[mid]) { high = mid } else { low = mid + 1 }
        }
        return low
    }

    /// What a segment between two breakpoints holds.
    private enum SegmentKind {
        case active
        case empty
        case skippedDays
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
