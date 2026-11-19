import Foundation
import SwiftData
import Testing
@testable import Piru

@Suite("Profiles — shared inventory")
@MainActor
struct SharedInventoryTests {
    private static let start = Date(timeIntervalSince1970: 1_800_000_000)

    private static func at(_ hours: Double) -> Date {
        start.addingTimeInterval(hours * 3_600)
    }

    private static func item(
        _ substance: String, amount: Double, isomer: String? = nil, saltForm: String? = nil,
        threshold: Double? = nil, since: Date = start, sharedWith: [UUID] = [],
    ) -> InventoryItem {
        let item = InventoryItem(
            substance: substance, saltForm: saltForm, isomer: isomer, unit: "mg", trackingStart: since,
            lowStockThreshold: threshold,
            manualEvents: [ManualEvent(kind: .initial, amount: amount, date: since)], createdAt: since,
        )
        item.sharedWith = sharedWith
        return item
    }

    private static func dose(
        _ substance: String, _ amount: Double, unit: String = "mg", isomer: String? = nil, saltForm: String? = nil, at date: Date,
    ) -> DoseEntry {
        DoseEntry(substance: substance, amount: amount, unit: unit, saltForm: saltForm, isomer: isomer, timestamp: date)
    }

    private static func context(_ directory: ProfileDirectory, _ id: UUID) throws -> ModelContext {
        try #require(directory.container(for: id, writable: true)).mainContext
    }

    @Test
    func `Stock counts every sharee's doses since tracking began, each in its own unit`() async throws {
        let (directory, _) = try makeScratchProfileDirectory()
        let alice = try directory.addProfile(name: "Alice")
        let mine = directory.activeContainer.mainContext
        let stock = Self.item("Caffeine", amount: 1_000, sharedWith: [alice.id])
        mine.insert(stock)
        mine.insert(Self.dose("Caffeine", 100, at: Self.at(1)))
        mine.insert(Self.dose("Caffeine", 300, at: Self.at(-1)))
        try mine.save()
        let theirs = try Self.context(directory, alice.id)
        theirs.insert(Self.dose("Caffeine", 200, at: Self.at(2)))
        theirs.insert(Self.dose("Caffeine", 0.05, unit: "g", at: Self.at(3)))
        theirs.insert(Self.dose("Caffeine", 400, at: Self.at(-2)))
        try theirs.save()

        let shared = SharedInventory(directory: directory)
        await shared.refresh(notify: false)

        // 1,000 − 100 (mine) − 200 − 50 (Alice's 0.05 g); both pre-start doses ignored.
        #expect(stock.currentQuantity == 650)
        #expect(SharedInventory.foreignDoses(for: stock).map(\.amount).sorted() == [0.05, 200])
        #expect(InventoryMath.quantity(for: stock, in: mine) == 650)

        // Unsharing drops her doses on the next pass.
        stock.sharedWith = []
        try mine.save()
        await shared.refresh(notify: false)
        #expect(stock.currentQuantity == 900)
        #expect(SharedInventory.foreignDoses(for: stock).isEmpty)
    }

    @Test
    func `A sharee's dose goes to the shared item of its form, or the plain one`() async throws {
        let (directory, _) = try makeScratchProfileDirectory()
        let alice = try directory.addProfile(name: "Alice")
        let mine = directory.activeContainer.mainContext
        let dextro = Self.item("Amphetamine", amount: 100, isomer: "D", sharedWith: [alice.id])
        let plain = Self.item("Amphetamine", amount: 100, sharedWith: [alice.id])
        let sulfate = Self.item("Amphetamine", amount: 100, saltForm: "sulfate")
        for item in [dextro, plain, sulfate] {
            mine.insert(item)
        }
        try mine.save()
        let theirs = try Self.context(directory, alice.id)
        theirs.insert(Self.dose("Amphetamine", 10, isomer: "D", at: Self.at(1)))
        theirs.insert(Self.dose("Amphetamine", 5, at: Self.at(2)))
        theirs.insert(Self.dose("Amphetamine", 7, isomer: "D", saltForm: "sulfate", at: Self.at(3)))
        theirs.insert(Self.dose("Caffeine", 100, at: Self.at(4)))
        try theirs.save()

        await SharedInventory(directory: directory).refresh(notify: false)

        #expect(dextro.currentQuantity == 90)
        #expect(plain.currentQuantity == 95)
        // The sulfate stock is not shared, so her sulfate dose touches nothing of mine.
        InventoryService.recomputeAll(in: mine, notify: false)
        #expect(sulfate.currentQuantity == 100)
    }

    @Test
    func `A sharee's own item takes her dose before a shared one does`() async throws {
        let (directory, _) = try makeScratchProfileDirectory()
        let alice = try directory.addProfile(name: "Alice")
        let mine = directory.activeContainer.mainContext
        let shared = Self.item("Caffeine", amount: 1_000, sharedWith: [alice.id])
        mine.insert(shared)
        try mine.save()
        let theirs = try Self.context(directory, alice.id)
        // Her own caffeine starts tracking at hour 10.
        let hers = Self.item("Caffeine", amount: 500, since: Self.at(10))
        theirs.insert(hers)
        theirs.insert(Self.dose("Caffeine", 100, at: Self.at(5)))
        theirs.insert(Self.dose("Caffeine", 50, at: Self.at(12)))
        try theirs.save()

        await SharedInventory(directory: directory).refresh(notify: false)
        InventoryService.recomputeAll(in: theirs, notify: false)

        // Before her item existed the shared one took her dose; after, hers does.
        #expect(shared.currentQuantity == 900)
        #expect(hers.currentQuantity == 450)
    }

