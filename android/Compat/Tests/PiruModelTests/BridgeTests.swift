import Foundation
import Synchronization
import Testing
@testable import PortableData

/// The renderer's bridge is made and called on the main thread only, and never by
/// PortableData's own passes over models. On Android each bridge holds a JNI global
/// reference, and Skip's bridge feeds animation state that only the main thread may touch.
@MainActor
@Suite("Observation bridge", .serialized)
struct BridgeTests {
    @Test
    func `Background reads and writes make no bridge and call none, while Observation still hears them`() throws {
        let store = TestStore()
        try seedJournal(store)
        let container = try store.container()
        let bridges = BridgeLog()
        ModelObservation.makeBridge = { CountingBridge(log: bridges) }
        defer { ModelObservation.makeBridge = nil }

        nonisolated(unsafe) let shown = DoseEntry(substance: "caffeine", amount: 80, timestamp: origin)
        _ = shown.amount
        #expect(bridges.made == 1)
        let callsOnMain = bridges.calls

        let observed = onBackgroundThread {
            shown.amount = 90
            _ = shown.substance
            let context = ModelContext(container)
            let doses = (try? context.fetch(FetchDescriptor<DoseEntry>(sortBy: [SortDescriptor(\.timestamp)]))) ?? []
            let fired = Mutex(false)
            withObservationTracking {
                _ = doses.first?.amount
                _ = doses.first?.session?.doses?.count
            } onChange: {
                fired.withLock { $0 = true }
            }
            doses.first?.amount = 1
            return fired.withLock { $0 } && doses.count == 3
        }

        #expect(observed)
        #expect(bridges.made == 1)
        #expect(bridges.calls == callsOnMain)
    }

    @Test
    func `Loading, rebuilding inverses, filtering and sorting make no bridge`() throws {
        let store = TestStore()
        let seeded = try seedJournal(store)
        let context = try ModelContext(store.container())
        let bridges = BridgeLog()
        ModelObservation.makeBridge = { CountingBridge(log: bridges) }
        defer { ModelObservation.makeBridge = nil }

        let cutoff = origin.addingTimeInterval(1800)
        let later = try context.fetch(FetchDescriptor<DoseEntry>(
            predicate: #Predicate { $0.timestamp > cutoff },
            sortBy: [SortDescriptor(\.substance, order: .reverse)],
        ))
        #expect(try context.fetchCount(FetchDescriptor<Session>()) == 1)
        #expect(try context.dose(seeded.doses[0]) != nil)
        #expect(bridges.made == 0)
        #expect(bridges.calls == 0)

        #expect(later.first?.substance == "caffeine2")
        #expect(bridges.made == 1)
        #expect(later.first?.session?.title == "Saturday")
        #expect(bridges.made == 2)
    }

    @Test
    func `A fetch's filter and sort report no read to the bridges views made`() throws {
        let store = TestStore()
        try seedJournal(store)
        let context = try ModelContext(store.container())
        let bridges = BridgeLog()
        ModelObservation.makeBridge = { CountingBridge(log: bridges) }
        defer { ModelObservation.makeBridge = nil }

        let shown = try context.doses()
        for dose in shown {
            _ = dose.timestamp
        }
        #expect(bridges.made == shown.count)
        let calls = bridges.calls

        let sorted = try context.fetch(FetchDescriptor<DoseEntry>(
            predicate: #Predicate { $0.amount > 0 },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)],
        ))
        #expect(sorted.count == shown.count)
        #expect(bridges.calls == calls)
        _ = sorted.first?.amount
        #expect(bridges.calls == calls + 1)
    }

    @Test
    func `Another context's save reaches the bridge of a model a view read, and bridges nothing else`() throws {
        let store = TestStore()
        let seeded = try seedJournal(store)
        let container = try store.container()
        let viewing = ModelContext(container)
        let bridges = BridgeLog()
        ModelObservation.makeBridge = { CountingBridge(log: bridges) }
        defer { ModelObservation.makeBridge = nil }

        let dose = try #require(try viewing.dose(seeded.doses[0]))
        _ = dose.amount
        #expect(bridges.made == 1)

        let editing = ModelContext(container)
        for edited in try editing.doses() {
            edited.amount = 1
        }
        try editing.save()
        _ = try viewing.doses()

        #expect(bridges.writes(to: \DoseEntry.amount) == 1)
        #expect(bridges.made == 1)
        #expect(dose.amount == 1)
    }

