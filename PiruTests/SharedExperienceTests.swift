import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Piru

/// A session in `context` holding one dose per `(substance, amount, unit, hours after start)`.
@MainActor
@discardableResult
private func makeSession(
    in context: ModelContext,
    at start: Date,
    experience: UUID?,
    doses: [(String, Double, String, Double)],
) -> Session {
    let session = Session(startDate: start)
    session.sharedExperienceID = experience
    context.insert(session)
    for (substance, amount, unit, hours) in doses {
        let entry = DoseEntry(substance: substance, amount: amount, unit: unit, timestamp: start.addingTimeInterval(hours * 3_600))
        context.insert(entry)
        entry.session = session
    }
    session.refreshDoseBounds()
    return session
}

/// Store generations a test moves by hand.
@MainActor
private final class Generations {
    var values: [UUID: Int] = [:]

    func bump(_ id: UUID) {
        values[id, default: 0] += 1
    }
}

@Suite("Profiles — shared experiences", .serialized)
@MainActor
struct SharedExperienceTests {
    private let night = Date(timeIntervalSince1970: 1_800_000_000)

    private func container(_ directory: ProfileDirectory, _ id: UUID) throws -> ModelContainer {
        try #require(directory.container(for: id, writable: true))
    }

    // MARK: - Reader

    @Test
    func `The reader groups by profile and ignores sessions outside the experience`() async throws {
        await SubstanceStore.shared.ensureAllLoaded()
        let (directory, _) = try makeScratchProfileDirectory()
        let alice = try directory.addProfile(name: "Alice")
        let bob = try directory.addProfile(name: "Bob")
        let carol = try directory.addProfile(name: "Carol")
        let experience = UUID()

        let mine = makeSession(in: directory.activeContainer.mainContext, at: night, experience: experience, doses: [("2C-B", 15, "mg", 0)])
        try directory.activeContainer.mainContext.save()

        let aliceContext = try container(directory, alice.id).mainContext
        makeSession(in: aliceContext, at: night, experience: experience, doses: [("2C-B", 20, "mg", 0.1), ("Caffeine", 100, "mg", 1)])
        makeSession(in: aliceContext, at: night.addingTimeInterval(-86_400), experience: nil, doses: [("Methylphenidate", 10, "mg", 0)])
        try aliceContext.save()

        let bobContext = try container(directory, bob.id).mainContext
        makeSession(in: bobContext, at: night, experience: UUID(), doses: [("LSD", 100, "µg", 0)])
        try bobContext.save()

        // In the experience, but with nothing logged: not a participant.
        let carolContext = try container(directory, carol.id).mainContext
        makeSession(in: carolContext, at: night, experience: experience, doses: [])
        try carolContext.save()

        let store = SharedExperienceStore(directory: directory) { _ in 0 }
        let participants = await store.participants(for: experience)
        #expect(participants.map(\.id) == [alice.id])
        let doses = try #require(participants.first).snapshot.doses
        #expect(doses.map(\.substance) == ["2C-B", "Caffeine"])
        #expect(participants.first?.doseLines.count == 2)

        await store.refreshIndex()
        #expect(store.participantsBySession == [mine.id: [alice.id]])
    }

