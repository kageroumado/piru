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
    var journalGeneration: Int?
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
    /// The watch's time zone when the dose was logged, which becomes
    /// ``DoseEntry/timeZoneIdentifier``. Absent from a payload sent by an older
    /// watch build, where the phone records its own zone.
    var timeZoneIdentifier: String?
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

    // MARK: PSID identity

    // Carried from the manifest item so the phone logs the right product and
    // family by identity. All nil for a facet-less log.

    var substanceUID: String?
    var isomer: String?
    var releaseForm: String?
    var saltForm: String?
    var productName: String?
    /// Resolved display title captured on the phone at manifest-build time.
    var displayName: String?

    /// The My Meds slot this dose checks off (``ManifestMedSlot/id``); nil for a
    /// quick-log dose. The phone resolves it back to the med and logs the dose the way
    /// My Meds does.
    var medSlot: String?
    /// The number of the tick that took it (``WatchMedChange``).
    var medChange: Int?

    init(
        id: UUID,
        substance: String,
        amount: Double,
        unit: String,
        route: String,
        timestamp: Date,
        timeZoneIdentifier: String? = TimeZone.current.identifier,
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
        medSlot: String? = nil,
        medChange: Int? = nil,
        journalGeneration: Int? = nil,
    ) {
        self.journalGeneration = journalGeneration
        self.id = id
        self.substance = substance
        self.amount = amount
        self.unit = unit
        self.route = route
        self.timestamp = timestamp
        self.timeZoneIdentifier = timeZoneIdentifier
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
        self.medSlot = medSlot
        self.medChange = medChange
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

// MARK: - Untaking a med

/// A My Meds slot unticked on the watch, sent like a dose over `transferUserInfo` so it
/// arrives after the take it undoes. Naming ``entryID``, it removes that dose or
/// nothing; without one, the dose that ticked ``medSlot`` that day.
nonisolated struct WatchMedUntake: Codable, Hashable, Sendable {
    var journalGeneration: Int?
    /// The slot's id (``ManifestMedSlot/id``).
    var medSlot: String
    /// The dose this watch's own tick of the slot queued; nil for a slot the phone ticked.
    var entryID: UUID?
    /// The untick's number (``WatchMedChange``).
    var medChange: Int?
    /// When the slot was unticked, which names its journal day on the phone.
    var timestamp: Date
    /// The watch's time zone when the slot was unticked, so its journal day is read on
    /// the same clock as a dose's.
    var timeZoneIdentifier: String?

    init(
        medSlot: String,
        entryID: UUID?,
        change: Int? = nil,
        timestamp: Date,
        timeZoneIdentifier: String? = TimeZone.current.identifier,
        journalGeneration: Int?,
    ) {
        self.journalGeneration = journalGeneration
        self.medSlot = medSlot
        self.entryID = entryID
        self.medChange = change
        self.timestamp = timestamp
        self.timeZoneIdentifier = timeZoneIdentifier
    }
}

nonisolated extension WatchMedUntake {
    private static let untakeKey = "watchMedUntake"

    /// Encode for `WCSession.transferUserInfo(_:)` — one key, one JSON blob, as a dose.
    func userInfo() -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return [Self.untakeKey: data]
    }

    /// Decode an untake delivered to `session(_:didReceiveUserInfo:)`; nil for any
    /// dictionary that isn't one.
    init?(userInfo: [String: Any]) {
        guard let data = userInfo[Self.untakeKey] as? Data,
              let decoded = try? JSONDecoder().decode(WatchMedUntake.self, from: data)
        else { return nil }
        self = decoded
    }
}
