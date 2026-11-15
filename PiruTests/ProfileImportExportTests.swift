import Foundation
import SwiftData
import Testing
@testable import Piru

// MARK: - Fixture

/// A made-up PsychonautWiki journal kept by the owner, with Alice and Bob:
///
/// - "Party": the owner, Alice and Bob together, a timed note and a text.
/// - "Quiet night": the owner alone.
/// - "Alice's morning": Alice alone, with a timed note.
/// - "Bob and Alice": no owner; Alice's dose comes first, then Bob's.
private enum PeopleFixture {
    static let base: Int64 = 1_760_000_000_000
    static let minute: Int64 = 60_000
    static let hour: Int64 = 60 * minute

    static func dose(_ name: String, _ amount: Double, at offset: Int64, by consumer: String?) -> PsyLogIngestion {
        PsyLogIngestion(
            substanceName: name, dose: amount, time: base + offset, route: "ORAL", notes: "", units: "mg",
            consumerName: consumer,
        )
    }

    static func experience(_ title: String, text: String = "", at offset: Int64, _ ingestions: [PsyLogIngestion], notes: [PsyLogTimedNote] = []) -> PsyLogExperience {
        PsyLogExperience(
            title: title, text: text, creationDate: base + offset, sortDate: base + offset,
            ingestions: ingestions, timedNotes: notes,
        )
    }

    static var file: PsyLogFile {
        PsyLogFile(experiences: [
            experience("Party", text: "Together", at: 0, [
                dose("Caffeine", 100, at: 0, by: nil),
                dose("Methylphenidate", 10, at: 10 * minute, by: "Alice"),
                dose("2C-B", 15, at: 20 * minute, by: "bob"),
            ], notes: [PsyLogTimedNote(time: base + 30 * minute, note: "Music got good")]),
            experience("Quiet night", at: 48 * hour, [dose("Caffeine", 50, at: 48 * hour, by: nil)]),
            experience("Alice's morning", at: 96 * hour, [
                dose("Caffeine", 80, at: 96 * hour, by: "Alice"),
            ], notes: [PsyLogTimedNote(time: base + 97 * hour, note: "Calm")]),
            experience("Bob and Alice", at: 144 * hour, [
                dose("Methylphenidate", 5, at: 144 * hour, by: "Alice"),
                dose("Caffeine", 120, at: 144 * hour + 5 * minute, by: "Bob"),
            ], notes: [PsyLogTimedNote(time: base + 145 * hour, note: "Walked home")]),
        ], companions: [])
    }

    static var data: Data {
        get throws { try DataExportImport.encodeJSON(file) }
    }
}

/// A store's doses as comparable rows.
@MainActor
private func doseRows(_ context: ModelContext) throws -> [String] {
    try context.fetch(FetchDescriptor<DoseEntry>()).map {
        "\($0.substance)|\($0.amount)|\($0.timestamp.msSince1970)"
    }.sorted()
}

@MainActor
private func sessions(_ context: ModelContext) throws -> [Session] {
    try context.fetch(FetchDescriptor<Session>(sortBy: [SortDescriptor(\.startDate)]))
}

@MainActor
private func session(titled title: String, in context: ModelContext) throws -> Session? {
    try sessions(context).first { $0.title == title }
}

/// Imports `data` into `directory` with each named person's choice, keeping
/// the custom-substance store isolated from the app's.
@MainActor
private func importPeople(
    _ data: Data,
    into directory: ProfileDirectory,
    choices: [String: PsyLogConsumerTarget]? = nil,
) throws {
    let pending = try #require(PsyLogPendingImport.inspect(data))
    let choices = choices ?? PsyLogImportMapping.defaults(for: pending.consumers, profiles: directory.profiles)
    let routing = try PsyLogImportMapping.routing(for: choices, consumers: pending.consumers, directory: directory)
    let customs = try ModelContainer(
        for: Schema(PiruSchema.models),
        configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none),
    )
    try DataExportImport.importJSON(
        data: data,
        context: directory.activeContainer.mainContext,
        customStore: CustomSubstanceStore.forTesting(context: customs.mainContext),
        psyLogRouting: routing,
    )
    withExtendedLifetime(customs) {}
}