    @Test
    func `A new dose in their store invalidates the cached read`() async throws {
        await SubstanceStore.shared.ensureAllLoaded()
        let (directory, _) = try makeScratchProfileDirectory()
        let alice = try directory.addProfile(name: "Alice")
        let experience = UUID()
        makeSession(in: directory.activeContainer.mainContext, at: night, experience: experience, doses: [("2C-B", 15, "mg", 0)])
        let aliceContext = try container(directory, alice.id).mainContext
        let theirs = makeSession(in: aliceContext, at: night, experience: experience, doses: [("2C-B", 20, "mg", 0)])
        try aliceContext.save()

        let generations = Generations()
        let store = SharedExperienceStore(directory: directory) { generations.values[$0] ?? 0 }
        #expect(await store.participants(for: experience).first?.snapshot.doses.count == 1)
        #expect(store.cachedParticipants(for: experience)?.first?.snapshot.doses.count == 1)

        let redose = DoseEntry(substance: "2C-B", amount: 5, unit: "mg", timestamp: night.addingTimeInterval(3_600))
        aliceContext.insert(redose)
        redose.session = theirs
        try aliceContext.save()
        // Same generation: the cache answers.
        #expect(await store.participants(for: experience).first?.snapshot.doses.count == 1)

        generations.bump(alice.id)
        #expect(store.cachedParticipants(for: experience) == nil)
        #expect(await store.participants(for: experience).first?.snapshot.doses.count == 2)
    }

    // MARK: - Titles

    @Test
    func `The section title names one, two, then two and a count`() {
        #expect(SharedExperienceStore.sectionTitle(names: ["Alice"]) == String(localized: "With \("Alice")"))
        let two = SharedExperienceStore.sectionTitle(names: ["Alice", "Bob"])
        #expect(two == String(localized: "With \(["Alice", "Bob"].formatted(.list(type: .and)))"))
        let three = SharedExperienceStore.sectionTitle(names: ["Alice", "Bob", "Carol"])
        #expect(three.contains("Carol"))
        let four = SharedExperienceStore.sectionTitle(names: ["Alice", "Bob", "Carol", "Dan"])
        #expect(four.contains("Alice") && four.contains("Bob"))
        #expect(!four.contains("Carol") && !four.contains("Dan"))
        #expect(four.contains(String(localized: "\(2) others")))
    }

    // MARK: - Add People

    @Test
    func `Overlap matching takes the closest session within the clustering gap`() throws {
        // Held for the whole test: a context does not retain its container.
        let container = try ModelContainer(
            for: Schema(PiruSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none),
        )
        let context = container.mainContext
        let window = DateInterval(start: night, end: night.addingTimeInterval(2 * 3_600))
        let far = makeSession(in: context, at: night.addingTimeInterval(6 * 3_600), experience: nil, doses: [("LSD", 100, "µg", 0)])
        let earlier = makeSession(in: context, at: night.addingTimeInterval(-2 * 3_600), experience: nil, doses: [("Caffeine", 100, "mg", 0)])
        let close = makeSession(in: context, at: night.addingTimeInterval(1_800), experience: nil, doses: [("2C-B", 20, "mg", 0)])

        #expect(SharedExperienceLinker.overlapping(window, in: [far, earlier, close]) === close)
        #expect(SharedExperienceLinker.overlapping(window, in: [far, earlier]) === earlier)
        #expect(SharedExperienceLinker.overlapping(window, in: [far]) == nil)
    }

    @Test
    func `Adding a person links their overlapping session, or reports none`() throws {
        let (directory, _) = try makeScratchProfileDirectory()
        let alice = try directory.addProfile(name: "Alice")
        let bob = try directory.addProfile(name: "Bob")
        let mine = makeSession(in: directory.activeContainer.mainContext, at: night, experience: nil, doses: [("2C-B", 15, "mg", 0)])
        try directory.activeContainer.mainContext.save()

        let aliceContext = try container(directory, alice.id).mainContext
        let theirs = makeSession(in: aliceContext, at: night.addingTimeInterval(1_200), experience: nil, doses: [("2C-B", 20, "mg", 0)])
        try aliceContext.save()
        let bobContext = try container(directory, bob.id).mainContext
        let bobsOther = makeSession(in: bobContext, at: night.addingTimeInterval(-3 * 86_400), experience: nil, doses: [("LSD", 100, "µg", 0)])
        try bobContext.save()

        #expect(try SharedExperienceLinker.add(bob.id, to: mine, directory: directory) == .noOverlap)
        #expect(mine.sharedExperienceID == nil)
        #expect(bobsOther.sharedExperienceID == nil)

        #expect(try SharedExperienceLinker.add(alice.id, to: mine, directory: directory) == .linked)
        let experience = try #require(mine.sharedExperienceID)
        #expect(theirs.sharedExperienceID == experience)
        #expect(try SharedExperienceLinker.add(alice.id, to: mine, directory: directory) == .alreadyLinked)
    }

