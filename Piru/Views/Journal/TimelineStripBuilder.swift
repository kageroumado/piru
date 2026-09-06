import SwiftData
import SwiftUI

/// Builds the global time map once, then lays out day slices on demand
/// (newest first) so the model can publish them progressively.
@MainActor
struct TimelineStripBuilder {
    private let colorMap: [String: Color]
    private let remainingFractions: [PersistentIdentifier: Double]
    private let style: TimelineDayLayout.Style
    private var pkCurves: Bool {
        style.pkMode
    }

    /// Effect states per substance (lowercased canonical name) — the same
    /// acute-effect curves every other timeline surface draws. Doses without
    /// duration data have no state and appear as dots/cards only, exactly as
    /// they render as markers elsewhere.
    private let statesBySubstance: [String: [ActiveSubstanceState]]
    /// Raw entries per substance (lowercased name, ascending) — the PK mode's
    /// input.
    private let entriesBySubstance: [String: [DoseEntry]]

    /// One day of the strip: its groups (newest first) and its time range
    /// [bottomTime, topTime) on the strip.
    private struct Slice {
        let date: Date
        let isToday: Bool
        let topTime: Date
        let bottomTime: Date
        let groups: [TimelineDayLayout.CardGroup]
        /// Whole days are skipped between this slice's top and the next
        /// newer one: the strip breaks above it.
        let breakAbove: Bool
        /// The next older slice starts after a break: the axis fades out at
        /// this slice's bottom.
        let breakBelow: Bool
    }

    /// Every drawable session note in the log, ascending. The summary note is
    /// left out: it describes the session rather than a moment in it.
    private let notes: [Note]

    /// One session note, flattened for layout.
    private struct Note {
        let id: UUID
        let sessionID: UUID
        let kind: SessionNote.Kind
        let timestamp: Date
        let text: String
    }

    /// Heart-rate samples across the strip's recent stretch, ascending. Empty
    /// when the health overlay is off or nothing was recorded.
    private let heartRate: [HeartRateSample]

    /// Per-day slices, newest first.
    private let slices: [Slice]
    private let map: TimelineTimeMap
    private let now = Date.now

    /// Per-substance all-time peak (effect intensity or PK concentration,
    /// depending on mode) — the normalization scale that keeps a substance's
    /// curve continuous across slice boundaries.
    private var peakCache: [String: Double] = [:]
    /// PK mode: per-substance resolved rate constants, cached across slices.
    private var pkConstantsCache: [String: PKConstants?] = [:]

    typealias PKConstants = (halfLife: Double, ke: Double, ka: Double)

    var sliceCount: Int {
        slices.count
    }

