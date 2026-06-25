import Foundation
import SwiftData

// MARK: - Quick Log Data Types

/// A recent/favorite substance with its route groups, backing one card in the
/// quick-log list. Built from the curated `QuickLogDose` rows, not raw history.
struct SubstanceCard: Identifiable {
    let substanceName: String
    let colorHex: String?
    let routes: [SubstanceGroup]
    let latestTimestamp: Date

    var id: String {
        substanceName.lowercased()
    }
}

/// One (substance, route) pairing within a card, carrying its curated dose
/// chips sorted for display.
struct SubstanceGroup: Identifiable {
    let id: String
    let substanceName: String
    let route: RouteOfAdministration
    let colorHex: String?
    let librarySubstance: Substance?
    var latestTimestamp: Date
    private var chipEntries: [(amount: Double, unit: String, sortOrder: Double)] = []

    var doses: [DoseChip] {
        // Alcohol (and any by-volume substance) presents its drink presets as the
        // tappable chips — Beer/Wine/Shot/Pint, each carrying that drink's grams —
        // instead of the raw grams the user happened to log. Tapping stages the
        // grams and accumulates exactly like any dose chip.
        if let byVolume = librarySubstance?.byVolumeDosing {
            return byVolume.drinkPresets.map { preset in
                let ml = preset.volume.converted(to: .milliliters).value
                let grams = (byVolume.canonicalAmount(volumeML: ml, strength: preset.defaultABV) * 10).rounded() / 10
                return DoseChip(amount: grams, unit: byVolume.canonicalUnit, label: preset.name, systemImage: preset.systemImage)
            }
        }
        return chipEntries
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { DoseChip(amount: $0.amount, unit: $0.unit) }
    }

    init(substanceName: String, route: RouteOfAdministration, colorHex: String?, librarySubstance: Substance?, latestTimestamp: Date) {
        self.id = "\(substanceName.lowercased())|\(route.rawValue)"
        self.substanceName = substanceName
        self.route = route
        self.colorHex = colorHex
        self.librarySubstance = librarySubstance
        self.latestTimestamp = latestTimestamp
    }

    /// Add a curated chip (sorted by `sortOrder` for display). Tracks the most
    /// recent use so cards order by recency.
    mutating func addChip(amount: Double, unit: String, sortOrder: Double, lastUsedAt: Date) {
        chipEntries.append((amount: amount, unit: unit, sortOrder: sortOrder))
        if lastUsedAt > latestTimestamp {
            latestTimestamp = lastUsedAt
        }
    }
}

/// A single tappable dose amount within a `SubstanceGroup`. Carries an optional
/// drink label + icon for by-volume substances (alcohol), where the chip reads
/// "🍺 Beer" rather than a bare gram amount.
struct DoseChip: Identifiable {
    let amount: Double
    let unit: String
    let label: LocalizedStringResource?
    let systemImage: String?

    init(amount: Double, unit: String, label: LocalizedStringResource? = nil, systemImage: String? = nil) {
        self.amount = amount
        self.unit = unit
        self.label = label
        self.systemImage = systemImage
    }

    var id: String {
        if let label { return "\(String(localized: label))|\(amount)|\(unit)" }
        return "\(amount)|\(unit)"
    }

    var formattedAmount: String {
        amount.doseFormatted
    }
}

// MARK: - Daily routine grouping

/// "Prescriptions" reconceived: pre-set daily drugs (meds, supplements,
/// anything routine) as first-class cards whose item-chips stage into the
/// same tray as everything else.
struct DailyCategoryGroup: Identifiable {
    let id: String
    let title: String
    let icon: String
    let items: [DailyDoseItem]
    let remaining: [DailyDoseItem]
}

// MARK: - Card PK badge

/// Precomputed PK badge data for one card, built when `cachedMostRecent`
/// rebuilds — so `DosePK.status` (two `SubstanceLibrary` lookups + PK math) and
/// the last-dose field reads run once per history change in the model, not per
/// card on every `body` evaluation. Carries the narrow last-dose values the
/// card's badge + expanded card need, never the live `DoseEntry`.
struct CardPKBadge {
    let remainingPercent: Double
    let waitMinutes: Double
    let lastDoseAmount: Double
    let lastDoseUnit: String
    let lastDoseTimestamp: Date
    let lastDoseRoute: RouteOfAdministration