@MainActor
private func journal(of name: String, in directory: ProfileDirectory) throws -> ModelContext {
    let profile = try #require(directory.profiles.first { $0.name == name })
    return try #require(directory.container(for: profile.id, writable: false)).mainContext
}

// MARK: - Reading consumerName

@Suite("Profiles — PsyLog consumers")
struct PsyLogConsumerTests {
    @Test
    func `consumerName decodes per ingestion; null, blank and absent are the owner`() throws {
        let json = """
        {"experiences": [{"title": "x", "creationDate": 1, "sortDate": 1, "ingestions": [
          {"substanceName": "Caffeine", "dose": 1, "time": 1, "consumerName": null},
          {"substanceName": "Caffeine", "dose": 1, "time": 2, "consumerName": " Alice "},
          {"substanceName": "Caffeine", "dose": 1, "time": 3, "consumerName": "   "},
          {"substanceName": "Caffeine", "dose": 1, "time": 4}
        ]}]}
        """
        let file = try JSONDecoder().decode(PsyLogFile.self, from: Data(json.utf8))
        #expect(file.experiences[0].ingestions.map(\.consumerName) == [nil, "Alice", nil, nil])
        #expect(file.namesAnyone)
    }

    @Test
    func `consumerName encodes as the name, and as null for the owner`() throws {
        let file = PsyLogFile(experiences: [PeopleFixture.experience("x", at: 0, [
            PeopleFixture.dose("Caffeine", 1, at: 0, by: nil),
            PeopleFixture.dose("Caffeine", 1, at: 1, by: "Alice"),
        ])], companions: [])
        let object = try #require(JSONSerialization.jsonObject(with: DataExportImport.encodeJSON(file)) as? [String: Any])
        let ingestions = try #require((object["experiences"] as? [[String: Any]])?.first?["ingestions"] as? [[String: Any]])
        #expect(ingestions[0].keys.contains("consumerName"))
        #expect(ingestions[0]["consumerName"] is NSNull)
        #expect(ingestions[1]["consumerName"] as? String == "Alice")
    }

    @Test
    func `The file lists the owner first, then each name once, case-insensitively`() {
        let consumers = PeopleFixture.file.consumers
        #expect(consumers.map(\.name) == [nil, "Alice", "bob"])
        #expect(consumers.map(\.doseCount) == [2, 3, 2])
        #expect(consumers.first?.isOwner == true)
    }

    @Test
    func `A file naming nobody asks no one anything`() throws {
        let file = PsyLogFile(experiences: [PeopleFixture.experience("x", at: 0, [
            PeopleFixture.dose("Caffeine", 1, at: 0, by: nil),
        ])], companions: [])
        #expect(!file.namesAnyone)
        #expect(try PsyLogPendingImport.inspect(DataExportImport.encodeJSON(file)) == nil)
    }
}

// MARK: - Mapping

@Suite("Profiles — import mapping")
@MainActor
struct PsyLogImportMappingTests {
    @Test
    func `A name matching a profile defaults to it; any other name to a new profile`() throws {
        let (directory, _) = try makeScratchProfileDirectory()
        let alice = try directory.addProfile(name: "ALICE")
        let defaults = PsyLogImportMapping.defaults(for: PeopleFixture.file.consumers, profiles: directory.profiles)
        #expect(defaults == ["alice": .profile(alice.id), "bob": .newProfile])
    }

