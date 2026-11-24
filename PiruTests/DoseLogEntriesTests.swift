import Foundation
import SwiftData
import Testing
@testable import Piru

/// ``DoseLogEntries`` hands every screen the dose log it read at the last
/// commit. Each way the log changes has to show in the next read: an add, an
/// edit, a delete, an import, a wipe, and another store.
@MainActor
@Suite("DoseLogEntries", .serialized)
struct DoseLogEntriesTests {
    /// An in-memory store with the full current schema, and the container
    /// that keeps it readable.
    private func makeStore() throws -> (ModelContext, ModelContainer) {
        let container = try ModelContainer(
            for: Schema(PiruSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none),
        )
        return (ModelContext(container), container)
    }

    /// Absent from the substance library, so the tests are independent of
    /// bundled data.
    private let unknown = "ZZDoseLogEntriesSubstance"
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func entry(hours: Double) -> DoseEntry {
        DoseEntry(substance: unknown, amount: 100, timestamp: base.addingTimeInterval(hours * 3_600))
    }

    /// The store's doses as a fresh fetch gives them, pending changes applied.
    private func fetched(_ context: ModelContext) throws -> [UUID] {
        try context.fetch(FetchDescriptor<DoseEntry>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])).map(\.id)
    }

    @Test
    func `A logged dose is in the next read, newest first`() throws {
        let (context, container) = try makeStore()
        defer { withExtendedLifetime(container) {} }
        let log = DoseLogEntries()
        #expect(log.entries(in: context).isEmpty)

        let first = entry(hours: 0)
        DoseLogService.shared.log(first, in: context)
        #expect(log.entries(in: context).map(\.id) == [first.id])

        let earlier = entry(hours: -5)
        let later = entry(hours: 2)
        DoseLogService.shared.logBatch([(earlier, nil), (later, nil)], colors: [], in: context)
        #expect(log.entries(in: context).map(\.id) == [later.id, first.id, earlier.id])
        #expect(try log.entries(in: context).map(\.id) == fetched(context))
    }

    @Test
    func `A deleted dose is gone from the next read, before its delete is saved`() throws {
        let (context, container) = try makeStore()
        defer { withExtendedLifetime(container) {} }
        let log = DoseLogEntries()
        let doses = [entry(hours: 0), entry(hours: 1), entry(hours: 2)]
        DoseLogService.shared.logBatch(doses.map { ($0, nil) }, colors: [], in: context)
        #expect(log.entries(in: context).count == 3)

        let removedID = doses[1].id
        // The delete path's order: delete, signal, and autosave commits later.
        context.delete(doses[1])
        DoseLogService.shared.changed()
        #expect(context.hasChanges)
        #expect(log.entries(in: context).map(\.id) == [doses[2].id, doses[0].id])

        try context.save()
        DoseLogService.shared.changed()
        #expect(!log.entries(in: context).map(\.id).contains(removedID))
        #expect(try log.entries(in: context).map(\.id) == fetched(context))
    }

    @Test
    func `A dose moved in time is re-ordered, before its edit is saved`() throws {
        let (context, container) = try makeStore()
        defer { withExtendedLifetime(container) {} }
        let log = DoseLogEntries()
        let doses = [entry(hours: 0), entry(hours: 1), entry(hours: 2)]
        DoseLogService.shared.logBatch(doses.map { ($0, nil) }, colors: [], in: context)
        #expect(log.entries(in: context).map(\.id) == [doses[2].id, doses[1].id, doses[0].id])

        doses[0].timestamp = base.addingTimeInterval(10 * 3_600)
        DoseLogService.shared.changed()
        #expect(context.hasChanges)
        #expect(log.entries(in: context).map(\.id) == [doses[0].id, doses[2].id, doses[1].id])

        try context.save()
        DoseLogService.shared.changed()
        #expect(log.entries(in: context).map(\.id) == [doses[0].id, doses[2].id, doses[1].id])
        #expect(log.entries(in: context).first?.timestamp == base.addingTimeInterval(10 * 3_600))
    }

    @Test
    func `A dose inserted and not yet saved is in the next read`() throws {
        let (context, container) = try makeStore()
        defer { withExtendedLifetime(container) {} }
        let log = DoseLogEntries()
        let saved = [entry(hours: 0), entry(hours: 4)]
        DoseLogService.shared.logBatch(saved.map { ($0, nil) }, colors: [], in: context)
        _ = log.entries(in: context)

        let middle = entry(hours: 2)
        context.insert(middle)
        DoseLogService.shared.changed()
        #expect(log.entries(in: context).map(\.id) == [saved[1].id, middle.id, saved[0].id])

        try context.save()
        DoseLogService.shared.changed()
        #expect(log.entries(in: context).map(\.id) == [saved[1].id, middle.id, saved[0].id])
    }

    @Test
    func `An import of many doses is read whole`() throws {
        let (context, container) = try makeStore()
        defer { withExtendedLifetime(container) {} }
        let log = DoseLogEntries()
        DoseLogService.shared.log(entry(hours: 0), in: context)
        #expect(log.entries(in: context).count == 1)

        for hour in 1 ... 120 {
            context.insert(entry(hours: Double(hour)))
        }
        try DataExportImport.commitImport(context: context)
        let read = log.entries(in: context)
        #expect(read.count == 121)
        #expect(try read.map(\.id) == fetched(context))
    }

    @Test
    func `A wiped store reads empty, and what is imported after it reads back`() throws {
        let (context, container) = try makeStore()
        defer { withExtendedLifetime(container) {} }
        let log = DoseLogEntries()
        let doses = (0 ..< 5).map { entry(hours: Double($0)) }
        DoseLogService.shared.logBatch(doses.map { ($0, nil) }, colors: [], in: context)
        #expect(log.entries(in: context).count == 5)

        try DataExportImport.deleteAll(context: context)
        DoseLogService.shared.changed()
        #expect(log.entries(in: context).isEmpty)

        let restored = entry(hours: 1)
        context.insert(restored)
        try DataExportImport.commitImport(context: context)
        #expect(log.entries(in: context).map(\.id) == [restored.id])
    }

    @Test
    func `Another store's read holds only that store's doses`() throws {
        let (first, firstContainer) = try makeStore()
        let (second, secondContainer) = try makeStore()
        defer { withExtendedLifetime((firstContainer, secondContainer)) {} }
        let log = DoseLogEntries()
        let mine = entry(hours: 0)
        DoseLogService.shared.log(mine, in: first)
        #expect(log.entries(in: first).map(\.id) == [mine.id])

        let theirs = entry(hours: 1)
        DoseLogService.shared.log(theirs, in: second)
        DoseLogService.shared.storeSwitched()
        #expect(log.entries(in: second).map(\.id) == [theirs.id])
        #expect(log.entries(in: first).map(\.id) == [mine.id])
    }

    @Test
    func `A read hands back the same model objects from one commit to the next`() throws {
        let (context, container) = try makeStore()
        defer { withExtendedLifetime(container) {} }
        let log = DoseLogEntries()
        let doses = [entry(hours: 0), entry(hours: 1)]
        DoseLogService.shared.logBatch(doses.map { ($0, nil) }, colors: [], in: context)
        let before = log.entries(in: context)

        DoseLogService.shared.log(entry(hours: 2), in: context)
        let after = log.entries(in: context)
        #expect(after.count == 3)
        #expect(after[1] === before[0] && after[2] === before[1])
    }

    @Test
    func `A wipe reads empty before the change is signaled`() throws {
        let (context, container) = try makeStore()
        defer { withExtendedLifetime(container) {} }
        let log = DoseLogEntries.shared
        let doses = (0 ..< 3).map { entry(hours: Double($0)) }
        DoseLogService.shared.logBatch(doses.map { ($0, nil) }, colors: [], in: context)
        #expect(log.entries(in: context).count == 3)

        // The wipe saves its deletes; the caller signals after it.
        try DataExportImport.deleteAll(context: context)
        #expect(log.entries(in: context).isEmpty)
    }
}
