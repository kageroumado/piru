import AsyncAlgorithms
import SwiftData
import SwiftUI

// MARK: - Snapshot inputs (Sendable — cross the actor boundary to the sampler)

/// One logged dose reduced to the stored fields a body-load plan reads, so the
/// background warm fetches the log on ``DatabaseActor`` and hands the main actor
/// values. The view-driven path maps its `@Query` entries the same way, so both
/// paths resolve through one ``BodyLevelsManager/Plan/build``.
nonisolated struct BodyLoadEntry: Sendable {
    let substance: String
    let substanceUID: String?
    let amount: Double
    let unit: String
    let isUnknownDose: Bool
    let timestamp: Date
    let route: RouteOfAdministration
    let saltForm: String?
    let isomer: String?
    let releaseForm: String?
    let productName: String?
    let meal: MealState?

    init(_ entry: DoseEntry) {
        substance = entry.substance
        substanceUID = entry.substanceUID
        amount = entry.amount
        unit = entry.unit
        isUnknownDose = entry.isUnknownDose
        timestamp = entry.timestamp
        route = entry.route
        saltForm = entry.saltForm
        isomer = entry.isomer
        releaseForm = entry.releaseForm
        productName = entry.productName
        meal = entry.meal
    }
}

/// One dose reduced to its grouping identity + resolved PK params, so the per-day
/// body-load replay runs off the main actor. The `SubstanceLibrary`/duration
/// lookups behind `ke`/`ka` are all `@MainActor`, so they happen once while
/// building these on the main actor; only the exponential math crosses off-main.
nonisolated struct BodyLoadDose: Sendable {
    /// Index into the trail's series (one per substance + unit family).
    let seriesIndex: Int
    /// Amount in the series' established unit.
    let amount: Double
    let timestamp: Date
    let ke: Double
    let ka: Double
}

// MARK: - Trail output (built + consumed on the main actor)

/// The historic per-substance body-load trail across a time range — the data
/// behind the Insights "In your body over time" graph. Each series is one
/// substance (per unit family); values are the estimated in-body amount at each
/// sample date, and `fraction` normalizes each series to its own peak so lines in
/// different units can share one axis without a dishonest cross-substance sum.
nonisolated struct BodyLoadTrail: Codable, Sendable {
    nonisolated struct Point: Identifiable, Codable, Sendable {
        let id: Int
        let date: Date
        /// Estimated in-body amount at `date`, in the series' unit.
        let amount: Double
        /// `amount` as a share of the series' own peak over the window, `0…1`.
        let fraction: Double
    }

    nonisolated struct Series: Identifiable, Codable, Sendable {
        let id: Int
        /// The name to show the user (relabels applied).
        let displayName: String
        let color: Color
        let unit: String
        /// Peak in-body amount over the window, in `unit`.
        let peak: Double
        /// Doses logged inside the window.
        let doseCount: Int
        let points: [Point]

        init(id: Int, displayName: String, color: Color, unit: String, peak: Double, doseCount: Int, points: [Point]) {
            self.id = id
            self.displayName = displayName
            self.color = color
            self.unit = unit
            self.peak = peak
            self.doseCount = doseCount
            self.points = points
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case displayName
            case tint
            case unit
            case peak
            case doseCount
            case points
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(Int.self, forKey: .id)
            displayName = try c.decode(String.self, forKey: .displayName)
            color = try c.decode(P3Color.self, forKey: .tint).color
            unit = try c.decode(String.self, forKey: .unit)
            peak = try c.decode(Double.self, forKey: .peak)
            doseCount = try c.decode(Int.self, forKey: .doseCount)
            points = try c.decode([Point].self, forKey: .points)
        }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(displayName, forKey: .displayName)
            try c.encode(color.cacheTint(), forKey: .tint)
            try c.encode(unit, forKey: .unit)
            try c.encode(peak, forKey: .peak)
            try c.encode(doseCount, forKey: .doseCount)
            try c.encode(points, forKey: .points)
        }
    }

    /// Sample grid, oldest → newest.
    let dates: [Date]
    /// Series ordered by doses logged in the window, most first, then by peak.
    let series: [Series]

    var isEmpty: Bool {
        series.isEmpty || dates.isEmpty
    }

    static let empty = BodyLoadTrail(dates: [], series: [])
}

