import Foundation

/// The favorites + recents the phone pushes to the watch via
/// `WCSession.updateApplicationContext`. The **only** substance data on the wrist —
/// no SQLite, no 1,700-substance library, no timeline. Latest-wins and OS-persisted
/// (`session.receivedApplicationContext` survives the watch sleeping/relaunching), so
/// the watch always has the last manifest to render without the phone present.
///
/// Pure `Codable` — assembled on the phone from `FavoriteSubstance` + `QuickLogDose`
/// (`QuickLogManifestBuilder`), consumed on the watch as plain data. No `@Model`
/// reference, so it adds to the watch target without dragging SwiftData onto the wrist.
nonisolated struct QuickLogManifest: Codable, Hashable, Sendable {
    /// Build time — the latest-wins discriminator when two contexts race.
    var generatedAt: Date
    /// Favorites first, then recents, deduped by identity — most-recent order.
    var items: [QuickLogManifestItem]
    /// Drink presets for the alcohol by-volume flow, carried so the watch can log a
    /// drink with no pharmacology data. Empty when no alcohol favorite/recent exists.
    var drinkPresets: [ManifestDrinkPreset]

    init(generatedAt: Date, items: [QuickLogManifestItem], drinkPresets: [ManifestDrinkPreset] = []) {
        self.generatedAt = generatedAt
        self.items = items
        self.drinkPresets = drinkPresets
    }
}

/// One tile in the watch quick-log grid: a substance + route + a default measurement,
/// carrying the identity and drink detail needed to log it exactly as the phone would.
nonisolated struct QuickLogManifestItem: Codable, Hashable, Sendable, Identifiable {
    /// Stable wire identity — the `QuickLogDose.makeKey(...)` string, so favorites and
    /// recents dedupe on the same key the phone groups chips by.
    var id: String
    var substance: String
    /// Resolved display title ("Methylphenidate XR", "IPA"), else the bare substance.
    var displayName: String?
    var route: String
    /// Default amount in ``unit`` — the watch's Digital Crown nudges from here.
    var amount: Double
    var unit: String
    /// Tile color as a hex string (the substance's palette color), or nil for default.
    var colorHex: String?
    /// Whether the user has this substance favorited (vs. a plain recent).
    var isFavorite: Bool
    /// True when this item logs alcohol by volume — the watch shows the drink-preset
    /// flow (presets → Crown volume → log) instead of the generic amount stepper.
    var isByVolume: Bool

    // MARK: Drink detail (a specific recorded drink chip) — nil for mass items.
    var volumeML: Double?
    var abv: Double?
    var drinkName: String?
    var emoji: String?

    // MARK: PSID identity.
    var substanceUID: String?
    var isomer: String?
    var releaseForm: String?
    var saltForm: String?
    var productName: String?

    init(
        id: String,
        substance: String,
        displayName: String? = nil,
        route: String,
        amount: Double,
        unit: String,
        colorHex: String? = nil,
        isFavorite: Bool = false,
        isByVolume: Bool = false,
        volumeML: Double? = nil,
        abv: Double? = nil,
        drinkName: String? = nil,
        emoji: String? = nil,
        substanceUID: String? = nil,
        isomer: String? = nil,
        releaseForm: String? = nil,
        saltForm: String? = nil,
        productName: String? = nil,
    ) {
        self.id = id
        self.substance = substance
        self.displayName = displayName
        self.route = route
        self.amount = amount
        self.unit = unit
        self.colorHex = colorHex
        self.isFavorite = isFavorite
        self.isByVolume = isByVolume
        self.volumeML = volumeML
        self.abv = abv
        self.drinkName = drinkName
        self.emoji = emoji
        self.substanceUID = substanceUID
        self.isomer = isomer
        self.releaseForm = releaseForm
        self.saltForm = saltForm
        self.productName = productName
    }
}

/// A tappable drink preset on the watch — a fixed volume + default strength. The
/// phone resolves the localized name and canonical millilitres at build time so the
/// watch renders it with no `Measurement`/localization work of its own.
nonisolated struct ManifestDrinkPreset: Codable, Hashable, Sendable, Identifiable {
    /// Stable preset identity — the curated `DrinkPreset.Kind` rawValue, or the custom
    /// preset's own key.
    var id: String
    /// Display name ("Beer", "Wine", or a custom preset's name).
    var name: String
    var emoji: String
    /// Canonical volume in millilitres.
    var volumeML: Double
    /// Pre-filled ABV %, nudgeable on the watch.
    var defaultABV: Double

    init(id: String, name: String, emoji: String, volumeML: Double, defaultABV: Double) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.volumeML = volumeML
        self.defaultABV = defaultABV
    }
}

// MARK: - Watch-side payload construction

nonisolated extension QuickLogManifestItem {
    /// Build the dose payload the watch sends after the user adjusts this tile. `id` is a
    /// fresh UUID (the idempotency key); `amount`/`volumeML`/`abv`/`drinkName` override the
    /// tile defaults when the user nudged them. Pure and watch-safe — the watch never
    /// touches a `DoseEntry`.
    func makePayload(
        id: UUID,
        amount: Double,
        timestamp: Date,
        volumeML: Double? = nil,
        abv: Double? = nil,
        drinkName: String? = nil,
        emoji: String? = nil,
        notes: String? = nil,
    ) -> WatchDosePayload {
        WatchDosePayload(
            id: id,
            substance: substance,
            amount: amount,
            unit: unit,
            route: route,
            timestamp: timestamp,
            notes: notes,
            volumeML: volumeML ?? self.volumeML,
            abv: abv ?? self.abv,
            drinkName: drinkName ?? self.drinkName,
            emoji: emoji ?? self.emoji,
            substanceUID: substanceUID,
            isomer: isomer,
            releaseForm: releaseForm,
            saltForm: saltForm,
            productName: productName,
            displayName: displayName,
        )
    }
}

// MARK: - WatchConnectivity dictionary bridge

nonisolated extension QuickLogManifest {
    private static let manifestKey = "quickLogManifest"

    /// Encode for `WCSession.updateApplicationContext(_:)`. One key, one JSON blob, so the
    /// wire shape can't drift from the `Codable` synthesis.
    func applicationContext() -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return [Self.manifestKey: data]
    }

    /// Decode a manifest from `session.receivedApplicationContext` (or a delegate
    /// callback). Returns nil for any dictionary that isn't one of ours.
    init?(applicationContext: [String: Any]) {
        guard let data = applicationContext[Self.manifestKey] as? Data,
              let decoded = try? JSONDecoder().decode(QuickLogManifest.self, from: data)
        else { return nil }
        self = decoded
    }
}
