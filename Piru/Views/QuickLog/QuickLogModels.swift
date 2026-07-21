import Foundation
import SwiftData

// MARK: - Quick Log Data Types

/// A recent/favorite substance with its route groups, backing one card in the
/// quick-log list. Built from the curated `QuickLogDose` rows, not raw history.
///
/// Identified by substance **identity** (``id`` = the PSID family + form facets),
/// not name — so a Concerta card (Methylphenidate·XR) and a Ritalin IR card
/// (Methylphenidate·IR) are two cards, not one merged history. See
/// ``QuickLogDose/identityKey`` and `Specs/psid-identity-consumption.md` D.2.
struct SubstanceCard: Identifiable, Equatable {
    /// The substance-identity key — also what favorites/staged-counts join on.
    let id: String
    /// The canonical substance name (the color key and the fallback title).
    let substanceName: String
    /// The product/form title to show ("Concerta", "Methylphenidate XR"), or
    /// `nil` for a plain card — which titles from the regionalized display name.
    let title: String?
    let colorHex: String?
    let routes: [SubstanceGroup]
    let latestTimestamp: Date
    /// Identity components, carried so favoriting this card pins the same form.
    let substanceUID: String?
    let isomer: String?
    let releaseForm: String?
    let saltForm: String?
    let productName: String?
}

/// One (substance, route) pairing within a card, carrying its curated dose
/// chips sorted for display.
struct SubstanceGroup: Identifiable, Equatable {
    let id: String
    /// The card this group belongs to — its substance-identity key (== card id).
    /// Replaces splitting `id` on `"|"` to recover the card grouping.
    let cardKey: String
    let substanceName: String
    let route: RouteOfAdministration
    let colorHex: String?
    let librarySubstance: Substance?
    var latestTimestamp: Date
    /// Identity + product carried so a re-staged chip logs the same form/product.
    let substanceUID: String?
    let isomer: String?
    let releaseForm: String?
    let saltForm: String?
    let productName: String?

    /// One curated chip's backing data, including optional by-volume drink detail.
    private struct ChipEntry {
        var amount: Double
        var unit: String
        var sortOrder: Double
        var volumeML: Double?
        var abv: Double?
        var drinkName: String?
        var emoji: String?
    }

    private var chipEntries: [ChipEntry] = []

    /// Hand-written because `chipEntries` is a tuple array (no synthesized
    /// `Equatable`). Compares the display-relevant surface — identity, color,
    /// recency, the resolved library substance, and the rendered chips — which is
    /// exactly what a card's body draws, so two equal groups are visually
    /// interchangeable (and the card's `.equatable()` can skip rebuilding them).
    static func == (lhs: SubstanceGroup, rhs: SubstanceGroup) -> Bool {
        lhs.id == rhs.id
            && lhs.colorHex == rhs.colorHex
            && lhs.latestTimestamp == rhs.latestTimestamp
            && lhs.librarySubstance?.id == rhs.librarySubstance?.id
            && lhs.doses == rhs.doses
    }

    var doses: [DoseChip] {
        // Chips are the curated measurements the user actually logged. For a
        // by-volume substance (alcohol) a chip carries the recorded drink detail
        // (name / volume / % / grams) so it re-stages the exact drink; a plain
        // mass dose is just its amount. No hard-coded presets here — those live
        // in the editor's preset library, not the card.
        chipEntries
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { DoseChip(amount: $0.amount, unit: $0.unit, drinkName: $0.drinkName, emoji: $0.emoji, volumeML: $0.volumeML, abv: $0.abv) }
    }

    init(
        cardKey: String,
        substanceName: String,
        route: RouteOfAdministration,
        colorHex: String?,
        librarySubstance: Substance?,
        latestTimestamp: Date,
        substanceUID: String? = nil,
        isomer: String? = nil,
        releaseForm: String? = nil,
        saltForm: String? = nil,
        productName: String? = nil,
    ) {
        self.id = "\(cardKey)|\(route.rawValue)"
        self.cardKey = cardKey
        self.substanceName = substanceName
        self.route = route
        self.colorHex = colorHex
        self.librarySubstance = librarySubstance
        self.latestTimestamp = latestTimestamp
        self.substanceUID = substanceUID
        self.isomer = isomer
        self.releaseForm = releaseForm
        self.saltForm = saltForm
        self.productName = productName
    }

    /// The product name to re-stage this group's chips under, so a tapped Concerta
    /// chip logs Concerta — not the canonical family. Prefers the user's literal
    /// word; for a faceted group with no product string, falls back to the composed
    /// form title ("Methylphenidate XR") so the release/isomer still round-trips
    /// through the staging pipeline (which keys off the product name). `nil` for a
    /// plain group, which stages canonically as before. Computed on tap, not in
    /// `body`, so the `formTitle` resolve is off the render path.
    var stageProductName: String? {
        if let product = productName?.trimmingCharacters(in: .whitespaces), !product.isEmpty {
            return product
        }
        let namesForm = (isomer?.isEmpty == false && isomer != "0")
            || (releaseForm?.isEmpty == false && releaseForm != "0")
        guard namesForm else { return nil }
        return SubstanceLibrary.formTitle(for: substanceName, isomer: isomer, release: releaseForm)
    }

