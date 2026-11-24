import Foundation
import SwiftData
import Testing
@testable import Piru

/// The med detail screen resolves its med from the store on every change, so a
/// med deleted or replaced underneath it (Delete Med, Delete Everything, a
/// restore) is never read.
@MainActor
@Suite("MedDetailRoute")
struct MedDetailRouteTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(PiruSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none),
        )
        return ModelContext(container)
    }

    private func items(_ context: ModelContext) throws -> [DailyDoseItem] {
        try context.fetch(FetchDescriptor<DailyDoseItem>(sortBy: [SortDescriptor(\.sortOrder)]))
    }

    @Test
    func `Resolves the med by identity and position`() throws {
        let context = try makeContext()
        let oral = DailyDoseItem(substance: "ZZTestMed", amount: 10, sortOrder: 0)
        let second = DailyDoseItem(substance: "ZZTestMed", amount: 20, sortOrder: 1)
        context.insert(oral)
        context.insert(second)
        try context.save()

        let resolved = try MedDetailRoute.resolve(identityKey: second.identityKey, sortOrder: 1, in: items(context))
        #expect(resolved === second)
    }

    @Test
    func `A reordered med still resolves by identity`() throws {
        let context = try makeContext()
        let med = DailyDoseItem(substance: "ZZTestMed", amount: 10, sortOrder: 3)
        context.insert(med)
        try context.save()

        let resolved = try MedDetailRoute.resolve(identityKey: med.identityKey, sortOrder: 0, in: items(context))
        #expect(resolved === med)
    }

    @Test
    func `A deleted med resolves to nothing, before and after the save`() throws {
        let context = try makeContext()
        let med = DailyDoseItem(substance: "ZZTestMed", amount: 10, sortOrder: 0)
        context.insert(med)
        try context.save()
        let key = med.identityKey
        let held = try items(context)

        context.delete(med)
        #expect(MedDetailRoute.resolve(identityKey: key, sortOrder: 0, in: held) == nil)
        try context.save()
        #expect(MedDetailRoute.resolve(identityKey: key, sortOrder: 0, in: held) == nil)
        #expect(try MedDetailRoute.resolve(identityKey: key, sortOrder: 0, in: items(context)) == nil)
    }

    @Test
    func `A wipe leaves no med to resolve, and a restored one resolves to the new row`() throws {
        let context = try makeContext()
        let med = DailyDoseItem(substance: "ZZTestMed", amount: 10, sortOrder: 0)
        context.insert(med)
        try context.save()
        let key = med.identityKey
        let held = try items(context)

        try PiruSchema.deleteAll(in: context)
        #expect(MedDetailRoute.resolve(identityKey: key, sortOrder: 0, in: held) == nil)

        let restored = DailyDoseItem(substance: "ZZTestMed", amount: 10, sortOrder: 0)
        context.insert(restored)
        try context.save()
        #expect(try MedDetailRoute.resolve(identityKey: key, sortOrder: 0, in: items(context)) === restored)
    }
}
