import Foundation
import SwiftData
import Testing
@testable import Piru

@Suite("Profiles — backups")
@MainActor
struct ProfileBackupTests {
    private static func doses(in container: ModelContainer?) throws -> [String] {
        let container = try #require(container)
        return try container.mainContext.fetch(FetchDescriptor<DoseEntry>(sortBy: [SortDescriptor(\.substance)]))
            .map(\.substance)
    }

    @Test
    func `A backup with one profile is the single-journal file it always was`() throws {
        let (directory, _) = try makeScratchProfileDirectory()
        let context = directory.activeContainer.mainContext
        context.insert(DoseEntry(substance: "Caffeine", amount: 100))
        try context.save()
        let data = try DataExportImport.exportBackupJSON(context: context, directory: directory)
        #expect(DataExportImport.profilesSection(in: data) == nil)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["profiles"] == nil)
    }

    @Test
    func `Every profile and its journal survive a backup and a restore`() throws {
        let (source, _) = try makeScratchProfileDirectory()
        let alice = try source.addProfile(name: "Alice", avatar: .emoji("🦊"), color: .forest)
        let bob = try source.addProfile(name: "Bob")
        let ownerContext = source.activeContainer.mainContext
        ownerContext.insert(DoseEntry(substance: "Caffeine", amount: 100))
        try ownerContext.save()
        let aliceContext = try #require(source.container(for: alice.id, writable: true)).mainContext
        aliceContext.insert(DoseEntry(substance: "Methylphenidate", amount: 10))
        try aliceContext.save()

        let data = try DataExportImport.exportBackupJSON(context: ownerContext, directory: source)
        let section = try #require(DataExportImport.profilesSection(in: data))
        #expect(section.registry.map(\.id) == [PiruProfile.ownerID, alice.id, bob.id])
        #expect(section.journals.map(\.profileID) == [alice.id, bob.id])

        let (restored, _) = try makeScratchProfileDirectory()
        try BackupManager.shared.apply(
            plaintext: data, strategy: .merge, context: restored.activeContainer.mainContext, directory: restored,
        )
        #expect(restored.profiles.map(\.id) == [PiruProfile.ownerID, alice.id, bob.id])
        let restoredAlice = try #require(restored.profile(id: alice.id))
        #expect(restoredAlice.name == "Alice")
        #expect(restoredAlice.avatar.text == "🦊")
        #expect(restoredAlice.color == .forest)
        #expect(try Self.doses(in: restored.activeContainer) == ["Caffeine"])
        #expect(try Self.doses(in: restored.container(for: alice.id, writable: false)) == ["Methylphenidate"])
        #expect(try Self.doses(in: restored.container(for: bob.id, writable: false)).isEmpty)
    }