    @Test
    func `Settling the mapping creates new profiles and leaves skipped people out`() throws {
        let (directory, _) = try makeScratchProfileDirectory()
        let consumers = PeopleFixture.file.consumers
        let routing = try PsyLogImportMapping.routing(
            for: ["alice": .newProfile, "bob": .skip],
            consumers: consumers,
            directory: directory,
        )
        let alice = try #require(directory.profiles.first { $0.name == "Alice" })
        #expect(alice.avatar == .monogram(for: "Alice"))
        #expect(alice.color == .next(after: [directory.owner.color]))
        #expect(directory.profiles.count == 2)
        #expect(routing.owner == directory.activeProfileID)
        #expect(routing.profile(forConsumer: nil) == directory.activeProfileID)
        #expect(routing.profile(forConsumer: "alice") == alice.id)
        #expect(routing.profile(forConsumer: "Bob") == nil)
    }
}

// MARK: - Splitting

@Suite("Profiles — import splitting")
@MainActor
struct PsyLogImportSplittingTests {
    @Test
    func `Each experience splits into one session per person, linked when shared`() throws {
        let (directory, _) = try makeScratchProfileDirectory()
        try importPeople(PeopleFixture.data, into: directory)
        let owner = directory.activeContainer.mainContext
        let alice = try journal(of: "Alice", in: directory)
        let bob = try journal(of: "bob", in: directory)

        #expect(try doseRows(owner).count == 2)
        #expect(try doseRows(alice).count == 3)
        #expect(try doseRows(bob).count == 2)

        // Mixed: one session in each store, one shared id, title and text on all.
        let parties = try [owner, alice, bob].map { try #require(try session(titled: "Party", in: $0)) }
        let shared = try #require(parties[0].sharedExperienceID)
        #expect(parties.allSatisfy { $0.sharedExperienceID == shared })
        #expect(parties.allSatisfy { $0.note == "Together" })

        // Owner-only: in the owner's store, linked to nobody.
        let quiet = try #require(try session(titled: "Quiet night", in: owner))
        #expect(quiet.sharedExperienceID == nil)
        #expect(try session(titled: "Quiet night", in: alice) == nil)

        // Other-only: only in Alice's store.
        let morning = try #require(try session(titled: "Alice's morning", in: alice))
        #expect(morning.sharedExperienceID == nil)
        #expect(try session(titled: "Alice's morning", in: owner) == nil)
        #expect(try session(titled: "Alice's morning", in: bob) == nil)

        // Bob and Alice without the owner: linked to each other.
        let aliceWalk = try #require(try session(titled: "Bob and Alice", in: alice))
        let bobWalk = try #require(try session(titled: "Bob and Alice", in: bob))
        #expect(aliceWalk.sharedExperienceID != nil)
        #expect(aliceWalk.sharedExperienceID == bobWalk.sharedExperienceID)
        #expect(aliceWalk.sharedExperienceID != shared)
        #expect(try session(titled: "Bob and Alice", in: owner) == nil)
    }

    @Test
    func `Timed notes go to the owner's session, else the first person's`() throws {
        let (directory, _) = try makeScratchProfileDirectory()
        try importPeople(PeopleFixture.data, into: directory)
        let owner = directory.activeContainer.mainContext
        let alice = try journal(of: "Alice", in: directory)
        let bob = try journal(of: "bob", in: directory)
        func notes(_ title: String, _ context: ModelContext) throws -> [String] {
            try (session(titled: title, in: context)?.notes ?? []).filter { $0.kind != .summary }.map(\.text)
        }

        #expect(try notes("Party", owner) == ["Music got good"])
        #expect(try notes("Party", alice).isEmpty)
        #expect(try notes("Party", bob).isEmpty)
        #expect(try notes("Alice's morning", alice) == ["Calm"])
        #expect(try notes("Bob and Alice", alice) == ["Walked home"])
        #expect(try notes("Bob and Alice", bob).isEmpty)
    }

    @Test
    func `A skipped person's doses land nowhere`() throws {
        let (directory, _) = try makeScratchProfileDirectory()
        try importPeople(PeopleFixture.data, into: directory, choices: ["alice": .newProfile, "bob": .skip])
        #expect(directory.profiles.map(\.name).sorted() == ["Alice", directory.owner.name].sorted())
        let owner = directory.activeContainer.mainContext
        let alice = try journal(of: "Alice", in: directory)
        #expect(try !doseRows(owner).contains { $0.hasPrefix("2C-B") })
        #expect(try doseRows(alice).count == 3)
        let party = try #require(try session(titled: "Party", in: owner))
        #expect(party.sharedExperienceID != nil)
        #expect(try party.sharedExperienceID == session(titled: "Party", in: alice)?.sharedExperienceID)
    }

    @Test
    func `Without a mapping, only the owner's doses import`() throws {
        let (directory, _) = try makeScratchProfileDirectory()
        let customs = try ModelContainer(
            for: Schema(PiruSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none),
        )
        try DataExportImport.importJSON(
            data: PeopleFixture.data,
            context: directory.activeContainer.mainContext,
            customStore: CustomSubstanceStore.forTesting(context: customs.mainContext),
        )
        #expect(try doseRows(directory.activeContainer.mainContext) == [
            "Caffeine|100.0|\(PeopleFixture.base)",
            "Caffeine|50.0|\(PeopleFixture.base + 48 * PeopleFixture.hour)",
        ])
        #expect(!directory.hasMultipleProfiles)
    }

    @Test
    func `Importing the same file twice adds nothing to any store`() throws {
        let (directory, _) = try makeScratchProfileDirectory()
        try importPeople(PeopleFixture.data, into: directory)
        let stores = try [
            directory.activeContainer.mainContext,
            journal(of: "Alice", in: directory),
            journal(of: "bob", in: directory),
        ]
        let doses = try stores.map(doseRows)
        let sessionIDs = try stores.map { try sessions($0).map(\.id) }
        let shared = try stores.map { try sessions($0).map(\.sharedExperienceID) }
        let noteCounts = try stores.map { try $0.fetchCount(FetchDescriptor<SessionNote>()) }

        try importPeople(PeopleFixture.data, into: directory)
        #expect(directory.profiles.count == 3)
        #expect(try stores.map(doseRows) == doses)
        #expect(try stores.map { try sessions($0).map(\.id) } == sessionIDs)
        #expect(try stores.map { try sessions($0).map(\.sharedExperienceID) } == shared)
        #expect(try stores.map { try $0.fetchCount(FetchDescriptor<SessionNote>()) } == noteCounts)
    }
}

