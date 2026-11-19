import Foundation
import PortableData
import Testing

/// Contract items 3 and 4: a save writes only what changed, in one transaction, and
/// contexts see each other's saves without ever overwriting or resurrecting each other's rows.
@Suite("Saves between contexts")
struct ContextTests {
    let store = TestStore()

    /// ToleranceStore.persist's shape: a background context that fetched only the tolerance
    /// cache saves it while the main context has edited and deleted journal entries.
    @Test
    func `A background tolerance save preserves a concurrent journal edit and delete`() throws {
        let seeded = try seedJournal(store)
        let container = try store.container()
        let main = ModelContext(container)
        let background = ModelContext(container)

        let cache = try #require(try background.fetch(FetchDescriptor<ToleranceState>()).first)
        let doses = try main.doses()
        doses[0].amount = 999
        main.delete(doses[1])
        try main.save()

        cache.sAcute = 0.75
        try background.save()

        let reread = try ModelContext(store.container())
        let stored = try reread.doses()
        #expect(stored.map(\.id) == [seeded.doses[0], seeded.doses[2]])
        #expect(stored.first?.amount == 999)
        #expect(try reread.fetch(FetchDescriptor<ToleranceState>()).first?.sAcute == 0.75)
    }

    @Test
    func `A background save from a stale copy of the journal preserves the main context's edit and delete`() throws {
        let seeded = try seedJournal(store)
        let container = try store.container()
        let main = ModelContext(container)
        let background = ModelContext(container)
        // The background context holds the journal as it was before the main context's edits.
        #expect(try background.doses().count == 3)
        let cache = try #require(try background.fetch(FetchDescriptor<ToleranceState>()).first)

        let doses = try main.doses()
        doses[0].amount = 999
        main.delete(doses[1])
        try main.save()

        cache.sAcute = 0.75
        try background.save()

        let stored = try ModelContext(store.container()).doses()
        #expect(stored.map(\.id) == [seeded.doses[0], seeded.doses[2]])
        #expect(stored.first?.amount == 999)
        // After its save the background context has caught up with the main context's.
        #expect(try background.doses().map(\.amount) == [999, 102])
    }

    @Test
    func `A main-context save does not revert a tolerance cache another context saved`() throws {
        try seedJournal(store)
        let container = try store.container()
        let main = ModelContext(container)
        let background = ModelContext(container)
        #expect(try main.fetch(FetchDescriptor<ToleranceState>()).first?.sAcute == 0.25)
        _ = try main.doses()

        try #require(try background.fetch(FetchDescriptor<ToleranceState>()).first).sAcute = 0.9
        try background.save()

        try main.doses()[2].notes = "later"
        try main.save()

        let reread = try ModelContext(store.container())
        #expect(try reread.fetch(FetchDescriptor<ToleranceState>()).first?.sAcute == 0.9)
        #expect(try reread.doses()[2].notes == "later")
        #expect(try main.fetch(FetchDescriptor<ToleranceState>()).first?.sAcute == 0.9)
    }

    /// Probe P07: a long-lived context must see doses logged after it loaded.
    @Test
    func `A long-lived context sees another context's insert, edit and delete on its next fetch`() throws {
        try seedJournal(store)
        let container = try store.container()
        let longLived = ModelContext(container)
        let held = try longLived.doses()
        #expect(held.count == 3)

        let main = ModelContext(container)
        let doses = try main.doses()
        doses[0].amount = 5
        main.delete(doses[2])
        main.insert(DoseEntry(substance: "new dose", amount: 1, timestamp: origin.addingTimeInterval(9000)))
        try main.save()

        let seen = try longLived.doses()
        #expect(seen.map(\.substance) == ["caffeine0", "caffeine1", "new dose"])
        // The model the long-lived context already held is updated in place.
        #expect(seen[0] === held[0])
        #expect(held[0].amount == 5)
        #expect(held[2].isDeleted)
        let session = try #require(try longLived.sessions().first)
        #expect(Set((session.doses ?? []).map(\.substance)) == ["caffeine0", "caffeine1"])
    }

    /// Probe P06: a context that loaded only an unrelated entity saves; the journal is untouched.
    @Test
    func `An unrelated context's save never resurrects a deleted row`() throws {
        try seedJournal(store)
        let container = try store.container()
        let main = ModelContext(container)
        let background = ModelContext(container)
        _ = try background.fetch(FetchDescriptor<NotificationPreferences>())
        _ = try background.doses()

        try main.delete(main.doses()[2])
        try main.save()
        #expect(try store.count("DoseEntry") == 2)

        background.insert(FavoriteSubstance(substance: "caffeine"))
        try background.save()
        #expect(try store.count("DoseEntry") == 2)
    }

    @Test
    func `Two contexts editing different properties of one row both keep their change`() throws {
        let seeded = try seedJournal(store)
        let container = try store.container()
        let first = ModelContext(container)
        let second = ModelContext(container)
        let a = try #require(try first.dose(seeded.doses[0]))
        let b = try #require(try second.dose(seeded.doses[0]))

        a.amount = 250
        b.notes = "with food"
        try first.save()
        try second.save()

        let stored = try #require(try ModelContext(store.container()).dose(seeded.doses[0]))
        #expect(stored.amount == 250)
        #expect(stored.notes == "with food")
        // Each context now holds the other's change as well as its own.
        #expect(b.amount == 250)
        #expect(try first.dose(seeded.doses[0])?.notes == "with food")
    }