    @Test
    func `A backup made while another profile is open still puts the owner's journal on top`() throws {
        let (source, _) = try makeScratchProfileDirectory()
        let alice = try source.addProfile(name: "Alice")
        source.activeContainer.mainContext.insert(DoseEntry(substance: "Caffeine", amount: 100))
        try source.activeContainer.mainContext.save()
        let aliceContainer = try #require(source.activate(alice.id))
        aliceContainer.mainContext.insert(DoseEntry(substance: "Methylphenidate", amount: 10))
        try aliceContainer.mainContext.save()

        let data = try DataExportImport.exportBackupJSON(context: aliceContainer.mainContext, directory: source)
        let file = try JSONDecoder().decode(PiruFile.self, from: data)
        #expect(file.sessions.flatMap(\.doses).map(\.substance) + file.orphanDoses.map(\.substance) == ["Caffeine"])
        let journal = try #require(file.profiles?.journals.first)
        #expect(journal.profileID == alice.id)
        #expect(journal.file.sessions.flatMap(\.doses).map(\.substance) + journal.file.orphanDoses.map(\.substance)
            == ["Methylphenidate"])
        #expect(journal.file.settings == nil)
    }

    @Test
    func `A single-profile backup restores into the open journal, whoever it is`() throws {
        let (source, _) = try makeScratchProfileDirectory()
        source.activeContainer.mainContext.insert(DoseEntry(substance: "Caffeine", amount: 100))
        try source.activeContainer.mainContext.save()
        let data = try DataExportImport.exportBackupJSON(context: source.activeContainer.mainContext, directory: source)

        let (target, _) = try makeScratchProfileDirectory()
        let alice = try target.addProfile(name: "Alice")
        let aliceContainer = try #require(target.activate(alice.id))
        try BackupManager.shared.apply(
            plaintext: data, strategy: .merge, context: aliceContainer.mainContext, directory: target,
        )
        #expect(try Self.doses(in: aliceContainer) == ["Caffeine"])
        #expect(try Self.doses(in: target.container(for: PiruProfile.ownerID, writable: false)).isEmpty)
        #expect(target.profiles.count == 2)
    }

    // MARK: Plain JSON export and import

    @Test
    func `An Everyone export imports as two profiles, each journal under its own id`() throws {
        let (source, _) = try makeScratchProfileDirectory()
        let alice = try source.addProfile(name: "Alice", avatar: .emoji("🦊"), color: .forest)
        let ownerContext = source.activeContainer.mainContext
        ownerContext.insert(DoseEntry(substance: "Caffeine", amount: 100))
        try ownerContext.save()
        let aliceContext = try #require(source.container(for: alice.id, writable: true)).mainContext
        aliceContext.insert(DoseEntry(substance: "Methylphenidate", amount: 10))
        try aliceContext.save()
        let data = try DataExportImport.exportBackupJSON(context: ownerContext, directory: source)

        let (target, _) = try makeScratchProfileDirectory()
        #expect(!target.hasMultipleProfiles)
        try BackupFileImport.importJSON(data, context: target.activeContainer.mainContext, directory: target)
        #expect(target.hasMultipleProfiles)
        #expect(target.profiles.map(\.id) == [PiruProfile.ownerID, alice.id])
        #expect(target.profile(id: alice.id)?.name == "Alice")
        #expect(try Self.doses(in: target.activeContainer) == ["Caffeine"])
        #expect(try Self.doses(in: target.container(for: alice.id, writable: false)) == ["Methylphenidate"])

        // A second import merges into the profiles it made, adding nothing.
        try BackupFileImport.importJSON(data, context: target.activeContainer.mainContext, directory: target)
        #expect(target.profiles.count == 2)
        #expect(try Self.doses(in: target.activeContainer) == ["Caffeine"])
        #expect(try Self.doses(in: target.container(for: alice.id, writable: false)) == ["Methylphenidate"])
    }

    @Test
    func `A This Profile export still imports into the open journal alone`() throws {
        let (source, _) = try makeScratchProfileDirectory()
        let alice = try source.addProfile(name: "Alice")
        let aliceContainer = try #require(source.activate(alice.id))
        aliceContainer.mainContext.insert(DoseEntry(substance: "Methylphenidate", amount: 10))
        try aliceContainer.mainContext.save()
        let data = try DataExportImport.exportJSON(format: .piru, context: aliceContainer.mainContext)
        #expect(DataExportImport.profilesSection(in: data) == nil)

        let (target, _) = try makeScratchProfileDirectory()
        try BackupFileImport.importJSON(data, context: target.activeContainer.mainContext, directory: target)
        #expect(target.profiles.map(\.id) == [PiruProfile.ownerID])
        #expect(try Self.doses(in: target.activeContainer) == ["Methylphenidate"])
    }

    @Test
    func `A file without a profiles section goes into whichever journal is open`() throws {
        let (source, _) = try makeScratchProfileDirectory()
        source.activeContainer.mainContext.insert(DoseEntry(substance: "Caffeine", amount: 100))
        try source.activeContainer.mainContext.save()
        var json = try #require(try JSONSerialization.jsonObject(
            with: DataExportImport.exportJSON(context: source.activeContainer.mainContext),
        ) as? [String: Any])
        json["profiles"] = nil
        let oldFile = try JSONSerialization.data(withJSONObject: json)

        let (target, _) = try makeScratchProfileDirectory()
        let bob = try target.addProfile(name: "Bob")
        let bobContainer = try #require(target.activate(bob.id))
        try BackupFileImport.importJSON(oldFile, context: bobContainer.mainContext, directory: target)
        #expect(target.profiles.map(\.id) == [PiruProfile.ownerID, bob.id])
        #expect(try Self.doses(in: bobContainer) == ["Caffeine"])
        #expect(try Self.doses(in: target.container(for: PiruProfile.ownerID, writable: false)).isEmpty)
    }
}

@Suite("Profiles — deep links")
struct ProfileDeepLinkTests {
    @Test
    func `A link names the profile it opens without changing where it lands`() throws {
        let id = UUID()
        let base = try #require(URL(string: "piru://quicklog?routine=morning"))
        let tagged = DeepLink.tagging(base, profile: id)
        #expect(DeepLink.profileID(in: tagged) == id)
        #expect(DeepLink.profileID(in: base) == nil)
        #expect(DeepLink.decode(tagged) == DeepLink.decode(base))
        let retagged = DeepLink.tagging(tagged, profile: PiruProfile.ownerID)
        #expect(DeepLink.profileID(in: retagged) == PiruProfile.ownerID)
        #expect(retagged.absoluteString.components(separatedBy: "profile=").count == 2)
    }

    @Test
    func `Manage Profiles has a link of its own`() throws {
        let url = try #require(URL(string: "piru://profiles"))
        #expect(DeepLink.decode(url)?.sheet == .profiles)
        #expect(DeepLink.encode(NavigatorSnapshot(sheetStack: [.profiles]))?.host == "profiles")
    }
}
