import Foundation
import SwiftData

/// Assembles the `QuickLogManifest` the phone pushes to the watch, from the same
/// `FavoriteSubstance` + `QuickLogDose` rows that drive the phone quick-log. This is the
/// phone→watch half of the sync contract; it lives on the phone (not `Shared/`) because it
/// reads `@Model`s the watch deliberately never sees.
///
/// Each recent chip becomes one tile (preserving distinct measurements and distinct drinks,
/// like the phone). A favorited substance with no history becomes one tile from its default
/// dose. Favorites sort first; the list is capped for `updateApplicationContext`'s size limit.
@MainActor
enum QuickLogManifestBuilder {
    /// A favorite substance's default measurement, resolved by the caller (from
    /// `SubstanceLibrary`'s common dose) so a favorite that's never been logged still gets a
    /// loggable tile. Nil default → the favorite is skipped (nothing sensible to pre-fill).
    struct FavoriteDefault {
        var amount: Double
        var unit: String
        var route: RouteOfAdministration
        var displayName: String?
    }

    /// Default cap on manifest items — all favorites plus the most recent chips. Small so the
    /// application-context payload stays well under WatchConnectivity's limit.
    static let defaultItemLimit = 20

    /// Fetch favorites + recents from the store and build the manifest. `tint`,
    /// `displayName`, and `favoriteDefault` are injected so this stays independent of the
    /// palette/library singletons (and unit-testable). `generatedAt` is passed in rather than
    /// read from the clock so callers control the latest-wins stamp.
    static func build(
        in context: ModelContext,
        generatedAt: Date,
        itemLimit: Int = defaultItemLimit,
        tint: (String) -> P3Color? = { _ in nil },
        displayName: (QuickLogDose) -> String? = { $0.substance },
        favoriteDefault: (FavoriteSubstance) -> FavoriteDefault? = { _ in nil },
        step: @MainActor (String, RouteOfAdministration, String, Double) -> Double = Self.fallbackStep,
    ) -> QuickLogManifest {
        let recents = (try? context.fetch(recentsDescriptor())) ?? []
        let favorites = (try? context.fetch(FetchDescriptor<FavoriteSubstance>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)],
        ))) ?? []
        return build(
            recents: recents,
            favorites: favorites,
            generatedAt: generatedAt,
            itemLimit: itemLimit,
            tint: tint,
            displayName: displayName,
            favoriteDefault: favoriteDefault,
            step: step,
        )
    }

    /// Crown step when the caller doesn't resolve a library reference dose — the
    /// same magnitude fallback the dock uses for unknown substances.
    static func fallbackStep(_: String, _: RouteOfAdministration, _: String, _ amount: Double) -> Double {
        DoseStepping.step(referenceDose: nil, amount: amount)
    }

    /// Pure assembly over already-fetched rows — the unit-testable core.
    static func build(
        recents: [QuickLogDose],
        favorites: [FavoriteSubstance],
        generatedAt: Date,
        itemLimit: Int = defaultItemLimit,
        tint: (String) -> P3Color? = { _ in nil },
        displayName: (QuickLogDose) -> String? = { $0.substance },
        favoriteDefault: (FavoriteSubstance) -> FavoriteDefault? = { _ in nil },
        step: @MainActor (String, RouteOfAdministration, String, Double) -> Double = Self.fallbackStep,
    ) -> QuickLogManifest {
        let favoriteIdentities = Set(favorites.map(\.identityKey))
        let recentIdentities = Set(recents.map(\.identityKey))

        var items = recents.prefix(itemLimit).map { recent in
            item(
                from: recent,
                isFavorite: favoriteIdentities.contains(recent.identityKey),
                tint: tint,
                displayName: displayName,
                step: step(recent.substance, recent.route, recent.unit, recent.amount),
            )
        }

        // A favorited substance with no recent chip still deserves a tile — resolve its
        // default dose so the watch can log it.
        for favorite in favorites where !recentIdentities.contains(favorite.identityKey) {
            guard let def = favoriteDefault(favorite) else { continue }
            let s = step(favorite.substance, def.route, def.unit, def.amount)
            items.append(item(from: favorite, default: def, tint: tint, step: s))
        }

        // Favorites first, otherwise preserve the recents order (stable).
        let ordered = items.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.isFavorite != rhs.element.isFavorite { return lhs.element.isFavorite }
                return lhs.offset < rhs.offset
            }
            .map(\.element)

        let presets = ordered.first { $0.isByVolume }
            .flatMap { ByVolumeCatalog.capability(forAnyOf: [$0.substance]) }
            .map(ManifestDrinkPreset.wireForm(of:)) ?? []
        return QuickLogManifest(generatedAt: generatedAt, items: ordered, drinkPresets: presets)
    }

    // MARK: - Item mapping

    private static func item(
        from recent: QuickLogDose,
        isFavorite: Bool,
        tint: (String) -> P3Color?,
        displayName: (QuickLogDose) -> String?,
        step: Double,
    ) -> QuickLogManifestItem {
        QuickLogManifestItem(
            id: recent.key,
            substance: recent.substance,
            displayName: displayName(recent),
            route: recent.route.rawValue,
            amount: recent.amount,
            unit: recent.unit,
            step: step,
            tint: tint(recent.substance),
            isFavorite: isFavorite,
            isByVolume: recent.hasDrinkDetail || isByVolume(recent.substance),
            volumeML: recent.volumeML,
            abv: recent.abv,
            drinkName: recent.drinkName,
            emoji: recent.emoji,
            substanceUID: recent.substanceUID,
            isomer: recent.isomer,
            releaseForm: recent.releaseForm,
            saltForm: recent.saltForm,
            productName: recent.productName,
        )
    }

    private static func item(
        from favorite: FavoriteSubstance,
        default def: FavoriteDefault,
        tint: (String) -> P3Color?,
        step: Double,
    ) -> QuickLogManifestItem {
        let id = QuickLogDose.makeKey(
            substance: favorite.substance,
            route: def.route,
            amount: def.amount,
            unit: def.unit,
            substanceUID: favorite.substanceUID,
            isomer: favorite.isomer,
            releaseForm: favorite.releaseForm,
            saltForm: favorite.saltForm,
        )
        return QuickLogManifestItem(
            id: id,
            substance: favorite.substance,
            displayName: def.displayName ?? favorite.substance,
            route: def.route.rawValue,
            amount: def.amount,
            unit: def.unit,
            step: step,
            tint: tint(favorite.substance),
            isFavorite: true,
            isByVolume: isByVolume(favorite.substance),
            substanceUID: favorite.substanceUID,
            isomer: favorite.isomer,
            releaseForm: favorite.releaseForm,
            saltForm: favorite.saltForm,
        )
    }

    /// Whether a substance logs by volume (alcohol today) — drives the watch drink flow.
    private static func isByVolume(_ substance: String) -> Bool {
        ByVolumeCatalog.capability(forAnyOf: [substance]) != nil
    }

    private static func recentsDescriptor() -> FetchDescriptor<QuickLogDose> {
        FetchDescriptor<QuickLogDose>(sortBy: [
            SortDescriptor(\.sortOrder),
            SortDescriptor(\.lastUsedAt, order: .reverse),
        ])
    }
}