    @Test
    func `A shared item shows in the sharee's inventory and her restock lands in the owner's store`() async throws {
        let (directory, _) = try makeScratchProfileDirectory()
        let alice = try directory.addProfile(name: "Alice")
        let mine = directory.activeContainer.mainContext
        let stock = Self.item("Caffeine", amount: 1_000, sharedWith: [alice.id])
        mine.insert(stock)
        try mine.save()
        let aliceContainer = try #require(directory.activate(alice.id))
        aliceContainer.mainContext.insert(Self.dose("Caffeine", 100, at: Self.at(1)))
        try aliceContainer.mainContext.save()

        let shared = SharedInventory(directory: directory)
        await shared.refresh(notify: false)
        let entry = try #require(shared.sharedIn.first)
        #expect(shared.sharedIn.count == 1)
        #expect(entry.ownerID == directory.owner.id)
        #expect(shared.owner(of: entry.item)?.id == directory.owner.id)
        #expect(shared.item(id: stock.id, in: aliceContainer.mainContext) === entry.item)
        #expect(entry.item.currentQuantity == 900)

        let item = entry.item
        let ownerContext = try #require(item.modelContext)
        SharedInventory.write(to: item, directory: directory) {
            InventoryService.restock(item, amount: 250, note: "Alice's top-up", setBaseline: false, in: ownerContext)
        }
        #expect(item.currentQuantity == 1_150)

        let ownerStore = try #require(directory.container(for: directory.owner.id, writable: false))
        let stored = try #require(ModelContext(ownerStore).fetch(FetchDescriptor<InventoryItem>()).first)
        #expect(stored.manualEvents.map(\.note).contains("Alice's top-up"))
        #expect(try aliceContainer.mainContext.fetchCount(FetchDescriptor<InventoryItem>()) == 0)
    }

    @Test
    func `A sharee's dose that crosses the threshold alerts the owner`() async throws {
        let (directory, _) = try makeScratchProfileDirectory()
        let alice = try directory.addProfile(name: "Alice")
        let mine = directory.activeContainer.mainContext
        let stock = Self.item("Caffeine", amount: 200, threshold: 100, sharedWith: [alice.id])
        mine.insert(stock)
        try mine.save()
        let aliceContainer = try #require(directory.activate(alice.id))
        aliceContainer.mainContext.insert(Self.dose("Caffeine", 150, at: Self.at(1)))
        try aliceContainer.mainContext.save()

        let alerts = await SharedInventory(directory: directory).refresh()

        #expect(alerts == [SharedInventory.Alert(profileID: directory.owner.id, itemID: stock.id)])
        #expect(stock.lowStockNotified)
    }

    @Test
    func `Deleting a profile takes it off every shared item in every store`() async throws {
        let (directory, _) = try makeScratchProfileDirectory()
        let alice = try directory.addProfile(name: "Alice")
        let bob = try directory.addProfile(name: "Bob")
        let mine = directory.activeContainer.mainContext
        let stock = Self.item("Caffeine", amount: 100, sharedWith: [alice.id, bob.id])
        mine.insert(stock)
        try mine.save()
        let bobs = try Self.context(directory, bob.id)
        let bobStock = Self.item("Ketamine", amount: 100, sharedWith: [alice.id])
        bobs.insert(bobStock)
        try bobs.save()

        let shared = SharedInventory(directory: directory)
        try directory.deleteProfile(id: alice.id)
        await shared.profileDeleted(alice.id)

        #expect(stock.sharedWith == [bob.id])
        #expect(bobStock.sharedWith.isEmpty)
        #expect(shared.entries.map(\.item.id) == [stock.id])
    }

    @Test
    func `Who an item is shared with survives a backup and a restore`() throws {
        let (source, _) = try makeScratchProfileDirectory()
        let alice = try source.addProfile(name: "Alice")
        let bob = try source.addProfile(name: "Bob")
        let mine = source.activeContainer.mainContext
        mine.insert(Self.item("Caffeine", amount: 100, sharedWith: [alice.id, bob.id]))
        try mine.save()
        let bobs = try Self.context(source, bob.id)
        bobs.insert(Self.item("Ketamine", amount: 100, sharedWith: [source.owner.id]))
        try bobs.save()

        let data = try DataExportImport.exportBackupJSON(context: mine, directory: source)
        let (restored, _) = try makeScratchProfileDirectory()
        try BackupManager.shared.apply(
            plaintext: data, strategy: .merge, context: restored.activeContainer.mainContext, directory: restored,
        )

        let restoredMine = try restored.activeContainer.mainContext.fetch(FetchDescriptor<InventoryItem>())
        #expect(restoredMine.map(\.sharedWith) == [[alice.id, bob.id].sorted { $0.uuidString < $1.uuidString }])
        let restoredBob = try Self.context(restored, bob.id).fetch(FetchDescriptor<InventoryItem>())
        #expect(restoredBob.map(\.sharedWith) == [[restored.owner.id]])
    }
}
