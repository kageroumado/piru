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

    @Test
    func `Batch recompute respects each item's own trackingStart`() throws {
        // Two items on the same substance, started a week apart; the shared
        // batch fetch is bounded by the OLDER start, so the per-item re-filter
        // is what keeps the pre-tracking dose off the newer item.
        let ctx = try makeContext()
        let older = makeItem(ctx, trackingStart: now, initial: 100)
        let newer = makeItem(ctx, trackingStart: now.addingTimeInterval(7 * 86_400), initial: 100)
        logDose(ctx, amount: 10, at: 24) // day 1: after older's start, before newer's
        InventoryService.recomputeAll(in: ctx)
        #expect(older.currentQuantity == 90)
        #expect(newer.currentQuantity == 100)
    }

    @Test
    func `Batch recompute keeps salt buckets strict`() throws {
        // Two items differing only in saltForm share one identity bucket;
        // each must see only its own salt's doses (nil == nil stays strict).
        let ctx = try makeContext()
        let freebase = makeItem(ctx, initial: 100)
        let salted = makeItem(ctx, saltForm: "HCl", initial: 100)
        logDose(ctx, amount: 10, at: 1)
        logDose(ctx, amount: 25, saltForm: "HCl", at: 1)
        InventoryService.recomputeAll(in: ctx)
        #expect(freebase.currentQuantity == 90)
        #expect(salted.currentQuantity == 75)
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

    // MARK: - Scoped recompute (log-path optimization)

    /// The log path's `recompute(forSubstances:)` must land the **affected**
    /// item's cache on the same value the blanket `recomputeAll` does, and must
    /// leave items for *other* substances untouched (that's the whole point —
    /// O(affected × doses), not O(all-items × doses)).
    @Test
    func `Scoped recompute equals recomputeAll for the affected item, skips others`() throws {
        let ctx = try makeContext()
        let other = "ZZOtherInventorySubstance"
        let affected = makeItem(ctx, unit: "mg", initial: 100)
        let untouched = makeItem(ctx, substance: other, unit: "mg", initial: 100)
        logDose(ctx, amount: 30, at: 1)
        logDose(ctx, substance: other, amount: 40, at: 1)

        // Baseline from the blanket recompute.
        InventoryService.recomputeAll(in: ctx)
        let affectedExpected = affected.currentQuantity // 70
        let untouchedExpected = untouched.currentQuantity // 60

        // Poison both caches so the scoped pass has to write the affected one.
        affected.currentQuantity = -1
        untouched.currentQuantity = -1
        InventoryService.recompute(forSubstances: [drug], in: ctx)

        #expect(affected.currentQuantity == affectedExpected)
        #expect(untouched.currentQuantity == -1) // never recomputed
        #expect(untouchedExpected == 60) // sanity on the baseline
    }

    /// The off-main scoped recompute (deferred log bookkeeping) must produce the
    /// same cached quantity as the synchronous path — same affected items, same
    /// `replayQuantity` math, just moved off the actor.
    @Test
    func `Off-main scoped recompute matches the on-main recompute`() async throws {
        let ctx = try makeContext()
        let item = makeItem(ctx, unit: "g", initial: 5)
        logDose(ctx, amount: 200, unit: "mg", at: 1) // 0.2 g

        InventoryService.recomputeAll(in: ctx)
        let expected = item.currentQuantity // 4.8

        item.currentQuantity = -1
        await InventoryService.recompute(forSubstances: [drug], replayingOffMainIn: ctx)
        #expect(item.currentQuantity == expected)
    }

    // MARK: - One identity per substance

    private func allItems(_ ctx: ModelContext) throws -> [InventoryItem] {
        try ctx.fetch(FetchDescriptor<InventoryItem>())
    }

    @Test
    func `create twice is one item with a restock, and the box note stays on the event`() throws {
        let ctx = try makeContext()
        let first = InventoryService.create(
            substance: drug, saltForm: nil, unit: "mg", initial: 180,
            threshold: nil, setBaseline: false, note: "Box · 60 tablets", in: ctx,
        )
        let second = InventoryService.create(
            substance: drug.uppercased(), saltForm: nil, unit: "mg", initial: 270,
            threshold: nil, setBaseline: false, note: "Box · 90 tablets", in: ctx,
        )
        #expect(second.id == first.id)
        #expect(try allItems(ctx).count == 1)
        #expect(first.currentQuantity == 450)
        #expect(first.manualEvents.map(\.kind) == [.initial, .restock])
        #expect(first.manualEvents.map(\.note) == ["Box · 60 tablets", "Box · 90 tablets"])
    }

    @Test
    func `create keeps salts apart`() throws {
        let ctx = try makeContext()
        InventoryService.create(substance: drug, saltForm: nil, unit: "mg", initial: 10, threshold: nil, setBaseline: false, in: ctx)
        InventoryService.create(substance: drug, saltForm: "HCl", unit: "mg", initial: 10, threshold: nil, setBaseline: false, in: ctx)
        #expect(try allItems(ctx).count == 2)
    }

    @Test
    func `create folds a counted box into a milligram item through its strength`() throws {
        let ctx = try makeContext()
        let item = InventoryService.create(substance: drug, saltForm: nil, unit: "mg", initial: 90, threshold: nil, setBaseline: false, in: ctx)
        InventoryService.create(
            substance: drug, saltForm: nil, unit: "tabs", initial: 30,
            threshold: nil, setBaseline: false, unitStrengthMG: 3, in: ctx,
        )
        #expect(try allItems(ctx).count == 1)
        #expect(item.unit == "mg")
        #expect(item.currentQuantity == 180)
    }

    @Test
    func `create folds a milligram box into a counted item through its strength`() throws {
        let ctx = try makeContext()
        let item = InventoryService.create(
            substance: drug, saltForm: nil, unit: "tabs", initial: 30,
            threshold: nil, setBaseline: false, unitStrengthMG: 3, in: ctx,
        )
        InventoryService.create(substance: drug, saltForm: nil, unit: "mg", initial: 90, threshold: nil, setBaseline: false, in: ctx)
        #expect(try allItems(ctx).count == 1)
        #expect(item.unit == "tabs")
        #expect(item.unitStrengthMG == 3)
        #expect(item.currentQuantity == 60)
    }

    @Test
    func `Counted stock is drawn down by a milligram dose through its strength`() throws {
        let ctx = try makeContext()
        let item = makeItem(ctx, unit: "tabs", initial: 28)
        item.unitStrengthMG = 36
        logDose(ctx, amount: 36, at: 1)
        logDose(ctx, amount: 18, at: 2)
        #expect(InventoryMath.quantity(for: item, in: ctx) == 26.5)
    }

    @Test
    func `Import of the same file twice is one item with its events once`() throws {
        let ctx = try makeContext()
        InventoryService.create(substance: drug, saltForm: nil, unit: "mg", initial: 180, threshold: nil, setBaseline: false, in: ctx)
        try ctx.save()
        let data = try DataExportImport.exportJSON(context: ctx)
        try DataExportImport.deleteAll(context: ctx)
        try ctx.save()

        try DataExportImport.importJSON(data: data, context: ctx)
        try DataExportImport.importJSON(data: data, context: ctx)

        let items = try allItems(ctx)
        #expect(items.count == 1)
        #expect(items.first?.manualEvents.count == 1)
        #expect(items.first?.currentQuantity == 180)
    }

    @Test
    func `Import folds two rows of one identity into one item`() throws {
        let ctx = try makeContext()
        // Two rows for one identity, as a store written before `create`
        // enforced it would export them.
        _ = makeItem(ctx, substance: drug, initial: 180)
        _ = makeItem(ctx, substance: drug.lowercased(), initial: 270)
        try ctx.save()
        let data = try DataExportImport.exportJSON(context: ctx)
        try DataExportImport.deleteAll(context: ctx)
        try ctx.save()

        try DataExportImport.importJSON(data: data, context: ctx)

        let items = try allItems(ctx)
        #expect(items.count == 1)
        #expect(items.first?.currentQuantity == 450)
    }

    @Test
    func `mergeDuplicateItems keeps the older id, concatenates events, and counts each dose once`() throws {
        let ctx = try makeContext()
        let older = makeItem(ctx, substance: drug, trackingStart: now, initial: 180)
        older.createdAt = now
        let newer = makeItem(ctx, substance: drug.uppercased(), trackingStart: now.addingTimeInterval(3_600), initial: 270)
        newer.createdAt = now.addingTimeInterval(3_600)
        newer.baselineQuantity = 450
        let olderID = older.id
        logDose(ctx, amount: 3, at: 2)

        let newerID = newer.id
        #expect(InventoryService.mergeDuplicateItems(in: ctx) == [newerID])

        let items = try allItems(ctx)
        #expect(items.count == 1)
        let kept = try #require(items.first)
        #expect(kept.id == olderID)
        #expect(kept.trackingStart == now)
        #expect(kept.manualEvents.map(\.amount) == [180, 270])
        #expect(kept.baselineQuantity == 450)
        #expect(kept.currentQuantity == 447)
        #expect(InventoryService.mergeDuplicateItems(in: ctx).isEmpty)
    }

    @Test
    func `mergeDuplicateItems converts a duplicate into the keeper's unit`() throws {
        let ctx = try makeContext()
        let keeper = makeItem(ctx, unit: "mg", initial: 500)
        keeper.createdAt = now
        let dup = makeItem(ctx, unit: "g", initial: 1)
        dup.createdAt = now.addingTimeInterval(60)

        InventoryService.mergeDuplicateItems(in: ctx)

        #expect(try allItems(ctx).count == 1)
        #expect(keeper.unit == "mg")
        #expect(keeper.currentQuantity == 1_500)
    }

    @Test
    func `mergeDuplicateItems leaves an unreconcilable duplicate alone`() throws {
        let ctx = try makeContext()
        let keeper = makeItem(ctx, unit: "mg", initial: 500)
        keeper.createdAt = now
        let dup = makeItem(ctx, unit: "mL", initial: 30)
        dup.createdAt = now.addingTimeInterval(60)

        #expect(InventoryService.mergeDuplicateItems(in: ctx).isEmpty)
        #expect(try allItems(ctx).count == 2)
    }

    // MARK: - Count × strength

    @Test
    func `A scanned pack opens as a count at its strength and is stored that way`() throws {
        let ctx = try makeContext()
        let draft = InventoryAmountDraft(
            prefill: InventoryPrefill(count: 28, unit: "tabs", strengthMG: 36, note: nil),
            existingItem: nil,
        )
        #expect(draft.mode == .pieces)
        let stated = draft.stated
        #expect(stated.amount == 28)
        #expect(stated.unit == "tabs")
        #expect(stated.unitStrengthMG == 36)

        let item = InventoryService.create(
            substance: drug, saltForm: nil, unit: stated.unit, initial: stated.amount,
            threshold: nil, setBaseline: false, unitStrengthMG: stated.unitStrengthMG, in: ctx,
        )
        #expect(item.unit == "tabs")
        #expect(item.currentQuantity == 28)
        #expect(item.unitStrengthMG == 36)
        #expect(item.doseSize == nil)
    }

    @Test
    func `A bare piece count defaults to tabs, a liquid stays an amount`() {
        let pieces = InventoryAmountDraft(prefill: InventoryPrefill(count: 30, unit: nil, strengthMG: nil, note: nil), existingItem: nil)
        #expect(pieces.mode == .pieces)
        #expect(pieces.countUnit == "tabs")
        #expect(pieces.strengthMG == 0)

        let liquid = InventoryAmountDraft(prefill: InventoryPrefill(count: 118, unit: "mL", strengthMG: nil, note: nil), existingItem: nil)
        #expect(liquid.mode == .amount)
        #expect(liquid.stated.unit == "mL")
        #expect(liquid.stated.amount == 118)
    }

    @Test
    func `A restock from a scanned box adopts a counted item's unit and fills its strength`() throws {
        let ctx = try makeContext()
        let caps = makeItem(ctx, unit: "caps", initial: 10)
        let draft = InventoryAmountDraft(
            prefill: InventoryPrefill(count: 30, unit: "tabs", strengthMG: 3, note: nil),
            existingItem: caps,
        )
        #expect(draft.mode == .pieces)
        #expect(draft.countUnit == "caps")
        #expect(draft.restockAmount(for: caps) == 30)

        InventoryService.restock(caps, amount: 30, note: nil, setBaseline: false, unitStrengthMG: 3, in: ctx)
        #expect(caps.unitStrengthMG == 3)
        #expect(caps.currentQuantity == 40)
    }

    @Test
    func `unitStrengthMG survives an export round-trip`() throws {
        let ctx = try makeContext()
        InventoryService.create(
            substance: drug, saltForm: nil, unit: "tabs", initial: 28,
            threshold: nil, setBaseline: false, unitStrengthMG: 36, in: ctx,
        )
        try ctx.save()
        let data = try DataExportImport.exportJSON(context: ctx)
        try DataExportImport.deleteAll(context: ctx)
        try ctx.save()

        try DataExportImport.importJSON(data: data, context: ctx)

        let item = try #require(try allItems(ctx).first)
        #expect(item.unit == "tabs")
        #expect(item.unitStrengthMG == 36)
        #expect(item.currentQuantity == 28)
    }

    @Test
    func `A restock stated as a box reconciles into the item's unit`() throws {
        let ctx = try makeContext()
        let milligrams = makeItem(ctx, unit: "mg", initial: 90)
        let draft = InventoryAmountDraft(prefill: nil, existingItem: milligrams)
        draft.mode = .pieces
        draft.count = 30
        draft.strengthMG = 3
        #expect(draft.restockAmount(for: milligrams) == 90)

        let liquid = makeItem(ctx, substance: "ZZLiquid", unit: "mL", initial: 30)
        #expect(draft.restockAmount(for: liquid) == nil)
    }
}
