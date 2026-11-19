import CryptoKit
import Foundation
import Security
import Synchronization

/// Who a profile is to people on other devices: a random person id and a
/// Curve25519 key pair, one per local profile. A friend's phone files what this
/// profile shares under the person id, and seals what it sends back to the
/// public key.
///
/// The private key never leaves the device. It lives in the Keychain, readable
/// after first unlock and never synced, and no backup carries it, so a restore
/// on a new phone mints a new identity and friends pair again.
nonisolated struct ShareIdentity: Sendable {
    let personID: UUID
    let privateKey: Curve25519.KeyAgreement.PrivateKey

    var publicKey: Curve25519.KeyAgreement.PublicKey {
        privateKey.publicKey
    }

    static func make() -> ShareIdentity {
        ShareIdentity(personID: UUID(), privateKey: Curve25519.KeyAgreement.PrivateKey())
    }
}

/// Where identities are kept, by local profile id.
nonisolated protocol ShareIdentityStorage: Sendable {
    func read(profileID: UUID) -> Data?
    func write(_ data: Data, profileID: UUID) throws
    func delete(profileID: UUID)
}

/// Each local profile's ``ShareIdentity``, minted on first use.
nonisolated struct ShareIdentityStore: Sendable {
    static let shared = ShareIdentityStore(storage: KeychainShareIdentityStorage())

    let storage: any ShareIdentityStorage

    private struct Stored: Codable {
        let personID: UUID
        let privateKey: Data
    }

    /// `profileID`'s identity, minting and saving one the first time.
    func identity(for profileID: UUID) throws -> ShareIdentity {
        if let existing = existingIdentity(for: profileID) { return existing }
        let identity = ShareIdentity.make()
        let stored = Stored(personID: identity.personID, privateKey: identity.privateKey.rawRepresentation)
        try storage.write(JSONEncoder().encode(stored), profileID: profileID)
        return identity
    }

    /// `profileID`'s identity when one was ever minted.
    func existingIdentity(for profileID: UUID) -> ShareIdentity? {
        guard let data = storage.read(profileID: profileID),
              let stored = try? JSONDecoder().decode(Stored.self, from: data),
              let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: stored.privateKey)
        else { return nil }
        return ShareIdentity(personID: stored.personID, privateKey: key)
    }

    func forget(profileID: UUID) {
        storage.delete(profileID: profileID)
    }
}

/// Generic-password Keychain items, one per profile, in the data-protection
/// keychain on both platforms.
nonisolated struct KeychainShareIdentityStorage: ShareIdentityStorage {
    private static let service = "glass.kagerou.piru.share-identity"

    private func query(_ profileID: UUID) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccount: profileID.uuidString.lowercased(),
            kSecUseDataProtectionKeychain: true,
        ]
    }

    func read(profileID: UUID) -> Data? {
        var query = query(profileID)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    func write(_ data: Data, profileID: UUID) throws {
        delete(profileID: profileID)
        var item = query(profileID)
        item[kSecValueData] = data
        item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        item[kSecAttrSynchronizable] = false
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    func delete(profileID: UUID) {
        SecItemDelete(query(profileID) as CFDictionary)
    }
}

/// Identities held in memory, for tests.
final nonisolated class InMemoryShareIdentityStorage: ShareIdentityStorage {
    private let items = Mutex<[UUID: Data]>([:])

    func read(profileID: UUID) -> Data? {
        items.withLock { $0[profileID] }
    }

    func write(_ data: Data, profileID: UUID) throws {
        items.withLock { $0[profileID] = data }
    }

    func delete(profileID: UUID) {
        _ = items.withLock { $0.removeValue(forKey: profileID) }
    }
}
