import Foundation
import SwiftData

// MARK: - Manual Event

/// A user-entered change to an inventory item's stock: the initial amount, a
/// restock, or a manual correction. Plain value type — **not** a `@Model`.
///
/// Manual events are embedded as a JSON array inside
/// ``InventoryItem/restocksData`` (mirroring ``DailyDoseItem/frequencyDays``)
/// rather than living in a separate ledger model: they are few, never queried
/// independently, and only ever read alongside their item. Dose *consumption* is
/// not stored here at all — it is derived on read from the `DoseEntry` log.
struct ManualEvent: Codable, Identifiable, Hashable {
    /// Stable identity, used to union events idempotently on re-import.
    var id: UUID = .init()
    /// What kind of manual change this represents.
    var kind: Kind = .restock
    /// Signed amount in the item's unit. `initial`/`restock` are positive; an
    /// `adjustment` is signed (a correction up or down).
    var amount: Double = 0
    /// When the change happened; drives the date-sorted replay.
    var date: Date = .now
    /// Optional free-form note (e.g. "pharmacy refill").
    var note: String? = nil
    /// Provenance flag: this event pinned the item's baseline. Purely
    /// informational — the UI shows the baseline as a fraction, not a ledger tag.
    var setsBaseline: Bool = false

    enum Kind: String, Codable {
        case initial
        case restock
        case adjustment
    }
}

// MARK: - Inventory Item

/// An opt-in stock record for one `(substance, salt/form)` pair, optionally
/// narrowed to one isomer or one branded product.
///
/// SwiftData `@Model` shared across the main Piru app, the Home Screen widget
/// (`PiruWidget`), and the Lock Screen Live Activity extension
/// (`PiruLiveActivityExtension`).
///
/// ## Derived, not stored
/// The current amount on hand is **not** a running tally. It is replayed on read
/// from two sources by ``InventoryMath``:
/// 1. The manual side — ``manualEvents`` (restocks / corrections / initial),
///    persisted here as embedded JSON.
/// 2. The consumption side — a `SELECT` over the `DoseEntry` rows the app already
///    keeps, filtered by substance, salt, and `timestamp >= trackingStart`.
///
/// Because consumption is a fresh projection of the dose log, editing or deleting
/// a dose is reflected automatically with no sync code, and imported doses count
/// exactly like typed ones. ``currentQuantity`` is only a denormalized **cache**
/// of that computation for cheap badge/widget reads; it self-heals on the next
/// `recompute`.
///
/// ## Identity
/// Mirrors `FavoriteSubstance` / `SubstanceColor`: ``substance`` is a
/// case-insensitive `String` and ``saltForm`` is the second axis. No
/// `@Attribute(.unique)` — the `(substance, saltForm)` pair is the key and we
/// match in code (avoids unique-constraint / CloudKit edges).
///
/// ``isomer`` and ``productName`` narrow an item to one form of the substance
/// (Dextroamphetamine, Adderall), the same facets a logged `DoseEntry` carries.
/// At most one is set. An item with neither is the *plain* item: it takes every
/// dose of the substance that no narrower item claims — the routing lives in
/// ``InventoryMath/owner(of:among:)``.
///
/// ## Schema Migration Note
/// Every persisted property has a default value, so adding this model — and any
/// future field on it — is an additive lightweight migration with no
/// `SchemaMigrationPlan` (see `StoreRecovery.swift`).
@Model
final class InventoryItem {
    /// Stable identity for routing (sheets, deep links).
    var id: UUID = UUID()
    /// Canonical substance name; matched case-insensitively against `DoseEntry`.
    var substance: String = ""
    /// Salt/form variant; `nil` means base/freebase. Matched strictly.
    var saltForm: String?
    /// The stereoisomer this stock is (`"D"` for Dextroamphetamine), matching
    /// `DoseEntry.isomer`. `nil` = any isomer.
    var isomer: String?
    /// The branded product this stock is ("Adderall"), matched
    /// case-insensitively against `DoseEntry.productName`. `nil` = any product.
    var productName: String?
    /// The canonical form title captured when the item was created
    /// ("Dextroamphetamine"), for the widget, which cannot reach the catalog.
    /// `nil` for a plain or product item, whose stored names already say it.
    var displayNameSnapshot: String?
    /// Base unit the stock is measured in (e.g. `"mg"`, `"mL"`, `"caps"`).
    var unit: String = "mg"
    /// Doses on/after this instant count against stock; earlier ones do not.
    var trackingStart: Date = Date.now
    /// Opt-in low-stock alert level, in ``unit``. `nil` = no alert.
    var lowStockThreshold: Double?
    /// De-dupe flag for the low-stock notification; reset when stock rises back
    /// above the threshold (e.g. on restock).
    var lowStockNotified: Bool = false
    /// Amount that reads as 100% for the supply bar, in ``unit``. `nil` or `0`
    /// hides the bar (see the Baseline section of the spec).
    var baselineQuantity: Double?
    /// "Single dose" in ``unit``, powering "~N doses left". Optional, **not**
    /// prefilled; `nil` or `0` hides the doses-left value.
    var doseSize: Double?
    /// Milligrams of substance in one ``unit`` when the stock is counted in
    /// pieces (`"tabs"`, `"caps"`) — the strength printed on the box. It is the
    /// bridge that lets a dose logged in milligrams draw down a count, and a
    /// count merge into a mass-denominated item. `nil` for a mass or volume
    /// unit, or when the strength is unknown.
    var unitStrengthMG: Double?
    /// Cache of ``InventoryMath/quantity(for:in:)`` for cheap badge/widget reads.
    /// Pure-derived, so a stale value self-heals on the next recompute.
    var currentQuantity: Double = 0
    /// JSON-encoded backing storage for ``manualEvents``. Prefer the accessor.
    var restocksData: Data = Data()
    /// When the user started tracking this item.
    var createdAt: Date = Date.now
    /// User's manual list position. `0` for every item until the first drag, at
    /// which point the whole list is renumbered `0…n`. While all items share `0`
    /// the manager falls back to the status-based auto-sort (out → low → recent).
    var sortOrder: Int = 0

