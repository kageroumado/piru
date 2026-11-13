import Foundation
import SwiftData
import Testing
@testable import Piru

/// Inventory items narrowed to an isomer or a product: which item each dose
/// deducts from, and that the narrowing survives a backup.
@MainActor
@Suite("Inventory — form routing")
struct InventoryFormRoutingTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(PiruSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none),
        )
        return ModelContext(container)
    }

    /// Absent from the substance library, so nothing depends on bundled data.
    private let drug = "ZZTestInventoryFormSubstance"
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeItem(
        _ ctx: ModelContext,
        isomer: String? = nil,
        productName: String? = nil,
        unit: String = "mg",
        unitStrengthMG: Double? = nil,
        initial: Double = 100,
        startHours: Double = 0,
        createdHours: Double = 0,
    ) -> InventoryItem {
        let start = now.addingTimeInterval(startHours * 3_600)
        let item = InventoryItem(
            substance: drug,
            isomer: isomer,
            productName: productName,
            unit: unit,
            trackingStart: start,
            unitStrengthMG: unitStrengthMG,
            manualEvents: [ManualEvent(kind: .initial, amount: initial, date: start)],
            createdAt: now.addingTimeInterval(createdHours * 3_600),
        )
        ctx.insert(item)
        return item
    }

    @discardableResult
    private func logDose(
        _ ctx: ModelContext,
        amount: Double,
        isomer: String? = nil,
        productName: String? = nil,
        at hours: Double = 1,
    ) -> DoseEntry {
        let entry = DoseEntry(
            substance: drug, amount: amount, isomer: isomer, productName: productName,
            timestamp: now.addingTimeInterval(hours * 3_600),
        )
        ctx.insert(entry)
        return entry
    }

    // MARK: - Routing

    @Test
    func `An isomer dose deducts from the isomer item only`() throws {
        let ctx = try makeContext()
        let plain = makeItem(ctx)
        let dextro = makeItem(ctx, isomer: "D")
        logDose(ctx, amount: 10, isomer: "D")
        logDose(ctx, amount: 20)
        InventoryService.recomputeAll(in: ctx)
        #expect(dextro.currentQuantity == 90)
        #expect(plain.currentQuantity == 80)
    }

    @Test
    func `A product dose deducts from the product item, matched case-insensitively`() throws {
        let ctx = try makeContext()
        let plain = makeItem(ctx)
        let product = makeItem(ctx, productName: "Brandol")
        logDose(ctx, amount: 15, productName: "brandol")
        InventoryService.recomputeAll(in: ctx)
        #expect(product.currentQuantity == 85)
        #expect(plain.currentQuantity == 100)
    }

    @Test
    func `A dose no narrower item claims falls back to the plain item`() throws {
        let ctx = try makeContext()
        let plain = makeItem(ctx)
        let dextro = makeItem(ctx, isomer: "D")
        logDose(ctx, amount: 5, isomer: "L")
        logDose(ctx, amount: 7, productName: "Otherbrand")
        InventoryService.recomputeAll(in: ctx)
        #expect(plain.currentQuantity == 88)
        #expect(dextro.currentQuantity == 100)
    }

    @Test
    func `With no plain item an unclaimed dose deducts from nothing`() throws {
        let ctx = try makeContext()
        let dextro = makeItem(ctx, isomer: "D")
        logDose(ctx, amount: 10)
        InventoryService.recomputeAll(in: ctx)
        #expect(dextro.currentQuantity == 100)
    }

    @Test
    func `A product outranks an isomer for a dose naming both`() throws {
        let ctx = try makeContext()
        let plain = makeItem(ctx)
        let dextro = makeItem(ctx, isomer: "D")
        let product = makeItem(ctx, productName: "Brandol")
        logDose(ctx, amount: 10, isomer: "D", productName: "Brandol")
        InventoryService.recomputeAll(in: ctx)
        #expect(product.currentQuantity == 90)
        #expect(dextro.currentQuantity == 100)
        #expect(plain.currentQuantity == 100)
    }

    @Test
    func `A dose before the narrower item started stays with the plain item`() throws {
        let ctx = try makeContext()
        let plain = makeItem(ctx)
        let dextro = makeItem(ctx, isomer: "D", startHours: 24, createdHours: 24)
        logDose(ctx, amount: 10, isomer: "D", at: 1)
        logDose(ctx, amount: 4, isomer: "D", at: 30)
        InventoryService.recomputeAll(in: ctx)
        #expect(plain.currentQuantity == 90)
        #expect(dextro.currentQuantity == 96)
    }

    @Test
    func `Every dose is counted exactly once across the items`() throws {
        let ctx = try makeContext()
        let items = [makeItem(ctx), makeItem(ctx, isomer: "D"), makeItem(ctx, productName: "Brandol")]
        logDose(ctx, amount: 1)
        logDose(ctx, amount: 2, isomer: "D")
        logDose(ctx, amount: 4, productName: "Brandol")
        logDose(ctx, amount: 8, isomer: "D", productName: "Brandol")
        logDose(ctx, amount: 16, isomer: "S")
        InventoryService.recomputeAll(in: ctx)
        let consumed = items.reduce(0.0) { $0 + (100 - $1.currentQuantity) }
        #expect(consumed == 31)
    }

    @Test
    func `The single-item path routes the same as the batch`() throws {
        let ctx = try makeContext()
        let plain = makeItem(ctx)
        let dextro = makeItem(ctx, isomer: "D")
        logDose(ctx, amount: 10, isomer: "D")
        logDose(ctx, amount: 20)
        #expect(InventoryMath.quantity(for: plain, in: ctx) == 80)
        #expect(InventoryMath.quantity(for: dextro, in: ctx) == 90)
        #expect(InventoryMath.doses(for: dextro, in: ctx).map(\.amount) == [10])
    }

    @Test
    func `A counted isomer item draws down in pieces at its strength`() throws {
        let ctx = try makeContext()
        let plain = makeItem(ctx)
        let tabs = makeItem(ctx, isomer: "D", unit: "tabs", unitStrengthMG: 5, initial: 30)
        logDose(ctx, amount: 10, isomer: "D")
        InventoryService.recomputeAll(in: ctx)
        #expect(tabs.currentQuantity == 28)
        #expect(plain.currentQuantity == 100)
    }

    @Test
    func `The scoped off-main recompute routes by form`() async throws {
        let ctx = try makeContext()
        let plain = makeItem(ctx)
        let dextro = makeItem(ctx, isomer: "D")
        logDose(ctx, amount: 10, isomer: "D")
        logDose(ctx, amount: 20)
        await InventoryService.recompute(forSubstances: [drug], replayingOffMainIn: ctx, notify: false)
        #expect(dextro.currentQuantity == 90)
        #expect(plain.currentQuantity == 80)
    }

    // MARK: - Identity

    @Test
    func `find and create key on the form, so forms are separate items`() throws {
        let ctx = try makeContext()
        let plain = InventoryService.create(
            substance: drug, saltForm: nil, unit: "mg", initial: 100, threshold: nil, setBaseline: false, in: ctx,
        )
        let dextro = InventoryService.create(
            substance: drug, saltForm: nil, isomer: "D", unit: "mg", initial: 50, threshold: nil, setBaseline: false, in: ctx,
        )
        let again = InventoryService.create(
            substance: drug, saltForm: nil, isomer: "D", unit: "mg", initial: 25, threshold: nil, setBaseline: false, in: ctx,
        )
        #expect(plain !== dextro)
        #expect(again === dextro)
        #expect(dextro.currentQuantity == 75)
        #expect(InventoryService.find(substance: drug, saltForm: nil, in: ctx) === plain)
        #expect(InventoryService.find(substance: drug, saltForm: nil, isomer: "D", in: ctx) === dextro)
        #expect(InventoryService.find(substance: drug, saltForm: nil, productName: "Brandol", in: ctx) == nil)
    }

    @Test
    func `stock finds the item a med's dose would draw on`() throws {
        let ctx = try makeContext()
        let plain = makeItem(ctx)
        let dextro = makeItem(ctx, isomer: "D")
        let items = [plain, dextro]
        let later = now.addingTimeInterval(3_600)
        #expect(InventoryService.stock(substance: drug, saltForm: nil, isomer: "D", productName: nil, among: items, at: later) === dextro)
        #expect(InventoryService.stock(substance: drug, saltForm: nil, isomer: nil, productName: nil, among: items, at: later) === plain)
        #expect(InventoryService.stock(substance: drug, saltForm: "HCl", isomer: "D", productName: nil, among: items, at: later) === dextro)
    }

    @Test
    func `The display lookup prefers the plain item`() throws {
        let ctx = try makeContext()
        let dextro = makeItem(ctx, isomer: "D")
        let plain = makeItem(ctx)
        #expect(InventoryService.find(substance: drug, preferringSalt: nil, among: [dextro, plain]) === plain)
    }

    @Test
    func `Merging duplicates keeps distinct forms apart`() throws {
        let ctx = try makeContext()
        _ = makeItem(ctx)
        _ = makeItem(ctx, isomer: "D")
        _ = makeItem(ctx, isomer: "D", createdHours: 1)
        let merged = InventoryService.mergeDuplicateItems(in: ctx)
        #expect(merged.count == 1)
        let remaining = try ctx.fetch(FetchDescriptor<InventoryItem>())
        #expect(remaining.count == 2)
        #expect(Set(remaining.map(\.isomer)) == [nil, "D"])
    }

    // MARK: - Backup

    @Test
    func `A backup round-trip keeps each item's form and stock`() throws {
        let ctx = try makeContext()
        _ = makeItem(ctx)
        let dextro = makeItem(ctx, isomer: "D")
        dextro.displayNameSnapshot = "ZZ Dextro"
        _ = makeItem(ctx, productName: "Brandol")
        logDose(ctx, amount: 10, isomer: "D")
        logDose(ctx, amount: 20)
        logDose(ctx, amount: 30, productName: "Brandol")
        InventoryService.recomputeAll(in: ctx)
        try ctx.save()

        let data = try DataExportImport.exportJSON(context: ctx)
        try DataExportImport.deleteAll(context: ctx)
        try ctx.save()
        try DataExportImport.importJSON(data: data, context: ctx)
        try ctx.save()

        let items = try ctx.fetch(FetchDescriptor<InventoryItem>())
        #expect(items.count == 3)
        let byForm = Dictionary(uniqueKeysWithValues: items.map { ("\($0.isomer ?? "-")|\($0.productName ?? "-")", $0) })
        #expect(byForm["-|-"]?.currentQuantity == 80)
        #expect(byForm["D|-"]?.currentQuantity == 90)
        #expect(byForm["D|-"]?.displayNameSnapshot == "ZZ Dextro")
        #expect(byForm["-|Brandol"]?.currentQuantity == 70)

        // A second import of the same file merges by form rather than duplicating.
        try DataExportImport.importJSON(data: data, context: ctx)
        try ctx.save()
        #expect(try ctx.fetch(FetchDescriptor<InventoryItem>()).count == 3)
    }

    @Test
    func `A backup written before forms existed imports as a plain item`() throws {
        let source = try makeContext()
        _ = makeItem(source, isomer: "D")
        logDose(source, amount: 10, isomer: "D")
        InventoryService.recomputeAll(in: source)
        try source.save()

        // Strip the form keys, as a file from an older build lacks them.
        var json = try #require(try JSONSerialization.jsonObject(with: DataExportImport.exportJSON(context: source)) as? [String: Any])
        var inventory = try #require(json["inventory"] as? [[String: Any]])
        for index in inventory.indices {
            #expect(inventory[index]["isomer"] as? String == "D")
            inventory[index]["isomer"] = nil
            inventory[index]["productName"] = nil
            inventory[index]["displayNameSnapshot"] = nil
        }
        json["inventory"] = inventory
        let oldFile = try JSONSerialization.data(withJSONObject: json)

        let dest = try makeContext()
        try DataExportImport.importJSON(data: oldFile, context: dest)
        try dest.save()
        let item = try #require(try dest.fetch(FetchDescriptor<InventoryItem>()).first)
        #expect(item.isPlain)
        #expect(item.currentQuantity == 90)
    }
}
