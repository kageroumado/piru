import SwiftData
import SwiftUI

/// Owns the Usage screen's derived state.
///
/// Two stages, split by what each one is allowed to touch:
///
/// 1. **On the main actor** — walk the `@Query` results once and reduce every
///    `DoseEntry` to a `Sendable` ``UsageEntrySnapshot``. This is where the
///    `SubstanceLibrary` lookups happen (category, dose ladder), because both
///    the façade and the `@Model` accessors are main-isolated. It's bounded by
///    the number of *distinct* substances, not entries — the per-substance
///    resolution is memoized in ``resolve(entries:)``.
/// 2. **Off the main actor** — ``UsageAnalytics/compute(entries:substances:range:calendar:now:)``
///    does the heavy part: heatmap cells, rolling windows over every bucket,
///    the O(days × k²) co-occurrence pass, periodicity. On a multi-year history
///    that is far too much to do inside `body`.
///
/// Both stages are memoized. Stage 1 re-runs only when the entries' content
/// fingerprint changes; stage 2 only when the fingerprint *or* the selected
/// range changes. Scrolling recomputes nothing.
@Observable
@MainActor
final class UsageAnalyticsModel {
    /// The finished aggregation, or `nil` before the first pass completes.
    private(set) var result: UsageAnalyticsResult?
    /// `true` while a recompute is in flight and no previous result is showing.
    private(set) var isLoading = false
    /// Lowercased substance name → assigned color.
    private(set) var colorMap: [String: Color] = [:]

    /// Every substance seen across all logged entries — the full list, unaffected
    /// by the active substance filter — so the toolbar filter menu can always
    /// offer every substance to re-add.
    var allSubstances: [UsageSubstanceRef] {
        substances
    }

    /// Stage-1 output, kept so a range change doesn't re-walk SwiftData.
    private var snapshots: [UsageEntrySnapshot] = []
    private var substances: [UsageSubstanceRef] = []
    private var snapshotFingerprint: Int?
    private var resultKey: Int?

    // MARK: - Refresh

    /// Recompute if the entries or the range changed. Safe (and cheap) to call
    /// on every `task(id:)` fire.
    func refresh(
        entries: [DoseEntry],
        colors: [SubstanceColor],
        range: UsageTimeRange,
        substanceFilter: Set<String> = [],
        now: Date = .now,
    ) async {
        var fpHasher = Hasher()
        fpHasher.combine(DoseLogService.shared.revision)
        fpHasher.combine(ColorsFingerprint.make(colors))
        let fingerprint = fpHasher.finalize()
        if snapshotFingerprint != fingerprint {
            colorMap = colors.colorMap
            let resolved = Self.resolve(entries: entries)
            snapshots = resolved.snapshots
            substances = resolved.substances
            snapshotFingerprint = fingerprint
        }

        var hasher = Hasher()
        hasher.combine(fingerprint)
        hasher.combine(range)
        hasher.combine(substanceFilter.sorted().joined(separator: "\u{1}"))
        let key = hasher.finalize()
        guard resultKey != key else { return }

        isLoading = result == nil
        // Narrow the stage-1 snapshots to the chosen substances (empty = all),
        // but always hand `compute` the FULL substance list: `result.substances`
        // is what populates the filter menu, so it must keep every substance even
        // when the charts are showing a subset.
        let allowed: Set<Int>? = substanceFilter.isEmpty ? nil
            : Set(substances.enumerated().compactMap {
                substanceFilter.contains($0.element.name) ? $0.offset : nil
            })
        let payload = allowed.map { indices in
            snapshots.filter { indices.contains($0.substanceIndex) }
        } ?? snapshots
        let refs = substances
        let calendar = Calendar.current
        let computed = await Task.detached(priority: .userInitiated) {
            UsageAnalytics.compute(
                entries: payload, substances: refs, range: range,
                calendar: calendar, now: now,
            )
        }.value
        // The key is committed only once the result is actually published: a
        // pass cancelled mid-flight (the user flicked through ranges) must not
        // leave its key behind, or coming back to that range would short-circuit
        // to a result that never landed.
        guard !Task.isCancelled else { return }
        resultKey = key
        result = computed
        isLoading = false
    }

    // MARK: - Stage 1: SwiftData → Sendable snapshots