    /// Add a curated chip (sorted by `sortOrder` for display). Tracks the most
    /// recent use so cards order by recency. By-volume detail rides along for
    /// alcohol drinks; `nil` for ordinary mass doses.
    mutating func addChip(
        amount: Double,
        unit: String,
        sortOrder: Double,
        lastUsedAt: Date,
        volumeML: Double? = nil,
        abv: Double? = nil,
        drinkName: String? = nil,
        emoji: String? = nil,
    ) {
        chipEntries.append(ChipEntry(
            amount: amount, unit: unit, sortOrder: sortOrder,
            volumeML: volumeML, abv: abv, drinkName: drinkName, emoji: emoji,
        ))
        if lastUsedAt > latestTimestamp {
            latestTimestamp = lastUsedAt
        }
    }

    /// Whether any chip in this group carries by-volume detail — the card then
    /// renders the whole row as detailed drink chips (larger); otherwise plain
    /// same-size gram/mass chips like every other card.
    var usesDrinkChips: Bool {
        chipEntries.contains { $0.drinkName != nil || $0.volumeML != nil || $0.abv != nil }
    }
}

/// A single tappable dose amount within a `SubstanceGroup`. For a by-volume
/// substance (alcohol) a chip carries the recorded drink detail — emoji, name,
/// volume, and %ABV — so it renders as "🍺 IPA · 330 mL · 6% · 16 g" and
/// re-stages that exact drink; a plain mass dose is just its amount.
struct DoseChip: Identifiable, Equatable {
    let amount: Double
    let unit: String
    let drinkName: String?
    let emoji: String?
    let volumeML: Double?
    let abv: Double?

    init(
        amount: Double,
        unit: String,
        drinkName: String? = nil,
        emoji: String? = nil,
        volumeML: Double? = nil,
        abv: Double? = nil,
    ) {
        self.amount = amount
        self.unit = unit
        self.drinkName = drinkName
        self.emoji = emoji
        self.volumeML = volumeML
        self.abv = abv
    }

    var id: String {
        QuickLogDose.makeKey(
            substance: "",
            route: .oral,
            amount: amount,
            unit: unit,
            volumeML: volumeML,
            abv: abv,
            drinkName: drinkName,
        )
    }

    /// A drink chip carries measured/named detail; a plain dose is just grams.
    var hasDrinkDetail: Bool {
        drinkName != nil || volumeML != nil || abv != nil
    }

    var formattedAmount: String {
        amount.doseFormatted
    }

