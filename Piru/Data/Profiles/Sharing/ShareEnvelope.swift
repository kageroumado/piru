import Compression
import CryptoKit
import Foundation

/// A sealed share as it travels: readable only by the people it names, and
/// provably from the sender whose key it carries.
///
/// The body is compressed, then sealed with ChaChaPoly under a random content
/// key. That key is sealed to each recipient with HPKE in auth mode
/// (X25519, SHA-256, ChaChaPoly), so opening it also proves the sender held the
/// private key for `sender.key`. The header (format, version, sender) is the
/// associated data of every seal, so none of it can be swapped. Each sealed key
/// also authenticates a hash of the body: every recipient learns the content
/// key, and without that hash one of them could seal a body of their own under
/// it and pass it to another recipient beside the key the sender sealed to them.
nonisolated struct ShareEnvelope: Codable, Equatable, Sendable {
    static let format = "piru-share"
    static let version = 2
    private static let info = Data("piru-share/1".utf8)
    private static let suite = HPKE.Ciphersuite.Curve25519_SHA256_ChachaPoly
    /// The largest file read as a share. A session's share is a few KB; this
    /// leaves room for thousands of doses and notes.
    static let maxFileBytes = 4_000_000
    /// The most a body may inflate to. Anyone holding a public key can seal to
    /// it, so the inflated size is capped before it is believed.
    static let maxBodyBytes = 8_000_000

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
            let sealedKey = try hpke.seal(keyBytes, authenticating: keyAAD(header: aad, body: body))
            return Recipient(id: recipient.id, enc: hpke.encapsulatedKey, sealedKey: sealedKey)
        }
        return ShareEnvelope(format: format, version: version, sender: sender, recipients: sealed, body: body)
    }

    // MARK: - Opening

    /// The envelope in `data`, before anything is opened.
    static func decode(_ data: Data) throws -> ShareEnvelope {
        guard data.count <= maxFileBytes else { throw EnvelopeError.damaged }
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
            let keyBytes = try hpke.open(mine.sealedKey, authenticating: Self.keyAAD(header: aad, body: body))
            let box = try ChaChaPoly.SealedBox(combined: body)
            let compressed = try ChaChaPoly.open(box, using: SymmetricKey(data: keyBytes), authenticating: aad)
            guard let plaintext = Self.inflate(compressed, limit: Self.maxBodyBytes) else { throw EnvelopeError.damaged }
            return plaintext
        } catch {
            throw EnvelopeError.damaged
        }
    }

    /// Raw-deflate `data` into at most `limit` bytes; `nil` when it is empty,
    /// malformed, or would inflate past `limit`.
    private static func inflate(_ data: Data, limit: Int) -> Data? {
        guard !data.isEmpty else { return nil }
        var output = Data(count: limit + 1)
        let written = output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                guard let out = destination.bindMemory(to: UInt8.self).baseAddress,
                      let input = source.bindMemory(to: UInt8.self).baseAddress
                else { return 0 }
                return compression_decode_buffer(out, limit + 1, input, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0, written <= limit else { return nil }
        output.count = written
        return output
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(self)
    }

    static func header(sender: Party, version: Int) -> Data {
        Data("\(format)|\(version)|\(sender.id.uuidString.lowercased())|".utf8) + sender.key
    }

    /// The associated data of a sealed content key: the header and the body's
    /// SHA-256, which ties the key to the one body the sender sealed with it.
    static func keyAAD(header: Data, body: Data) -> Data {
        header + Data(SHA256.hash(data: body))
    }
}
