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

    /// Fetch favorites + recents from the store and build the manifest. `colorHex`,
    /// `displayName`, and `favoriteDefault` are injected so this stays independent of the
    /// palette/library singletons (and unit-testable). `generatedAt` is passed in rather than
    /// read from the clock so callers control the latest-wins stamp.
    static func build(
        in context: ModelContext,
        generatedAt: Date,
        itemLimit: Int = defaultItemLimit,
        colorHex: (String) -> String? = { _ in nil },
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
            colorHex: colorHex,
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
        colorHex: (String) -> String? = { _ in nil },
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
                colorHex: colorHex,
                displayName: displayName,
                step: step(recent.substance, recent.route, recent.unit, recent.amount),
            )
        }

        // A favorited substance with no recent chip still deserves a tile — resolve its
        // default dose so the watch can log it.
        for favorite in favorites where !recentIdentities.contains(favorite.identityKey) {
            guard let def = favoriteDefault(favorite) else { continue }
            let s = step(favorite.substance, def.route, def.unit, def.amount)
            items.append(item(from: favorite, default: def, colorHex: colorHex, step: s))
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
        colorHex: (String) -> String?,
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
            colorHex: colorHex(recent.substance),
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
        colorHex: (String) -> String?,
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
            colorHex: colorHex(favorite.substance),
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
