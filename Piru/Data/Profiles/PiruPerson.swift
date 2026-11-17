import CryptoKit
import Foundation

/// Someone on another device this one has paired with: their public key, and a
/// profile that holds what they share. The profile's id is their person id,
/// and its store holds only their shared sessions, written by
/// ``ShareReceiver`` and never logged into here.
nonisolated struct PiruPerson: Codable, Hashable, Identifiable, Sendable {
    var profile: PiruProfile
    /// Their X25519 public key, raw.
    let publicKey: Data
    let pairedAt: Date

    var id: UUID {
        profile.id
    }

    var key: Curve25519.KeyAgreement.PublicKey? {
        try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: publicKey)
    }

    static func new(
        personID: UUID, name: String, avatar: ProfileAvatar, color: ProfileColor, publicKey: Data, now: Date = .now,
    ) -> PiruPerson {
        PiruPerson(
            profile: PiruProfile(
                id: personID,
                name: name,
                avatar: avatar,
                color: color,
                storeFileName: storeFileName(for: personID),
                createdAt: now,
            ),
            publicKey: publicKey,
            pairedAt: now,
        )
    }

    /// `person-<uuid>.store`, beside the profiles' stores and outside the
    /// owner store's recovery candidates.
    static func storeFileName(for id: UUID) -> String {
        "person-\(id.uuidString.lowercased()).store"
    }
}

/// The paired people, as `people.json` beside `profiles.json`. Only the app
/// reads it: the widgets and the Live Activity draw the active journal alone.
nonisolated enum PeopleRegistry {
    static let fileName = "people.json"
    static let formatVersion = 1

    private struct File: Codable {
        var version: Int
        var people: [PiruPerson]
    }

    static func load(from directory: URL) -> [PiruPerson] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(fileName)),
              let file = try? decoder.decode(File.self, from: data),
              file.version <= formatVersion
        else { return [] }
        var seen = Set<UUID>()
        return file.people.filter { $0.id != PiruProfile.ownerID && seen.insert($0.id).inserted }
    }

    static func save(_ people: [PiruPerson], to directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(File(version: formatVersion, people: people))
        try data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
    }
}
