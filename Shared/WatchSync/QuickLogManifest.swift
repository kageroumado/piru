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
    /// A reset invalidates every tile and queued entry from an earlier journal.
    var journalGeneration: Int?
    /// Build time — the latest-wins discriminator when two contexts race.
    var generatedAt: Date
    /// Favorites first, then recents, deduped by identity — most-recent order.
    var items: [QuickLogManifestItem]
    /// Drink presets for the alcohol by-volume flow, carried so the watch can log a
    /// drink with no pharmacology data. Empty when no alcohol favorite/recent exists.
    var drinkPresets: [ManifestDrinkPreset]

    init(generatedAt: Date, items: [QuickLogManifestItem], drinkPresets: [ManifestDrinkPreset] = [], journalGeneration: Int? = nil) {
        self.journalGeneration = journalGeneration
        self.generatedAt = generatedAt
        self.items = items
        self.drinkPresets = drinkPresets
    }
}

/// One tile in the watch quick-log grid: a substance + route + a default measurement,
/// carrying the identity and drink detail needed to log it exactly as the phone would.
nonisolated struct QuickLogManifestItem: Codable, Hashable, Sendable, Identifiable {
    /// The journal this tile belongs to, retained when a logging form is open.
    var journalGeneration: Int?
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
    /// Digital-Crown increment, computed on the phone with the same `DoseStepping`
    /// logic the quick-log dock uses, so the watch nudges in identical steps (no
    /// off-ladder values like 124.5). Always > 0.
    var step: Double
    /// Tile color as a hex string (the substance's palette color), or nil for default.
    var tint: P3Color?
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
        step: Double = 1,
        tint: P3Color? = nil,
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
        self.step = step
        self.tint = tint
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
            journalGeneration: journalGeneration,
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

/// Persistent deletion boundary shared by the phone and Watch wire format.
nonisolated enum JournalResetGeneration {
    static let key = "journalResetGeneration"
    static let dateKey = "journalResetDate"

    static func current(in defaults: UserDefaults = .standard) -> Int {
        defaults.integer(forKey: key)
    }

    @discardableResult
    static func advance(in defaults: UserDefaults = .standard, at date: Date = Date()) -> Int {
        let next = current(in: defaults) + 1
        defaults.set(next, forKey: key)
        defaults.set(date, forKey: dateKey)
        return next
    }

    static func accepts(_ payload: WatchDosePayload, generation: Int) -> Bool {
        (payload.journalGeneration ?? 0) == generation
    }

    static func accepts(_ manifest: QuickLogManifest, after current: QuickLogManifest?, minimumGeneration: Int) -> Bool {
        let incoming = manifest.journalGeneration ?? 0
        guard incoming >= minimumGeneration else { return false }
        guard let current else { return true }
        let existing = current.journalGeneration ?? 0
        return incoming > existing || (incoming == existing && manifest.generatedAt >= current.generatedAt)
    }
}
