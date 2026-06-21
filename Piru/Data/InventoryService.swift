import Foundation
import SwiftData

// MARK: - InventoryMath (pure derivation)

/// The read side of inventory: turns an ``InventoryItem``'s embedded manual
/// events plus the `DoseEntry` log into the current amount on hand and the
/// derived "doses left" / run-out estimates.
///
/// Everything here is a fresh projection of persisted rows — there is no stored
/// running tally — so editing or deleting a dose is reflected on the next read
/// with no sync code, and imported doses count exactly like typed ones.
@MainActor
enum InventoryMath {
    /// Rolling-window run-out estimate for an item.
    struct RunOut: Equatable {
        /// Average consumption per day over the last 7 days, in the item's unit.
        let dailyAvg: Double
        /// Estimated days until the current stock reaches zero at ``dailyAvg``.
        let daysLeft: Double
    }

    /// All doses that count against this item: matching substance (case-
    /// insensitive) and salt (strict, `nil == nil`), on or after `trackingStart`.
    ///
    /// We fetch by the `timestamp` predicate, then filter substance/salt in
    /// memory — a case-insensitive compare and a nil-safe `saltForm` match aren't
    /// expressible cleanly in `#Predicate`, and the per-item volume is small.
    static func doses(for item: InventoryItem, in ctx: ModelContext) -> [DoseEntry] {
        let start = item.trackingStart
        let lowered = item.substance.lowercased()
        let all = (try? ctx.fetch(FetchDescriptor<DoseEntry>(
            predicate: #Predicate { $0.timestamp >= start },
        ))) ?? []
        return all.filter {
            $0.substance.lowercased() == lowered && $0.saltForm == item.saltForm
        }
    }

    /// Convert a dose amount into the item's unit. Delegates to the existing
    /// mass-family conversion (µg ↔ mg ↔ g), which also returns the amount
    /// unchanged for an exact-unit match (mL→mL, caps→caps). Anything else
    /// (mg vs mL, IU, drops) returns `nil` → that dose is skipped, never blocked.
    static func convert(_ amount: Double, from: String, to: String) -> Double? {
        DoseUnit.convert(amount, from: from, to: to)
    }

    /// Stock = replay(manual events ∪ converted doses), floored at 0 on the way
    /// down. Restocks/initial add; adjustments and consumption floor at 0 so an
    /// overdraw is forgiven (30 − log 50 → 0; a later +100 → 100).
    static func quantity(for item: InventoryItem, in ctx: ModelContext) -> Double {
        struct Tick { let date: Date; let delta: Double; let floors: Bool }
        var ticks: [Tick] = item.manualEvents.map {
            Tick(date: $0.date, delta: $0.amount, floors: $0.kind == .adjustment)
        }
        for dose in doses(for: item, in: ctx) {
            guard let converted = convert(dose.amount, from: dose.unit, to: item.unit) else { continue }
            ticks.append(Tick(date: dose.timestamp, delta: -converted, floors: true))
        }
        var balance = 0.0
        for tick in ticks.sorted(by: { $0.date < $1.date }) {
            balance = tick.floors ? max(0, balance + tick.delta) : balance + tick.delta
        }
        return balance
    }

    /// Whole doses remaining, only when a `doseSize` is set/non-zero.
    /// Reads the cached ``InventoryItem/currentQuantity``.
    static func dosesLeft(for item: InventoryItem) -> Int? {
        guard let size = item.doseSize, size > 0 else { return nil }
        return Int((item.currentQuantity / size).rounded(.down))
    }

    /// Run-out estimate from a rolling 7-day average, gated so it only shows for a
    /// daily / semi-daily pattern (≥5 of the last 7 calendar days had a matching
    /// dose). Returns `nil` when the guard fails — never a fabricated estimate.
    ///
    /// `daysLeft` is computed from the cached ``InventoryItem/currentQuantity``,
    /// per the spec; callers refresh the cache (`recompute`) before display.
    static func runOut(for item: InventoryItem, in ctx: ModelContext, now: Date = .now) -> RunOut? {
        let calendar = Calendar.current
        guard let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) else { return nil }
        let recent = doses(for: item, in: ctx).filter { $0.timestamp >= weekAgo && $0.timestamp <= now }
        let daysWithADose = Set(recent.map { calendar.startOfDay(for: $0.timestamp) }).count
        guard daysWithADose >= 5 else { return nil }
        let consumed = recent.reduce(0.0) { sum, dose in
            sum + (convert(dose.amount, from: dose.unit, to: item.unit) ?? 0)
        }
        let dailyAvg = consumed / 7
        guard dailyAvg > 0 else { return nil }
        return RunOut(dailyAvg: dailyAvg, daysLeft: item.currentQuantity / dailyAvg)
    }
}

