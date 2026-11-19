import Foundation
import Testing
@testable import Piru

@Suite("Profiles — registry and scope")
struct ProfileRegistryTests {
    private static func scratch() throws -> (URL, UserDefaults) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("profiles-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let defaults = try #require(UserDefaults(suiteName: "piru.tests.profiles.\(UUID().uuidString)"))
        return (dir, defaults)
    }

    @Test
    func `With no file the owner is the only profile and nothing is written`() throws {
        let (dir, defaults) = try Self.scratch()
        let profiles = ProfileRegistry.load(from: dir)
        #expect(profiles.count == 1)
        #expect(profiles.first?.isOwner == true)
        #expect(profiles.first?.storeFileName == PiruProfile.ownerStoreFileName)
        #expect(ProfileRegistry.activeProfileID(defaults: defaults, directory: dir) == PiruProfile.legacyOwnerID)
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent(ProfileRegistry.fileName).path))
    }

    @Test
    func `Saved profiles load back, the owner first`() throws {
        let (dir, _) = try Self.scratch()
        let alice = PiruProfile.new(name: "Alice", avatar: .monogram(for: "Alice"), color: .violet)
        let owner = PiruProfile.defaultOwner(name: "Kiri")
        try ProfileRegistry.save([alice, owner], to: dir)
        let loaded = ProfileRegistry.load(from: dir)
        #expect(loaded.map(\.id) == [owner.id, alice.id])
        #expect(loaded[1].name == "Alice")
        #expect(loaded[1].color == .violet)
        #expect(loaded[1].storeFileName == "profile-\(alice.id.uuidString.lowercased()).store")
    }

    @Test
    func `A file missing the owner or repeating an id normalizes`() {
        let alice = PiruProfile.new(name: "Alice", avatar: .monogram(for: "Alice"), color: .violet)
        let normalized = ProfileRegistry.normalized([alice, alice])
        #expect(normalized.count == 2)
        #expect(normalized[0].isOwner)
        #expect(normalized[1].id == alice.id)
    }

    @Test
    func `An active id naming nobody falls back to the owner`() throws {
        let (dir, defaults) = try Self.scratch()
        let alice = PiruProfile.new(name: "Alice", avatar: .monogram(for: "Alice"), color: .violet)
        try ProfileRegistry.save([.defaultOwner(name: "Me"), alice], to: dir)
        ProfileRegistry.setActiveProfileID(alice.id, defaults: defaults, directory: dir)
        #expect(ProfileRegistry.activeProfileID(defaults: defaults, directory: dir) == alice.id)
        #expect(ProfileRegistry.activeStoreURL(defaults: defaults, directory: dir).lastPathComponent == alice.storeFileName)
        defaults.set(UUID().uuidString, forKey: ProfileRegistry.activeProfileKey)
        #expect(ProfileRegistry.activeProfileID(defaults: defaults, directory: dir) == ProfileRegistry.ownerID(in: dir))
        ProfileRegistry.setActiveProfileID(ProfileRegistry.ownerID(in: dir), defaults: defaults, directory: dir)
        #expect(defaults.string(forKey: ProfileRegistry.activeProfileKey) == nil)
    }

    @Test
    func `The owner keeps every key and identifier it always had`() {
        for owner in [ProfileRegistry.ownerID(), PiruProfile.legacyOwnerID] {
            #expect(ProfileScope.key("doseLogStoreGeneration", for: owner) == "doseLogStoreGeneration")
            #expect(ProfileScope.notificationNamespace(for: owner).isEmpty)
        }
        let id = UUID()
        #expect(ProfileScope.key("doseLogStoreGeneration", for: id) == "doseLogStoreGeneration.\(id.uuidString.lowercased())")
        #expect(ProfileScope.notificationNamespace(for: id) == "\(id.uuidString.lowercased()).")
    }

    @Test
    func `A notification identifier names its profile`() {
        let id = UUID()
        let scoped = ProfileScope.$pinned.withValue(id) {
            NotificationType.routine.identifier(anchor: "methylphenidate-oral")
        }
        #expect(scoped == "piru.notif.\(id.uuidString.lowercased()).routine.methylphenidate-oral")
        #expect(ProfileScope.profileID(fromNotificationIdentifier: scoped) == id)
        let owner = ProfileScope.$pinned.withValue(ProfileRegistry.ownerID()) {
            NotificationType.routine.identifier(anchor: "methylphenidate-oral")
        }
        #expect(owner == "piru.notif.routine.methylphenidate-oral")
        #expect(ProfileScope.profileID(fromNotificationIdentifier: owner) == ProfileRegistry.ownerID())
        #expect(ProfileScope.profileID(fromNotificationIdentifier: "routineReminder_x") == ProfileRegistry.ownerID())
    }

    @Test
    func `One profile's sweep never matches another's requests`() {
        let alice = UUID()
        let ownerPrefixes = ProfileScope.$pinned.withValue(ProfileRegistry.ownerID()) {
            NotificationType.allCases.flatMap(\.identifierPrefixes)
        }
        let alicePrefixes = ProfileScope.$pinned.withValue(alice) {
            NotificationType.allCases.flatMap(\.identifierPrefixes)
        }
        let aliceIDs = ProfileScope.$pinned.withValue(alice) {
            NotificationType.allCases.map { $0.identifier(anchor: "x", ordinal: "1") }
        }
        let ownerIDs = ProfileScope.$pinned.withValue(ProfileRegistry.ownerID()) {
            NotificationType.allCases.map { $0.identifier(anchor: "x", ordinal: "1") }
        }
        for id in aliceIDs {
            #expect(!ownerPrefixes.contains { id.hasPrefix($0) }, "owner sweep hits \(id)")
        }
        for id in ownerIDs {
            #expect(!alicePrefixes.contains { id.hasPrefix($0) }, "Alice's sweep hits \(id)")
        }
    }

    @Test
    func `Avatars keep one emoji or two letters`() {
        #expect(ProfileAvatar.monogram(for: " alice").text == "A")
        #expect(ProfileAvatar.monogram(text: "bo b").text == "BO")
        #expect(ProfileAvatar.emoji("hi 🦊 there")?.text == "🦊")
        #expect(ProfileAvatar.emoji("abc") == nil)
        #expect(ProfileAvatar.emoji("1#") == nil)
    }
}