// MARK: - Export

@Suite("Profiles — PsyLog export")
@MainActor
struct PsyLogPeopleExportTests {
    @Test
    func `This profile's export names nobody and holds only its doses`() throws {
        let (directory, _) = try makeScratchProfileDirectory()
        try importPeople(PeopleFixture.data, into: directory)
        let file = try DataExportImport.makePsyLogFile(context: directory.activeContainer.mainContext)
        let ingestions = file.experiences.flatMap(\.ingestions)
        #expect(ingestions.count == 2)
        #expect(ingestions.allSatisfy { $0.consumerName == nil })
    }

    @Test
    func `Everyone's export round-trips profiles, doses and links`() throws {
        let (source, _) = try makeScratchProfileDirectory()
        try importPeople(PeopleFixture.data, into: source)
        let file = try DataExportImport.makePsyLogFile(
            people: DataExportImport.everyone(activeContext: source.activeContainer.mainContext, directory: source),
        )
        // One experience per shared experience, one per unshared session.
        #expect(file.experiences.count == 4)
        #expect(file.experiences.first { $0.title == "Party" }?.ingestions.map(\.consumerName) == [nil, "Alice", "bob"])

        let (copy, _) = try makeScratchProfileDirectory()
        try importPeople(DataExportImport.encodeJSON(file), into: copy)
        #expect(copy.profiles.map(\.name) == source.profiles.map(\.name))
        for name in source.profiles.map(\.name) {
            #expect(try doseRows(journal(of: name, in: copy)) == doseRows(journal(of: name, in: source)))
        }
        #expect(try links(in: copy) == links(in: source))
    }