// MARK: - InventoryService (mutations + cache refresh)

/// The write side of inventory: stateless mutations that append ``ManualEvent``s,
/// refresh the ``InventoryItem/currentQuantity`` cache, and manage the baseline
/// and low-stock flag. Notification *scheduling* is wired separately
/// (`DoseNotificationManager`, Phase 2); this type only keeps the de-dupe flag
/// honest so a future dip re-fires.
@MainActor
enum InventoryService {
    /// Existing tracked item for a `(substance, salt)` pair, if any.
    static func find(substance: String, saltForm: String?, in ctx: ModelContext) -> InventoryItem? {
        let lowered = substance.lowercased()
        let all = (try? ctx.fetch(FetchDescriptor<InventoryItem>())) ?? []
        return all.first { $0.substance.lowercased() == lowered && $0.saltForm == saltForm }
    }

    /// Start tracking a substance with an optional initial amount. With
    /// `setBaseline: true`, pins the post-event total as the baseline (100%).
    @discardableResult
    static func create(
        substance: String,
        saltForm: String?,
        unit: String,
        initial: Double,
        threshold: Double?,
        setBaseline: Bool,
        in ctx: ModelContext,
    ) -> InventoryItem {
        var events: [ManualEvent] = []
        if initial != 0 {
            events.append(ManualEvent(kind: .initial, amount: initial, date: .now, setsBaseline: setBaseline))
        }
        let item = InventoryItem(
            substance: substance,
            saltForm: saltForm,
            unit: unit,
            trackingStart: .now,
            lowStockThreshold: normalizedPositive(threshold),
            manualEvents: events,
        )
        ctx.insert(item)
        ensureColor(for: item.substance, in: ctx)
        recompute(item, in: ctx)
        if setBaseline { item.baselineQuantity = normalizedPositive(item.currentQuantity) }
        return item
    }

    /// Add stock. With `setBaseline: true`, captures the post-restock total as the
    /// new baseline and tags the event's provenance.
    static func restock(
        _ item: InventoryItem,
        amount: Double,
        note: String?,
        setBaseline: Bool,
        in ctx: ModelContext,
    ) {
        var events = item.manualEvents
        events.append(ManualEvent(
            kind: .restock, amount: amount, date: .now, note: note, setsBaseline: setBaseline,
        ))
        item.manualEvents = events
        recompute(item, in: ctx)
        if setBaseline { item.baselineQuantity = normalizedPositive(item.currentQuantity) }
    }

    /// Set the exact amount on hand (recount / spill) by appending a signed
    /// adjustment that lands the live quantity on `exact`.
    static func correctTo(_ item: InventoryItem, exact: Double, note: String?, in ctx: ModelContext) {
        let current = InventoryMath.quantity(for: item, in: ctx)
        let delta = exact - current
        var events = item.manualEvents
        events.append(ManualEvent(kind: .adjustment, amount: delta, date: .now, note: note))
        item.manualEvents = events
        recompute(item, in: ctx)
    }

    /// Set the supply-bar baseline directly (Edit screen). `nil`, `0`, or a
    /// negative value disables the bar.
    static func setBaseline(_ item: InventoryItem, value: Double?, in _: ModelContext) {
        item.baselineQuantity = normalizedPositive(value)
    }

    /// Set the optional "single dose" size powering "~N doses left".
    /// `nil`, `0`, or negative disables it.
    static func setDoseSize(_ item: InventoryItem, value: Double?) {
        item.doseSize = normalizedPositive(value)
    }