    /// Subtitle for a detailed drink chip: "330 mL · 6% · 16 g" (volume/strength
    /// only shown when known); falls back to just the grams.
    var detailLine: String {
        var parts: [String] = []
        if let volumeML { parts.append("\(Int(volumeML.rounded())) mL") }
        if let abv { parts.append("\(ByVolumeDosing.formatTrimmed(abv))%") }
        parts.append("\(formattedAmount) \(unit)")
        return parts.joined(separator: " · ")
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
struct CardPKBadge: Equatable {
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

    /// VoiceOver value for the badge — the visible chip's numbers spoken as a
    /// sentence, since the badge button's label is just a short noun ("Active
    /// dose"). Mirrors `DosePKBadge.label`, so the two never disagree.
    var accessibilityValue: String {
        let active = (lastDoseAmount * remainingPercent / 100).doseFormatted
        let ago = DosePK.shortElapsed(since: lastDoseTimestamp)
        if waitMinutes > 1 {
            let wait = DosePK.shortDuration(minutes: waitMinutes)
            return String(localized: "about \(active) \(lastDoseUnit) active, last dose \(ago) ago, \(wait) left")
        }
        return String(localized: "about \(active) \(lastDoseUnit) active, last dose \(ago) ago")
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
    private(set) var cachedLibraryResults: [SubstanceMatch] = []
    private(set) var cachedColorLookup: [String: String] = [:]

    /// Lowercased substance names logged today — drives the routine "done" check.
    /// Doses logged today per substance identity — a COUNT, not a set, so a
    /// multi-time med's group pills only read "done" once every slot is
    /// covered (one morning dose must not mark the evening pill done too).
    private(set) var cachedLoggedToday: [String: Int] = [:]
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
        // The PK badge is only ever read for a *displayed* card (favorites + the
        // capped recents), so resolve `DosePK.status` for those substances only —
        // not the whole 120-day history (~50 substances). Requires `rebuildCards`
        // to have run first (the `.task` orders it so).
        let displayed = Set(cachedFavoriteCards.map(\.id)).union(cachedNonFavoriteCards.map(\.id))

        var loggedToday: [String: Int] = [:]
        var mostRecentEntry: [String: DoseEntry] = [:]
        var seenLocations = Set<String>()
        var locations: [PickedLocation] = []
        var tagCounts: [String: Int] = [:]
        var stillToday = true

        for entry in allEntries {
            // Key on substance identity, not name, so a displayed card's badge and
            // a daily item's "done today" check match the same form — a Concerta
            // dose satisfies a Concerta card/item, not a plain Methylphenidate one.
            let identity = entry.identityKey
            if displayed.contains(identity), mostRecentEntry[identity] == nil { mostRecentEntry[identity] = entry }
            if stillToday, Calendar.current.isDateInToday(entry.timestamp) {
                loggedToday[identity, default: 0] += 1
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
            // no "≈X active · Yh left" badge — that is base-form timing wearing the
            // product's name, exactly what D.4 withholds everywhere else.
            guard !entry.namesUnmodeledForm else { continue }
            guard let status = DosePK.status(
                substanceName: entry.substance,
                route: entry.route,
                lastDoseTimestamp: entry.timestamp,
            ) else { continue }
            badges[identity] = CardPKBadge(
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

    /// The product/form title a card shows, or `nil` for a plain card (which
    /// titles from the regionalized display name). Mirrors ``DoseTitle``'s
    /// precedence — a relabel outranks the product, which outranks the composed
    /// form title — so a card and its doses' journal rows never disagree.
    private static func cardTitle(for group: SubstanceGroup) -> String? {
        let hasProduct = group.productName?.trimmingCharacters(in: .whitespaces).isEmpty == false
        let namesForm = (group.isomer?.isEmpty == false && group.isomer != "0")
            || (group.releaseForm?.isEmpty == false && group.releaseForm != "0")
        guard hasProduct || namesForm else { return nil }
        if let relabel = CustomSubstanceStore.shared.relabel(forCanonicalName: group.substanceName) {
            return relabel
        }
        if hasProduct { return group.productName }
        return SubstanceLibrary.formTitle(for: group.substanceName, isomer: group.isomer, release: group.releaseForm)
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
                    colorHex: colorLookup[dose.substance.lowercased()],
                    // Batch-cache lookup (class/routes/doses/salts/durations) —
                    // all a card needs — instead of the heavy per-substance SQL
                    // resolve, which cold-stalled the first open. Same path the
                    // journal uses; pre-warmed via `ensureAllLoaded()` on open.
                    librarySubstance: SubstanceLibrary.timelineLookup(dose.substance.lowercased()),
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
                colorHex: first.colorHex,
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
        // identity, since `cachedHistoryNames` holds card identity keys.
        cachedFavoriteLibrarySubstances = favorites
            .filter { !cachedHistoryNames.contains($0.identityKey) }
            .compactMap { SubstanceLibrary.timelineLookup($0.substance.lowercased()) }
    }

    /// Rebuild only the routine-pill groups (the settings sheet edited a routine
    /// row or daily item, but history is unchanged).
    func rebuildDailyGroups(dailyDoseItems: [DailyDoseItem], routines: [DoseRoutine]) {
        cachedDailyGroups = makeDailyGroups(dailyDoseItems: dailyDoseItems, routines: routines)
    }

    /// The Meds redesign's group pills: one pill per derived time-of-day
    /// group (`MedTimeGroup`), no named routines. A multi-time med shows in
    /// every group it has a time in; staging is idempotent, so tapping two
    /// groups never double-stages it. The `routines` parameter is retained
    /// for call-site stability but no longer read.
    func makeDailyGroups(dailyDoseItems: [DailyDoseItem], routines _: [DoseRoutine]) -> [DailyCategoryGroup] {
        guard !dailyDoseItems.isEmpty else { return [] }
        let loggedToday = cachedLoggedToday

        func remaining(in items: [DailyDoseItem]) -> [DailyDoseItem] {
            // Join on substance identity — a "Concerta" med is satisfied by
            // a dose logged as Methylphenidate XR, which a name join never
            // matched. A multi-time med needs one dose per slot before it
            // stops counting as remaining, so its morning log doesn't mark
            // its evening group's pill done.
            items.filter { (loggedToday[$0.identityKey] ?? 0) < max(1, $0.reminderTimesMinutes.count) }
        }

        return MedTimeGroup.allCases.compactMap { group in
            let items = dailyDoseItems.filter { MedTimeGroup.belongs($0, to: group) }
            guard !items.isEmpty else { return nil }
            return DailyCategoryGroup(
                id: group.slug,
                title: String(localized: group.label),
                icon: group.symbol,
                items: items,
                remaining: remaining(in: items),
            )
        }
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