@Suite("Profiles — colors")
struct ProfileColorTests {
    /// WCAG relative luminance of an encoded Display P3 color.
    private static func luminance(_ p3: P3Color) -> Double {
        func linear(_ v: Double) -> Double {
            v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2289746 * linear(p3.red) + 0.6917385 * linear(p3.green) + 0.0792869 * linear(p3.blue)
    }

    @Test(arguments: ProfileColor.allCases)
    func `White monograms read at 4.5 to 1 or better`(color: ProfileColor) {
        let contrast = 1.05 / (Self.luminance(color.p3) + 0.05)
        #expect(contrast >= 4.5, "\(color): \(contrast)")
        #expect(color.oklch.isInDisplayP3)
    }

    @Test
    func `Every pair of profile colors is told apart`() {
        func lab(_ c: Oklch) -> (Double, Double, Double) {
            (c.l, c.c * cos(c.h * .pi / 180), c.c * sin(c.h * .pi / 180))
        }
        let colors = ProfileColor.allCases
        for (i, a) in colors.enumerated() {
            for b in colors[(i + 1)...] {
                let (l1, a1, b1) = lab(a.oklch)
                let (l2, a2, b2) = lab(b.oklch)
                let distance = sqrt(pow(l1 - l2, 2) + pow(a1 - a2, 2) + pow(b1 - b2, 2))
                #expect(distance >= 0.08, "\(a) vs \(b): \(distance)")
            }
        }
    }

    @Test
    func `A new profile gets the first color nobody wears`() {
        #expect(ProfileColor.next(after: [.rose]) == .plum)
        #expect(ProfileColor.next(after: [.rose, .plum, .violet]) == .indigo)
        #expect(ProfileColor.allCases.contains(ProfileColor.next(after: ProfileColor.allCases)))
    }
}