    /// The badge shows only above a 5% floor (matching the full card).
    var showsBadge: Bool {
        remainingPercent > 5
    }
}

// MARK: - Quick Log Content Model

/// Holds every derived dataset the quick-log screen renders. Extracted off
/// `QuickLogView` because the view-struct previously stored ~12 caches inline —
/// several of them arrays of the ~40-field `Substance` value type — so every
/// `body` pass deep-copied the whole dataset (`initializeWithCopy` dominated a
/// 784 ms first-render trace). Owning them on a reference type drops the view's
/// stored surface to a handful of references; `body` reads through the model.
///
/// The rebuild methods take the view's `@Query` arrays and search text as
/// parameters rather than reading view state, so the model stays a pure derived
/// store the view drives from its `.task`/`.onChange` sites.
@Observable
@MainActor
final class QuickLogContentModel {
    private(set) var cachedCards: [SubstanceCard] = []
    private(set) var cachedFavoriteSet: Set<String> = []
    private(set) var cachedFavoriteOrder: [String: Int] = [:]
    private(set) var cachedHistoryNames: Set<String> = []
    private(set) var cachedLibraryResults: [Substance] = []
    private(set) var cachedColorLookup: [String: String] = [:]

    /// Lowercased substance names logged today — drives the routine "done" check.
    private(set) var cachedLoggedToday: Set<String> = []
    /// Precomputed PK badge per lowercased substance name — feeds each card's
    /// glanceable badge without re-running `DosePK.status` in `body`.
    private(set) var cachedMostRecent: [String: CardPKBadge] = [:]
    /// Distinct dose locations, most recent first — the tray's location panel.
    private(set) var cachedRecentLocations: [PickedLocation] = []
    /// Tag suggestions (used-most-first + common extras) — the tray's tag panel.
    private(set) var cachedTagSuggestions: [String] = []

    private(set) var cachedFavoriteCards: [SubstanceCard] = []
    private(set) var cachedNonFavoriteCards: [SubstanceCard] = []
    private(set) var cachedFavoriteLibrarySubstances: [Substance] = []

    private(set) var cachedDailyGroups: [DailyCategoryGroup] = []

    /// Gates the empty-state placeholder: it must not show until the first
    /// rebuild has actually run, or the sheet briefly flashes "No Previous
    /// Substances" on every open before the (now warm-cache, fast) caches fill.
    private(set) var hasLoaded = false

    func markLoaded() {
        hasLoaded = true
    }

    // MARK: Signatures

    /// Cheap content fingerprint of the dose history, used as the rebuild
    /// trigger. `allEntries.count` alone misses an in-place edit (re-dating a
    /// dose, renaming its substance, retagging): the count is unchanged, so
    /// the caches would go stale. Hashing the fields the derived caches
    /// depend on closes that gap.
    static func entriesSignature(_ entries: [DoseEntry]) -> Int {
        var hasher = Hasher()
        for entry in entries {
            hasher.combine(entry.persistentModelID)
            hasher.combine(entry.timestamp)
            hasher.combine(entry.substance)
            hasher.combine(entry.tags)
            hasher.combine(entry.locationName)
        }
        return hasher.finalize()
    }

    // MARK: Rebuilds

    func rebuildColorLookup(substanceColors: [SubstanceColor]) {
        cachedColorLookup = Array(substanceColors).hexColorMap
    }