// MARK: - My Meds

extension QuickLogManifestBuilder {
    /// Today's and tomorrow's My Meds checklists, slot for slot as the phone card derives
    /// them (``MyMedsModel/slots(items:occurrences:boundaryHour:now:)``). Today's states
    /// come from its occurrence rows, reconciled first: `logBatch` reconciles only after
    /// the change signal that triggers this push. Nothing has happened tomorrow yet, so
    /// its slots are all open.
    static func medDays(
        in context: ModelContext,
        now: Date,
        boundaryHour: Int = Calendar.sessionDayBoundaryHour,
        displayName: (DailyMedSnapshot) -> String = { $0.productName ?? $0.substance },
    ) -> [ManifestMedDay] {
        RoutineOccurrenceService.reconcile(in: context, now: now)
        let items = (try? context.fetch(FetchDescriptor<DailyDoseItem>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        let today = Calendar.current.journalDay(for: now, boundaryHour: boundaryHour)
        let occurrences = (try? context.fetch(FetchDescriptor<RoutineOccurrence>(
            predicate: #Predicate { $0.dueDay == today },
        ))) ?? []
        return medDays(items: items, todayOccurrences: occurrences, now: now, boundaryHour: boundaryHour, displayName: displayName)
    }

    /// Pure assembly over already-fetched rows — the unit-testable core.
    static func medDays(
        items: [DailyDoseItem],
        todayOccurrences: [RoutineOccurrence],
        now: Date,
        boundaryHour: Int = Calendar.sessionDayBoundaryHour,
        displayName: (DailyMedSnapshot) -> String = { $0.productName ?? $0.substance },
    ) -> [ManifestMedDay] {
        let calendar = Calendar.current
        let today = calendar.journalDay(for: now, boundaryHour: boundaryHour)
        let tomorrow = calendar.journalDay(after: today)
        let todayStart = calendar.journalDayStart(of: today, boundaryHour: boundaryHour)
        let tomorrowStart = calendar.journalDayStart(of: tomorrow, boundaryHour: boundaryHour)
        let dayAfterStart = calendar.journalDayStart(of: calendar.journalDay(after: tomorrow), boundaryHour: boundaryHour)
        let itemsByID = Dictionary(items.map { ($0.persistentModelID, $0) }, uniquingKeysWith: { first, _ in first })

        func day(start: Date, end: Date, occurrences: [RoutineOccurrence]) -> ManifestMedDay {
            // Two meds alike in everything share an id, and one row: a dose of either is
            // the same dose, ticking the one occurrence they share.
            var ids: Set<String> = []
            let slots = MyMedsModel.slots(items: items, occurrences: occurrences, boundaryHour: boundaryHour, now: start)
                .compactMap { slot in itemsByID[slot.itemID].map { medSlot(slot, of: $0, displayName: displayName(slot.med)) } }
                .filter { ids.insert($0.id).inserted }
            return ManifestMedDay(start: start, end: end, slots: slots)
        }
        return [
            day(start: todayStart, end: tomorrowStart, occurrences: todayOccurrences),
            day(start: tomorrowStart, end: dayAfterStart, occurrences: []),
        ]
    }

    private static func medSlot(_ slot: MyMedsCard.MedSlot, of item: DailyDoseItem, displayName: String) -> ManifestMedSlot {
        ManifestMedSlot(
            id: ManifestMedSlot.id(of: item, slotMinutes: slot.time),
            substance: item.substance,
            displayName: displayName,
            route: item.route.rawValue,
            amount: item.amount,
            unit: item.unit,
            slotMinutes: slot.time,
            isQuiet: item.isQuiet,
            taken: slot.state == .taken,
            skipped: slot.state == .skipped,
            substanceUID: item.substanceUID,
            isomer: item.isomer,
            releaseForm: item.releaseForm,
            saltForm: item.saltForm,
            productName: item.productName,
        )
    }
}

// MARK: - Med slots → wire id

extension ManifestMedSlot {
    /// The id of `item`'s slot at `slotMinutes`: what the med is (identity, route, dose
    /// and product word) and the reminder time. Nothing in it moves when another med is
    /// added, deleted or reordered, so a tick from a wrist holding an older manifest
    /// still names its med; and two strengths of one med at one time, which share a slot
    /// key (`RoutineOccurrenceService.slotKey`), each keep their own.
    static func id(of item: DailyDoseItem, slotMinutes: Int?) -> String {
        id(item.identityKey, item.route, item.amount, item.unit, item.productName, slotMinutes)
    }

    /// The id of the slot at `slotMinutes` whose med `dose` is a dose of, as
    /// ``DoseEntry/init(medication:timestamp:slotMinutes:displayNameSnapshot:)`` builds one.
    static func id(of dose: DoseEntry, slotMinutes: Int?) -> String {
        id(dose.identityKey, dose.route, dose.amount, dose.unit, dose.productName, slotMinutes)
    }

    private static func id(
        _ identityKey: String, _ route: RouteOfAdministration, _ amount: Double, _ unit: String,
        _ productName: String?, _ slotMinutes: Int?,
    ) -> String {
        "\(identityKey)|\(route.rawValue)|\(amount)|\(unit)|\(productName ?? "")|\(slotMinutes.map(String.init) ?? "any")"
    }
}

// MARK: - Drink presets → wire form

extension ManifestDrinkPreset {
    /// A by-volume capability's drink presets (Beer/Wine/Shot/Pint), with names and canonical
    /// millilitres resolved on the phone so the watch renders them with no `Measurement` or
    /// localization work. The name localizes to the phone's locale at build time.
    static func wireForm(of capability: ByVolumeDosing) -> [ManifestDrinkPreset] {
        capability.drinkPresets.map { preset in
            ManifestDrinkPreset(
                id: preset.kind.rawValue,
                name: String(localized: preset.name),
                emoji: preset.kind.emoji,
                volumeML: preset.volume.converted(to: .milliliters).value,
                defaultABV: preset.defaultABV,
            )
        }
    }
}
