import CommonCrypto
import CryptoKit
import Foundation
import os

private nonisolated let cryptoLogger = Logger(subsystem: "dev.yumeji.piru", category: "BackupCrypto")

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
/// The header (format, kind, KDF parameters, key id) is bound as AES-GCM
/// *associated data*, so those fields can't be tampered with — a forged
/// `rounds` or `salt` makes the open fail rather than steering key derivation.
/// Device-key backups also carry a `keyID` so a device holding a different
/// iCloud-Keychain key reports an accurate "key unavailable" rather than an
/// opaque decrypt failure.
///
/// On any decryption failure the same opaque ``BackupError/decryptionFailed`` is
/// thrown whether the key was wrong or the ciphertext was tampered with — the
/// caller (and an attacker) learns nothing more than "this didn't open".
///
/// Every entry point is `nonisolated` so the caller can — and should — run key
/// derivation, keychain IO, and sealing **off the main actor** (PBKDF2 at
/// 600 000 rounds is a multi-hundred-millisecond CPU burst). See ``BackupManager``.
nonisolated enum BackupCrypto {
    /// On-disk envelope format version. Bump only for breaking changes.
    static let format = 1

    /// PBKDF2 iteration count we write. 600 000 matches the OWASP 2023 floor for
    /// PBKDF2-HMAC-SHA256; recorded per-file in the envelope so it can be raised
    /// later without breaking old backups.
    static let pbkdf2Rounds = 600_000

    /// Accepted PBKDF2 work-factor band when *reading* a file. The lower bound
    /// stops a tampered file from trivially weakening derivation; the upper
    /// bound stops a hostile file from pinning the CPU — and, just as important,
    /// keeps `rounds` inside `UInt32` so `UInt32(rounds)` can't trap. Files we
    /// write always use ``pbkdf2Rounds``.
    private static let minRounds = 100_000
    private static let maxRounds = 10_000_000

    /// Hard ceiling on an envelope we'll parse, so a hostile file can't OOM the
    /// app on decode. A real journal export is a few MB; 256 MB is generous.
    static let maxEnvelopeBytes = 256 * 1_024 * 1_024

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
        /// hasn't synced it yet, the backup was made on a device you no longer
        /// have, or a different key won an iCloud-Keychain sync race).
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
        /// Identifies which device key sealed this (``Kind/deviceKey`` only).
        /// A short hash of the key bytes; reveals nothing about the key itself
        /// but lets a device tell whether the synced key is the right one.
        var keyID: String?
        /// `AES.GCM.SealedBox.combined`: nonce ‖ ciphertext ‖ tag.
        var sealed: Data
        var createdAt: Date
        var appVersion: String
    }

    /// Read a backup's metadata (kind, creation date, app version) **without
    /// decrypting** — used by the UI to decide whether to prompt for a
    /// passphrase. Also the single validation gate: rejects oversized input, an
    /// unsupported format, and out-of-band KDF parameters before any of those
    /// values can reach key derivation.
    static func inspect(_ envelopeData: Data) throws -> Envelope {
        guard envelopeData.count <= maxEnvelopeBytes else { throw BackupError.malformed }
        guard let env = try? decoder.decode(Envelope.self, from: envelopeData) else {
            throw BackupError.malformed
        }
        guard env.format == format else {
            throw BackupError.unsupportedFormat(env.format)
        }
        if env.kind == .passphrase {
            // Validate the attacker-controllable KDF header before it can steer
            // derivation: a hostile `rounds` would otherwise hang the CPU (or
            // trap `UInt32(rounds)`), and a wrong-length salt is nonsense.
            guard let kdf = env.kdf,
                  kdf.algorithm == "pbkdf2-hmac-sha256",
                  kdf.salt.count == saltByteCount,
                  (minRounds ... maxRounds).contains(kdf.rounds)
            else { throw BackupError.malformed }
        }
        return env
    }

    // MARK: - Encrypt

    /// Encrypt `plaintext` with the device's iCloud-Keychain backup key,
    /// creating the key on first use. Used for automatic iCloud backups.
    static func encryptWithDeviceKey(_ plaintext: Data, now: Date = Date()) throws -> Data {
        let key = try loadOrCreateDeviceKey()
        let id = keyID(of: key)
        let aad = headerAAD(format: format, kind: .deviceKey, kdf: nil, keyID: id)
        let sealed = try seal(plaintext, using: key, aad: aad)
        let env = Envelope(
            format: format,
            kind: .deviceKey,
            kdf: nil,
            keyID: id,
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
        let kdf = Envelope.KDF(algorithm: "pbkdf2-hmac-sha256", salt: salt, rounds: pbkdf2Rounds)
        let aad = headerAAD(format: format, kind: .passphrase, kdf: kdf, keyID: nil)
        let sealed = try seal(plaintext, using: key, aad: aad)
        let env = Envelope(
            format: format,
            kind: .passphrase,
            kdf: kdf,
            keyID: nil,
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
        let aad: Data
        switch env.kind {
        case .deviceKey:
            let loaded: SymmetricKey
            do {
                loaded = try loadDeviceKey()
            } catch {
                throw BackupError.deviceKeyUnavailable
            }
            // The key the file names must be *this* device's key; a mismatch
            // means a different key synced in (cross-device race) and the backup
            // can't be read here.
            if let fileID = env.keyID, keyID(of: loaded) != fileID {
                throw BackupError.deviceKeyUnavailable
            }
            key = loaded
            aad = headerAAD(format: env.format, kind: .deviceKey, kdf: nil, keyID: env.keyID)
        case .passphrase:
            guard let kdf = env.kdf else { throw BackupError.malformed }
            let normalized = normalize(passphrase ?? "")
            guard !normalized.isEmpty else { throw BackupError.emptyPassphrase }
            key = try deriveKey(passphrase: normalized, salt: kdf.salt, rounds: kdf.rounds)
            aad = headerAAD(format: env.format, kind: .passphrase, kdf: kdf, keyID: nil)
        }
        return try open(env.sealed, using: key, aad: aad)
    }

    // MARK: - Device key (iCloud Keychain)

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
            // Readable after first unlock so an auto-backup triggered while the
            // app is backgrounding (and a future background task) can reach the
            // key, but never before the device has been unlocked once since boot.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: keyData,
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            // Lost a race with another thread or a just-synced item — read it.
            // Never overwrite: the existing key is the only thing that can open
            // backups already written with it.
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

    private static func seal(_ plaintext: Data, using key: SymmetricKey, aad: Data) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: key, authenticating: aad)
        guard let combined = box.combined else { throw BackupError.malformed }
        return combined
    }

    private static func open(_ combined: Data, using key: SymmetricKey, aad: Data) throws -> Data {
        do {
            let box = try AES.GCM.SealedBox(combined: combined)
            return try AES.GCM.open(box, using: key, authenticating: aad)
        } catch {
            // Opaque on purpose: wrong key vs. tamper are indistinguishable here.
            throw BackupError.decryptionFailed
        }
    }

    /// Canonical, deterministic serialization of the header fields that must be
    /// authenticated. Bound as AES-GCM associated data so tampering any of them
    /// (notably a hostile `rounds`/`salt`) makes the open fail. Built by hand —
    /// not via `JSONEncoder` — so the exact bytes are reproducible on decrypt.
    private static func headerAAD(format: Int, kind: Envelope.Kind, kdf: Envelope.KDF?, keyID: String?) -> Data {
        var parts = ["piru.backup.header.v\(format)", "kind=\(kind.rawValue)"]
        if let kdf {
            parts.append("kdf=\(kdf.algorithm)")
            parts.append("rounds=\(kdf.rounds)")
            parts.append("salt=\(kdf.salt.base64EncodedString())")
        }
        if let keyID {
            parts.append("keyID=\(keyID)")
        }
        return Data(parts.joined(separator: "\n").utf8)
    }

    /// A short, non-reversible fingerprint of a key (first 8 bytes of its
    /// SHA-256). Distinct keys get distinct ids; the value leaks nothing usable
    /// about the 256-bit key itself.
    private static func keyID(of key: SymmetricKey) -> String {
        let digest = key.withUnsafeBytes { SHA256.hash(data: Data($0)) }
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// PBKDF2-HMAC-SHA256. `passphrase` must already be NFC-normalized; `rounds`
    /// must already be validated in range (see ``inspect(_:)``) so the
    /// `UInt32` conversion is safe.
    private static func deriveKey(passphrase: String, salt: Data, rounds: Int) throws -> SymmetricKey {
        var passwordData = Data(passphrase.utf8)
        defer { passwordData.resetBytes(in: 0 ..< passwordData.count) }

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
        let key = SymmetricKey(data: derived) // copies the bytes into protected storage
        derived.resetBytes(in: 0 ..< derived.count) // scrub our transient copy
        return key
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
