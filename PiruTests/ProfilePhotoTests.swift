import CoreGraphics
import Foundation
import SwiftData
import Testing
@testable import Piru

@Suite("Profiles — photos")
@MainActor
struct ProfilePhotoTests {
    private static let pixels = Data([0x01, 0x02, 0x03])

    @Test
    func `An avatar without a photo encodes as it did before photos`() throws {
        let avatar = ProfileAvatar.monogram(for: "Alice")
        let json = try #require(String(data: JSONEncoder().encode(avatar), encoding: .utf8))
        #expect(!json.contains("photo"))
        let withPhoto = avatar.withPhoto("a.heic")
        let decoded = try JSONDecoder().decode(ProfileAvatar.self, from: JSONEncoder().encode(withPhoto))
        #expect(decoded == withPhoto)
        #expect(decoded.text == "A")
    }

    @Test
    func `A registry write keeps the photos profiles name and removes the rest`() throws {
        let (directory, dir) = try makeScratchProfileDirectory()
        let kept = try ProfilePhotoStore.write(Self.pixels, fileExtension: "heic", in: dir)
        let orphan = try ProfilePhotoStore.write(Self.pixels, fileExtension: "heic", in: dir)
        try directory.addProfile(name: "Alice", avatar: ProfileAvatar.monogram(for: "Alice").withPhoto(kept))
        #expect(ProfilePhotoStore.data(named: kept, in: dir) == Self.pixels)
        #expect(ProfilePhotoStore.data(named: orphan, in: dir) == nil)
    }

    @Test
    func `Deleting a profile removes its photo`() throws {
        let (directory, dir) = try makeScratchProfileDirectory()
        let name = try ProfilePhotoStore.write(Self.pixels, fileExtension: "heic", in: dir)
        let alice = try directory.addProfile(name: "Alice", avatar: ProfileAvatar.monogram(for: "Alice").withPhoto(name))
        try directory.deleteProfile(id: alice.id)
        #expect(ProfilePhotoStore.data(named: name, in: dir) == nil)
    }

    @Test
    func `A name from a backup can't leave the photo folder`() throws {
        let (_, dir) = try makeScratchProfileDirectory()
        #expect(throws: (any Error).self) {
            try ProfilePhotoStore.write(Self.pixels, named: "../profiles.json", in: dir)
        }
        #expect(ProfilePhotoStore.data(named: "../profiles.json", in: dir) == nil)
    }

    @Test
    func `An owner's photo survives a backup made with one profile`() throws {
        let (source, sourceDir) = try makeScratchProfileDirectory()
        let name = try ProfilePhotoStore.write(Self.pixels, fileExtension: "heic", in: sourceDir)
        var owner = source.owner
        owner.avatar = owner.avatar.withPhoto(name)
        try source.update(owner)
        let data = try DataExportImport.exportBackupJSON(context: source.activeContainer.mainContext, directory: source)
        let section = try #require(DataExportImport.profilesSection(in: data))
        #expect(section.photos?[name] == Self.pixels)

        let (restored, restoredDir) = try makeScratchProfileDirectory()
        try BackupManager.shared.apply(
            plaintext: data, strategy: .merge, context: restored.activeContainer.mainContext, directory: restored,
        )
        #expect(restored.owner.avatar.photo == name)
        #expect(ProfilePhotoStore.data(named: name, in: restoredDir) == Self.pixels)
    }

    // MARK: - Crop geometry

    private let landscape = CropLayout(imageSize: CGSize(width: 1000, height: 500), diameter: 250)

    @Test
    func `Zoom 1 covers the circle with the short side`() {
        let crop = landscape.crop(for: CropFrame(zoom: 1, offset: .zero))
        #expect(crop == CGRect(x: 250, y: 0, width: 500, height: 500))
    }

    @Test
    func `The photo can't be dragged off the circle or zoomed out past it`() {
        let clamped = landscape.clamped(CropFrame(zoom: 0.5, offset: CGSize(width: 900, height: -900)))
        #expect(clamped.zoom == 1)
        // 1000 px at 0.5 pt/px is 500 pt wide: 125 pt of slack each side, none vertically.
        #expect(clamped.offset == CGSize(width: 125, height: 0))
        let crop = landscape.crop(for: clamped)
        #expect(crop.minX == 0)
        #expect(crop.width == 500)
    }

    @Test
    func `A face opens framed in the circle`() {
        let face = CGRect(x: 700, y: 150, width: 100, height: 100)
        let frame = landscape.framing(face: face)
        let crop = landscape.crop(for: frame)
        #expect(crop.contains(face))
        #expect(crop.width < 500)
        #expect(abs(crop.midX - face.midX) < 1)
    }
}
