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
        #expect(section.registry.map(\.id) == [source.owner.id, alice.id, bob.id])
        #expect(section.journals.map(\.profileID) == [alice.id, bob.id])

        let (restored, _) = try makeScratchProfileDirectory()
        try BackupManager.shared.apply(
            plaintext: data, strategy: .merge, context: restored.activeContainer.mainContext, directory: restored,
        )
        // The source's owner is another device's: by default its journal goes
        // into this device's owner, which keeps its own id.
        #expect(restored.profiles.map(\.id) == [restored.owner.id, alice.id, bob.id])
        #expect(restored.owner.id != source.owner.id)
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
        #expect(try Self.doses(in: target.container(for: target.owner.id, writable: false)).isEmpty)
        #expect(target.profiles.count == 2)
    }

    // MARK: Owner identity

    @Test
    func `An owner on the legacy id gets its own, keeping its store and sharing identity`() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("profile-dir-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let defaults = try #require(UserDefaults(suiteName: "piru.tests.profile-dir.\(UUID().uuidString)"))
        let identities = ShareIdentityStore(storage: InMemoryShareIdentityStorage())
        let legacy = PiruProfile.legacyOwnerID
        // A registry as profiles first shipped it: the owner on the legacy id,
        // Alice on her own, and an item of hers shared with the owner.
        let alice = PiruProfile.new(name: "Alice", avatar: .monogram(for: "Alice"), color: .forest)
        try Self.writeVersion1Registry([.defaultOwner(name: "Kiri"), alice], to: dir)
        let mintedIdentity = try identities.identity(for: legacy)
        let opener: (PiruProfile, URL) -> ModelContainer = { _, url in StoreRecovery.openContainer(at: url).container }
        let seed = StoreRecovery.openContainer(at: dir.appendingPathComponent(alice.storeFileName)).container
        let shared = InventoryItem(
            substance: "Caffeine", unit: "mg", manualEvents: [ManualEvent(kind: .initial, amount: 100, date: .now)],
        )
        shared.sharedWith = [legacy]
        seed.mainContext.insert(shared)
        try seed.mainContext.save()
        let ownerSeed = StoreRecovery.openContainer(at: dir.appendingPathComponent(StoreRecovery.activeStoreName)).container
        ownerSeed.mainContext.insert(DoseEntry(substance: "Caffeine", amount: 100))
        try ownerSeed.mainContext.save()

        let directory = ProfileDirectory(directory: dir, defaults: defaults, identities: identities, opener: opener)
        directory.openActiveStore()

        let owner = directory.owner
        #expect(owner.id != legacy)
        #expect(owner.name == "Kiri")
        #expect(owner.storeFileName == PiruProfile.ownerStoreFileName)
        #expect(ProfileRegistry.load(from: dir).map(\.id) == [owner.id, alice.id])
        #expect(directory.activeProfileID == owner.id)
        #expect(try Self.doses(in: directory.activeContainer) == ["Caffeine"])
        #expect(identities.existingIdentity(for: owner.id)?.personID == mintedIdentity.personID)
        #expect(identities.existingIdentity(for: legacy) == nil)
        #expect(directory.profile(id: legacy)?.id == owner.id)
        let aliceItems = try #require(directory.container(for: alice.id, writable: true))
            .mainContext.fetch(FetchDescriptor<InventoryItem>())
        #expect(aliceItems.map(\.sharedWith) == [[owner.id]])

        // A second launch finds nothing to migrate.
        let again = ProfileDirectory(directory: dir, defaults: defaults, identities: identities, opener: opener)
        #expect(again.owner.id == owner.id)
    }

    @Test
    func `A backup naming the owner by the legacy id restores into this device's owner`() throws {
        let (source, _) = try makeScratchProfileDirectory()
        let alice = try source.addProfile(name: "Alice")
        source.activeContainer.mainContext.insert(DoseEntry(substance: "Caffeine", amount: 100))
        try source.activeContainer.mainContext.save()
        let aliceContext = try #require(source.container(for: alice.id, writable: true)).mainContext
        let item = InventoryItem(
            substance: "Caffeine", unit: "mg", manualEvents: [ManualEvent(kind: .initial, amount: 100, date: .now)],
        )
        item.sharedWith = [source.owner.id]
        aliceContext.insert(item)
        try aliceContext.save()
        let data = try Self.asVersion1Backup(
            DataExportImport.exportBackupJSON(context: source.activeContainer.mainContext, directory: source),
            owner: source.owner.id,
        )

        let (target, _) = try makeScratchProfileDirectory()
        #expect(BackupManager.shared.profileConflicts(in: data, directory: target).isEmpty)
        try BackupFileImport.importJSON(data, context: target.activeContainer.mainContext, directory: target)
        #expect(target.profiles.map(\.id) == [target.owner.id, alice.id])
        #expect(try Self.doses(in: target.activeContainer) == ["Caffeine"])
        let aliceItems = try #require(target.container(for: alice.id, writable: false))
            .mainContext.fetch(FetchDescriptor<InventoryItem>())
        #expect(aliceItems.map(\.sharedWith) == [[target.owner.id]])
    }

    @Test
    func `A profile that looks different here is asked about, and each answer applies`() throws {
        let (source, _) = try makeScratchProfileDirectory()
        let alice = try source.addProfile(name: "Alice", avatar: .emoji("🦊"), color: .forest)
        let data = try DataExportImport.exportBackupJSON(context: source.activeContainer.mainContext, directory: source)

        func device(renaming: Bool) throws -> ProfileDirectory {
            let (target, _) = try makeScratchProfileDirectory()
            try target.restoreProfile(alice, as: alice.id, takingDetails: true)
            if renaming {
                var here = try #require(target.profile(id: alice.id))
                here.name = "Ali"
                try target.update(here)
            }
            return target
        }

        let same = try device(renaming: false)
        #expect(BackupManager.shared.profileConflicts(in: data, directory: same).map(\.kind) == [.otherOwner])

        let kept = try device(renaming: true)
        let conflicts = BackupManager.shared.profileConflicts(in: data, directory: kept)
        #expect(conflicts.map(\.kind) == [.otherOwner, .details])
        let detail = try #require(conflicts.first { $0.kind == .details })
        #expect(detail.incoming.name == "Alice")
        #expect(detail.local.name == "Ali")
        #expect(detail.choices == [.keepThisDevice, .useBackup])
        try BackupFileImport.importJSON(data, context: kept.activeContainer.mainContext, directory: kept)
        #expect(kept.profile(id: alice.id)?.name == "Ali")

        let taken = try device(renaming: true)
        try BackupFileImport.importJSON(
            data, context: taken.activeContainer.mainContext, directory: taken, choices: [alice.id: .useBackup],
        )
        #expect(taken.profile(id: alice.id)?.name == "Alice")
        #expect(taken.profiles.count == 2)
    }

    @Test
    func `Another device's owner goes into this owner's journal unless added as a new profile`() throws {
        let (source, _) = try makeScratchProfileDirectory()
        var sourceOwner = source.owner
        sourceOwner.name = "Kiri"
        try source.update(sourceOwner)
        _ = try source.addProfile(name: "Alice")
        source.activeContainer.mainContext.insert(DoseEntry(substance: "Caffeine", amount: 100))
        try source.activeContainer.mainContext.save()
        let data = try DataExportImport.exportBackupJSON(context: source.activeContainer.mainContext, directory: source)

        let (merged, _) = try makeScratchProfileDirectory()
        let conflict = try #require(BackupManager.shared.profileConflicts(in: data, directory: merged).first)
        #expect(conflict.kind == .otherOwner)
        #expect(conflict.choices == [.keepThisDevice, .useBackup, .newProfile])
        try BackupFileImport.importJSON(data, context: merged.activeContainer.mainContext, directory: merged)
        #expect(merged.owner.name == ProfileRegistry.defaultOwnerName)
        #expect(merged.profiles.count == 2)
        #expect(try Self.doses(in: merged.activeContainer) == ["Caffeine"])

        let (renamed, _) = try makeScratchProfileDirectory()
        try BackupFileImport.importJSON(
            data, context: renamed.activeContainer.mainContext, directory: renamed, choices: [source.owner.id: .useBackup],
        )
        #expect(renamed.owner.name == "Kiri")
        #expect(renamed.owner.id != source.owner.id)

        let (separate, _) = try makeScratchProfileDirectory()
        try BackupFileImport.importJSON(
            data, context: separate.activeContainer.mainContext, directory: separate, choices: [source.owner.id: .newProfile],
        )
        #expect(separate.profiles.map(\.id) == [separate.owner.id, source.owner.id, source.profiles[1].id])
        let added = try #require(separate.profile(id: source.owner.id))
        #expect(added.name == "Kiri")
        #expect(!added.isOwner)
        #expect(try Self.doses(in: separate.activeContainer).isEmpty)
        #expect(try Self.doses(in: separate.container(for: source.owner.id, writable: false)) == ["Caffeine"])
    }

    /// `profiles` as a version-1 build wrote it.
    private static func writeVersion1Registry(_ profiles: [PiruProfile], to dir: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let profilesJSON = try JSONSerialization.jsonObject(with: encoder.encode(profiles))
        let data = try JSONSerialization.data(withJSONObject: ["version": 1, "profiles": profilesJSON])
        try data.write(to: dir.appendingPathComponent(ProfileRegistry.fileName))
    }

    /// `backup` with its owner named by the legacy id, as a build before
    /// owners had ids of their own wrote it.
    private static func asVersion1Backup(_ backup: Data, owner: UUID) throws -> Data {
        let text = try #require(String(data: backup, encoding: .utf8))
        return Data(text.replacingOccurrences(of: owner.uuidString, with: PiruProfile.legacyOwnerID.uuidString).utf8)
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
        #expect(target.profiles.map(\.id) == [target.owner.id, alice.id])
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
        #expect(target.profiles.map(\.id) == [target.owner.id])
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
        #expect(target.profiles.map(\.id) == [target.owner.id, bob.id])
        #expect(try Self.doses(in: bobContainer) == ["Caffeine"])
        #expect(try Self.doses(in: target.container(for: target.owner.id, writable: false)).isEmpty)
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
        let owner = UUID()
        let retagged = DeepLink.tagging(tagged, profile: owner)
        #expect(DeepLink.profileID(in: retagged) == owner)
        #expect(retagged.absoluteString.components(separatedBy: "profile=").count == 2)
    }

    @Test
    func `Manage Profiles has a link of its own`() throws {
        let url = try #require(URL(string: "piru://profiles"))
        #expect(DeepLink.decode(url)?.sheet == .profiles)
        #expect(DeepLink.encode(NavigatorSnapshot(sheetStack: [.profiles]))?.host == "profiles")
    }
}
