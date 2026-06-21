import Foundation
import SwiftData
import Testing
@testable import Piru

@MainActor
@Suite("Inventory")
struct InventoryTests {
    /// An in-memory store with the full current schema.
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(StoreRecovery.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none),
        )
        return ModelContext(container)
    }

    /// A name guaranteed absent from the substance library, so nothing depends on
    /// bundled data.
    private let drug = "ZZTestInventorySubstance"

    /// Fixed clock so date math is deterministic.
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @discardableResult
    private func logDose(
        _ ctx: ModelContext,
        substance: String? = nil,
        amount: Double,
        unit: String = "mg",
        saltForm: String? = nil,
        at offsetHours: Double = 1,
    ) -> DoseEntry {
        let entry = DoseEntry(
            substance: substance ?? drug,
            amount: amount,
            unit: unit,
            saltForm: saltForm,
            timestamp: now.addingTimeInterval(offsetHours * 3_600),
        )
        ctx.insert(entry)
        return entry
    }

    private func makeItem(
        _ ctx: ModelContext,
        substance: String? = nil,
        unit: String = "mg",
        trackingStart: Date? = nil,
        saltForm: String? = nil,
        initial: Double = 0,
    ) -> InventoryItem {
        let start = trackingStart ?? now
        let item = InventoryItem(
            substance: substance ?? drug,
            saltForm: saltForm,
            unit: unit,
            trackingStart: start,
            // The initial amount exists from the start of tracking, so date it at
            // `trackingStart` — otherwise back-dated consumption would floor away
            // before the stock "arrives".
            manualEvents: initial == 0
                ? []
                : [ManualEvent(kind: .initial, amount: initial, date: start)],
        )
        ctx.insert(item)
        return item
    }

    // MARK: - Replay, floor, forgive

    @Test
    func `Initial minus a converted dose`() throws {
        let ctx = try makeContext()
        let item = makeItem(ctx, unit: "g", initial: 5)
        logDose(ctx, amount: 200, unit: "mg", at: 1) // 0.2 g
        #expect(InventoryMath.quantity(for: item, in: ctx) == 4.8)
    }

    @Test
    func `Over-log floors at 0`() throws {
        let ctx = try makeContext()
        let item = makeItem(ctx, unit: "mg", initial: 30)
        logDose(ctx, amount: 50, at: 1)
        #expect(InventoryMath.quantity(for: item, in: ctx) == 0)
    }

    @Test
    func `Overdraw is forgiven before a later restock`() throws {
        let ctx = try makeContext()
        let item = makeItem(ctx, unit: "mg", initial: 30)
        logDose(ctx, amount: 50, at: 1) // floors to 0
        InventoryService.restock(item, amount: 100, note: nil, setBaseline: false, in: ctx)
        #expect(InventoryMath.quantity(for: item, in: ctx) == 100)
    }

    @Test
    func `Negative adjustment floors at 0`() throws {
        let ctx = try makeContext()
        let item = makeItem(ctx, unit: "mg", initial: 10)
        InventoryService.correctTo(item, exact: 0, note: nil, in: ctx)
        // A further down-adjustment can't go below 0.
        item.manualEvents.append(ManualEvent(kind: .adjustment, amount: -5, date: now.addingTimeInterval(7_200)))
        #expect(InventoryMath.quantity(for: item, in: ctx) == 0)
    }

    // MARK: - Conversion / mismatch

    @Test
    func `Unit-mismatched dose is skipped, not blocked`() throws {
        let ctx = try makeContext()
        let item = makeItem(ctx, unit: "mg", initial: 100)
        logDose(ctx, amount: 5, unit: "mL", at: 1) // not mass-convertible → skipped
        #expect(InventoryMath.quantity(for: item, in: ctx) == 100)
    }

    @Test
    func `Exact-unit (count) match decrements`() throws {
        let ctx = try makeContext()
        let item = makeItem(ctx, unit: "caps", initial: 30)
        logDose(ctx, amount: 2, unit: "caps", at: 1)
        #expect(InventoryMath.quantity(for: item, in: ctx) == 28)
    }

    // MARK: - Salt matching

    @Test
    func `Strict salt match: wrong-form dose is not counted`() throws {
        let ctx = try makeContext()
        let item = makeItem(ctx, unit: "mg", saltForm: "Glycinate", initial: 100)
        logDose(ctx, amount: 20, saltForm: "Citrate", at: 1) // different salt
        logDose(ctx, amount: 10, saltForm: nil, at: 2) // base form
        logDose(ctx, amount: 5, saltForm: "Glycinate", at: 3) // matches
        #expect(InventoryMath.quantity(for: item, in: ctx) == 95)
    }

    // MARK: - trackingStart cutoff

    @Test
    func `Doses before trackingStart don't count`() throws {
        let ctx = try makeContext()
        let item = makeItem(ctx, unit: "mg", trackingStart: now, initial: 100)
        logDose(ctx, amount: 40, at: -2) // before tracking start
        logDose(ctx, amount: 10, at: 2) // after
        #expect(InventoryMath.quantity(for: item, in: ctx) == 90)
    }

    // MARK: - Back-dated reorder

    @Test
    func `Back-dated dose is replayed in date order`() throws {
        let ctx = try makeContext()
        // initial 100 @0h, restock +50 @10h, with a dose back-dated to +5h —
        // between the two manual events. Date-sorted replay: 100 → 70 → 120.
        let item = makeItem(ctx, unit: "mg", initial: 100)
        item.manualEvents.append(ManualEvent(
            kind: .restock, amount: 50, date: now.addingTimeInterval(10 * 3_600),
        ))
        logDose(ctx, amount: 30, at: 5)
        #expect(InventoryMath.quantity(for: item, in: ctx) == 120)
    }

    // MARK: - Edit/delete reflected

    @Test
    func `Deleting a dose restores stock on re-query`() throws {
        let ctx = try makeContext()
        let item = makeItem(ctx, unit: "mg", initial: 100)
        let dose = logDose(ctx, amount: 25, at: 1)
        #expect(InventoryMath.quantity(for: item, in: ctx) == 75)
        ctx.delete(dose)
        #expect(InventoryMath.quantity(for: item, in: ctx) == 100)
    }

    @Test
    func `Editing a dose amount is reflected on re-query`() throws {
        let ctx = try makeContext()
        let item = makeItem(ctx, unit: "mg", initial: 100)
        let dose = logDose(ctx, amount: 25, at: 1)
        dose.amount = 40
        #expect(InventoryMath.quantity(for: item, in: ctx) == 60)
    }

    // MARK: - Cache

    @Test
    func `recompute refreshes the currentQuantity cache`() throws {
        let ctx = try makeContext()
        let item = makeItem(ctx, unit: "mg", initial: 100)
        #expect(item.currentQuantity == 0) // not yet computed
        logDose(ctx, amount: 30, at: 1)
        InventoryService.recompute(item, in: ctx)
        #expect(item.currentQuantity == 70)
    }

    @Test
    func `recomputeAll touches every tracked item`() throws {
        let ctx = try makeContext()
        let a = makeItem(ctx, unit: "mg", initial: 100)
        let b = makeItem(ctx, substance: "ZZOther", unit: "mg", initial: 50)
        logDose(ctx, amount: 10, at: 1)
        logDose(ctx, substance: "ZZOther", amount: 5, at: 1)
        InventoryService.recomputeAll(in: ctx)
        #expect(a.currentQuantity == 90)
        #expect(b.currentQuantity == 45)
    }

    // MARK: - find / create

    @Test
    func `find matches case-insensitively on substance + strict salt`() throws {
        let ctx = try makeContext()
        _ = makeItem(ctx, unit: "mg", saltForm: "Glycinate")
        #expect(InventoryService.find(substance: drug.lowercased(), saltForm: "Glycinate", in: ctx) != nil)
        #expect(InventoryService.find(substance: drug, saltForm: nil, in: ctx) == nil)
    }

    @Test
    func `create with setBaseline pins the post-initial total`() throws {
        let ctx = try makeContext()
        let item = InventoryService.create(
            substance: drug, saltForm: nil, unit: "g", initial: 5,
            threshold: nil, setBaseline: true, in: ctx,
        )
        #expect(item.baselineQuantity == 5)
        #expect(item.manualEvents.first?.setsBaseline == true)
    }

    // MARK: - Baseline

    @Test
    func `setBaseline with 0 disables the bar`() throws {
        let ctx = try makeContext()
        let item = makeItem(ctx, unit: "mg", initial: 100)
        InventoryService.setBaseline(item, value: 200, in: ctx)
        #expect(item.baselineQuantity == 200)
        InventoryService.setBaseline(item, value: 0, in: ctx)
        #expect(item.baselineQuantity == nil)
    }

    @Test
    func `restock with setBaseline captures the new full level`() throws {
        let ctx = try makeContext()
        let item = makeItem(ctx, unit: "mg", initial: 20)
        InventoryService.restock(item, amount: 80, note: "refill", setBaseline: true, in: ctx)
        #expect(item.currentQuantity == 100)
        #expect(item.baselineQuantity == 100)
    }

    // MARK: - correctTo

    @Test
    func `correctTo lands the exact amount via a signed adjustment`() throws {
        let ctx = try makeContext()
        let item = makeItem(ctx, unit: "mg", initial: 100)
        logDose(ctx, amount: 30, at: 1) // -> 70
        InventoryService.correctTo(item, exact: 65, note: "recount", in: ctx)
        #expect(InventoryMath.quantity(for: item, in: ctx) == 65)
        #expect(item.currentQuantity == 65)
    }

    // MARK: - Unit change

    @Test
    func `changeUnit converts events + derived fields within the mass family`() throws {
        let ctx = try makeContext()
        let item = makeItem(ctx, unit: "g", initial: 5)
        InventoryService.setBaseline(item, value: 5, in: ctx)
        item.lowStockThreshold = 1
        InventoryService.setDoseSize(item, value: 0.2)

        InventoryService.changeUnit(item, to: "mg", in: ctx)

        #expect(item.unit == "mg")
        #expect(item.baselineQuantity == 5_000)
        #expect(item.lowStockThreshold == 1_000)
        #expect(item.doseSize == 200)
        #expect(item.currentQuantity == 5_000) // 5 g -> 5000 mg
    }

    @Test
    func `changeUnit to a non-convertible unit clears derived fields`() throws {
        let ctx = try makeContext()
        let item = makeItem(ctx, unit: "mg", initial: 100)
        InventoryService.setBaseline(item, value: 200, in: ctx)
        item.lowStockThreshold = 10
        InventoryService.setDoseSize(item, value: 5)

        InventoryService.changeUnit(item, to: "mL", in: ctx)

        #expect(item.unit == "mL")
        #expect(item.baselineQuantity == nil)
        #expect(item.lowStockThreshold == nil)
        #expect(item.doseSize == nil)
    }

    // MARK: - doses left

    @Test
    func `dosesLeft only when a dose size is set`() throws {
        let ctx = try makeContext()
        let item = makeItem(ctx, unit: "mg", initial: 100)
        InventoryService.recompute(item, in: ctx)
        #expect(InventoryMath.dosesLeft(for: item) == nil) // no doseSize
        InventoryService.setDoseSize(item, value: 30)
        #expect(InventoryMath.dosesLeft(for: item) == 3) // floor(100 / 30)
    }

    // MARK: - Run-out gate

    @Test
    func `runOut requires at least 5 of the last 7 days dosed`() throws {
        let ctx = try makeContext()
        let item = makeItem(ctx, unit: "mg", trackingStart: now.addingTimeInterval(-30 * 86_400), initial: 100)
        // Only 3 distinct days in the last week.
        for day in 1 ... 3 {
            logDose(ctx, amount: 10, at: Double(-day) * 24)
        }
        InventoryService.recompute(item, in: ctx)
        #expect(InventoryMath.runOut(for: item, in: ctx, now: now) == nil)
    }

    @Test
    func `runOut computes daily average and days left when the gate passes`() throws {
        let ctx = try makeContext()
        let item = makeItem(ctx, unit: "mg", trackingStart: now.addingTimeInterval(-30 * 86_400), initial: 700)
        // 7 distinct days, 10 mg each -> 70 mg consumed -> dailyAvg 10.
        for day in 0 ... 6 {
            logDose(ctx, amount: 10, at: Double(-day) * 24 - 1)
        }
        InventoryService.recompute(item, in: ctx)
        let result = try #require(InventoryMath.runOut(for: item, in: ctx, now: now))
        #expect(result.dailyAvg == 10)
        // current = 700 - 70 = 630 -> 63 days left.
        #expect(result.daysLeft == 63)
    }
}