    /// Each shared experience as the set of its people's doses, so two worlds
    /// compare without their minted ids.
    private func links(in directory: ProfileDirectory) throws -> Set<Set<String>> {
        var groups: [UUID: Set<String>] = [:]
        for profile in directory.profiles {
            let context = try journal(of: profile.name, in: directory)
            for session in try sessions(context) {
                guard let shared = session.sharedExperienceID else { continue }
                for dose in session.doses ?? [] {
                    groups[shared, default: []].insert("\(profile.name)|\(dose.substance)|\(dose.timestamp.msSince1970)")
                }
            }
        }
        return Set(groups.values)
    }
}

// MARK: - Log for

@Suite("Profiles — log for")
@MainActor
struct LogForTests {
    @Test
    func `A dose logged for someone else lands in their store and links to the live session`() throws {
        let (directory, _) = try makeScratchProfileDirectory()
        let alice = try directory.addProfile(name: "Alice")
        let mine = directory.activeContainer.mainContext
        let myDose = DoseEntry(substance: "Caffeine", amount: 100, timestamp: .now.addingTimeInterval(-600))
        mine.insert(myDose)
        let live = SessionService.assignSession(for: myDose, in: mine)
        try mine.save()

        let recipient = try #require(DoseRecipient.other(alice.id, directory: directory))
        #expect(!recipient.isActive)
        let entry = DoseEntry(substance: "Methylphenidate", amount: 10, timestamp: .now)
        recipient.log([(entry, nil)], liveSession: live)
        defer { DoseLogService.shared.cancelPendingBookkeeping() }

        let theirs = try #require(directory.container(for: alice.id, writable: false)).mainContext
        #expect(try doseRows(theirs).map { $0.hasPrefix("Methylphenidate") } == [true])
        #expect(try doseRows(mine).count == 1)
        let theirSession = try #require(entry.session)
        #expect(live.sharedExperienceID != nil)
        #expect(theirSession.sharedExperienceID == live.sharedExperienceID)
        #expect(!live.hasChanges)

        // A second dose for her joins the same session and keeps the link.
        let second = DoseEntry(substance: "Methylphenidate", amount: 5, timestamp: .now.addingTimeInterval(60))
        recipient.log([(second, nil)], liveSession: live)
        #expect(second.session === theirSession)
        #expect(theirSession.sharedExperienceID == live.sharedExperienceID)
    }

    @Test
    func `With no live session, someone else's dose opens an unlinked session`() throws {
        let (directory, _) = try makeScratchProfileDirectory()
        let alice = try directory.addProfile(name: "Alice")
        let recipient = try #require(DoseRecipient.other(alice.id, directory: directory))
        let entry = DoseEntry(substance: "Caffeine", amount: 80, timestamp: .now)
        recipient.log([(entry, nil)], liveSession: nil)
        defer { DoseLogService.shared.cancelPendingBookkeeping() }
        #expect(entry.session?.sharedExperienceID == nil)
        #expect(try doseRows(directory.activeContainer.mainContext).isEmpty)
    }

    @Test
    func `The active profile is never "someone else"`() throws {
        let (directory, _) = try makeScratchProfileDirectory()
        _ = try directory.addProfile(name: "Alice")
        #expect(DoseRecipient.other(directory.activeProfileID, directory: directory) == nil)
        #expect(DoseRecipient.other(UUID(), directory: directory) == nil)
    }

    @Test
    func `The For choice lasts one log`() {
        let tray = DoseTrayModel()
        #expect(tray.recipientID == nil)
        let alice = UUID()
        tray.recipientID = alice
        #expect(tray.takeRecipient() == alice)
        #expect(tray.recipientID == nil)
        #expect(tray.takeRecipient() == nil)
    }

    @Test
    func `Linking keeps a shared experience someone already has`() {
        let live = Session(startDate: .now)
        let existing = UUID()
        let theirs = Session(startDate: .now)
        theirs.sharedExperienceID = existing
        SharedExperienceLink.link([theirs], to: live)
        #expect(live.sharedExperienceID == existing)
        #expect(theirs.sharedExperienceID == existing)
    }
}