    @Test
    func `A write makes no bridge, nor does keeping the inverse side of a relationship`() {
        let bridges = BridgeLog()
        ModelObservation.makeBridge = { CountingBridge(log: bridges) }
        defer { ModelObservation.makeBridge = nil }
        let dose = DoseEntry(substance: "caffeine", amount: 80, timestamp: origin)
        let session = Session(startDate: origin, title: "Saturday")
        dose.amount = 90
        dose.session = session
        #expect(bridges.made == 0)
        _ = dose.amount
        dose.amount = 100
        #expect(bridges.made == 1)
        #expect(bridges.writes(to: \DoseEntry.amount) == 1)
    }

    @Test
    func `Nested and throwing passes leave bridge creation balanced`() throws {
        let bridges = BridgeLog()
        ModelObservation.makeBridge = { CountingBridge(log: bridges) }
        defer { ModelObservation.makeBridge = nil }
        let first = DoseEntry(substance: "caffeine", amount: 80, timestamp: origin)
        let second = DoseEntry(substance: "theanine", amount: 200, timestamp: origin)

        #expect(throws: PassFailed.self) {
            try ModelObservation.traversing {
                ModelObservation.traversing {
                    _ = first.amount
                }
                _ = second.amount
                throw PassFailed()
            }
        }
        #expect(bridges.made == 0)
        #expect(ModelObservation.makesBridges)
        _ = first.amount
        #expect(bridges.made == 1)
    }

    @Test
    func `A save that throws leaves bridge creation balanced`() throws {
        let store = TestStore()
        try seedJournal(store)
        let context = try ModelContext(store.container(allowsSave: false))
        let bridges = BridgeLog()
        ModelObservation.makeBridge = { CountingBridge(log: bridges) }
        defer { ModelObservation.makeBridge = nil }

        let dose = try #require(try context.doses().first)
        context.delete(dose)
        #expect(throws: PortableDataError.self) {
            try context.save()
        }
        #expect(bridges.made == 0)
        _ = try context.sessions().first?.title
        #expect(bridges.made == 1)
    }
}

private struct PassFailed: Error {}

/// Runs `body` on a thread of its own and waits for it, keeping the main thread blocked so
/// no other test's bridge factory can replace this one's meanwhile.
private func onBackgroundThread<T: Sendable>(_ body: @escaping @Sendable () -> T) -> T {
    let result = Mutex<T?>(nil)
    let done = DispatchSemaphore(value: 0)
    let thread = Thread {
        let value = body()
        result.withLock { $0 = value }
        done.signal()
    }
    thread.start()
    done.wait()
    return result.withLock { $0! }
}

private final nonisolated class BridgeLog: Sendable {
    private struct State {
        var made = 0
        var calls: [String] = []
    }

    private let state = Mutex(State())

    var made: Int {
        state.withLock { $0.made }
    }

    var calls: Int {
        state.withLock { $0.calls.count }
    }

    func writes(to keyPath: AnyKeyPath) -> Int {
        let entry = "willSet \(keyPath)"
        return state.withLock { state in state.calls.count(where: { $0 == entry }) }
    }

    func noteMade() {
        state.withLock { $0.made += 1 }
    }

    func record(_ event: String, _ keyPath: AnyKeyPath) {
        let entry = "\(event) \(keyPath)"
        state.withLock { $0.calls.append(entry) }
    }
}

private nonisolated struct CountingBridge: ModelObservationBridge {
    let log: BridgeLog

    init(log: BridgeLog) {
        self.log = log
        log.noteMade()
    }

    func access<Subject: Observable>(_: Subject, keyPath: KeyPath<Subject, some Any>) {
        log.record("access", keyPath)
    }

    func willSet<Subject: Observable>(_: Subject, keyPath: KeyPath<Subject, some Any>) {
        log.record("willSet", keyPath)
    }

    func didSet<Subject: Observable>(_: Subject, keyPath: KeyPath<Subject, some Any>) {
        log.record("didSet", keyPath)
    }
}
