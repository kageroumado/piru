import Foundation

/// Evaluates the journal's dose-effect curves over an **arbitrary time window**
/// — the engine behind the continuous timeline ribbon.
///
/// Time is continuous; sessions are an analysis artifact. Because every curve is
/// *model-evaluated* (a phase-shaped bell per dose, Hill-merged per substance —
/// see ``TimelineCurveModel``), a window's plot is simply the same sum evaluated
/// over `[start, end]` for every dose whose activity window intersects it. This
/// namespace reuses the session math verbatim (``TimelineCurveModel/pkParams(for:)``,
/// ``TimelineCurveModel/intensity(at:for:params:)``, ``TimelineCurveModel/hill(_:)``,
/// ``TimelineCurveModel/curveExtent(for:params:)``) — no pharmacology is re-derived.
///
/// Two deliberate deviations from the session *display* pipeline, both in favor
/// of cross-window consistency:
///
/// - **Per-dose extent clipping.** A dose contributes only inside
///   `[timestamp, timestamp + curveExtent]`. The session renderer draws exactly
///   this (its path starts/ends on the baseline at the group range), but its
///   underlying `stackedIntensity` sum would still carry a ≤ ~2 % Gaussian tail
///   past the extent. Clipping makes the evaluated value a **pure function of
///   absolute time** — independent of which window it's sampled through — so
///   adjacent tiles agree exactly at their shared boundary and culling
///   out-of-window doses never changes a value.
/// - **No γ-compression, no per-window normalization.** Values are the raw
///   Hill-merged intensity in `[0, 1)`. Amplitude compression and y-scaling
///   depend on the *whole* dose set on screen, so they belong to the view's
///   shared y-scale policy (recomputed over the loaded tiles), not to a single
///   window's samples — baking them in here would make tile seams visible.
nonisolated enum TimelineWindowEvaluator {
    /// Samples per evaluated window (endpoints inclusive). 121 across a 6 h tile
    /// is one sample every 3 minutes — smooth at any plausible tile width.
    static let defaultSampleCount = 121

    /// One substance-route group's sampled curve over the window.
    struct Series: Hashable, Identifiable, Sendable {
        /// Grouping key (`name|route`, lowercased) — matches
        /// ``TimelineCurveModel/stackedGroups(of:)`` so redoses share a curve
        /// while distinct routes stay separate, exactly like the session graph.
        let key: String
        /// Canonical substance display name (curve label).
        let name: String
        let colorHex: String
        /// Raw Hill-merged intensity at each of the window's `sampleCount`
        /// uniformly spaced instants, endpoints inclusive.
        let values: [Double]
        /// Timestamps of this group's doses that fall inside the window —
        /// baseline tick positions.
        let doseTimes: [Date]

        var id: String {
            key
        }
    }

    /// Everything a view needs to draw one window: the per-substance sample
    /// arrays plus the window peak that feeds the shared y-scale.
    struct WindowPlot: Hashable, Sendable {
        let start: Date
        let end: Date
        let sampleCount: Int
        let series: [Series]
        /// Highest sample across all series (0 when the window is silent).
        let peakValue: Double
    }

    /// The absolute interval a dose's curve occupies: from the dose to the point
    /// the drawn curve returns to baseline (``TimelineCurveModel/curveExtent(for:params:)``).
    static func activityInterval(of dose: ActiveSubstanceState) -> DateInterval {
        let params = TimelineCurveModel.pkParams(for: dose)
        let extentMinutes = TimelineCurveModel.curveExtent(for: dose, params: params)
        return DateInterval(start: dose.doseTimestamp, duration: extentMinutes * 60)
    }

    /// The subset of `doses` whose activity window intersects `[start, end]`.
    /// Doses outside contribute exactly zero (see the clipping note above), so
    /// dropping them changes nothing — this is the memoization key's content:
    /// a tile only re-renders when a dose *it can see* changes.
    static func relevantDoses(_ doses: [ActiveSubstanceState], from start: Date, to end: Date) -> [ActiveSubstanceState] {
        guard end > start else { return [] }
        let window = DateInterval(start: start, end: end)
        return doses.filter { activityInterval(of: $0).intersects(window) }
    }

    /// Evaluate every dose curve over `[start, end]`, producing one sampled
    /// series per (substance, route) group — the same grouping, superposition,
    /// and Hill link as the session graph's stacked rendering.
    static func evaluate(
        doses: [ActiveSubstanceState],
        from start: Date,
        to end: Date,
        sampleCount: Int = defaultSampleCount,
    ) -> WindowPlot {
        let count = max(sampleCount, 2)
        guard end > start else {
            return WindowPlot(start: start, end: end, sampleCount: count, series: [], peakValue: 0)
        }

        let relevant = relevantDoses(doses, from: start, to: end)
        let groups = TimelineCurveModel.stackedGroups(of: relevant)
        let spanSeconds = end.timeIntervalSince(start)

        var series: [Series] = []
        series.reserveCapacity(groups.count)
        var peak = 0.0

        for group in groups {
            guard let first = group.first else { continue }
            let params = group.map { TimelineCurveModel.pkParams(for: $0) }
            let extents = zip(group, params).map { TimelineCurveModel.curveExtent(for: $0, params: $1) }

            var values = [Double](repeating: 0, count: count)
            for i in 0 ..< count {
                let t = start.addingTimeInterval(spanSeconds * Double(i) / Double(count - 1))
                let v = intensity(of: group, params: params, extents: extents, at: t)
                values[i] = v
                peak = max(peak, v)
            }

            let doseTimes = group.map(\.doseTimestamp)
                .filter { $0 >= start && $0 <= end }
                .sorted()

            series.append(Series(
                key: "\(first.substanceName.lowercased())|\(first.route.lowercased())",
                name: first.substanceName,
                colorHex: first.colorHex,
                values: values,
                doseTimes: doseTimes,
            ))
        }

        return WindowPlot(start: start, end: end, sampleCount: count, series: series, peakValue: peak)
    }

    /// The group's merged intensity at an absolute instant: linear dose
    /// superposition through one saturating Hill link
    /// (``TimelineCurveModel/stackedIntensity(atGlobalMinutes:group:params:earliestDose:)``'s
    /// math, keyed by absolute time), with each dose clipped to its own curve
    /// extent so the value matches what the session actually draws and is
    /// window-independent.
    static func intensity(
        of group: [ActiveSubstanceState],
        params: [TimelineCurveModel.PKCurveParams],
        extents: [Double],
        at date: Date,
    ) -> Double {
        var sum = 0.0
        for (index, dose) in group.enumerated() {
            let localMinutes = date.timeIntervalSince(dose.doseTimestamp) / 60
            guard localMinutes >= 0, localMinutes <= extents[index] else { continue }
            sum += dose.doseMagnitude * TimelineCurveModel.intensity(at: localMinutes, for: dose, params: params[index])
        }
        return TimelineCurveModel.hill(sum)
    }
}