    /// JSON-encoded backing storage for ``sharedWith``. Prefer the accessor.
    var sharedWithData: Data = Data()

    /// Other profiles that draw from this item. The item lives in its owner's
    /// store; doses from these profiles that match its identity count against
    /// its stock too.
    var sharedWith: [UUID] {
        get { (try? JSONDecoder().decode([UUID].self, from: sharedWithData)) ?? [] }
        set { sharedWithData = newValue.isEmpty ? Data() : (try? JSONEncoder().encode(Array(Set(newValue)).sorted { $0.uuidString < $1.uuidString })) ?? Data() }
    }

    /// The manual side of the ledger, decoded from ``restocksData``.
    ///
    /// Backed by a `Data` column (JSON) for the same reason
    /// ``DailyDoseItem/frequencyDays`` is: arrays of value types are awkward to
    /// model across SwiftData and the extension targets, and this set is small
    /// and read-mostly.
    var manualEvents: [ManualEvent] {
        get { (try? JSONDecoder().decode([ManualEvent].self, from: restocksData)) ?? [] }
        set { restocksData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    init(
        id: UUID = UUID(),
        substance: String = "",
        saltForm: String? = nil,
        isomer: String? = nil,
        productName: String? = nil,
        displayNameSnapshot: String? = nil,
        unit: String = "mg",
        trackingStart: Date = .now,
        lowStockThreshold: Double? = nil,
        baselineQuantity: Double? = nil,
        doseSize: Double? = nil,
        unitStrengthMG: Double? = nil,
        manualEvents: [ManualEvent] = [],
        createdAt: Date = .now,
        sortOrder: Int = 0,
    ) {
        self.id = id
        self.substance = substance
        self.saltForm = saltForm
        self.isomer = isomer
        self.productName = productName
        self.displayNameSnapshot = displayNameSnapshot
        self.unit = unit
        self.trackingStart = trackingStart
        self.lowStockThreshold = lowStockThreshold
        self.lowStockNotified = false
        self.baselineQuantity = baselineQuantity
        self.doseSize = doseSize
        self.unitStrengthMG = unitStrengthMG
        self.currentQuantity = 0
        self.restocksData = (try? JSONEncoder().encode(manualEvents)) ?? Data()
        self.createdAt = createdAt
        self.sortOrder = sortOrder
    }
}

// MARK: - Form identity

extension InventoryItem {
    /// A form facet as identity: `nil`, `""` and `"0"` (the PSID unspecified
    /// sentinel) all mean "no facet", the same rule `QuickLogDose.identityKey`
    /// applies to a dose.
    nonisolated static func facet(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespaces), !trimmed.isEmpty, trimmed != "0" else {
            return nil
        }
        return trimmed
    }

    /// Whether this item names no isomer and no product, so it takes every dose
    /// of its substance that no narrower item claims.
    var isPlain: Bool {
        Self.facet(isomer) == nil && Self.facet(productName) == nil
    }
}
