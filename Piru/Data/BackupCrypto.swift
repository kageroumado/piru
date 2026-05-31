import CommonCrypto
import CryptoKit
import Foundation
import os

private let cryptoLogger = Logger(subsystem: "dev.yumeji.piru", category: "BackupCrypto")

/// The cryptographic core of Piru's encrypted backups.
///
/// All backups are sealed with **AES-256-GCM** (authenticated encryption — any
/// tampering is detected on open). Two key sources are supported, expressed in
/// a single versioned envelope so a file is self-describing:
///
/// - **Device key** (`.deviceKey`): a random 256-bit key kept in the iCloud
///   Keychain. Because the key never leaves the Secure Enclave-backed keychain
///   and syncs end-to-end across the user's own devices, automatic iCloud
///   backups are E2E encrypted — neither Apple nor we can read them.
/// - **Passphrase** (`.passphrase`): a key derived from a user passphrase with
///   PBKDF2-HMAC-SHA256 (600 000 iterations, fresh 16-byte salt per file). The
///   passphrase is never stored or transmitted; a forgotten passphrase means
///   the file is unrecoverable, by design.
///
/// On any decryption failure the same opaque ``BackupError/decryptionFailed`` is
/// thrown whether the key was wrong or the ciphertext was tampered with — the
/// caller (and an attacker) learns nothing more than "this didn't open".
enum BackupCrypto {
    /// On-disk envelope format version. Bump only for breaking changes; add new
    /// cases to ``Envelope`` decoders for backward-compatible additions.
    static let format = 1

    /// PBKDF2 iteration count. 600 000 matches the OWASP 2023 floor for
    /// PBKDF2-HMAC-SHA256; recorded per-file in the envelope so it can be raised
    /// later without breaking old backups.
    static let pbkdf2Rounds = 600_000

    private static let keyByteCount = 32 // AES-256
    private static let saltByteCount = 16

    private static let keychainService = "dev.yumeji.piru.backup"
    private static let keychainAccount = "backupKey.v1"

    // MARK: - Errors

    enum BackupError: Error, LocalizedError, Equatable {
        /// Wrong key/passphrase, corruption, or tampering — deliberately not
        /// distinguished so neither users nor attackers can tell which.
        case decryptionFailed
        case emptyPassphrase
        case keyDerivationFailed
        case unsupportedFormat(Int)
        case malformed
        /// The device backup key isn't on this device (e.g. iCloud Keychain
        /// hasn't synced it yet, or it was created on a device you no longer have).
        case deviceKeyUnavailable
        case keychainFailure(OSStatus)

        var errorDescription: String? {
            switch self {
            case .decryptionFailed:
                String(localized: "Couldn't decrypt this backup. The passphrase may be wrong, or the file may be damaged.")
            case .emptyPassphrase:
                String(localized: "A passphrase is required.")
            case .keyDerivationFailed:
                String(localized: "Couldn't derive a key from the passphrase.")
            case let .unsupportedFormat(v):
                String(localized: "This backup uses a newer format (v\(v)) than this version of Piru understands. Please update the app.")
            case .malformed:
                String(localized: "This file isn't a valid Piru backup.")
            case .deviceKeyUnavailable:
                String(localized: "This device's backup key isn't available yet. If you just signed in, give iCloud Keychain a moment to sync.")
            case .keychainFailure:
                String(localized: "Couldn't access the secure keychain.")
            }
        }
    }

    // MARK: - Envelope

    /// Self-describing container persisted to disk (encoded as JSON).
    struct Envelope: Codable {
        enum Kind: String, Codable {
            case deviceKey
            case passphrase
        }

        struct KDF: Codable {
            var algorithm: String // "pbkdf2-hmac-sha256"
            var salt: Data
            var rounds: Int
        }

        var format: Int
        var kind: Kind
        /// Present only for ``Kind/passphrase``.
        var kdf: KDF?
        /// `AES.GCM.SealedBox.combined`: nonce ‖ ciphertext ‖ tag.
        var sealed: Data
        var createdAt: Date
        var appVersion: String
    }

    /// Read a backup's metadata (kind, creation date, app version) **without
    /// decrypting** — used by the UI to decide whether to prompt for a passphrase.
    static func inspect(_ envelopeData: Data) throws -> Envelope {
        guard let env = try? decoder.decode(Envelope.self, from: envelopeData) else {
            throw BackupError.malformed
        }
        guard env.format == format else { throw BackupError.unsupportedFormat(env.format) }
        return env
    }

    // MARK: - Encrypt

    /// Encrypt `plaintext` with the device's iCloud-Keychain backup key,
    /// creating the key on first use. Used for automatic iCloud backups.
    static func encryptWithDeviceKey(_ plaintext: Data, now: Date = Date()) throws -> Data {
        let key = try loadOrCreateDeviceKey()
        let sealed = try seal(plaintext, using: key)
        let env = Envelope(
            format: format,
            kind: .deviceKey,
            kdf: nil,
            sealed: sealed,
            createdAt: now,
            appVersion: appVersion,
        )
        return try encoder.encode(env)
    }

