import Foundation
import SwiftData
import Testing
@testable import Piru

/// A directory over a scratch folder whose stores are real files, opened the
/// way a non-owner store opens (no recovery, which reads the real App Group).
@MainActor
func makeScratchProfileDirectory() throws -> (ProfileDirectory, URL) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("profile-dir-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let defaults = try #require(UserDefaults(suiteName: "piru.tests.profile-dir.\(UUID().uuidString)"))
    let directory = ProfileDirectory(directory: dir, defaults: defaults) { _, url in
        StoreRecovery.openContainer(at: url).container
    }
    directory.openActiveStore()
    return (directory, dir)
}

@Suite("Profiles — directory")
@MainActor
struct ProfileDirectoryTests {
    @Test
    func `Adding a person writes the registry and leaves the owner active`() throws {
        let (directory, dir) = try makeScratchProfileDirectory()
        #expect(!directory.hasMultipleProfiles)
        let alice = try directory.addProfile(name: "  Alice ")
        #expect(alice.name == "Alice")
        #expect(alice.avatar.text == "A")
        #expect(alice.color != directory.owner.color)
        #expect(directory.hasMultipleProfiles)
        #expect(directory.activeProfileID == PiruProfile.ownerID)
        #expect(ProfileRegistry.load(from: dir).map(\.id) == [PiruProfile.ownerID, alice.id])
        #expect(throws: ProfileDirectory.DirectoryError.self) { try directory.addProfile(name: "   ") }
    }

    @Test
    func `Each profile's doses stay in its own store`() throws {
        let (directory, _) = try makeScratchProfileDirectory()
        let alice = try directory.addProfile(name: "Alice")
        let ownerContext = directory.activeContainer.mainContext
        ownerContext.insert(DoseEntry(substance: "Caffeine", amount: 100))
        try ownerContext.save()

        let aliceContainer = try #require(directory.activate(alice.id))
        #expect(directory.activeProfileID == alice.id)
        #expect(directory.activeContainer === aliceContainer)
        #expect(try aliceContainer.mainContext.fetchCount(FetchDescriptor<DoseEntry>()) == 0)
        aliceContainer.mainContext.insert(DoseEntry(substance: "Methylphenidate", amount: 10))
        try aliceContainer.mainContext.save()

        let ownerAgain = try #require(directory.activate(PiruProfile.ownerID))
        let ownerDoses = try ownerAgain.mainContext.fetch(FetchDescriptor<DoseEntry>())
        #expect(ownerDoses.map(\.substance) == ["Caffeine"])
        let aliceRead = try #require(directory.container(for: alice.id, writable: false))
        #expect(try aliceRead.mainContext.fetch(FetchDescriptor<DoseEntry>()).map(\.substance) == ["Methylphenidate"])
        #expect(directory.activate(PiruProfile.ownerID) == nil)
    }

    @Test
    func `Reading a journal nobody has written creates no file`() throws {
        let (directory, dir) = try makeScratchProfileDirectory()
        let bob = try directory.addProfile(name: "Bob")
        let container = try #require(directory.container(for: bob.id, writable: false))
        #expect(try container.mainContext.fetchCount(FetchDescriptor<DoseEntry>()) == 0)
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent(bob.storeFileName).path))
        #expect(directory.container(for: UUID(), writable: false) == nil)
    }

    @Test
    func `Deleting a profile sets its store aside under an intentional name`() throws {
        let (directory, dir) = try makeScratchProfileDirectory()
        let alice = try directory.addProfile(name: "Alice")
        let container = try #require(directory.container(for: alice.id, writable: true))
        container.mainContext.insert(DoseEntry(substance: "Methylphenidate", amount: 10))
        try container.mainContext.save()

        try directory.deleteProfile(id: alice.id)
        #expect(directory.profile(id: alice.id) == nil)
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(!files.contains(alice.storeFileName))
        let aside = files.filter { $0.hasPrefix(alice.storeFileName + ".") && !$0.hasSuffix("-wal") && !$0.hasSuffix("-shm") }
        #expect(aside.count == 1)
        let reason = aside.first.map { String($0.dropFirst(alice.storeFileName.count + 1)) }
        #expect(reason?.hasPrefix(StoreRecovery.profileDeleteReason + "-") == true)
        #expect(StoreRecovery.intentionalReasons.contains(StoreRecovery.profileDeleteReason))
        // The owner store's recovery never sees it: every candidate starts `default.store.`.
        #expect(!(aside.first ?? "").hasPrefix(StoreRecovery.storeName + "."))
        #expect(throws: ProfileDirectory.DirectoryError.self) { try directory.deleteProfile(id: PiruProfile.ownerID) }
    }

    @Test
    func `Renaming keeps the id and the store`() throws {
        let (directory, _) = try makeScratchProfileDirectory()
        var alice = try directory.addProfile(name: "Alice")
        alice.name = "Alicia"
        alice.avatar = try #require(ProfileAvatar.emoji("🦊"))
        alice.color = .forest
        try directory.update(alice)
        let stored = try #require(directory.profile(id: alice.id))
        #expect(stored.name == "Alicia")
        #expect(stored.avatar.kind == .emoji)
        #expect(stored.color == .forest)
        #expect(stored.storeFileName == PiruProfile.storeFileName(for: alice.id))
    }
}