// MARK: - Manager

/// Computes the historic body-load trail from the dose log, sampled over a day
/// grid, with the same proven shape as ``ToleranceStore``: an `@Observable`
/// `@MainActor` singleton that resolves PK params on the main actor, runs the
/// exponential replay off-main, caches per ``BodyLevelsTrailCache/Key``, and
/// warms the default range in the background off a debounced dose-log loop so the
/// first navigation to the graph is instant.
///
/// The cache is keyed by the dose log's identity (store generation, count,
/// newest timestamp) and the hour, so an unchanged log is a no-op, and by
/// range so toggling 30D↔90D reuses earlier work. The warmed default range is
/// also kept on disk (``BodyLevelsTrailCache``), so the warm after a launch
/// whose log is unchanged reads a file instead of fetching the log. A dose never changes the
/// past, so a future per-day causal cache could recompute only the tail past an
/// edit; the whole-trail recompute here mirrors what `ToleranceStore` actually
/// does today (one signature-gated replay) and is fast enough that the finer
/// cache is deferred.
@Observable
@MainActor
final class BodyLevelsManager {
    static let shared = BodyLevelsManager()

    /// The trail for the most recent view-driven ``refresh(entries:colors:range:now:)``.
    private(set) var trail: BodyLoadTrail?

    /// The latest trail per range; a newer key for a range replaces the older one.
    @ObservationIgnored private var cache: [BodyLevelsTrailCache.Key: BodyLoadTrail] = [:]
    @ObservationIgnored private var container: ModelContainer?
    @ObservationIgnored private var warmTask: Task<Void, Never>?

    /// The range warmed in the background, so a cold navigation to the graph lands
    /// on a filled cache. Matches the graph's own default.
    private static let warmRange: UsageTimeRange = .thirtyDays

    init() {}

    /// Bind to the shared container and start the debounced background warm loop
    /// (only for the singleton — a test instance must not race the change stream).
    func configure(container: ModelContainer) {
        self.container = container
        guard self === Self.shared else { return }
        startBackgroundWarm()
    }

    /// View-driven compute. Returns the cached trail when the `(range, log
    /// identity)` key is unchanged; otherwise resolves on the main actor,
    /// replays off-main, caches, and publishes to ``trail``.
    func refresh(entries: [DoseEntry], colors: [SubstanceColor], range: UsageTimeRange, now: Date = .now) async {
        let key = Self.key(
            range: range,
            entryCount: entries.count,
            newestTimestamp: entries.map(\.timestamp).max(),
            colorSignature: LaunchCacheInputs.colorSignature(colors),
            now: now,
        )
        if let cached = cache[key] {
            trail = cached
            return
        }
        trail = await computeAndCache(
            entries: entries.map(BodyLoadEntry.init), colorMap: colors.colorMap, range: range, key: key, now: now,
        )
    }

    // MARK: Background warm

