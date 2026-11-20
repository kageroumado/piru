import Foundation
import SwiftData

// MARK: - Quick Log Content Model

/// Holds every derived dataset the quick-log screen renders, on a reference
/// type: stored inline on the `QuickLogView` struct, the caches (several of
/// them arrays of the wide `Substance` value type) would be deep-copied on
/// every `body` pass, which dominates a first-render trace. Here the view's
/// stored surface is a handful of references; `body` reads through the model.
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
    private(set) var cachedLibraryResults: [SubstanceMatch] = []
    private(set) var cachedColorLookup: [String: P3Color] = [:]

    /// Today's logged doses — the "done today" and "due now" source for the
    /// daily groups. Kept as entries (not a pre-aggregated identity dict)
    /// so the done-check runs through ``AdherenceCalculator/entryMatches(entry:item:)``
    /// → ``MedSchedule/identityMatches(keyA:nameA:keyB:nameB:)``, the same join
    /// the My Meds checklist's occurrence records run — a dose's PSID can
    /// resolve differently than its schedule item, so only matching through
    /// entries, never a strict identity key, keeps the two screens agreeing.
    /// Read only at group-build time, through ``liveTodayEntries``, since a
    /// dose can be deleted after this was captured.
    private(set) var cachedTodayEntries: [DoseEntry] = []

    /// ``cachedTodayEntries`` minus any row deleted since it was captured —
    /// reading a deleted model's properties traps in SwiftData.
    private var liveTodayEntries: [DoseEntry] {
        cachedTodayEntries.filter { !$0.isDeleted }
    }

    /// The last week of logged doses, newest first — what the tray's
    /// interaction check reads (``TrayInteractionCheck``), so a backdated dose
    /// can meet what was running then. Not observed: the banner reads it from
    /// its recheck, and re-runs on ``recentEntriesGeneration``.
    @ObservationIgnored private(set) var recentEntries: [DoseEntry] = []
    /// Bumped on every ``recentEntries`` rebuild — the one observed value the
    /// tray's banner keys its recheck on.
    private(set) var recentEntriesGeneration = 0

    /// How far back ``recentEntries`` reaches.
    static let recentEntriesSpan: TimeInterval = 7 * 86_400

    /// Doses logged today that satisfy `item`, by the shared adherence matcher.
    func takenToday(_ item: DailyDoseItem) -> Int {
        liveTodayEntries.count { AdherenceCalculator.entryMatches(entry: $0, item: item) }
    }
    /// Precomputed PK badge per lowercased substance name — feeds each card's
    /// glanceable badge without re-running `DosePK.status` in `body`.
    private(set) var cachedMostRecent: [String: CardPKBadge] = [:]
    /// Distinct dose locations, most recent first — the tray's location panel.
    private(set) var cachedRecentLocations: [PickedLocation] = []
    /// Tag suggestions (used-most-first + common extras) — the tray's tag panel.
    private(set) var cachedTagSuggestions: [String] = []

    /// Max recent (non-favorite) cards rendered. ~50 distinct substances can
    /// accumulate in the curated list, but the quick-log surface is for the
    /// handful you reach for repeatedly — anything older is one search away.
    /// Capping the rendered set is the lever on `QuickLogView.body` cost (each
    /// card is a `SubstanceCardView` with chip rows + context menus); favorites
    /// are exempt because they're explicitly pinned.
    static let recentCardLimit = 10

    private(set) var cachedFavoriteCards: [SubstanceCard] = []
    private(set) var cachedNonFavoriteCards: [SubstanceCard] = []
    private(set) var cachedFavoriteLibrarySubstances: [Substance] = []

    private(set) var cachedDailyGroups: [DailyCategoryGroup] = []

    /// Gates the empty-state placeholder: it must not show until the first
    /// rebuild has actually run, or the sheet briefly flashes "No Previous
    /// Substances" on every open before the caches fill.
    private(set) var hasLoaded = false

    func markLoaded() {
        hasLoaded = true
    }

    // MARK: Dock browse

    /// The effect-family pills the dock shows in its suggestions state.
    private(set) var browseFamilies: [LibraryFamily] = []
    /// The family whose substances the dock is listing, or `nil` for the bare
    /// pill row.
    var selectedFamilyID: String?
    /// Top-by-popularity substances of the selected family.
    var browseResults: [Substance] = []

    /// Resolve the browsable taxonomy. `LibraryFamily.browsable` reads
    /// `SubstanceStore.all`, so the store's prewarm has to finish first — the
    /// dock can appear before it does on a cold launch. Resolved once: the
    /// taxonomy is static over a session.
    func loadBrowseFamilies() async {
        guard browseFamilies.isEmpty else { return }
        await SubstanceStore.shared.ensureAllLoaded()
        browseFamilies = LibraryFamily.browsable
    }

    /// Drop the family selection, returning the dock's browse face to its pills.
    func clearBrowseSelection() {
        selectedFamilyID = nil
        browseResults = []
    }

    // MARK: Rebuilds

    func rebuildColorLookup(substanceColors: [SubstanceColor]) {
        cachedColorLookup = Array(substanceColors).tintMap
    }

    /// Recompute everything derived from `allEntries` in a single pass. Called
    /// on open and whenever the history changes (a logged dose) — never from
    /// `body`. `allEntries` is newest-first, which every consumer relies on
    /// (today's slice stops at the first non-today row; most-recent wins).
    func rebuildEntryDerived(allEntries: [DoseEntry], dailyDoseItems: [DailyDoseItem]) {
        // The PK badge is only ever read for a *displayed* card (favorites + the
        // capped recents), so resolve `DosePK.status` for those substances only,
        // never the whole recent history. Requires `rebuildCards`
        // to have run first (the `.task` orders it so).
        let displayed = Set(cachedFavoriteCards.map(\.id)).union(cachedNonFavoriteCards.map(\.id))

        var todayEntries: [DoseEntry] = []
        var mostRecentEntry: [String: DoseEntry] = [:]
        var seenLocations = Set<String>()
        var locations: [PickedLocation] = []
        var tagCounts: [String: Int] = [:]
        var stillToday = true
        var recent: [DoseEntry] = []
        let recentCutoff = Date.now.addingTimeInterval(-Self.recentEntriesSpan)
        // Today is the journal day, and a dose is today's when its own journal
        // day is, on the clock of the zone it was logged in. Every such dose
        // lies inside the day's fetch window, so the newest-first walk stops
        // once it passes the window's start.
        let calendar = Calendar.current
        let boundaryHour = Calendar.sessionDayBoundaryHour
        let today = calendar.journalDay(for: .now, boundaryHour: boundaryHour)
        let todayWindowStart = calendar.doseFetchWindow(forJournalDay: today, boundaryHour: boundaryHour).start

        for entry in allEntries {
            if entry.timestamp >= recentCutoff { recent.append(entry) }
            // Key on substance identity, not name, so a displayed card's badge and
            // a daily item's "done today" check match the same form — a Concerta
            // dose satisfies a Concerta card/item, not a plain Methylphenidate one.
            let identity = entry.identityKey
            if displayed.contains(identity), mostRecentEntry[identity] == nil { mostRecentEntry[identity] = entry }
            if stillToday, entry.timestamp >= todayWindowStart {
                if entry.journalDay(in: calendar, boundaryHour: boundaryHour) == today {
                    todayEntries.append(entry)
                }
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
        for (identity, entry) in mostRecentEntry {
            // A form whose kinetics we decline to model (Concerta, a depot) draws
            // no "est. X active" badge — that is base-form timing wearing the
            // product's name, exactly what every other surface withholds.
            guard !entry.namesUnmodeledForm else { continue }
            guard let remainingPercent = DosePK.status(
                substanceName: entry.substance,
                route: entry.route,
                lastDoseTimestamp: entry.timestamp,
            ) else { continue }
            badges[identity] = CardPKBadge(
                remainingPercent: remainingPercent,
                lastDoseAmount: entry.amount,
                lastDoseUnit: entry.unit,
                lastDoseTimestamp: entry.timestamp,
                lastDoseRoute: entry.route,
            )
        }

        cachedTodayEntries = todayEntries
        recentEntries = recent
        recentEntriesGeneration += 1
        cachedMostRecent = badges
        cachedRecentLocations = locations
        cachedTagSuggestions = Array((used + extras).prefix(8))
        // `makeDailyGroups` reads `cachedTodayEntries` (the "done" and "due"
        // checks), so it must rebuild after that's assigned above.
        cachedDailyGroups = makeDailyGroups(dailyDoseItems: dailyDoseItems)
    }

    /// The title a card shows when it names more than the plain substance —
    /// a relabel, the product the user logged ("Concerta"), a composed form
    /// ("Methylphenidate XR"), or an injectable ester folded into the name
    /// ("Estradiol Enanthate") so no chip has to say it — or `nil` for a plain
    /// card, which titles from the regionalized display name. Resolves through
    /// ``DoseTitle`` so a card and its doses' journal rows never disagree.
    private static func cardTitle(for group: SubstanceGroup) -> String? {
        let hasProduct = group.productName?.trimmingCharacters(in: .whitespaces).isEmpty == false
        let namesForm = (group.isomer?.isEmpty == false && group.isomer != "0")
            || (group.releaseForm?.isEmpty == false && group.releaseForm != "0")
        let uid = group.substanceUID ?? group.librarySubstance?.substanceUID
        let namesEster = SubstanceStore.shared.isEster(group.saltForm, forParentUID: uid)
        guard hasProduct || namesForm || namesEster else { return nil }
        return DoseTitle.resolve(
            substance: group.substanceName, productName: group.productName,
            namesForm: namesForm, isomer: group.isomer, releaseForm: group.releaseForm,
            saltForm: group.saltForm, esterParentUID: uid,
        )
    }

    func rebuildCards(quickLogDoses: [QuickLogDose], favorites: [FavoriteSubstance]) {
        let colorLookup = cachedColorLookup

        var groupMap: [String: SubstanceGroup] = [:]

        // Cards are built from the curated quick-log list (seeded once from
        // history, then maintained on log), not raw history — so a removed chip
        // stays gone and the order is the user's, not just recency. Grouped by
        // substance *identity* (family + form facets), so Concerta and Ritalin IR
        // split into two cards even though both are canonical Methylphenidate.
        for dose in quickLogDoses {
            let cardKey = dose.identityKey
            let key = "\(cardKey)|\(dose.route.rawValue)"
            if var group = groupMap[key] {
                group.addChip(
                    amount: dose.amount,
                    unit: dose.unit,
                    sortOrder: dose.sortOrder,
                    lastUsedAt: dose.lastUsedAt,
                    volumeML: dose.volumeML,
                    abv: dose.abv,
                    drinkName: dose.drinkName,
                    emoji: dose.emoji,
                )
                groupMap[key] = group
            } else {
                var group = SubstanceGroup(
                    cardKey: cardKey,
                    substanceName: dose.substance,
                    route: dose.route,
                    // Color keys on the canonical name so every form of a substance
                    // shares its color — a Concerta chip takes Methylphenidate's.
                    tint: SubstancePalette.tint(for: dose.substance, tintMap: colorLookup),
                    // Batch-cache lookup (class/routes/doses/salts/durations) —
                    // all a card needs — instead of the heavy per-substance SQL
                    // resolve, which cold-stalled the first open. Same path the
                    // journal uses; pre-warmed via `ensureAllLoaded()` on open.
                    librarySubstance: SubstanceLibrary.lookup(dose.substance.lowercased()),
                    latestTimestamp: dose.lastUsedAt,
                    substanceUID: dose.substanceUID,
                    isomer: dose.isomer,
                    releaseForm: dose.releaseForm,
                    saltForm: dose.saltForm,
                    productName: dose.productName,
                )
                group.addChip(
                    amount: dose.amount,
                    unit: dose.unit,
                    sortOrder: dose.sortOrder,
                    lastUsedAt: dose.lastUsedAt,
                    volumeML: dose.volumeML,
                    abv: dose.abv,
                    drinkName: dose.drinkName,
                    emoji: dose.emoji,
                )
                groupMap[key] = group
            }
        }

        var cardMap: [String: [SubstanceGroup]] = [:]
        for group in groupMap.values {
            cardMap[group.cardKey, default: []].append(group)
        }

        let newCards: [SubstanceCard] = cardMap.map { cardKey, routes in
            let sorted = routes.sorted { $0.latestTimestamp > $1.latestTimestamp }
            let first = sorted[0]
            return SubstanceCard(
                id: cardKey,
                substanceName: first.substanceName,
                title: Self.cardTitle(for: first),
                tint: first.tint,
                routes: sorted,
                latestTimestamp: first.latestTimestamp,
                substanceUID: first.substanceUID,
                isomer: first.isomer,
                releaseForm: first.releaseForm,
                saltForm: first.saltForm,
                productName: first.productName,
            )
        }.sorted { $0.latestTimestamp > $1.latestTimestamp }

        cachedCards = newCards
        cachedHistoryNames = Set(newCards.map(\.id))
        rebuildFavorites(favorites: favorites)
    }

    func rebuildFavorites(favorites: [FavoriteSubstance]) {
        // Membership keys on substance identity (== a card's `id`), so a Concerta
        // favorite highlights the Concerta card, not a plain Methylphenidate one.
        cachedFavoriteSet = Set(favorites.map(\.identityKey))
        // `uniquingKeysWith` guards against two rows resolving to one identity
        // (e.g. a pre-PSID and a resolved row for the same drug).
        cachedFavoriteOrder = Dictionary(
            favorites.enumerated().map { ($0.element.identityKey, $0.offset) },
            uniquingKeysWith: { first, _ in first },
        )

        // Favorites hold their user-given positions (the reorder sheet) instead
        // of jumping around with logging recency like the Recent section.
        cachedFavoriteCards = cachedCards
            .filter { cachedFavoriteSet.contains($0.id) }
            .sorted { (cachedFavoriteOrder[$0.id] ?? .max) < (cachedFavoriteOrder[$1.id] ?? .max) }
        cachedNonFavoriteCards = Array(
            cachedCards
                .filter { !cachedFavoriteSet.contains($0.id) }
                .prefix(Self.recentCardLimit),
        )
        // Favorites with no recents card of their own (never logged) — matched by
        // identity, since `cachedHistoryNames` holds card identity keys. Two
        // starred forms of one drug look up the same substance, which the list
        // shows once.
        cachedFavoriteLibrarySubstances = favorites
            .filter { !cachedHistoryNames.contains($0.identityKey) }
            .compactMap { SubstanceLibrary.lookup($0.substance.lowercased()) }
            .uniqued(by: \.id)
    }

    /// Rebuild only the routine-pill groups (the settings sheet edited a routine
    /// row or daily item, but history is unchanged).
    func rebuildDailyGroups(dailyDoseItems: [DailyDoseItem]) {
        cachedDailyGroups = makeDailyGroups(dailyDoseItems: dailyDoseItems)
    }

    /// The group pills: one pill per derived time-of-day
    /// group (`MedTimeGroup`), no named routines. A multi-time med shows in
    /// every group it has a time in; staging is idempotent, so tapping two
    /// groups never double-stages it. As-needed meds are NOT one all-or-
    /// nothing group — different PRN meds serve different moments, so each
    /// gets its own single-med pill (a pre-workout stack is still one tap
    /// per med, never "stage every PRN med I own"). Each group carries the
    /// ``DueNowSlot``s that opened inside it, so the pill can answer "what
    /// should I take now?" itself.
    ///
    /// Every model is read here, once, and copied into ``DailyMedSnapshot``s;
    /// rows deleted since the caller's `@Query` result or since
    /// ``cachedTodayEntries`` was captured are dropped before any read.
    func makeDailyGroups(dailyDoseItems allItems: [DailyDoseItem], now: Date = .now) -> [DailyCategoryGroup] {
        let dailyDoseItems = allItems.filter { !$0.isDeleted }
        guard !dailyDoseItems.isEmpty else { return [] }

        let dueSlots = DueNowSlot.derive(items: dailyDoseItems, todayEntries: liveTodayEntries, now: now)
        func due(in group: MedTimeGroup) -> [DueNowSlot] {
            dueSlots.filter { slot in
                slot.slotMinutes.map { MedTimeGroup.group(forMinutes: $0) == group } ?? (group == .anytime)
            }
        }

        func remaining(in items: [DailyDoseItem]) -> [DailyMedSnapshot] {
            // Join via the shared adherence matcher (identity OR name, same
            // route) — a "Concerta" med is satisfied by a dose logged as
            // Methylphenidate XR, and the count agrees with My Meds even when
            // PSID resolves the two sides differently. A multi-time med needs
            // one dose per slot before it stops counting as remaining, so its
            // morning log doesn't mark its evening group's pill done.
            items
                .filter { takenToday($0) < max(1, $0.reminderTimesMinutes.count) }
                .map(DailyMedSnapshot.init)
        }

        var groups: [DailyCategoryGroup] = MedTimeGroup.allCases.compactMap { group in
            guard group != .asNeeded else { return nil }
            let items = dailyDoseItems.filter { MedTimeGroup.belongs($0, to: group) }
            guard !items.isEmpty else { return nil }
            let snapshots = items.map(DailyMedSnapshot.init)
            // A slot holding one med is titled by the med: "✓ Anytime" reads
            // as a substance called Anytime being checked, "✓ Memantine" reads
            // as the med being taken. The slot's icon still says when.
            let title = snapshots.count == 1 ? snapshots[0].displayName : String(localized: group.label)
            return DailyCategoryGroup(
                id: group.slug,
                title: title,
                icon: group.symbol,
                items: snapshots,
                remaining: remaining(in: items),
                due: due(in: group),
            )
        }

        // PRN meds: one pill each. "Done" only when a declared daily cap is
        // reached — an uncapped as-needed med is never "done" (no expectation).
        for item in dailyDoseItems where item.isAsNeeded {
            let capped = item.maxPerDay.map { takenToday(item) >= $0 } ?? false
            let snapshot = DailyMedSnapshot(item)
            groups.append(DailyCategoryGroup(
                id: "prn-\(item.identityKey)-\(item.sortOrder)",
                title: snapshot.displayName,
                icon: "cross.vial",
                items: [snapshot],
                remaining: capped ? [] : [snapshot],
                due: [],
            ))
        }
        return groups
    }

    // MARK: Search

    func setLibraryResults(_ results: [SubstanceMatch]) {
        cachedLibraryResults = results
    }

    // MARK: Favorites

    /// Toggle a card's membership in the cached favorite set without a full
    /// rebuild — the persistence write happens in the view; this keeps the
    /// in-memory set in sync for an instant star update. Keyed by the card's
    /// substance-identity (its `id`), not a name.
    func setFavorite(identity: String, on: Bool) {
        if on {
            cachedFavoriteSet.insert(identity)
        } else {
            cachedFavoriteSet.remove(identity)
        }
    }
}