    /// Encrypt `plaintext` with a key derived from `passphrase`. Each call uses a
    /// fresh random salt. Used for manual, portable backups the user can restore
    /// on any device with the passphrase.
    static func encryptWithPassphrase(_ plaintext: Data, passphrase: String, now: Date = Date()) throws -> Data {
        let normalized = normalize(passphrase)
        guard !normalized.isEmpty else { throw BackupError.emptyPassphrase }
        let salt = try randomBytes(saltByteCount)
        let key = try deriveKey(passphrase: normalized, salt: salt, rounds: pbkdf2Rounds)
        let sealed = try seal(plaintext, using: key)
        let env = Envelope(
            format: format,
            kind: .passphrase,
            kdf: .init(algorithm: "pbkdf2-hmac-sha256", salt: salt, rounds: pbkdf2Rounds),
            sealed: sealed,
            createdAt: now,
            appVersion: appVersion,
        )
        return try encoder.encode(env)
    }

    // MARK: - Decrypt

    /// Decrypt a backup envelope. For ``Envelope/Kind/passphrase`` files a
    /// non-empty `passphrase` is required; for ``Envelope/Kind/deviceKey`` files
    /// the device's keychain key is used and `passphrase` is ignored.
    static func decrypt(_ envelopeData: Data, passphrase: String?) throws -> Data {
        let env = try inspect(envelopeData)
        let key: SymmetricKey
        switch env.kind {
        case .deviceKey:
            do {
                key = try loadDeviceKey()
            } catch {
                throw BackupError.deviceKeyUnavailable
            }
        case .passphrase:
            guard let kdf = env.kdf else { throw BackupError.malformed }
            let normalized = normalize(passphrase ?? "")
            guard !normalized.isEmpty else { throw BackupError.emptyPassphrase }
            key = try deriveKey(passphrase: normalized, salt: kdf.salt, rounds: kdf.rounds)
        }
        return try open(env.sealed, using: key)
    }

    // MARK: - Device key (iCloud Keychain)

    /// Whether a device backup key exists on (or has synced to) this device.
    static func deviceKeyExists() -> Bool {
        (try? loadDeviceKey()) != nil
    }

    private static func loadOrCreateDeviceKey() throws -> SymmetricKey {
        if let existing = try? loadDeviceKey() { return existing }

        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            // Sync end-to-end across the user's devices via iCloud Keychain.
            kSecAttrSynchronizable as String: kCFBooleanTrue!,
            // Readable after first unlock so background auto-backups work, but
            // never before the device has been unlocked once since boot.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: keyData,
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            // Lost a race with another thread or a just-synced item — read it.
            return try loadDeviceKey()
        }
        guard status == errSecSuccess else {
            cryptoLogger.error("Keychain add failed: \(status, privacy: .public)")
            throw BackupError.keychainFailure(status)
        }
        return key
    }

    private static func loadDeviceKey() throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            // Match whether the item is local or synchronized.
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data, data.count == keyByteCount else {
            throw BackupError.keychainFailure(status)
        }
        return SymmetricKey(data: data)
    }

    // MARK: - Primitives

    private static func seal(_ plaintext: Data, using key: SymmetricKey) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: key)
        guard let combined = box.combined else { throw BackupError.malformed }
        return combined
    }

    private static func open(_ combined: Data, using key: SymmetricKey) throws -> Data {
        do {
            let box = try AES.GCM.SealedBox(combined: combined)
            return try AES.GCM.open(box, using: key)
        } catch {
            // Opaque on purpose: wrong key vs. tamper are indistinguishable here.
            throw BackupError.decryptionFailed
        }
    }

    /// PBKDF2-HMAC-SHA256. `passphrase` must already be NFC-normalized.
    private static func deriveKey(passphrase: String, salt: Data, rounds: Int) throws -> SymmetricKey {
        let passwordData = Data(passphrase.utf8)
        var derived = Data(count: keyByteCount)
        let status: Int32 = derived.withUnsafeMutableBytes { derivedBuf in
            salt.withUnsafeBytes { saltBuf in
                passwordData.withUnsafeBytes { passBuf in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passBuf.baseAddress?.assumingMemoryBound(to: CChar.self),
                        passwordData.count,
                        saltBuf.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(rounds),
                        derivedBuf.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        keyByteCount,
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw BackupError.keyDerivationFailed }
        return SymmetricKey(data: derived)
    }

    private static func randomBytes(_ count: Int) throws -> Data {
        var bytes = Data(count: count)
        let status = bytes.withUnsafeMutableBytes { buf in
            SecRandomCopyBytes(kSecRandomDefault, count, buf.baseAddress!)
        }
        guard status == errSecSuccess else { throw BackupError.keyDerivationFailed }
        return bytes
    }

    /// NFC-normalize so a passphrase typed with different input methods (e.g.
    /// decomposed vs. precomposed accents) derives the same key.
    private static func normalize(_ passphrase: String) -> String {
        passphrase.precomposedStringWithCanonicalMapping
    }

    // MARK: - Coding

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.dataEncodingStrategy = .base64
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        d.dataDecodingStrategy = .base64
        return d
    }

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
