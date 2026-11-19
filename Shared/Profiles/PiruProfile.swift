import Foundation

/// One person's journal: a name, an avatar on a color, and the SwiftData store
/// file that holds everything they log. Every profile's store has the full
/// ``PiruSchema``, so a profile's doses, sessions, meds, tolerance and body
/// weight are separate by construction: a query only ever sees its own store.
///
/// The device owner is the first profile and the one whose store is the one
/// Piru has always opened. Owning is a role, kept by that store file; the id is
/// the owner's own, minted on the device like anyone's, so two devices' owners
/// are two people.
nonisolated struct PiruProfile: Codable, Hashable, Identifiable, Sendable {
    /// The id every owner had before owners got ids of their own. A registry
    /// still carrying it is migrated at launch, and a backup, link or shared
    /// inventory item that names it means this device's owner.
    static let legacyOwnerID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    /// The owner's store, beside every other profile's in the App Group container.
    static let ownerStoreFileName = "default.store"

    let id: UUID
    var name: String
    var avatar: ProfileAvatar
    var color: ProfileColor
    /// The store's file name in the App Group container.
    let storeFileName: String
    let createdAt: Date

    var isOwner: Bool {
        storeFileName == Self.ownerStoreFileName
    }

    /// The owner as it stands before anyone renames it: "Me", a monogram of
    /// its first letter, on the accent rose.
    static func defaultOwner(name: String, id: UUID = legacyOwnerID) -> PiruProfile {
        PiruProfile(
            id: id,
            name: name,
            avatar: .monogram(for: name),
            color: .rose,
            storeFileName: ownerStoreFileName,
            createdAt: .distantPast,
        )
    }

    /// The same person under another id, on the store that id names: the owner
    /// keeps the owner's store, anyone else gets `profile-<id>.store`.
    func reidentified(as id: UUID, asOwner: Bool) -> PiruProfile {
        PiruProfile(
            id: id,
            name: name,
            avatar: avatar,
            color: color,
            storeFileName: asOwner ? Self.ownerStoreFileName : Self.storeFileName(for: id),
            createdAt: createdAt,
        )
    }

    /// Whether `other` shows as this profile does: same name, avatar and color.
    func looksLike(_ other: PiruProfile) -> Bool {
        name == other.name && avatar == other.avatar && color == other.color
    }

    /// A new person, on a store file of its own.
    static func new(name: String, avatar: ProfileAvatar, color: ProfileColor, now: Date = .now) -> PiruProfile {
        let id = UUID()
        return PiruProfile(
            id: id,
            name: name,
            avatar: avatar,
            color: color,
            storeFileName: storeFileName(for: id),
            createdAt: now,
        )
    }

    /// `profile-<uuid>.store`: the prefix keeps every profile's file and its
    /// sidecars out of the owner store's recovery candidates, which all start
    /// `default.store.`.
    static func storeFileName(for id: UUID) -> String {
        "profile-\(id.uuidString.lowercased()).store"
    }
}

/// What a profile's avatar circle shows: the photo `photo` names, or else one
/// or two letters or one emoji. The letters or emoji stay set under a photo,
/// so a build or screen that can't draw the photo still has an avatar.
nonisolated struct ProfileAvatar: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case monogram
        case emoji
    }

    let kind: Kind
    let text: String
    /// The photo's file name in ``ProfilePhotoStore``. A new photo always
    /// gets a new name, so the avatar changes whenever the photo does and
    /// every cache keyed by the avatar refreshes.
    var photo: String?

    /// The same letters or emoji with `photo` drawn over them, or without one.
    func withPhoto(_ photo: String?) -> ProfileAvatar {
        ProfileAvatar(kind: kind, text: text, photo: photo)
    }

    /// The first letter of `name`, uppercased; "?" for a name with no letter.
    static func monogram(for name: String) -> ProfileAvatar {
        let letter = name.trimmingCharacters(in: .whitespacesAndNewlines).first { $0.isLetter || $0.isNumber }
        return ProfileAvatar(kind: .monogram, text: letter.map { String($0).uppercased() } ?? "?")
    }

    /// Up to two letters, uppercased. Empty input falls back to "?".
    static func monogram(text: String) -> ProfileAvatar {
        let letters = text.filter { $0.isLetter || $0.isNumber }.prefix(2)
        return ProfileAvatar(kind: .monogram, text: letters.isEmpty ? "?" : String(letters).uppercased())
    }

    /// The first emoji in `text`, or `nil` when it holds none.
    static func emoji(_ text: String) -> ProfileAvatar? {
        guard let first = text.first(where: \.isEmojiGlyph) else { return nil }
        return ProfileAvatar(kind: .emoji, text: String(first))
    }
}

nonisolated extension Character {
    /// Drawn as an emoji: a presentation-emoji scalar, or any emoji scalar with
    /// a variation selector or joiner after it. Digits and `#` are emoji
    /// scalars too, but draw as text on their own.
    var isEmojiGlyph: Bool {
        guard let first = unicodeScalars.first else { return false }
        return first.properties.isEmojiPresentation
            || (first.properties.isEmoji && unicodeScalars.count > 1)
    }
}

/// The eight colors a profile can wear. Each is defined in Oklch, dark enough
/// (L ≈ 0.48–0.54) that a white monogram on it clears 4.5:1, and darker than
/// every substance class color, so an avatar never reads as a substance dot.
/// Neighbors sit ≥ 0.08 apart in Oklab.
nonisolated enum ProfileColor: String, Codable, CaseIterable, Sendable {
    case rose
    case plum
    case violet
    case indigo
    case ocean
    case teal
    case forest
    case amber

    var oklch: Oklch {
        switch self {
        case .rose: Oklch(l: 0.53, c: 0.17, h: 8)
        case .plum: Oklch(l: 0.50, c: 0.16, h: 335)
        case .violet: Oklch(l: 0.52, c: 0.17, h: 300)
        case .indigo: Oklch(l: 0.48, c: 0.15, h: 268)
        case .ocean: Oklch(l: 0.52, c: 0.12, h: 240)
        case .teal: Oklch(l: 0.53, c: 0.09, h: 195)
        case .forest: Oklch(l: 0.50, c: 0.11, h: 148)
        case .amber: Oklch(l: 0.54, c: 0.11, h: 62)
        }
    }

    var p3: P3Color {
        oklch.displayP3
    }

    /// The same hue lifted to L 0.70 for a curve stroke and fill, which has to
    /// read on black as well as on white; the avatar's L ≈ 0.5 sinks into a
    /// dark background.
    var curveP3: P3Color {
        Oklch(l: 0.70, c: oklch.c, h: oklch.h).displayP3
    }

    /// The color the next new profile gets: the first one nobody wears yet.
    static func next(after used: some Sequence<ProfileColor>) -> ProfileColor {
        let taken = Set(used)
        return allCases.first { !taken.contains($0) } ?? allCases[taken.count % allCases.count]
    }
}