    /// Recompute everything derived from `allEntries` in a single pass. Called
    /// on open and whenever the history changes (a logged dose) — never from
    /// `body`. `allEntries` is newest-first, which every consumer relies on
    /// (today's slice stops at the first non-today row; most-recent wins).
    func rebuildEntryDerived(allEntries: [DoseEntry], dailyDoseItems: [DailyDoseItem], routines: [DoseRoutine]) {
        var loggedToday: Set<String> = []
        var mostRecentEntry: [String: DoseEntry] = [:]
        var seenLocations = Set<String>()
        var locations: [PickedLocation] = []
        var tagCounts: [String: Int] = [:]
        var stillToday = true

        for entry in allEntries {
            let lower = entry.substance.lowercased()
            if mostRecentEntry[lower] == nil { mostRecentEntry[lower] = entry }
            if stillToday, Calendar.current.isDateInToday(entry.timestamp) {
                loggedToday.insert(lower)
            } else {
                stillToday = false
            }
            for tag in entry.tags {
                tagCounts[tag, default: 0] += 1
            }
            if locations.count < 10,
               let name = entry.locationName, !name.isEmpty,
               let latitude = entry.latitude, let longitude = entry.longitude,
               seenLocations.insert(name).inserted {
                locations.append(PickedLocation(name: name, latitude: latitude, longitude: longitude))
            }
        }

        let used = tagCounts.sorted { $0.value > $1.value }.map(\.key)
        let extras = TagExtractor.suggestions.filter { !used.contains($0) }

        // Resolve the per-substance PK badge once here (the heavy
        // `DosePK.status` work + last-dose field reads) so the card body never
        // touches a live `DoseEntry` or recomputes PK on every render.
        var badges: [String: CardPKBadge] = [:]
        badges.reserveCapacity(mostRecentEntry.count)
        for (lower, entry) in mostRecentEntry {
            guard let status = DosePK.status(
                substanceName: entry.substance,
                route: entry.route,
                lastDoseTimestamp: entry.timestamp,
            ) else { continue }
            badges[lower] = CardPKBadge(
                remainingPercent: status.remainingPercent,
                waitMinutes: status.waitMinutes,
                lastDoseAmount: entry.amount,
                lastDoseUnit: entry.unit,
                lastDoseTimestamp: entry.timestamp,
                lastDoseRoute: entry.route,
            )
        }

        cachedLoggedToday = loggedToday
        cachedMostRecent = badges
        cachedRecentLocations = locations
        cachedTagSuggestions = Array((used + extras).prefix(8))
        // `makeDailyGroups` reads `cachedLoggedToday` (the "done" check), so it
        // must rebuild after that's assigned above.
        cachedDailyGroups = makeDailyGroups(dailyDoseItems: dailyDoseItems, routines: routines)
    }

    func rebuildCards(quickLogDoses: [QuickLogDose], favorites: [FavoriteSubstance]) {
        let colorLookup = cachedColorLookup

        var groupMap: [String: SubstanceGroup] = [:]

        // Cards are built from the curated quick-log list (seeded once from
        // history, then maintained on log), not raw history — so a removed chip
        // stays gone and the order is the user's, not just recency.
        for dose in quickLogDoses {
            let nameLower = dose.substance.lowercased()
            let key = "\(nameLower)|\(dose.route.rawValue)"
            if var group = groupMap[key] {
                group.addChip(amount: dose.amount, unit: dose.unit, sortOrder: dose.sortOrder, lastUsedAt: dose.lastUsedAt)
                groupMap[key] = group
            } else {
                var group = SubstanceGroup(
                    substanceName: dose.substance,
                    route: dose.route,
                    colorHex: colorLookup[nameLower],
                    // Batch-cache lookup (class/routes/doses/salts/durations) —
                    // all a card needs — instead of the heavy per-substance SQL
                    // resolve, which cold-stalled the first open. Same path the
                    // journal uses; pre-warmed via `ensureAllLoaded()` on open.
                    librarySubstance: SubstanceLibrary.timelineLookup(nameLower),
                    latestTimestamp: dose.lastUsedAt,
                )
                group.addChip(amount: dose.amount, unit: dose.unit, sortOrder: dose.sortOrder, lastUsedAt: dose.lastUsedAt)
                groupMap[key] = group
            }
        }

        var cardMap: [String: [SubstanceGroup]] = [:]
        for group in groupMap.values {
            cardMap[group.id.components(separatedBy: "|").first ?? "", default: []].append(group)
        }

        let newCards: [SubstanceCard] = cardMap.values.map { routes in
            let sorted = routes.sorted { $0.latestTimestamp > $1.latestTimestamp }
            let first = sorted[0]
            return SubstanceCard(
                substanceName: first.substanceName,
                colorHex: first.colorHex,
                routes: sorted,
                latestTimestamp: sorted[0].latestTimestamp,
            )
        }.sorted { $0.latestTimestamp > $1.latestTimestamp }

        cachedCards = newCards
        cachedHistoryNames = Set(newCards.map(\.id))
        rebuildFavorites(favorites: favorites)
    }

