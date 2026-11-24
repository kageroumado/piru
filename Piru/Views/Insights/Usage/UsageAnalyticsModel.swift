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
    /// The journal's first entry, whatever the substance filter narrows to.
    private var journalStart: Date?
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
            journalStart = resolved.snapshots.map(\.timestamp).min()
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
        let journalStart = journalStart
        let computed = await Task.detached(priority: .userInitiated) {
            UsageAnalytics.compute(
                entries: payload, substances: refs, range: range,
                calendar: calendar, now: now, journalStart: journalStart,
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
        var moleculeIndices: [String: Int] = [:]
        var substances: [UsageSubstanceRef] = []
        var resolvedSubstances: [String: Substance?] = [:]
        var titles: [TitleKey: String] = [:]
        var ladders: [LadderKey: DoseLadder?] = [:]

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

            // A row per dose title, so a branded med ("Concerta") is its own row.
            let titleKey = TitleKey(
                substance: key, productName: entry.productName, namesForm: entry.namesAForm,
                isomer: entry.isomer, releaseForm: entry.releaseForm, saltForm: entry.saltForm,
            )
            let title: String
            if let cached = titles[titleKey] {
                title = cached
            } else {
                title = DoseTitle.resolve(for: entry)
                titles[titleKey] = title
            }

            let categoryIndex = substance.flatMap { categoryIndices[$0.category] } ?? otherCategoryIndex
            // The molecule is the library's canonical substance, which a brand row shares.
            let canonical = substance?.name ?? entry.substance
            let moleculeKey = canonical.lowercased()
            let rowKey = title.lowercased()
            let substanceIndex: Int
            if let existing = substanceIndices[rowKey] {
                substanceIndex = existing
            } else {
                substanceIndex = substances.count
                substanceIndices[rowKey] = substanceIndex
                substances.append(UsageSubstanceRef(
                    name: title,
                    displayName: title,
                    categoryIndex: categoryIndex,
                    colorKey: entry.substance,
                    moleculeName: DoseTitle.resolve(
                        substance: canonical, productName: nil, namesForm: false,
                        isomer: nil, releaseForm: nil, saltForm: nil,
                    ),
                ))
            }

            let moleculeIndex: Int
            if let existing = moleculeIndices[moleculeKey] {
                moleculeIndex = existing
            } else {
                moleculeIndex = moleculeIndices.count
                moleculeIndices[moleculeKey] = moleculeIndex
            }

            let ladderKey = LadderKey(
                substance: key, route: entry.route,
                saltForm: entry.saltForm, isomer: entry.isomer, releaseForm: entry.releaseForm,
            )
            var ladder: DoseLadder?
            if let cached = ladders[ladderKey] {
                ladder = cached
            } else {
                ladder = substance?.tierLadder(
                    for: entry.route, saltForm: entry.saltForm, isomer: entry.isomer, releaseForm: entry.releaseForm,
                )
                ladders[ladderKey] = ladder
            }
            // An unknown dose is counted but has no tier and no common-dose
            // multiple — a 0 would read as the lowest tier.
            let dose = substance?.quantity(of: entry) ?? entry.quantity

            snapshots.append(UsageEntrySnapshot(
                substanceIndex: substanceIndex,
                moleculeIndex: moleculeIndex,
                categoryIndex: categoryIndex,
                routeIndex: routeIndices[entry.route] ?? 0,
                doseLevelIndex: dose.flatMap { ladder?.level(of: $0) }.map(Self.index(of:)),
                commonDoses: dose.flatMap { ladder?.commonDoses(of: $0) },
                timestamp: entry.timestamp,
            ))
        }

        return (snapshots, substances)
    }

    /// Every field ``DoseTitle/resolve(for:)`` reads, so a thousand Concerta
    /// doses resolve their title once.
    private struct TitleKey: Hashable {
        let substance: String
        let productName: String?
        let namesForm: Bool
        let isomer: String?
        let releaseForm: String?
        let saltForm: String?
    }

    /// Identity of one dose ladder: a substance's tiers for a route, narrowed to
    /// the logged salt/isomer (the salt overload matters — a magnesium glycinate
    /// dose must not be read against the default form's numbers) and release
    /// form (an extended-release product has no ladder).
    private struct LadderKey: Hashable {
        let substance: String
        let route: RouteOfAdministration
        let saltForm: String?
        let isomer: String?
        let releaseForm: String?
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
