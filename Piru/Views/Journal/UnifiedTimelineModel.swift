import SwiftData
import SwiftUI

/// Owns the precomputed strip. All the expensive work — substance lookups, PK
/// curve sampling, remaining-fraction math, the global time map, geometry —
/// happens here once per (dose-log revision, zoom, compression), after the
/// store is warm, so day slices render from plain values and `body` stays
/// cheap while scrolling.
@MainActor @Observable
final class UnifiedTimelineModel {
    private(set) var days: [TimelineDayLayout] = []
    /// Key the current `days` were fully built from; partial (canceled)
    /// builds never set it, so they are redone on next appearance.
    private var builtKey: String?

    /// `cacheable` is true only for the unfiltered journal strip: the launch
    /// cache (``TimelineStripCache``) is keyed by the whole log, so a filtered
    /// or searched strip must neither read nor write it.
    func rebuild(
        entries: [DoseEntry],
        colors: [SubstanceColor],
        colorMap: [String: Color],
        revision: Int,
        zoom: Double,
        compressGaps: Bool,
        pkCurves: Bool,
        curveScale: TimelineCurveScale,
        showsAxis: Bool,
        bubbleStyle: TimelineBubbleStyle,
        showsVitals: Bool,
        cacheable: Bool = true,
    ) async {
        let preferences = "\(zoom)|\(compressGaps)|\(pkCurves)|\(curveScale.rawValue)|\(showsAxis)|\(bubbleStyle.rawValue)|\(showsVitals)|\(TimelineDoseBubble.heightScale)"
        let key = "\(revision)|\(preferences)|\(entries.count)"
        if key == builtKey, !days.isEmpty { return }
        let now = DebugClock.now
        let cacheKey = TimelineStripCache.key(
            storeGeneration: DoseLogService.storeGeneration,
            entryCount: entries.count,
            newestTimestamp: entries.map(\.timestamp).max(),
            preferences: preferences,
            now: now,
        )
        await SubstanceStore.shared.ensureAllLoaded()
        guard !Task.isCancelled else { return }
        let sessions = Self.sessionsByID(of: entries)

        let heartRate = showsAxis && HealthKitVitals.shared.isOn(overlay: showsVitals) ? await Self.recentHeartRate(entries: entries) : []
        guard !Task.isCancelled else { return }

        guard var builder = TimelineStripBuilder(
            entries: entries,
            colors: colors,
            colorMap: colorMap,
            zoom: zoom,
            compressGaps: compressGaps,
            style: TimelineDayLayout.Style(
                showsAxis: showsAxis,
                bubbleStyle: bubbleStyle,
                pkMode: pkCurves,
            ),
            curveScale: curveScale,
            heartRate: heartRate,
            sessions: sessions,
        ) else {
            days = []
            builtKey = key
            return
        }

        // Progressive build: publish the most recent slices as soon as they
        // are ready (the visible top of the strip), then keep appending in
        // chunks, yielding between them so a multi-year log never blocks the
        // UI. On a rebuild, the previous strip's older days stay below the
        // fresh ones until they are replaced, so the list never shrinks to
        // the finished prefix and throws a scrolled-down reader back up.
        let previous = days
        var built: [TimelineDayLayout] = []
        built.reserveCapacity(builder.sliceCount)
        for index in 0 ..< builder.sliceCount {
            built.append(builder.layout(sliceAt: index))
            // Small chunks: each slice is a few ms of layout on the main actor,
            // and a 30-slice chunk between yields is a 250 ms stall at launch.
            if index == 9 || (index > 9 && (index - 9).isMultiple(of: 6)) {
                let frontier = built[built.count - 1].date
                days = built + previous.filter { $0.date < frontier }
                await Task.yield()
                guard !Task.isCancelled else { return }
            }
        }
        days = built
        builtKey = key
        if cacheable {
            TimelineStripCache.save(built, key: cacheKey, now: now)
        }
    }

    /// Paint the strip from the launch cache when one was written by the last
    /// launch from this exact log and these preferences. The log's identity
    /// comes from a `COUNT` and a one-row fetch on ``DatabaseActor``, so a hit
    /// never materializes the dose log on the main actor; the file decodes
    /// off the main actor. `false` on a miss, leaving the build to
    /// ``rebuild(entries:colors:colorMap:revision:zoom:compressGaps:pkCurves:curveScale:showsAxis:bubbleStyle:showsVitals:cacheable:)``.
    func restoreCached(
        container: ModelContainer,
        revision: Int,
        zoom: Double,
        compressGaps: Bool,
        pkCurves: Bool,
        curveScale: TimelineCurveScale,
        showsAxis: Bool,
        bubbleStyle: TimelineBubbleStyle,
        showsVitals: Bool,
    ) async -> Bool {
        guard days.isEmpty else { return false }
        let preferences = "\(zoom)|\(compressGaps)|\(pkCurves)|\(curveScale.rawValue)|\(showsAxis)|\(bubbleStyle.rawValue)|\(showsVitals)|\(TimelineDoseBubble.heightScale)"
        let now = DebugClock.now
        let identity = await DoseLogIdentity.fetch(container: container)
        guard identity.entryCount > 0, !Task.isCancelled else { return false }
        let cacheKey = TimelineStripCache.key(
            storeGeneration: DoseLogService.storeGeneration,
            entryCount: identity.entryCount,
            newestTimestamp: identity.newestTimestamp,
            preferences: preferences,
            now: now,
        )
        guard let cached = await TimelineStripCache.load(matching: cacheKey, now: now), !Task.isCancelled else { return false }
        days = cached
        builtKey = "\(revision)|\(preferences)|\(identity.entryCount)"
        return true
    }

    /// Every `Session` in one fetch, keyed by identifier, for the builder's
    /// session reads (see `TimelineStripBuilder.session(of:in:)`).
    private static func sessionsByID(of entries: [DoseEntry]) -> [PersistentIdentifier: Session] {
        guard let context = entries.first?.modelContext,
              let sessions = try? context.fetch(FetchDescriptor<Session>()) else { return [:] }
        return Dictionary(sessions.map { ($0.persistentModelID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// How far back the heart-rate trace is read. A wrist sensor records
    /// every few minutes, so a whole log would be hundreds of thousands of
    /// samples for a texture only the recent strip has room to show.
    private static let heartRateLookbackDays = 14

    /// The recent stretch's heart rate, read the way the session detail reads
    /// it: a plain query with no authorization prompt, empty when there is no
    /// access or nothing recorded. The caller has already asked
    /// ``HealthKitVitals/isOn(overlay:)``.
    private static func recentHeartRate(entries: [DoseEntry]) async -> [HeartRateSample] {
        let now = DebugClock.now
        guard let oldest = entries.map(\.timestamp).min() else { return [] }
        let start = max(oldest, Calendar.current.date(byAdding: .day, value: -heartRateLookbackDays, to: now) ?? now)
        guard start < now else { return [] }

        #if DEBUG
            // On-simulator visual verification without Health data.
            if HealthKitVitals.usesFakeVitals {
                let doses = entries.map(\.timestamp).filter { $0 >= start && $0 <= now }
                return DebugVitals.synthetic(doses: doses, start: start, end: now).heartRate
            }
        #endif
        return await HealthKitVitals.shared.vitals(from: start, to: now).heartRate
    }
}