    init?(
        entries: [DoseEntry],
        colors: [SubstanceColor],
        colorMap: [String: Color],
        zoom: Double,
        compressGaps: Bool,
        style: TimelineDayLayout.Style,
        heartRate: [HeartRateSample] = [],
    ) {
        guard !entries.isEmpty else { return nil }
        self.colorMap = colorMap
        self.style = style
        self.heartRate = heartRate.sorted { $0.date < $1.date }
        remainingFractions = Self.computeRemainingFractions(entries: entries)

        // One state per dose that resolves duration data — the curves' input
        // and, per entry, the bubble's phase progress.
        let hexMap = colors.hexColorMap
        var states: [ActiveSubstanceState] = []
        var statesByEntry: [PersistentIdentifier: ActiveSubstanceState] = [:]
        for entry in entries {
            // A depot injection (an injectable ester) has no acute onset/peak/offset
            // to draw — its release runs over days-to-weeks — so it gets no effect
            // state: the dose still shows as a bubble, just without a curve or phase.
            if Self.isDepotInjection(entry) { continue }
            let hex = SubstancePalette.hex(for: entry.substance, hexMap: hexMap)
            guard let state = ActiveSubstanceState.from(entry: entry, colorHex: hex) else { continue }
            states.append(state)
            statesByEntry[entry.persistentModelID] = state
        }
        statesBySubstance = Dictionary(grouping: states) { $0.substanceName.lowercased() }
        var bySubstance = Dictionary(grouping: entries) { $0.substance.lowercased() }
        for k in bySubstance.keys {
            bySubstance[k]?.sort { $0.timestamp < $1.timestamp }
        }
        entriesBySubstance = bySubstance

        var sessions: [UUID: Session] = [:]
        for entry in entries {
            if let session = entry.session {
                sessions[session.id] = session
            }
        }
        notes = sessions.values
            .flatMap { session in
                (session.notes ?? [])
                    .filter { $0.kind != .summary }
                    .map { note in
                        Note(
                            id: note.id,
                            sessionID: session.id,
                            kind: note.kind,
                            timestamp: note.timestamp,
                            text: note.text.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? "",
                        )
                    }
            }
            .sorted { $0.timestamp < $1.timestamp }

        let calendar = Calendar.current
        let byDay = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.timestamp) }
        // Today always gets a slice, dosed or not: the live edge lies in it,
        // and a slice tagged with the last dosed day would otherwise run past
        // midnight and call this morning "Yesterday".
        let today = calendar.startOfDay(for: now)
        let dayDates = Set(byDay.keys).union([today]).sorted(by: >)
        guard let oldestDay = byDay.keys.min() else { return nil }

        // Strip bounds: from just before the oldest dose up past "now" to
        // where the longest still-running curve ends plus a margin, capped at
        // a day so a multi-day half-life can't make the future a screen-tall
        // empty run. The curve mode decides what "running" means: effect
        // windows, or six half-lives in body-load mode.
        let globalStart = byDay[oldestDay]!.map(\.timestamp).min()!.addingTimeInterval(-5 * 60)
        let currentTime = now
        let modeledEnds: [Date] = style.pkMode
            ? Self.pkActivityEnds(entries: entries)
            : states.map { $0.doseTimestamp.addingTimeInterval($0.totalMinutes * 60) }
        let curvesEnd = modeledEnds.filter { $0 > currentTime }.max()
        let globalEnd = max(
            currentTime.addingTimeInterval(Self.minimumFutureSeconds),
            min(
                (curvesEnd ?? .distantPast).addingTimeInterval(Self.futureMarginSeconds),
                currentTime.addingTimeInterval(Self.maximumFutureSeconds),
            ),
        )

        // Where each curve is still above threshold — the spans compression
        // must leave at the uniform scale.
        let activeIntervals: [DateInterval] = style.pkMode
            ? Self.pkActiveIntervals(entries: entries)
            : states.map { Self.activeInterval(of: $0) }
        let activeByDay: [Date: Date] = Dictionary(
            activeIntervals.map { (calendar.startOfDay(for: $0.start), $0.end) },
            uniquingKeysWith: { Swift.max($0, $1) },
        )

        // Slices, newest first. A slice runs from its day's start up to the
        // next newer dosed day's start; when whole days lie between the two
        // and compression is on, the slice instead ends where its day's
        // activity ends (midnight at the earliest) and the skipped days
        // become a break. The newest slice runs to the strip's live edge.
        var sliceInfos: [Slice] = []
        let cardHeight = TimelineDoseBubble.height(for: style.bubbleStyle)
        var activeUntil = Date.distantPast
        for day in dayDates.reversed() {
            activeUntil = max(activeUntil, activeByDay[day] ?? .distantPast)
            let nextDay = calendar.date(byAdding: .day, value: 1, to: day)!
            let newerDay = dayDates.last(where: { $0 > day })
            var topTime = newerDay ?? globalEnd
            var breakAbove = false
            if compressGaps, let newerDay, newerDay > nextDay {
                let activityEnd = max(nextDay, activeUntil.addingTimeInterval(Self.futureMarginSeconds))
                if activityEnd < newerDay {
                    topTime = activityEnd
                    breakAbove = true
                }
            }
            let bottomTime = day == oldestDay ? globalStart : day
            let groups = Self.makeGroups(
                dayEntries: byDay[day] ?? [],
                colorMap: colorMap,
                remainingFractions: remainingFractions,
                statesByEntry: statesByEntry,
                cardHeight: cardHeight,
                now: currentTime,
            )
            sliceInfos.append(Slice(
                date: day,
                isToday: calendar.isDateInToday(day),
                topTime: topTime,
                bottomTime: bottomTime,
                groups: groups,
                breakAbove: breakAbove,
                breakBelow: sliceInfos.last?.breakAbove ?? false,
            ))
        }
        sliceInfos.reverse()
        slices = sliceInfos

        // Global map: uniform points-per-minute, with dead time capped
        // (unless compression is off) and every curve's active span left at
        // the uniform scale. Every slice boundary, group anchor, curve edge,
        // and "now" is a breakpoint.
        let ppm = TimelineDayLayout.basePointsPerMinute * CGFloat(zoom)
        map = TimelineTimeMap(
            start: globalStart,
            end: globalEnd,
            now: currentTime,
            slices: sliceInfos.map { slice in
                TimelineTimeMap.Slice(
                    bottomTime: slice.bottomTime,
                    topTime: slice.topTime,
                    breakAbove: slice.breakAbove,
                    minimumHeight: Self.minimumSliceHeight(groups: slice.groups),
                )
            },
            anchors: sliceInfos.flatMap { $0.groups.map(\.representativeTime) },
            activeIntervals: activeIntervals,
            pointsPerMinute: ppm,
            compressGaps: compressGaps,
        )
    }

    /// The strip always runs at least this far past now, so the live edge
    /// has room for its arrowhead and fade even when nothing is active.
    private static let minimumFutureSeconds: TimeInterval = 10 * 60
    /// Breathing room past the last curve's modeled end.
    private static let futureMarginSeconds: TimeInterval = 30 * 60
    /// Ceiling on the future extent, whatever is still active.
    private static let maximumFutureSeconds: TimeInterval = 24 * 3_600
    /// A curve counts as active while it is above this fraction of its own
    /// peak; below it, the span is dead time compression may squeeze.
    static let activeThreshold = 0.05

    /// Room a slice's cards need so they never spill into the next day.
    private static func minimumSliceHeight(groups: [TimelineDayLayout.CardGroup]) -> CGFloat {
        groups.map(\.height).reduce(0, +)
            + CGFloat(max(0, groups.count - 1)) * TimelineDayLayout.groupGap
            + CGFloat(groups.count) * TimelineDayLayout.envelopePad * 2
            + TimelineDayLayout.envelopeFooterHeight + 40
    }

    /// Effect mode: from the dose to the moment its curve drops below
    /// ``activeThreshold`` of its own peak.
    private static func activeInterval(of state: ActiveSubstanceState) -> DateInterval {
        let minutes = TimelineCurveModel.visibleExtent(
            for: state,
            peerMagnitude: state.doseMagnitude,
            threshold: activeThreshold,
        )
        return DateInterval(start: state.doseTimestamp, duration: max(minutes, 1) * 60)
    }

    /// Body-load mode: from the dose to the moment its concentration drops
    /// below ``activeThreshold`` of its own peak. Doses that draw no
    /// body-load curve contribute nothing.
    private static func pkActiveIntervals(entries: [DoseEntry]) -> [DateInterval] {
        var constantsCache: [String: PKConstants?] = [:]
        var intervals: [DateInterval] = []
        for entry in entries {
            let key = entry.substance.lowercased()
            let constants: PKConstants?
            if let cached = constantsCache[key] {
                constants = cached
            } else {
                constants = resolvePKConstants(key: key, name: entry.substance)
                constantsCache[key] = constants
            }
            guard let constants else { continue }
            let minutes = PKModel.timeToFraction(activeThreshold, ke: constants.ke, ka: constants.ka)
            intervals.append(DateInterval(start: entry.timestamp, duration: max(minutes, 1) * 60))
        }
        return intervals
    }

    /// Body-load mode's activity end per dose: six half-lives, the same cutoff
    /// ``computeRemainingFractions(entries:)`` treats as cleared. Doses that
    /// draw no body-load curve (supplements, no half-life) contribute nothing.
    private static func pkActivityEnds(entries: [DoseEntry]) -> [Date] {
        var substanceCache: [String: Substance?] = [:]
        var ends: [Date] = []
        for entry in entries {
            let key = entry.substance.lowercased()
            let substance: Substance?
            if let cached = substanceCache[key] {
                substance = cached
            } else {
                substance = SubstanceLibrary.lookup(entry.substance)
                substanceCache[key] = substance
            }
            if substance?.category == .supplement { continue }
            guard let halfLife = PKResolver.halfLifeMinutes(substance: substance, entryName: entry.substance) else { continue }
            ends.append(entry.timestamp.addingTimeInterval(halfLife * 6 * 60))
        }
        return ends
    }

    private func globalY(_ t: Date) -> CGFloat {
        map.reversedY(t)
    }

    // MARK: Slice layout

    mutating func layout(sliceAt index: Int) -> TimelineDayLayout {
        let slice = slices[index]
        let breakAbove: CGFloat = slice.breakAbove ? TimelineTimeMap.breakHeight : 0
        // The slice owns the break above it: its rendered top is the break's
        // top, and the day tag sits below the break.
        let sliceTopY = globalY(slice.topTime) - breakAbove
        let mapHeight = globalY(slice.bottomTime) - sliceTopY
        // Captures the map, not `self` — `curveSeries` below mutates self and
        // takes this closure at the same time.
        let map = map
        let localY: (Date) -> CGFloat = { t in
            map.reversedY(t) - sliceTopY
        }

        var groups = slice.groups

        // Session runs — consecutive groups sharing a session, with at least
        // two doses total, earn an envelope (single-dose sessions would just
        // duplicate the card's own tap target; the dose screen links onward).
        var runs: [(sessionID: UUID, range: ClosedRange<Int>)] = []
        var i = 0
        while i < groups.count {
            guard let sid = groups[i].sessionID else { i += 1; continue }
            var j = i
            while j + 1 < groups.count, groups[j + 1].sessionID == sid {
                j += 1
            }
            let doseCount = groups[i ... j].reduce(0) { $0 + $1.items.count }
            if doseCount >= 2 {
                runs.append((sid, i ... j))
                for k in i ... j {
                    groups[k].inSession = true
                }
            }
            i = j + 1
        }
        // Envelope padding, in axis direction: above the run's newest group
        // and pad+footer below its oldest. Groups are newest-first.
        var padAbove = [CGFloat](repeating: 0, count: groups.count)
        var padBelow = [CGFloat](repeating: 0, count: groups.count)
        for run in runs {
            padAbove[run.range.lowerBound] = TimelineDayLayout.envelopePad
            padBelow[run.range.upperBound] = TimelineDayLayout.envelopePad + TimelineDayLayout.envelopeFooterHeight
        }

        // Anchor each group's center at its time, then push down (into the
        // past) whatever collides — the connectors keep the true position
        // legible. The newest group also clears the day tag's row, so its
        // capsule never slides under the tag.
        let reservedTop = TimelineStripDayContent.reservedTop(breakAbove: breakAbove)
        for k in groups.indices {
            groups[k].timeY = localY(groups[k].representativeTime)
            var top = groups[k].timeY - groups[k].height / 2
            if k == 0 {
                top = max(top, padAbove[0] + reservedTop + TimelineGutterLabels.gap)
            } else {
                top = max(
                    top,
                    groups[k - 1].topY + groups[k - 1].height
                        + padBelow[k - 1] + TimelineDayLayout.groupGap + padAbove[k],
                )
            }
            groups[k].topY = top
        }

        let envelopes = runs.map { run in
            let newest = groups[run.range.lowerBound]
            let oldest = groups[run.range.upperBound]
            return TimelineDayLayout.SessionEnvelope(
                id: run.sessionID,
                yStart: newest.topY - TimelineDayLayout.envelopePad,
                yEnd: oldest.bottomY + TimelineDayLayout.envelopePad + TimelineDayLayout.envelopeFooterHeight,
            )
        }

        let deepestBottom = groups.indices.map { groups[$0].bottomY + padBelow[$0] }.max() ?? 0
        let totalHeight = max(mapHeight, deepestBottom + 12)

        var doseDots: [TimelineDayLayout.DoseDot] = []
        var connectors: [TimelineDayLayout.Connector] = []
        for group in groups {
            for (itemIndex, item) in group.items.enumerated() {
                let dotY = localY(item.entry.timestamp)
                doseDots.append(TimelineDayLayout.DoseDot(y: dotY, color: item.color))
                let cardCenterY = group.topY
                    + CGFloat(itemIndex) * (group.cardHeight + TimelineDayLayout.cardSpacing)
                    + group.cardHeight / 2
                connectors.append(TimelineDayLayout.Connector(fromY: dotY, toY: cardCenterY, color: item.color))
            }
        }

        let showsLiveEdge = index == 0
        let nowY: CGFloat? = if now >= slice.bottomTime, now <= slice.topTime {
            localY(now)
        } else {
            nil
        }

        let visibleLabels = TimelineGutterLabels.doseLabelsVisible(doseYs: groups.map(\.timeY), nowY: nowY)
        for k in groups.indices {
            groups[k].showsTimeLabel = visibleLabels[k]
        }

        let hourTicks = hourTicks(
            slice: slice,
            localY: localY,
            mapHeight: mapHeight,
            reservedTop: reservedTop,
            groups: groups,
            nowY: nowY,
        )

        // With the axis off nothing draws the curves, so skip sampling them.
        let series = style.showsAxis ? curveSeries(slice: slice, localY: localY) : []

        let capsuleYs = groups.filter(\.showsTimeLabel).map(\.timeY) + [nowY].compactMap(\.self)
        let noteMarks = notes
            .filter { $0.timestamp >= slice.bottomTime && $0.timestamp < slice.topTime }
            .map { note in
                let y = localY(note.timestamp)
                let frame = TimelineGutterLabels.Frame(center: y, height: TimelineNoteLane.glyphSize)
                return TimelineDayLayout.NoteMark(
                    id: note.id,
                    sessionID: note.sessionID,
                    kind: note.kind,
                    timestamp: note.timestamp,
                    text: note.text,
                    y: y,
                    curveFraction: Self.curveFraction(at: y, series: series),
                    besideCapsule: capsuleYs.contains { capsuleY in
                        frame.collides(
                            with: TimelineGutterLabels.Frame(center: capsuleY, height: TimelineGutterLabels.doseLabelHeight),
                            gap: 0,
                        )
                    },
                )
            }

        let heartRatePoints = Self.heartRatePoints(
            samples: heartRate,
            from: slice.bottomTime,
            to: slice.topTime,
            localY: localY,
        )

        return TimelineDayLayout(
            date: slice.date,
            isToday: slice.isToday,
            style: style,
            showsLiveEdge: showsLiveEdge,
            breakAbove: breakAbove,
            fadesAxisBelow: slice.breakBelow,
            cardGroups: groups,
            envelopes: envelopes,
            series: series,
            doseDots: doseDots,
            connectors: connectors,
            noteMarks: noteMarks,
            heartRate: heartRatePoints,
            hourTicks: hourTicks,
            nowY: nowY,
            mapHeight: mapHeight,
            totalHeight: totalHeight,
        )
    }

    /// The heart-rate band the lane maps: 40 bpm sits on the axis, 160 bpm at
    /// the trace's full width. Beyond either end the trace flattens rather
    /// than running out of the lane.
    static let heartRateRange: ClosedRange<Double> = 40 ... 160

    /// Fewer samples than this in a slice is a scatter, not a line, so the
    /// trace is skipped there.
    static let minimumHeartRateSamples = 6

    /// One slice's heart-rate samples as lane points. Empty when too few
    /// samples fall in the slice to read as a trace.
    static func heartRatePoints(
        samples: [HeartRateSample],
        from bottomTime: Date,
        to topTime: Date,
        localY: (Date) -> CGFloat,
    ) -> [TimelineDayLayout.CurvePoint] {
        let inSlice = samples.filter { $0.date >= bottomTime && $0.date < topTime }
        guard inSlice.count >= minimumHeartRateSamples else { return [] }
        let low = heartRateRange.lowerBound
        let span = heartRateRange.upperBound - low
        return inSlice
            .map { sample in
                TimelineDayLayout.CurvePoint(
                    y: localY(sample.date),
                    v: min(max((sample.bpm - low) / span, 0), 1),
                )
            }
            .sorted { $0.y < $1.y }
    }

    /// How far into the lane the widest curve reaches at `y`, `0…1` — what a
    /// note placed there has to clear. Points bracketing `y` are interpolated,
    /// so a note between two samples reads the curve at its own height.
    static func curveFraction(at y: CGFloat, series: [TimelineDayLayout.CurveSeries]) -> Double {
        var widest = 0.0
        for curve in series {
            let points = curve.points
            guard let upper = points.firstIndex(where: { $0.y >= y }) else { continue }
            guard upper > 0 else {
                widest = max(widest, points[0].y == y ? points[0].v : 0)
                continue
            }
            let a = points[upper - 1]
            let b = points[upper]
            let span = b.y - a.y
            let f = span > 0 ? Double((y - a.y) / span) : 0
            widest = max(widest, a.v + (b.v - a.v) * f)
        }
        return widest
    }

    // MARK: Hour ruler

    /// A gridline for every hour that fits (≥8 pt apart — in a compressed
    /// gap they bunch, which is the compression cue); labels additionally
    /// thin out around the day tag, dose capsules, the "Now" tag, each other,
    /// and any label a displaced card has pushed out of time order.
    private func hourTicks(
        slice: Slice,
        localY: (Date) -> CGFloat,
        mapHeight: CGFloat,
        reservedTop: CGFloat,
        groups: [TimelineDayLayout.CardGroup],
        nowY: CGFloat?,
    ) -> [TimelineDayLayout.HourTick] {
        let calendar = Calendar.current
        guard var t = calendar.dateInterval(of: .hour, for: slice.bottomTime)?.end else { return [] }

        let labels = groups.map { (time: $0.representativeTime, y: $0.timeY) }
        let visibleDoseYs = groups.filter(\.showsTimeLabel).map(\.timeY)
        let labelHalf = TimelineGutterLabels.hourLabelHeight / 2
        let labelSpacing = TimelineGutterLabels.hourLabelHeight + TimelineGutterLabels.gap
        var ticks: [TimelineDayLayout.HourTick] = []
        var lastTickY: CGFloat = .infinity
        var lastLabelY: CGFloat = .infinity
        while t <= slice.topTime {
            let y = localY(t)
            defer { t = t.addingTimeInterval(3_600) }
            guard y >= 6, y <= mapHeight - 6, lastTickY - y >= 8 else { continue }
            lastTickY = y
            let ordered = labels.allSatisfy { label in
                label.time < t ? label.y > y - 4 : label.y < y + 4
            }
            let labelFits = y >= labelHalf && y <= mapHeight - labelHalf
                && ordered
                && TimelineGutterLabels.hourLabelFits(y: y, doseYs: visibleDoseYs, nowY: nowY, reservedTop: reservedTop)
                && lastLabelY - y >= labelSpacing
            if labelFits {
                ticks.append(TimelineDayLayout.HourTick(y: y, label: TimelineHourMark.label(for: t)))
                lastLabelY = y
            } else {
                ticks.append(TimelineDayLayout.HourTick(y: y, label: nil))
            }
        }
        return ticks
    }

    // MARK: Effect curves

    /// Samples every substance's **acute effect intensity** on a y-grid
    /// derived from the global map — the same phase-based curves the journal
    /// cards and session detail draw, so a dose's spine curve ends when its
    /// effects end, not when the last molecule clears (that's the %-badge's
    /// and In Your System's job). Normalized to the substance's all-time
    /// effect peak, so widths mean the same thing on every day and the curve
    /// crosses slice boundaries without a jump.
    private mutating func curveSeries(slice: Slice, localY: (Date) -> CGFloat) -> [TimelineDayLayout.CurveSeries] {
        // Sample grid over the slice's time range, denser where the map is
        // stretched: walk global segments clipped to the slice.
        var grid: [(t: Date, y: CGFloat)] = []
        var segStart = slice.bottomTime
        let mapTimes = map.times
        while segStart < slice.topTime {
            var lo = 0
            var hi = mapTimes.count - 1
            while hi - lo > 1 {
                let mid = (lo + hi) / 2
                if mapTimes[mid] <= segStart { lo = mid } else { hi = mid }
            }
            let segEnd = min(mapTimes[hi], slice.topTime)
            let h = localY(segStart) - localY(segEnd)
            let steps = max(2, Int(h / 3))
            let span = segEnd.timeIntervalSince(segStart)
            for s in 0 ..< steps {
                let t = segStart.addingTimeInterval(span * Double(s) / Double(steps))
                grid.append((t: t, y: localY(t)))
            }
            segStart = segEnd
        }
        grid.append((t: slice.topTime, y: localY(slice.topTime)))
        grid.sort { $0.y < $1.y }

        var result: [TimelineDayLayout.CurveSeries] = if pkCurves {
            pkSeries(slice: slice, grid: grid)
        } else {
            effectSeries(slice: slice, grid: grid)
        }

        // Widest fills draw first so a slim spike is never buried under a
        // broad neighbor.
        result.sort { a, b in
            a.points.reduce(0) { $0 + $1.v } > b.points.reduce(0) { $0 + $1.v }
        }
        return result
    }

    private mutating func effectSeries(slice: Slice, grid: [(t: Date, y: CGFloat)]) -> [TimelineDayLayout.CurveSeries] {
        var result: [TimelineDayLayout.CurveSeries] = []
        for (key, states) in statesBySubstance {
            // Only states whose effect window overlaps this slice contribute.
            let relevant = states.filter { state in
                let end = state.doseTimestamp.addingTimeInterval(state.totalMinutes * 60)
                return state.doseTimestamp <= slice.topTime && end >= slice.bottomTime
            }
            guard !relevant.isEmpty else { continue }

            var values: [Double] = []
            var phases: [TimelineCurvePhase?] = []
            values.reserveCapacity(grid.count)
            phases.reserveCapacity(grid.count)
            var sliceMax = 0.0
            for sample in grid {
                let v = Self.effectValue(at: sample.t, states: relevant)
                values.append(v)
                phases.append(TimelineCurvePhase.phase(at: sample.t, states: relevant))
                sliceMax = max(sliceMax, v)
            }

            let scale = globalEffectPeak(key: key, states: states)
            guard scale > 0, sliceMax > scale * 0.02 else { continue }

            let color = SubstancePalette.color(for: relevant[0].substanceName, colorMap: colorMap)
            let points = Self.trimmed(zip(grid, zip(values, phases)).map {
                TimelineDayLayout.CurvePoint(y: $0.y, v: min($1.0 / scale, 1), phase: $1.1)
            })
            result.append(TimelineDayLayout.CurveSeries(color: color, points: points))
        }
        return result
    }

    /// Body-load mode: half-life decay per substance, normalized to the
    /// substance's all-time stacked peak concentration. Long tails draw as
    /// long as they honestly persist — that's what this mode is for.
    private mutating func pkSeries(slice: Slice, grid: [(t: Date, y: CGFloat)]) -> [TimelineDayLayout.CurveSeries] {
        var result: [TimelineDayLayout.CurveSeries] = []
        for (key, substanceEntries) in entriesBySubstance {
            guard let name = substanceEntries.first?.substance,
                  let pk = cachedPKConstants(key: key, name: name) else { continue }

            let lookback = slice.bottomTime.addingTimeInterval(-pk.halfLife * 60 * 6)
            let relevant = substanceEntries.filter {
                $0.timestamp >= lookback && $0.timestamp <= slice.topTime
            }
            guard !relevant.isEmpty else { continue }

            var values: [Double] = []
            values.reserveCapacity(grid.count)
            var sliceMax = 0.0
            for sample in grid {
                var conc = 0.0
                for entry in relevant {
                    let elapsed = sample.t.timeIntervalSince(entry.timestamp) / 60
                    if elapsed >= 0 {
                        conc += doseWeight(entry) * PKModel.concentration(at: elapsed, ke: pk.ke, ka: pk.ka)
                    }
                }
                values.append(conc)
                sliceMax = max(sliceMax, conc)
            }

            let scale = globalPKPeak(key: key, pk: pk)
            guard scale > 0, sliceMax > scale * 0.03 else { continue }

            let color = SubstancePalette.color(for: name, colorMap: colorMap)
            let points = Self.trimmed(zip(grid, values).map {
                TimelineDayLayout.CurvePoint(y: $0.y, v: min($1 / scale, 1))
            })
            result.append(TimelineDayLayout.CurveSeries(color: color, points: points))
        }
        return result
    }

    /// The series without its leading and trailing zero runs (one zero point
    /// kept at each end so the curve still lands on the axis). Otherwise a
    /// curve's silent stretch before its dose draws as a colored line down
    /// the axis.
    private static func trimmed(_ points: [TimelineDayLayout.CurvePoint]) -> [TimelineDayLayout.CurvePoint] {
        guard let first = points.firstIndex(where: { $0.v > 0 }),
              let last = points.lastIndex(where: { $0.v > 0 }) else { return [] }
        return Array(points[max(first - 1, 0) ... min(last + 1, points.count - 1)])
    }

    /// PK mode: a substance's rate constants; `nil` for substances that draw
    /// no body-load curve (no half-life, supplements).
    private static func resolvePKConstants(key: String, name: String) -> PKConstants? {
        guard let substance = SubstanceLibrary.lookup(key),
              substance.category != .supplement,
              let halfLife = PKResolver.halfLifeMinutes(substance: substance, entryName: name),
              halfLife > 0 else { return nil }
        let (ke, ka) = PKResolver.rateConstants(
            halfLifeMinutes: halfLife,
            duration: substance.resolveDuration(for: .oral),
        )
        guard PKModel.cmax(ke: ke, ka: ka) > 0 else { return nil }
        return (halfLife, ke, ka)
    }

    /// ``resolvePKConstants(key:name:)`` memoized across slices.
    private mutating func cachedPKConstants(key: String, name: String) -> PKConstants? {
        if let cached = pkConstantsCache[key] { return cached }
        let resolved = Self.resolvePKConstants(key: key, name: name)
        pkConstantsCache[key] = resolved
        return resolved
    }

    /// PK mode: the substance's all-time stacked peak concentration,
    /// evaluated at each dose's own peak moment. Cached — the normalization
    /// scale for every slice.
    private mutating func globalPKPeak(key: String, pk: PKConstants) -> Double {
        if let cached = peakCache["pk|\(key)"] { return cached }
        let substanceEntries = entriesBySubstance[key] ?? []
        let tmax = pk.ka > pk.ke ? log(pk.ka / pk.ke) / (pk.ka - pk.ke) : pk.halfLife
        var peak = 0.0
        for anchor in substanceEntries {
            let t = anchor.timestamp.addingTimeInterval(tmax * 60)
            var conc = 0.0
            for entry in substanceEntries {
                let elapsed = t.timeIntervalSince(entry.timestamp) / 60
                if elapsed >= 0 {
                    conc += doseWeight(entry) * PKModel.concentration(at: elapsed, ke: pk.ke, ka: pk.ka)
                }
            }
            peak = max(peak, conc)
        }
        peakCache["pk|\(key)"] = peak
        return peak
    }

    /// PK mode's per-dose weight: the logged amount.
    private func doseWeight(_ entry: DoseEntry) -> Double {
        entry.amount
    }

    /// Stacked effect intensity for one substance at `t` — each dose's
    /// phase-curve shape scaled by its dose intensity, summed. Unit weight
    /// would send every dose to the lane cap and flatten the peaks.
    private static func effectValue(at t: Date, states: [ActiveSubstanceState]) -> Double {
        var total = 0.0
        for state in states {
            let minutes = t.timeIntervalSince(state.doseTimestamp) / 60
            guard minutes >= 0, minutes <= state.totalMinutes else { continue }
            total += state.doseIntensity * TimelineCurveModel.intensity(at: minutes, for: state)
        }
        return total
    }

    /// The substance's all-time stacked effect peak: its summed intensity
    /// evaluated around each dose's own crest. Cached — this is the
    /// normalization scale for every slice.
    private mutating func globalEffectPeak(key: String, states: [ActiveSubstanceState]) -> Double {
        if let cached = peakCache[key] { return cached }
        var peak = 0.0
        for state in states {
            let crest = state.doseTimestamp.addingTimeInterval(
                (state.comeupEndMinutes + state.peakEndMinutes) / 2 * 60,
            )
            peak = max(peak, Self.effectValue(at: crest, states: states))
        }
        peakCache[key] = peak
        return peak
    }

    // MARK: Static helpers

    private static func makeGroups(
        dayEntries: [DoseEntry],
        colorMap: [String: Color],
        remainingFractions: [PersistentIdentifier: Double],
        statesByEntry: [PersistentIdentifier: ActiveSubstanceState],
        cardHeight: CGFloat,
        now: Date,
    ) -> [TimelineDayLayout.CardGroup] {
        let sorted = dayEntries.sorted { $0.timestamp < $1.timestamp }
        var groups: [TimelineDayLayout.CardGroup] = []
        var currentBatch: [DoseEntry] = []
        func flushBatch() {
            guard !currentBatch.isEmpty else { return }
            let repTime = currentBatch[currentBatch.count / 2].timestamp
            groups.append(TimelineDayLayout.CardGroup(
                id: currentBatch[0].persistentModelID,
                items: currentBatch.reversed().map { entry in
                    let state = statesByEntry[entry.persistentModelID]
                    let running = state.map { $0.doseTimestamp.addingTimeInterval($0.totalMinutes * 60) > now } ?? false
                    return TimelineDayLayout.CardItem(
                        entry: entry,
                        displayName: DoseTitle.resolve(for: entry),
                        color: SubstancePalette.color(for: entry.substance, colorMap: colorMap),
                        remainingFraction: remainingFractions[entry.persistentModelID],
                        state: running ? state : nil,
                    )
                },
                representativeTime: repTime,
                sessionID: currentBatch[0].session?.id,
                cardHeight: cardHeight,
            ))
            currentBatch = []
        }
        for entry in sorted {
            if let prev = currentBatch.last,
               entry.timestamp.timeIntervalSince(prev.timestamp) > 5 * 60 {
                flushBatch()
            }
            currentBatch.append(entry)
        }
        flushBatch()
        return groups.reversed()
    }

    /// Whether a dose is a depot injection — an injectable ester (Estradiol Valerate
    /// IM/SC). Its release runs over days-to-weeks, so the acute onset/peak/offset
    /// effect model and the half-life "in your system" readout don't apply; the
    /// Injection Levels tool models it instead. The dose still shows as a bubble.
    static func isDepotInjection(_ entry: DoseEntry) -> Bool {
        guard entry.route == .intramuscular || entry.route == .subcutaneous else { return false }
        let uid = entry.substanceUID ?? SubstanceStore.shared.substanceUID(forNameOrAlias: entry.substance)
        return SubstanceStore.shared.isEster(entry.saltForm, forParentUID: uid)
    }

    /// Fraction of each dose still in the body, keyed by entry identity.
    /// Mirrors ``ActiveSubstanceCalculator``'s gates (supplements and unmodeled
    /// forms contribute nothing; ≤3% counts as cleared) so the card badge and
    /// the In Your System readout can never disagree about what is active.
    private static func computeRemainingFractions(entries: [DoseEntry]) -> [PersistentIdentifier: Double] {
        var result: [PersistentIdentifier: Double] = [:]
        var substanceCache: [String: Substance?] = [:]
        let now = Date.now

        for entry in entries {
            // Depot injections don't model on the acute half-life timeline (see
            // isDepotInjection) — the Injection Levels tool is their home.
            if isDepotInjection(entry) { continue }
            let key = entry.substance.lowercased()
            let substance: Substance?
            if let cached = substanceCache[key] {
                substance = cached
            } else {
                substance = SubstanceLibrary.lookup(entry.substance)
                substanceCache[key] = substance
            }

            if substance?.category == .supplement { continue }
            let productDuration = entry.productDuration
            if productDuration == nil, entry.namesUnmodeledForm { continue }
            guard let halfLife = PKResolver.halfLifeMinutes(substance: substance, entryName: entry.substance) else { continue }

            let elapsed = now.timeIntervalSince(entry.timestamp) / 60
            guard elapsed >= 0, elapsed < halfLife * 6 else { continue }

            let (ke, ka) = PKResolver.rateConstants(
                halfLifeMinutes: halfLife,
                duration: productDuration ?? substance?.resolveDuration(
                    for: entry.route, saltForm: entry.saltForm, isomer: entry.isomer,
                ),
            )
            let fraction = PKModel.fractionRemainingInBody(at: elapsed, ke: ke, ka: ka)
            if fraction > 0.03 {
                result[entry.persistentModelID] = fraction
            }
        }
        return result
    }
}
