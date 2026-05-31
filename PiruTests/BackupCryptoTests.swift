import CryptoKit
import Foundation
import Testing
@testable import Piru

@Suite("BackupCrypto — passphrase round-trip")
struct BackupCryptoPassphraseTests {
    let plaintext = Data("the quick brown fox logs a dose".utf8)

    @Test
    func `Encrypts and decrypts with the correct passphrase`() throws {
        let envelope = try BackupCrypto.encryptWithPassphrase(plaintext, passphrase: "correct horse battery staple")
        let recovered = try BackupCrypto.decrypt(envelope, passphrase: "correct horse battery staple")
        #expect(recovered == plaintext)
    }

    @Test
    func `Wrong passphrase fails with the opaque error`() throws {
        let envelope = try BackupCrypto.encryptWithPassphrase(plaintext, passphrase: "correct horse battery staple")
        #expect(throws: BackupCrypto.BackupError.decryptionFailed) {
            _ = try BackupCrypto.decrypt(envelope, passphrase: "Tr0ub4dor&3")
        }
    }

    @Test
    func `Empty passphrase is rejected on encrypt`() {
        #expect(throws: BackupCrypto.BackupError.emptyPassphrase) {
            _ = try BackupCrypto.encryptWithPassphrase(plaintext, passphrase: "")
        }
    }

    @Test
    func `Whitespace-only passphrase still encrypts (not trimmed to empty)`() throws {
        // We normalize (NFC) but do not trim — a passphrase of spaces is a valid
        // (if unwise) secret and must round-trip exactly.
        let envelope = try BackupCrypto.encryptWithPassphrase(plaintext, passphrase: "   ")
        let recovered = try BackupCrypto.decrypt(envelope, passphrase: "   ")
        #expect(recovered == plaintext)
    }

    @Test
    func `Missing passphrase on a passphrase backup fails`() throws {
        let envelope = try BackupCrypto.encryptWithPassphrase(plaintext, passphrase: "hunter2")
        #expect(throws: BackupCrypto.BackupError.emptyPassphrase) {
            _ = try BackupCrypto.decrypt(envelope, passphrase: nil)
        }
    }

    @Test
    func `Unicode-normalization equivalence: decomposed and precomposed match`() throws {
        // "café" precomposed (U+00E9) vs decomposed (e + U+0301) must derive the
        // same key after NFC normalization.
        let precomposed = "caf\u{00E9}"
        let decomposed = "cafe\u{0301}"
        let envelope = try BackupCrypto.encryptWithPassphrase(plaintext, passphrase: precomposed)
        let recovered = try BackupCrypto.decrypt(envelope, passphrase: decomposed)
        #expect(recovered == plaintext)
    }
}

@Suite("BackupCrypto — integrity & tamper")
struct BackupCryptoIntegrityTests {
    let plaintext = Data("sensitive journal data".utf8)
    let passphrase = "a-reasonably-long-passphrase"

    /// Re-encode an envelope with the same coding strategy BackupCrypto uses, so
    /// a tampered re-encode is rejected by GCM (not by a date-format mismatch).
    private func reencode(_ env: BackupCrypto.Envelope) throws -> Data {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.dataEncodingStrategy = .base64
        return try e.encode(env)
    }

    @Test
    func `Flipping a byte of the sealed ciphertext fails authentication`() throws {
        let envelopeData = try BackupCrypto.encryptWithPassphrase(plaintext, passphrase: passphrase)
        var env = try BackupCrypto.inspect(envelopeData)
        var sealed = env.sealed
        // Flip a bit in the middle of the ciphertext (past the 12-byte nonce).
        let idx = sealed.startIndex + sealed.count / 2
        sealed[idx] ^= 0xFF
        env.sealed = sealed
        let tampered = try reencode(env)
        #expect(throws: BackupCrypto.BackupError.decryptionFailed) {
            _ = try BackupCrypto.decrypt(tampered, passphrase: passphrase)
        }
    }

    @Test
    func `Garbage data is reported as malformed, not a crash`() {
        let garbage = Data("not even json".utf8)
        #expect(throws: BackupCrypto.BackupError.malformed) {
            _ = try BackupCrypto.inspect(garbage)
        }
    }

    @Test
    func `A future format version is rejected as unsupported`() throws {
        let envelopeData = try BackupCrypto.encryptWithPassphrase(plaintext, passphrase: passphrase)
        var env = try BackupCrypto.inspect(envelopeData)
        env.format = 999
        let bumped = try reencode(env)
        #expect(throws: BackupCrypto.BackupError.unsupportedFormat(999)) {
            _ = try BackupCrypto.inspect(bumped)
        }
    }
}

@Suite("BackupCrypto — envelope metadata")
struct BackupCryptoEnvelopeTests {
    let plaintext = Data("payload".utf8)

    @Test
    func `inspect() reveals kind and KDF params without the plaintext`() throws {
        let envelopeData = try BackupCrypto.encryptWithPassphrase(plaintext, passphrase: "pw")
        let env = try BackupCrypto.inspect(envelopeData)
        #expect(env.kind == .passphrase)
        #expect(env.format == BackupCrypto.format)
        #expect(env.kdf?.algorithm == "pbkdf2-hmac-sha256")
        #expect(env.kdf?.rounds == BackupCrypto.pbkdf2Rounds)
        #expect(env.kdf?.salt.count == 16)
        #expect(!env.sealed.isEmpty)
    }

    @Test
    func `Two encryptions of identical plaintext produce different salts and ciphertext`() throws {
        let a = try BackupCrypto.inspect(BackupCrypto.encryptWithPassphrase(plaintext, passphrase: "pw"))
        let b = try BackupCrypto.inspect(BackupCrypto.encryptWithPassphrase(plaintext, passphrase: "pw"))
        #expect(a.kdf?.salt != b.kdf?.salt)
        #expect(a.sealed != b.sealed)
    }

    @Test
    func `createdAt is recorded from the supplied clock`() throws {
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        let envelopeData = try BackupCrypto.encryptWithPassphrase(plaintext, passphrase: "pw", now: when)
        let env = try BackupCrypto.inspect(envelopeData)
        #expect(abs(env.createdAt.timeIntervalSince(when)) < 1)
    }
}