    func rebuildFavorites(favorites: [FavoriteSubstance]) {
        cachedFavoriteSet = Set(favorites.map { $0.substance.lowercased() })
        // `uniquingKeysWith` guards against two casings of one name colliding
        // when lowercased (the unique attribute is case-sensitive).
        cachedFavoriteOrder = Dictionary(
            favorites.enumerated().map { ($0.element.substance.lowercased(), $0.offset) },
            uniquingKeysWith: { first, _ in first },
        )

        // Favorites hold their user-given positions (the reorder sheet) instead
        // of jumping around with logging recency like the Recent section.
        cachedFavoriteCards = cachedCards
            .filter { cachedFavoriteSet.contains($0.id) }
            .sorted { (cachedFavoriteOrder[$0.id] ?? .max) < (cachedFavoriteOrder[$1.id] ?? .max) }
        cachedNonFavoriteCards = cachedCards.filter { !cachedFavoriteSet.contains($0.id) }
        cachedFavoriteLibrarySubstances = favorites
            .filter { !cachedHistoryNames.contains($0.substance.lowercased()) }
            .compactMap { SubstanceLibrary.timelineLookup($0.substance.lowercased()) }
    }

    /// Rebuild only the routine-pill groups (the settings sheet edited a routine
    /// row or daily item, but history is unchanged).
    func rebuildDailyGroups(dailyDoseItems: [DailyDoseItem], routines: [DoseRoutine]) {
        cachedDailyGroups = makeDailyGroups(dailyDoseItems: dailyDoseItems, routines: routines)
    }

    func makeDailyGroups(dailyDoseItems: [DailyDoseItem], routines: [DoseRoutine]) -> [DailyCategoryGroup] {
        guard !dailyDoseItems.isEmpty else { return [] }
        let loggedToday = cachedLoggedToday

        func remaining(in items: [DailyDoseItem]) -> [DailyDoseItem] {
            items.filter { !loggedToday.contains($0.substance.lowercased()) }
        }

        // Routines flow through the day: timed ones first by clock,
        // untimed after in the user's arranged order.
        let ordered = routines.sorted {
            ($0.timeMinutes ?? .max, $0.sortOrder) < ($1.timeMinutes ?? .max, $1.sortOrder)
        }

        var groups: [DailyCategoryGroup] = []
        var claimed: Set<String> = []
        for routine in ordered {
            claimed.insert(routine.name)
            let items = dailyDoseItems.filter { $0.category == routine.name }
            guard !items.isEmpty else { continue }
            groups.append(DailyCategoryGroup(
                id: routine.name,
                title: routine.name,
                icon: RoutineIcon.symbol(for: routine.name),
                items: items,
                remaining: remaining(in: items),
            ))
        }

        // Items whose category has no routine row (first launch before
        // seeding, or an import) still get a pill so nothing is unreachable.
        let orphans = dailyDoseItems.filter { !claimed.contains($0.category) }
        if !orphans.isEmpty {
            for (category, items) in Dictionary(grouping: orphans, by: \.category).sorted(by: { $0.key < $1.key }) {
                groups.append(DailyCategoryGroup(
                    id: category.isEmpty ? "·uncategorized" : category,
                    title: category.isEmpty ? String(localized: "Routine") : category,
                    icon: RoutineIcon.symbol(for: category),
                    items: items,
                    remaining: remaining(in: items),
                ))
            }
        }
        return groups
    }

    // MARK: Search

    func setLibraryResults(_ results: [Substance]) {
        cachedLibraryResults = results
    }

    // MARK: Favorites

    /// Toggle `name`'s membership in the cached favorite set without a full
    /// rebuild — the persistence write happens in the view; this keeps the
    /// in-memory set in sync for an instant chip update.
    func setFavorite(_ name: String, on: Bool) {
        let lowered = name.lowercased()
        if on {
            cachedFavoriteSet.insert(lowered)
        } else {
            cachedFavoriteSet.remove(lowered)
        }
    }
}
