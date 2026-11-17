import CryptoKit
import Foundation

/// What a pairing QR code holds: a `piru://pair` link with the person id, the
/// public key and the name to show. The system Camera opens it in Piru as well
/// as the in-app scanner does.
nonisolated struct PairingCode: Hashable, Sendable {
    let personID: UUID
    let publicKey: Data
    let name: String
    let avatar: ProfileAvatar

    private static let host = "pair"

    init(personID: UUID, publicKey: Data, name: String, avatar: ProfileAvatar) {
        self.personID = personID
        self.publicKey = publicKey
        self.name = name
        self.avatar = avatar
    }

    init(identity: ShareIdentity, profile: PiruProfile) {
        self.init(
            personID: identity.personID,
            publicKey: identity.publicKey.rawRepresentation,
            name: profile.name,
            avatar: profile.avatar.withPhoto(nil),
        )
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = "piru"
        components.host = Self.host
        var items = [
            URLQueryItem(name: "v", value: "1"),
            URLQueryItem(name: "id", value: personID.uuidString.lowercased()),
            URLQueryItem(name: "k", value: publicKey.base64URLEncoded),
            URLQueryItem(name: "n", value: name),
        ]
        items.append(URLQueryItem(name: avatar.kind == .emoji ? "e" : "m", value: avatar.text))
        components.queryItems = items
        return components.url ?? URL(fileURLWithPath: "/")
    }

    /// The code in a `piru://pair` link; `nil` for any other link or one that
    /// is missing a part or carries a key that isn't an X25519 key.
    init?(url: URL) {
        guard url.scheme?.lowercased() == "piru", url.host?.lowercased() == Self.host,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return nil }
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }
        guard value("v") == "1",
              let id = value("id").flatMap(UUID.init(uuidString:)), id != PiruProfile.ownerID,
              let key = value("k").flatMap(Data.init(base64URLEncoded:)),
              (try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: key)) != nil
        else { return nil }
        let name = String((value("n") ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        guard !name.isEmpty else { return nil }
        let avatar: ProfileAvatar = if let emoji = value("e").flatMap(ProfileAvatar.emoji) {
            emoji
        } else if let letters = value("m") {
            .monogram(text: letters)
        } else {
            .monogram(for: name)
        }
        self.init(personID: id, publicKey: key, name: name, avatar: avatar)
    }
}

nonisolated extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded string: String) {
        var base64 = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }
}
