import CryptoKit
import Foundation

/// A sealed share as it travels: readable only by the people it names, and
/// provably from the sender whose key it carries.
///
/// The body is compressed, then sealed with ChaChaPoly under a random content
/// key. That key is sealed to each recipient with HPKE in auth mode
/// (X25519, SHA-256, ChaChaPoly), so opening it also proves the sender held the
/// private key for `sender.key`. The header (format, version, sender) is the
/// associated data of every seal, so none of it can be swapped.
nonisolated struct ShareEnvelope: Codable, Equatable, Sendable {
    static let format = "piru-share"
    static let version = 1
    private static let info = Data("piru-share/1".utf8)
    private static let suite = HPKE.Ciphersuite.Curve25519_SHA256_ChachaPoly

    struct Party: Codable, Equatable, Sendable {
        let id: UUID
        let key: Data
    }

    struct Recipient: Codable, Equatable, Sendable {
        let id: UUID
        /// HPKE's encapsulated key.
        let enc: Data
        /// The content key, sealed to this recipient.
        let sealedKey: Data
    }

    let format: String
    let version: Int
    let sender: Party
    let recipients: [Recipient]
    let body: Data

    enum EnvelopeError: Error, Equatable {
        case notAShare
        case newerVersion
        case notForYou
        case damaged
    }

    // MARK: - Sealing

    static func seal(
        _ plaintext: Data,
        from identity: ShareIdentity,
        to recipients: [(id: UUID, key: Curve25519.KeyAgreement.PublicKey)],
    ) throws -> ShareEnvelope {
        let sender = Party(id: identity.personID, key: identity.publicKey.rawRepresentation)
        let aad = header(sender: sender, version: version)
        let contentKey = SymmetricKey(size: .bits256)
        let compressed = try (plaintext as NSData).compressed(using: .zlib) as Data
        let body = try ChaChaPoly.seal(compressed, using: contentKey, authenticating: aad).combined
        let keyBytes = contentKey.withUnsafeBytes { Data($0) }
        let sealed = try recipients.map { recipient in
            var hpke = try HPKE.Sender(
                recipientKey: recipient.key, ciphersuite: suite, info: info, authenticatedBy: identity.privateKey,
            )
            let sealedKey = try hpke.seal(keyBytes, authenticating: aad)
            return Recipient(id: recipient.id, enc: hpke.encapsulatedKey, sealedKey: sealedKey)
        }
        return ShareEnvelope(format: format, version: version, sender: sender, recipients: sealed, body: body)
    }

    // MARK: - Opening

    /// The envelope in `data`, before anything is opened.
    static func decode(_ data: Data) throws -> ShareEnvelope {
        guard let envelope = try? JSONDecoder().decode(ShareEnvelope.self, from: data),
              envelope.format == format
        else { throw EnvelopeError.notAShare }
        guard envelope.version <= version else { throw EnvelopeError.newerVersion }
        return envelope
    }

    var senderKey: Curve25519.KeyAgreement.PublicKey? {
        try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: sender.key)
    }

    /// The plaintext, opened with `identity`. Throws ``EnvelopeError/notForYou``
    /// when no recipient is `identity`, and ``EnvelopeError/damaged`` when a seal
    /// fails: a changed byte, or a sender that doesn't hold `sender.key`.
    func open(with identity: ShareIdentity) throws -> Data {
        guard let mine = recipients.first(where: { $0.id == identity.personID }) else { throw EnvelopeError.notForYou }
        guard let senderKey else { throw EnvelopeError.damaged }
        let aad = Self.header(sender: sender, version: version)
        do {
            var hpke = try HPKE.Recipient(
                privateKey: identity.privateKey, ciphersuite: Self.suite, info: Self.info,
                encapsulatedKey: mine.enc, authenticatedBy: senderKey,
            )
            let keyBytes = try hpke.open(mine.sealedKey, authenticating: aad)
            let box = try ChaChaPoly.SealedBox(combined: body)
            let compressed = try ChaChaPoly.open(box, using: SymmetricKey(data: keyBytes), authenticating: aad)
            return try (compressed as NSData).decompressed(using: .zlib) as Data
        } catch {
            throw EnvelopeError.damaged
        }
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(self)
    }

    private static func header(sender: Party, version: Int) -> Data {
        Data("\(format)|\(version)|\(sender.id.uuidString.lowercased())|".utf8) + sender.key
    }
}