    private func startBackgroundWarm() {
        warmTask?.cancel()
        warmTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5)) // let first paint settle
            if Task.isCancelled { return }
            await self?.warm()
            let ticks = DoseLogService.shared.changeStream().debounce(for: .seconds(2))
            for await _ in ticks {
                if Task.isCancelled { return }
                await self?.warm()
            }
        }
    }

    /// Pre-fill the cache for the default range without touching ``trail`` (the
    /// user may be viewing another range). The log's identity is read off the
    /// main actor first; only a key nobody has built yet — in memory or on disk —
    /// fetches the log, as value snapshots on ``DatabaseActor``, and resolves it
    /// here. The colors are the ones the key was built from.
    private func warm() async {
        guard let container else { return }
        let now = Date.now
        let identity = await DoseLogIdentity.fetch(container: container)
        let key = Self.key(
            range: Self.warmRange,
            entryCount: identity.entryCount,
            newestTimestamp: identity.newestTimestamp,
            colorSignature: LaunchCacheInputs.colorSignature(identity.colors),
            now: now,
        )
        guard cache[key] == nil else { return }
        if let cached = await BodyLevelsTrailCache.load(matching: key) {
            store(cached, for: key)
            return
        }
        guard let entries = await Self.fetchEntries(container: container) else { return }
        let colorMap = Dictionary(
            identity.colors.map { ($0.substance.lowercased(), $0.tint.color) }, uniquingKeysWith: { _, last in last },
        )
        _ = await computeAndCache(entries: entries, colorMap: colorMap, range: Self.warmRange, key: key, now: now)
    }

    /// The whole dose log, newest first, as value snapshots read through a context of
    /// its own; `nil` when the fetch fails.
    @DatabaseActor
    private static func fetchEntries(container: ModelContainer) -> [BodyLoadEntry]? {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<DoseEntry>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        return (try? context.fetch(descriptor))?.map(BodyLoadEntry.init)
    }

    // MARK: Compute

    private func store(_ trail: BodyLoadTrail, for key: BodyLevelsTrailCache.Key) {
        cache = cache.filter { $0.key.range != key.range }
        cache[key] = trail
    }

    private func computeAndCache(
        entries: [BodyLoadEntry], colorMap: [String: Color],
        range: UsageTimeRange, key: BodyLevelsTrailCache.Key, now: Date,
    ) async -> BodyLoadTrail {
        // The plan resolves substances on the main actor; a cold store traps there.
        await SubstanceStore.shared.ensureAllLoaded()
        guard let plan = Plan.build(entries: entries, colorMap: colorMap, range: range, now: now) else {
            let empty = BodyLoadTrail.empty
            store(empty, for: key)
            return empty
        }
        let doses = plan.doses
        let dates = plan.dates
        let seriesCount = plan.meta.count
        // Off the main actor: the exponential replay only. `Task.detached` is what
        // forces it off main — a bare `nonisolated` call would be pulled back onto
        // the calling (main) actor under NonisolatedNonsendingByDefault (SE-0461).
        let values = await Task.detached(priority: .utility) {
            Self.sample(doses: doses, dates: dates, seriesCount: seriesCount)
        }.value
        let built = plan.assemble(values: values)
        store(built, for: key)
        if range == Self.warmRange {
            BodyLevelsTrailCache.save(built, key: key)
        }
        return built
    }

    /// The pure sampler: at each sample date, sum each dose's remaining fraction
    /// into its series. `nonisolated` + `Sendable` inputs, so it runs off-main.
    /// Doses are only summed at or after their own timestamp (causality); `dates`
    /// is ascending, so a per-dose lower bound skips the leading zero span.
    nonisolated static func sample(doses: [BodyLoadDose], dates: [Date], seriesCount: Int) -> [[Double]] {
        var out = Array(repeating: [Double](repeating: 0, count: dates.count), count: seriesCount)
        guard !dates.isEmpty else { return out }
        for dose in doses {
            let start = lowerBound(dates, dose.timestamp)
            guard start < dates.count else { continue }
            for i in start ..< dates.count {
                let elapsed = dates[i].timeIntervalSince(dose.timestamp) / 60
                out[dose.seriesIndex][i] += dose.amount * PKModel.fractionRemainingInBody(at: elapsed, ke: dose.ke, ka: dose.ka)
            }
        }
        return out
    }

    /// First index in the ascending `dates` whose value is `>= target`.
    private nonisolated static func lowerBound(_ dates: [Date], _ target: Date) -> Int {
        var lo = 0, hi = dates.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if dates[mid] < target { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    // MARK: Cache key

    /// The cache key for `range` over a log with this identity. Hourly-bucketed
    /// so decay refreshes at most ~hourly and never on mere navigation. Body
    /// weight is absent: the first-order `fractionRemainingInBody` used here
    /// doesn't depend on it.
    private static func key(
        range: UsageTimeRange, entryCount: Int, newestTimestamp: Date?, colorSignature: Int, now: Date,
    ) -> BodyLevelsTrailCache.Key {
        BodyLevelsTrailCache.Key(
            range: range.rawValue,
            storeGeneration: DoseLogService.storeGeneration,
            entryCount: entryCount,
            newestTimestamp: newestTimestamp,
            hourBucket: Int(now.timeIntervalSince1970 / 3_600),
            colorSignature: colorSignature,
            customSignature: LaunchCacheInputs.customSubstanceSignature,
            databaseSignature: LaunchCacheInputs.databaseSignature,
            appBuild: LaunchCacheInputs.appBuild,
        )
    }
}
