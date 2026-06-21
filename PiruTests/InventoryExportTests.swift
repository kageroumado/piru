import Foundation
import SwiftData
import Testing
@testable import Piru

@MainActor
@Suite("Inventory — export/import")
struct InventoryExportTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(StoreRecovery.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none),
        )
        return ModelContext(container)
    }

    private let drug = "ZZTestInventorySubstance"
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    /// Build a tracked item (initial 100 mg, baseline 100, threshold 10, dose
    /// size 25) with one 30 mg dose, so live stock is 70.
    private func seed(_ ctx: ModelContext) {
        let item = InventoryItem(
            substance: drug,
            unit: "mg",
            trackingStart: start,
            lowStockThreshold: 10,
            baselineQuantity: 100,
            doseSize: 25,
            manualEvents: [ManualEvent(kind: .initial, amount: 100, date: start, setsBaseline: true)],
            createdAt: start,
        )
        ctx.insert(item)
        ctx.insert(DoseEntry(substance: drug, amount: 30, unit: "mg", timestamp: start.addingTimeInterval(3_600)))
        InventoryService.recompute(item, in: ctx)
    }

    @Test
    func `Round-trip reproduces stock exactly`() throws {
        let ctx = try makeContext()
        seed(ctx)
        try ctx.save()
        #expect(InventoryService.find(substance: drug, saltForm: nil, in: ctx)?.currentQuantity == 70)

        let data = try DataExportImport.exportJSON(context: ctx)
        try DataExportImport.deleteAll(context: ctx)
        try ctx.save()
        #expect(try ctx.fetch(FetchDescriptor<InventoryItem>()).isEmpty)

        try DataExportImport.importJSON(data: data, context: ctx)
        try ctx.save()

        let items = try ctx.fetch(FetchDescriptor<InventoryItem>())
        #expect(items.count == 1)
        let item = try #require(items.first)
        #expect(item.substance == drug)
        #expect(item.unit == "mg")
        #expect(item.baselineQuantity == 100)
        #expect(item.lowStockThreshold == 10)
        #expect(item.doseSize == 25)
        #expect(abs(item.trackingStart.timeIntervalSince(start)) < 1)
        #expect(item.manualEvents.count == 1)
        #expect(item.manualEvents.first?.setsBaseline == true)
        // The dose was re-imported too, so derived stock matches the source: 70.
        #expect(item.currentQuantity == 70)
    }

    @Test
    func `Re-importing the same file is idempotent`() throws {
        let ctx = try makeContext()
        seed(ctx)
        try ctx.save()
        let data = try DataExportImport.exportJSON(context: ctx)

        // Import on top of the existing data twice.
        try DataExportImport.importJSON(data: data, context: ctx)
        try DataExportImport.importJSON(data: data, context: ctx)
        try ctx.save()

        let items = try ctx.fetch(FetchDescriptor<InventoryItem>())
        #expect(items.count == 1) // merged by (substance, salt), not duplicated
        let item = try #require(items.first)
        #expect(item.manualEvents.count == 1) // events unioned by id
        #expect(item.currentQuantity == 70) // dose deduped by content
    }

    @Test
    func `Import merges events into an existing item, keeping earliest start`() throws {
        // Source file: item created at `start` with the initial event.
        let source = try makeContext()
        seed(source)
        try source.save()
        let data = try DataExportImport.exportJSON(context: source)

        // Destination already has the same substance, tracked LATER, with a
        // different restock event.
        let dest = try makeContext()
        let laterStart = start.addingTimeInterval(10 * 86_400)
        let destItem = InventoryItem(
            substance: drug,
            unit: "mg",
            trackingStart: laterStart,
            manualEvents: [ManualEvent(kind: .restock, amount: 50, date: laterStart)],
            createdAt: laterStart,
        )
        dest.insert(destItem)
        try dest.save()

        try DataExportImport.importJSON(data: data, context: dest)
        try dest.save()

        let items = try dest.fetch(FetchDescriptor<InventoryItem>())
        #expect(items.count == 1) // merged, not duplicated
        let item = try #require(items.first)
        #expect(item.manualEvents.count == 2) // restock (50) + imported initial (100)
        #expect(abs(item.trackingStart.timeIntervalSince(start)) < 1) // earliest wins
    }

    @Test
    func `PsyLog export omits inventory`() throws {
        let ctx = try makeContext()
        seed(ctx)
        try ctx.save()

        let psyLog = try DataExportImport.exportJSON(format: .psyLog, context: ctx)
        let json = try #require(try JSONSerialization.jsonObject(with: psyLog) as? [String: Any])
        #expect(json["inventory"] == nil)

        // Importing the PsyLog file into a clean store creates no inventory.
        let fresh = try makeContext()
        try DataExportImport.importJSON(data: psyLog, context: fresh)
        try fresh.save()
        #expect(try fresh.fetch(FetchDescriptor<InventoryItem>()).isEmpty)
    }
}
