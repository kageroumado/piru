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
    var id: UUID = UUID()
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

/// An opt-in stock record for one `(substance, salt/form)` pair.
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
    var saltForm: String? = nil
    /// Base unit the stock is measured in (e.g. `"mg"`, `"mL"`, `"caps"`).
    var unit: String = "mg"
    /// Doses on/after this instant count against stock; earlier ones do not.
    var trackingStart: Date = Date.now
    /// Opt-in low-stock alert level, in ``unit``. `nil` = no alert.
    var lowStockThreshold: Double? = nil
    /// De-dupe flag for the low-stock notification; reset when stock rises back
    /// above the threshold (e.g. on restock).
    var lowStockNotified: Bool = false
    /// Amount that reads as 100% for the supply bar, in ``unit``. `nil` or `0`
    /// hides the bar (see the Baseline section of the spec).
    var baselineQuantity: Double? = nil
    /// "Single dose" in ``unit``, powering "~N doses left". Optional, **not**
    /// prefilled; `nil` or `0` hides the doses-left value.
    var doseSize: Double? = nil
    /// Cache of ``InventoryMath/quantity(for:in:)`` for cheap badge/widget reads.
    /// Pure-derived, so a stale value self-heals on the next recompute.
    var currentQuantity: Double = 0
    /// JSON-encoded backing storage for ``manualEvents``. Prefer the accessor.
    var restocksData: Data = Data()
    /// When the user started tracking this item.
    var createdAt: Date = Date.now

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
        unit: String = "mg",
        trackingStart: Date = .now,
        lowStockThreshold: Double? = nil,
        baselineQuantity: Double? = nil,
        doseSize: Double? = nil,
        manualEvents: [ManualEvent] = [],
        createdAt: Date = .now,
    ) {
        self.id = id
        self.substance = substance
        self.saltForm = saltForm
        self.unit = unit
        self.trackingStart = trackingStart
        self.lowStockThreshold = lowStockThreshold
        self.lowStockNotified = false
        self.baselineQuantity = baselineQuantity
        self.doseSize = doseSize
        self.currentQuantity = 0
        self.restocksData = (try? JSONEncoder().encode(manualEvents)) ?? Data()
        self.createdAt = createdAt
    }
}