    /// Reduce logged doses to plain values, resolving each one's category and
    /// dose level through the ``SubstanceLibrary`` façade (never the raw store —
    /// the façade is what overlays the user's own duration/relabel edits).
    ///
    /// The library lookup is memoized per distinct substance name and the dose
    /// ladder per (name, route, salt, isomer), so a thousand caffeine doses cost
    /// one lookup.
    static func resolve(entries: [DoseEntry]) -> (snapshots: [UsageEntrySnapshot], substances: [UsageSubstanceRef]) {
        let categoryIndices = Dictionary(
            SubstanceCategory.allCases.enumerated().map { ($1, $0) },
            uniquingKeysWith: { first, _ in first },
        )
        let routeIndices = Dictionary(
            RouteOfAdministration.allCases.enumerated().map { ($1, $0) },
            uniquingKeysWith: { first, _ in first },
        )
        let otherCategoryIndex = categoryIndices[.other] ?? 0

        var substanceIndices: [String: Int] = [:]
        var substances: [UsageSubstanceRef] = []
        var resolvedSubstances: [String: Substance?] = [:]
        var ladders: [LadderKey: Ladder?] = [:]

        var snapshots: [UsageEntrySnapshot] = []
        snapshots.reserveCapacity(entries.count)

        for entry in entries {
            let key = entry.substance.lowercased()
            var substance: Substance?
            if let cached = resolvedSubstances[key] {
                substance = cached
            } else {
                substance = SubstanceLibrary.lookup(entry.substance)
                resolvedSubstances[key] = substance
            }

            let categoryIndex = substance.flatMap { categoryIndices[$0.category] } ?? otherCategoryIndex
            let substanceIndex: Int
            if let existing = substanceIndices[key] {
                substanceIndex = existing
            } else {
                substanceIndex = substances.count
                substanceIndices[key] = substanceIndex
                substances.append(UsageSubstanceRef(
                    name: entry.substance,
                    displayName: CustomSubstanceStore.shared.displayName(for: entry.substance),
                    categoryIndex: categoryIndex,
                ))
            }

            let ladderKey = LadderKey(
                substance: key, route: entry.route,
                saltForm: entry.saltForm, isomer: entry.isomer,
            )
            var ladder: Ladder?
            if let cached = ladders[ladderKey] {
                ladder = cached
            } else {
                ladder = Ladder(substance: substance, key: ladderKey)
                ladders[ladderKey] = ladder
            }

            snapshots.append(UsageEntrySnapshot(
                substanceIndex: substanceIndex,
                categoryIndex: categoryIndex,
                routeIndex: routeIndices[entry.route] ?? 0,
                doseLevelIndex: ladder?.levelIndex(for: entry.amount, unit: entry.unit),
                amount: entry.amount,
                commonDoses: ladder?.commonDoses(for: entry.amount, unit: entry.unit),
                timestamp: entry.timestamp,
            ))
        }

        return (snapshots, substances)
    }

    /// Identity of one dose ladder: a substance's tiers for a route, narrowed to
    /// the logged salt/isomer (the salt overload matters — a magnesium glycinate
    /// dose must not be read against the default form's numbers).
    private struct LadderKey: Hashable {
        let substance: String
        let route: RouteOfAdministration
        let saltForm: String?
        let isomer: String?
    }

    /// A resolved dose ladder plus the unit its numbers are stated in.
    private struct Ladder {
        let range: DoseRange
        let unit: String

        init?(substance: Substance?, key: LadderKey) {
            guard let substance,
                  let range = substance.doseRange(for: key.route, saltForm: key.saltForm, isomer: key.isomer),
                  range.hasAnyValue else { return nil }
            self.range = range
            unit = substance.unit(for: key.route, saltForm: key.saltForm, isomer: key.isomer)
        }

        func levelIndex(for amount: Double, unit loggedUnit: String) -> Int? {
            UsageAnalyticsModel.doseLevelIndex(
                range: range, ladderUnit: unit, amount: amount, loggedUnit: loggedUnit,
            )
        }

        func commonDoses(for amount: Double, unit loggedUnit: String) -> Double? {
            UsageAnalyticsModel.commonDoses(
                range: range, ladderUnit: unit, amount: amount, loggedUnit: loggedUnit,
            )
        }
    }

    // MARK: - Dose-level resolution

    /// A dose's tier as an index into `DoseLevel.allCases`, or `nil` when it
    /// cannot be placed.
    ///
    /// The unit check is the whole point of the fallback. A ladder written in mg
    /// and a dose logged in mL are not comparable, and reading the bare number
    /// across would file a 5 mL drink in the same tier as 5 mg of a
    /// milligram-potent drug. `DoseUnit.convert` returns `nil` for anything that
    /// isn't a bare mass unit — including qualified spellings like
    /// "mg (freebase)", which state a basis rather than decorating one — so
    /// those entries drop out of §4 and are counted in its "N of M" footnote
    /// instead of being guessed at.
    static func doseLevelIndex(
        range: DoseRange,
        ladderUnit: String,
        amount: Double,
        loggedUnit: String,
    ) -> Int? {
        guard let converted = DoseUnit.convert(amount, from: loggedUnit, to: ladderUnit),
              let level = range.level(for: converted) else { return nil }
        return index(of: level)
    }

    /// A dose as a multiple of the substance's common dose, or `nil` when it
    /// can't be expressed that way.
    ///
    /// Two things have to hold, and both are the same honesty gate §4 already
    /// applies: the ladder must state a `common` band (a threshold-only or
    /// heavy-only ladder has no midpoint to divide by), and the logged unit must
    /// convert to the ladder's — a mL drink against a mg ladder is not a fraction
    /// of anything. When either fails the dose has no common-dose value and is
    /// left out of the common-dose ranking rather than counted as zero, which
    /// would read as "never taken" instead of "not measurable this way".
    static func commonDoses(
        range: DoseRange,
        ladderUnit: String,
        amount: Double,
        loggedUnit: String,
    ) -> Double? {
        guard let common = range.common else { return nil }
        let midpoint = (common.lowerBound + common.upperBound) / 2
        guard midpoint > 0,
              let converted = DoseUnit.convert(amount, from: loggedUnit, to: ladderUnit) else { return nil }
        return converted / midpoint
    }

    /// `DoseLevel` → its position in `DoseLevel.allCases`. Written out rather
    /// than derived from `allCases` so it is a compile-time total switch: a new
    /// tier would break the build here instead of silently shifting every band
    /// in §4.
    static func index(of level: DoseLevel) -> Int {
        switch level {
        case .sub: 0
        case .threshold: 1
        case .light: 2
        case .common: 3
        case .strong: 4
        case .heavy: 5
        }
    }
}