    /// Change the item's base unit, converting everything denominated in it.
    ///
    /// The spec calls out converting `baselineQuantity`, `lowStockThreshold`, and
    /// `doseSize` within the mass family (clearing them when the new unit isn't
    /// convertible). The manual-event amounts are *also* stored in the item's
    /// unit, so they must convert too — otherwise the replayed stock would silently
    /// read old-unit numbers as new-unit ones. If the units aren't convertible we
    /// leave the raw event amounts in place and clear the three derived fields,
    /// matching the spec's "user re-sets on next edit" intent.
    static func changeUnit(_ item: InventoryItem, to newUnit: String, in ctx: ModelContext) {
        let oldUnit = item.unit
        guard oldUnit != newUnit else { return }

        let factor = InventoryMath.convert(1, from: oldUnit, to: newUnit)
        if let factor {
            item.manualEvents = item.manualEvents.map { event in
                var converted = event
                converted.amount = event.amount * factor
                return converted
            }
            item.baselineQuantity = item.baselineQuantity.map { $0 * factor }
            item.lowStockThreshold = item.lowStockThreshold.map { $0 * factor }
            item.doseSize = item.doseSize.map { $0 * factor }
        } else {
            // Not convertible: keep raw event amounts, clear the derived fields.
            item.baselineQuantity = nil
            item.lowStockThreshold = nil
            item.doseSize = nil
        }
        item.unit = newUnit
        recompute(item, in: ctx)
    }

    /// Refresh the denormalized cache from the derived quantity, then evaluate
    /// the low-stock threshold. Pass `notify: false` to update the cache and the
    /// de-dupe flag *without* firing a notification — used by bulk import/restore
    /// so a restored backup doesn't spray one alert per low item.
    static func recompute(_ item: InventoryItem, in ctx: ModelContext, notify: Bool = true) {
        item.currentQuantity = InventoryMath.quantity(for: item, in: ctx)
        evaluateLowStock(item, notify: notify)
    }

    /// Refresh every tracked item's cache — used after a bulk insert (import /
    /// restore) and alongside the existing post-log widget reload.
    static func recomputeAll(in ctx: ModelContext, notify: Bool = true) {
        let items = (try? ctx.fetch(FetchDescriptor<InventoryItem>())) ?? []
        for item in items {
            recompute(item, in: ctx, notify: notify)
        }
    }

    // MARK: - Helpers

    /// Fire the low-stock alert at most once per dip, and reset the de-dupe flag
    /// once stock rises back above the threshold so a later dip re-fires.
    ///
    /// The flag is set whenever the item is at/below threshold regardless of
    /// `notify`, so a silent import acknowledges the low state (the in-app Low
    /// badge still shows) without re-notifying on the next foreground recompute.
    private static func evaluateLowStock(_ item: InventoryItem, notify: Bool) {
        guard let threshold = item.lowStockThreshold, threshold > 0 else {
            item.lowStockNotified = false
            return
        }
        if item.currentQuantity > threshold {
            item.lowStockNotified = false
            return
        }
        guard !item.lowStockNotified else { return }
        item.lowStockNotified = true
        if notify {
            DoseNotificationManager.inventoryLowStock(
                substance: item.substance,
                remaining: item.currentQuantity,
                unit: item.unit,
                isOut: item.currentQuantity <= 0,
                itemID: item.id,
            )
        }
    }

    /// `nil` for non-positive inputs; the value otherwise. Centralizes the
    /// "0 = off" convention shared by baseline, threshold, and dose size.
    private static func normalizedPositive(_ value: Double?) -> Double? {
        guard let value, value > 0 else { return nil }
        return value
    }

    /// Persist the substance's stable deterministic color if it has none yet, so
    /// a first-time-tracked substance appears in the colors menu and is editable
    /// right away — without waiting for its first logged dose. Mirrors the
    /// `ensureColor` the logging paths run, and uses the same
    /// `PresetColor.deterministic` that `SubstancePalette` falls back to, so the
    /// persisted color matches what inventory already showed.
    private static func ensureColor(for substance: String, in ctx: ModelContext) {
        let name = substance.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let existing = (try? ctx.fetch(FetchDescriptor<SubstanceColor>())) ?? []
        guard !existing.hasColor(for: name) else { return }
        ctx.insert(SubstanceColor(substance: name, hexColor: PresetColor.deterministic(for: name).hex))
    }
}