    @Test
    func `Removing people unlinks them, and the last one out unlinks you`() throws {
        let (directory, _) = try makeScratchProfileDirectory()
        let alice = try directory.addProfile(name: "Alice")
        let bob = try directory.addProfile(name: "Bob")
        let experience = UUID()
        let mine = makeSession(in: directory.activeContainer.mainContext, at: night, experience: experience, doses: [("2C-B", 15, "mg", 0)])
        try directory.activeContainer.mainContext.save()
        let aliceContext = try container(directory, alice.id).mainContext
        let alices = makeSession(in: aliceContext, at: night, experience: experience, doses: [("2C-B", 20, "mg", 0)])
        try aliceContext.save()
        let bobContext = try container(directory, bob.id).mainContext
        let bobs = makeSession(in: bobContext, at: night, experience: experience, doses: [("LSD", 100, "µg", 0)])
        try bobContext.save()

        try SharedExperienceLinker.remove(alice.id, from: experience, directory: directory)
        #expect(alices.sharedExperienceID == nil)
        #expect(mine.sharedExperienceID == experience)
        #expect(bobs.sharedExperienceID == experience)

        try SharedExperienceLinker.remove(bob.id, from: experience, directory: directory)
        #expect(bobs.sharedExperienceID == nil)
        #expect(mine.sharedExperienceID == nil)
    }

    // MARK: - Isolation

    @Test
    func `A shared experience leaves your own timeline, body load and insights untouched`() async throws {
        await SubstanceStore.shared.ensureAllLoaded()
        let (directory, _) = try makeScratchProfileDirectory()
        let alice = try directory.addProfile(name: "Alice")
        let context = directory.activeContainer.mainContext
        let start = Date.now.addingTimeInterval(-3_600)
        let mine = makeSession(in: context, at: start, experience: nil, doses: [("2C-B", 15, "mg", 0)])
        try context.save()

        func ownInputs() throws -> (ids: [UUID], active: [String], states: [ActiveSubstanceState], sessionDoses: [UUID]) {
            let entries = try context.fetch(FetchDescriptor<DoseEntry>(sortBy: [SortDescriptor(\.timestamp)]))
            let colors = try context.fetch(FetchDescriptor<SubstanceColor>())
            return (
                entries.map(\.id),
                ActiveSubstanceCalculator.compute(from: entries, colorMap: [:]).map { "\($0.name) \($0.totalDosed)" }.sorted(),
                ActiveSubstanceState.timeline(for: entries, colors: colors).states,
                mine.orderedDoses.map(\.id),
            )
        }
        let before = try ownInputs()

        let aliceContext = try container(directory, alice.id).mainContext
        makeSession(in: aliceContext, at: start.addingTimeInterval(600), experience: nil, doses: [("MDMA", 120, "mg", 0), ("Alcohol", 2, "units", 0.5)])
        try aliceContext.save()
        #expect(try SharedExperienceLinker.add(alice.id, to: mine, directory: directory) == .linked)
        let store = SharedExperienceStore(directory: directory)
        let experience = try #require(mine.sharedExperienceID)
        #expect(await store.participants(for: experience).first?.snapshot.doses.count == 2)
        await store.refreshIndex()

        let after = try ownInputs()
        #expect(after.ids == before.ids)
        #expect(after.active == before.active)
        #expect(after.states == before.states)
        #expect(after.sessionDoses == before.sessionDoses)
        #expect(try context.fetchCount(FetchDescriptor<DoseEntry>(predicate: #Predicate { $0.substance == "MDMA" })) == 0)
    }
}
