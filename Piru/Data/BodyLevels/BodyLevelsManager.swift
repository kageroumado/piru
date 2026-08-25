import AsyncAlgorithms
import SwiftData
import SwiftUI

// MARK: - Snapshot inputs (Sendable — cross the actor boundary to the sampler)

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
struct BodyLoadTrail {
    struct Point: Identifiable {
        let id: Int
        let date: Date
        /// Estimated in-body amount at `date`, in the series' unit.
        let amount: Double
        /// `amount` as a share of the series' own peak over the window, `0…1`.
        let fraction: Double
    }

    struct Series: Identifiable {
        let id: Int
        /// The name to show the user (relabels applied).
        let displayName: String
        let color: Color
        let unit: String
        /// Peak in-body amount over the window, in `unit`.
        let peak: Double
        let points: [Point]
    }

    /// Sample grid, oldest → newest.
    let dates: [Date]
    /// Series ordered by peak body-load, largest first.
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
/// exponential replay off-main, caches per `(range, content-signature)`, and
/// warms the default range in the background off a debounced dose-log loop so the
/// first navigation to the graph is instant.
///
/// The cache is keyed by a content signature so an unchanged log is a no-op, and
/// by range so toggling 30D↔90D reuses earlier work. A dose never changes the
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

    @ObservationIgnored private var cache: [String: BodyLoadTrail] = [:]
    @ObservationIgnored private var container: ModelContainer?
    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private var warmTask: Task<Void, Never>?

    /// The range warmed in the background, so a cold navigation to the graph lands
    /// on a filled cache. Matches the graph's own default.
    private static let warmRange: UsageTimeRange = .thirtyDays

    init() {}

    /// Bind to the shared container and start the debounced background warm loop
    /// (only for the singleton — a test instance must not race the change stream).
    func configure(container: ModelContainer) {
        self.container = container
        context = ModelContext(container)
        guard self === Self.shared else { return }
        startBackgroundWarm()
    }

    /// View-driven compute. Returns the cached trail when the `(range, content
    /// signature)` is unchanged; otherwise resolves on the main actor, replays
    /// off-main, caches, and publishes to ``trail``.
    func refresh(entries: [DoseEntry], colors: [SubstanceColor], range: UsageTimeRange, now: Date = .now) async {
        let key = Self.cacheKey(range: range, entries: entries, now: now)
        if let cached = cache[key] {
            trail = cached
            return
        }
        trail = await computeAndCache(entries: entries, colors: colors, range: range, key: key, now: now)
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

    /// Pre-fill the cache for the default range from the store's own context,
    /// without touching ``trail`` (the user may be viewing another range).
    private func warm() async {
        guard let context else { return }
        let now = Date.now
        let descriptor = FetchDescriptor<DoseEntry>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        guard let entries = try? context.fetch(descriptor) else { return }
        let colors = (try? context.fetch(FetchDescriptor<SubstanceColor>())) ?? []
        let key = Self.cacheKey(range: Self.warmRange, entries: entries, now: now)
        guard cache[key] == nil else { return }
        _ = await computeAndCache(entries: entries, colors: colors, range: Self.warmRange, key: key, now: now)
    }

    // MARK: Compute

    private func computeAndCache(
        entries: [DoseEntry], colors: [SubstanceColor],
        range: UsageTimeRange, key: String, now: Date,
    ) async -> BodyLoadTrail {
        guard let plan = Plan.build(entries: entries, colors: colors, range: range, now: now) else {
            let empty = BodyLoadTrail.empty
            cache[key] = empty
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
        cache[key] = built
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

    // MARK: Cache key / signature

    private static func cacheKey(range: UsageTimeRange, entries: [DoseEntry], now: Date) -> String {
        "\(range.rawValue)|\(signature(entries: entries, now: now))"
    }

    /// Order-independent XOR content signature over every dose at or before `now`,
    /// hourly-bucketed so decay refreshes at most ~hourly and never on mere
    /// navigation. Mirrors ``ToleranceStore``'s dedupe. Body weight is absent: the
    /// first-order `fractionRemainingInBody` used here doesn't depend on it.
    private static func signature(entries: [DoseEntry], now: Date) -> String {
        var combined: UInt64 = 0
        var count = 0
        for entry in entries where entry.timestamp <= now {
            count += 1
            var hasher = Hasher()
            hasher.combine(entry.substance)
            hasher.combine(entry.amount)
            hasher.combine(entry.unit)
            hasher.combine(entry.timestamp)
            hasher.combine(entry.route)
            combined ^= UInt64(bitPattern: Int64(hasher.finalize()))
        }
        return "\(count)|\(combined)|\(Int(now.timeIntervalSince1970 / 3_600))"
    }
}
