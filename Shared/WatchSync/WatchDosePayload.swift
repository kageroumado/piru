import Foundation

/// One dose logged on the watch, sent to the phone over `WCSession.transferUserInfo`.
///
/// A pure `Codable` value — the wire contract, and the *only* dose representation that
/// crosses the device boundary. The watch never opens the SwiftData store or builds a
/// `DoseEntry`; it fills one of these and hands it to the OS transfer queue, which
/// guarantees delivery even while the phone is unreachable. The phone reconstructs a
/// `DoseEntry` from it (`WatchDoseReceiver`) and inserts it through the canonical
/// `DoseLogService.log` path, so a watch dose behaves identically to a phone one.
///
/// Kept watch-safe: no reference to any `@Model`, so the file adds to the watch
/// target's membership without dragging SwiftData onto the wrist.
nonisolated struct WatchDosePayload: Codable, Hashable, Sendable, Identifiable {
    /// Idempotency key — becomes the reconstructed `DoseEntry.id`. The phone skips a
    /// payload whose id already exists, so a re-delivered transfer never double-logs.
    var id: UUID

    /// Canonical substance name, as it will be logged.
    var substance: String
    /// Canonical amount in ``unit`` — grams of ethanol for an alcohol-by-volume drink,
    /// already converted on the watch via the shared `ByVolumeDosing.grams(...)`.
    var amount: Double
    /// Unit of measure for ``amount`` (`"g"` for a drink, `"mg"`, `"µg"`, …).
    var unit: String
    /// Route of administration as its `RouteOfAdministration.rawValue`.
    var route: String
    /// When the dose was taken (defaults to send time on the watch).
    var timestamp: Date
    /// The user's own note, if any — never the by-volume breadcrumb (that is carried
    /// as first-class fields below, matching the phone quick-log commit).
    var notes: String?

    // MARK: By-volume detail (alcohol) — nil for ordinary mass doses.

    /// Measured volume in millilitres, paired with ``abv``.
    var volumeML: Double?
    /// Strength as percent alcohol-by-volume.
    var abv: Double?
    /// Optional drink name shown in place of the bare substance ("IPA").
    var drinkName: String?
    /// Emoji for the logged drink, carried through to the recents chip.
    var emoji: String?

    // MARK: PSID identity — carried from the manifest item so the phone logs the

    // right product/family, not a fuzzy name match. All nil for a facet-less log.

    var substanceUID: String?
    var isomer: String?
    var releaseForm: String?
    var saltForm: String?
    var productName: String?
    /// Resolved display title captured on the phone at manifest-build time.
    var displayName: String?

    init(
        id: UUID,
        substance: String,
        amount: Double,
        unit: String,
        route: String,
        timestamp: Date,
        notes: String? = nil,
        volumeML: Double? = nil,
        abv: Double? = nil,
        drinkName: String? = nil,
        emoji: String? = nil,
        substanceUID: String? = nil,
        isomer: String? = nil,
        releaseForm: String? = nil,
        saltForm: String? = nil,
        productName: String? = nil,
        displayName: String? = nil,
    ) {
        self.id = id
        self.substance = substance
        self.amount = amount
        self.unit = unit
        self.route = route
        self.timestamp = timestamp
        self.notes = notes
        self.volumeML = volumeML
        self.abv = abv
        self.drinkName = drinkName
        self.emoji = emoji
        self.substanceUID = substanceUID
        self.isomer = isomer
        self.releaseForm = releaseForm
        self.saltForm = saltForm
        self.productName = productName
        self.displayName = displayName
    }

    /// Whether this payload carries a measured drink rather than a bare mass.
    var hasDrinkDetail: Bool {
        drinkName != nil || volumeML != nil || abv != nil
    }
}

// MARK: - WatchConnectivity dictionary bridge

nonisolated extension WatchDosePayload {
    /// `transferUserInfo` takes a `[String: Any]` plist dictionary, not `Data`. Rather
    /// than hand-map every field, round-trip through JSON once — one key, one blob — so
    /// the wire shape is exactly the `Codable` synthesis and can't drift from it.
    private static let payloadKey = "watchDosePayload"

    /// Encode for `WCSession.transferUserInfo(_:)`. Returns nil only if encoding fails
    /// (never expected for this fixed value type).
    func userInfo() -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return [Self.payloadKey: data]
    }

    /// Decode a payload delivered to `WCSessionDelegate.session(_:didReceiveUserInfo:)`.
    /// Returns nil for any dictionary that isn't one of ours.
    init?(userInfo: [String: Any]) {
        guard let data = userInfo[Self.payloadKey] as? Data,
              let decoded = try? JSONDecoder().decode(WatchDosePayload.self, from: data)
        else { return nil }
        self = decoded
    }
}