    @Test
    func `An edit to a row another context deleted does not bring it back`() throws {
        let seeded = try seedJournal(store)
        let container = try store.container()
        let editor = ModelContext(container)
        let deleter = ModelContext(container)
        let dose = try #require(try editor.dose(seeded.doses[1]))

        try deleter.delete(#require(try deleter.dose(seeded.doses[1])))
        try deleter.save()

        dose.amount = 42
        try editor.save()

        #expect(try store.count("DoseEntry") == 2)
        #expect(dose.isDeleted)
        #expect(try editor.dose(seeded.doses[1]) == nil)
    }

    @Test
    func `A context's own unsaved edit survives another context's save of the same property`() throws {
        let seeded = try seedJournal(store)
        let container = try store.container()
        let first = ModelContext(container)
        let second = ModelContext(container)
        let mine = try #require(try first.dose(seeded.doses[0]))
        mine.amount = 1

        try #require(try second.dose(seeded.doses[0])).amount = 2
        try second.save()

        // The refresh on fetch leaves the unsaved edit in place; saving it wins.
        #expect(try first.dose(seeded.doses[0])?.amount == 1)
        try first.save()
        #expect(try ModelContext(store.container()).dose(seeded.doses[0])?.amount == 1)
    }

    @Test
    func `Two containers on one file see each other's saves`() throws {
        try seedJournal(store)
        let reader = try ModelContext(store.container())
        #expect(try reader.doses().count == 3)

        let writer = try ModelContext(store.container())
        writer.insert(DoseEntry(substance: "melatonin", amount: 3, timestamp: origin))
        try writer.save()

        #expect(try reader.doses().count == 4)
    }

    @Test
    func `A save writes only the rows that changed`() throws {
        let seeded = try seedJournal(store)
        let before = try store.generations("DoseEntry")
        let sessions = try store.generations("Session")
        let context = try ModelContext(store.container())
        let dose = try #require(try context.dose(seeded.doses[1]))
        dose.notes = "only this one"
        try context.save()

        let after = try store.generations("DoseEntry")
        let rewritten = after.filter { before[$0.key] != $0.value }
        #expect(rewritten.count == 1)
        #expect(try store.generations("Session") == sessions)
        #expect(try store.rows("DoseEntry")[dose.persistentModelID.primaryKey]?["notes"] as? String == "only this one")
    }

    @Test
    func `Saving with nothing changed writes nothing`() throws {
        try seedJournal(store)
        let before = try store.generations("DoseEntry")
        let context = try ModelContext(store.container())
        _ = try context.doses()
        _ = try context.sessions()
        #expect(!context.hasChanges)
        try context.save()
        #expect(try store.generations("DoseEntry") == before)
    }

    /// Probe P13: a non-finite Double fails the save; written as `null`, it would poison the entity.
    @Test
    func `A value that cannot be encoded fails the whole save and writes nothing`() throws {
        try seedJournal(store)
        let before = try store.generations("ToleranceState")
        let context = try ModelContext(store.container())
        context.insert(FavoriteSubstance(substance: "caffeine"))
        let state = ToleranceState(target: "dopamine", sAcute: .infinity)
        context.insert(state)

        #expect(throws: (any Error).self) { try context.save() }
        #expect(try store.count("FavoriteSubstance") == 0)
        #expect(try store.generations("ToleranceState") == before)

        state.sAcute = 1
        try context.save()
        #expect(try store.count("FavoriteSubstance") == 1)
        #expect(try store.count("ToleranceState") == 2)
    }

    /// Probe P12: numbers and dates come back bit for bit.
    @Test
    func `Doubles and dates round-trip exactly`() throws {
        var values: [Double] = [0.1, 0.1 + 0.2, 1.0 / 3.0, .pi * 1e10, 5e-324, 1.7976931348623157e308, 123_456_789.000_000_1]
        var generator = SystemRandomNumberGenerator()
        for _ in 0 ..< 500 {
            values.append(Double.random(in: -1e6 ... 1e6, using: &generator))
        }
        let context = try ModelContext(store.container())
        for (index, value) in values.enumerated() {
            context.insert(DoseEntry(substance: "s\(index)", amount: abs(value), timestamp: Date(timeIntervalSinceReferenceDate: value)))
        }
        try context.save()

        let stored = try ModelContext(store.container()).fetch(FetchDescriptor<DoseEntry>())
        #expect(stored.count == values.count)
        let expected = Set(values.map(\.bitPattern))
        #expect(stored.allSatisfy { expected.contains($0.timestamp.timeIntervalSinceReferenceDate.bitPattern) })
        #expect(stored.allSatisfy { expected.contains($0.amount.bitPattern) || expected.contains((-$0.amount).bitPattern) })
    }
}
