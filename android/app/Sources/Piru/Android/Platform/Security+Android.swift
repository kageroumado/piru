// The slice of Security and CommonCrypto that BackupCrypto and ShareIdentity call, so their
// code compiles unchanged. A keychain item is a file in the app's private directory, sealed
// with AES-GCM under a key the Android Keystore holds and never exports
// (Skip/AndroidKeystore.kt), so the file alone opens nowhere else. The manifest's backup rules
// keep the files on the device: no cloud backup and no device-to-device transfer carries them.
// Items written before the Keystore seal are plain files, read as they are until rewritten.

import _CryptoExtras
import Crypto
import Foundation
import SkipBridge

typealias OSStatus = Int32
typealias CFTypeRef = Any
typealias CFString = String
typealias CFDictionary = [String: Any]

nonisolated let errSecSuccess: OSStatus = 0
nonisolated let errSecDuplicateItem: OSStatus = -25299
nonisolated let errSecItemNotFound: OSStatus = -25300
nonisolated let errSecInteractionNotAllowed: OSStatus = -25308
nonisolated let errSecParam: OSStatus = -50

nonisolated let kSecClass = "class"
nonisolated let kSecClassGenericPassword = "genp"
nonisolated let kSecAttrService = "svce"
nonisolated let kSecAttrAccount = "acct"
nonisolated let kSecAttrSynchronizable = "sync"
nonisolated let kSecAttrSynchronizableAny = "syna"
nonisolated let kSecAttrAccessible = "pdmn"
nonisolated let kSecAttrAccessibleAfterFirstUnlock = "ck"
nonisolated let kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly = "cku"
nonisolated let kSecUseDataProtectionKeychain = "u_DataProtectionKeychain"
nonisolated let kSecValueData = "v_Data"
nonisolated let kSecReturnData = "r_Data"
nonisolated let kSecMatchLimit = "m_Limit"
nonisolated let kSecMatchLimitOne = "m_LimitOne"
nonisolated let kCFBooleanTrue: Bool? = true
nonisolated let kSecRandomDefault: Int? = nil

/// An item's files: the Keystore-sealed one written now, and the plain one an earlier build
/// wrote. The item's name is also the seal's associated data, so a sealed file renamed to
/// another item does not open.
private nonisolated struct KeychainItem {
    let name: String
    let sealed: URL
    let plain: URL

    init?(_ attributes: [String: Any]) {
        guard let service = attributes[kSecAttrService] as? String,
              let account = attributes[kSecAttrAccount] as? String,
              let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        let directory = support.appending(path: "keychain", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        name = "\(service).\(account)"
        sealed = directory.appending(path: "\(name).sealed")
        plain = directory.appending(path: name)
    }

    var exists: Bool {
        FileManager.default.fileExists(atPath: sealed.path) || FileManager.default.fileExists(atPath: plain.path)
    }
}

/// Calls into Skip/AndroidKeystore.kt.
private nonisolated enum AndroidKeystore {
    private static var kotlin: AnyDynamicObject? {
        try? AnyDynamicObject(forStaticsOfClassName: "piru.module.AndroidKeystore")
    }

    static func seal(_ data: Data, label: String) -> Data? {
        try? kotlin?.seal(data, label) as Data?
    }

    static func open(_ data: Data, label: String) -> Data? {
        try? kotlin?.open(data, label) as Data?
    }
}

nonisolated func SecItemAdd(_ attributes: CFDictionary, _: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
    guard let item = KeychainItem(attributes), let data = attributes[kSecValueData] as? Data else { return errSecParam }
    if item.exists { return errSecDuplicateItem }
    guard let sealed = AndroidKeystore.seal(data, label: item.name) else { return errSecInteractionNotAllowed }
    do {
        // `.withoutOverwriting` alone: swift-foundation traps on it combined with `.atomic`.
        try sealed.write(to: item.sealed, options: .withoutOverwriting)
        return errSecSuccess
    } catch {
        return item.exists ? errSecDuplicateItem : errSecParam
    }
}

/// A sealed item that no longer opens (its Keystore key is gone) answers
/// errSecInteractionNotAllowed, so a caller never takes it for an item that was never written.
nonisolated func SecItemCopyMatching(_ query: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
    guard let item = KeychainItem(query) else { return errSecParam }
    if let sealed = try? Data(contentsOf: item.sealed) {
        guard let data = AndroidKeystore.open(sealed, label: item.name) else { return errSecInteractionNotAllowed }
        result?.pointee = data
        return errSecSuccess
    }
    guard let data = try? Data(contentsOf: item.plain) else { return errSecItemNotFound }
    result?.pointee = data
    return errSecSuccess
}

@discardableResult
nonisolated func SecItemDelete(_ query: CFDictionary) -> OSStatus {
    guard let item = KeychainItem(query) else { return errSecParam }
    guard item.exists else { return errSecItemNotFound }
    try? FileManager.default.removeItem(at: item.sealed)
    try? FileManager.default.removeItem(at: item.plain)
    return item.exists ? errSecParam : errSecSuccess
}

nonisolated func SecRandomCopyBytes(_: Int?, _ count: Int, _ bytes: UnsafeMutableRawPointer) -> Int32 {
    var generator = SystemRandomNumberGenerator()
    let buffer = bytes.assumingMemoryBound(to: UInt8.self)
    for index in 0 ..< count {
        buffer[index] = generator.next()
    }
    return errSecSuccess
}

// MARK: - CommonCrypto

typealias CCPBKDFAlgorithm = UInt32
typealias CCPseudoRandomAlgorithm = UInt32
nonisolated let kCCPBKDF2: UInt32 = 2
nonisolated let kCCPRFHmacAlgSHA256: UInt32 = 3
nonisolated let kCCSuccess: Int32 = 0
nonisolated let kCCParamError: Int32 = -4300

/// PBKDF2-HMAC-SHA256 through swift-crypto, with CommonCrypto's signature.
nonisolated func CCKeyDerivationPBKDF(
    _ algorithm: CCPBKDFAlgorithm,
    _ password: UnsafePointer<CChar>?,
    _ passwordLength: Int,
    _ salt: UnsafePointer<UInt8>?,
    _ saltLength: Int,
    _ prf: CCPseudoRandomAlgorithm,
    _ rounds: UInt32,
    _ derivedKey: UnsafeMutablePointer<UInt8>?,
    _ derivedKeyLength: Int,
) -> Int32 {
    guard algorithm == kCCPBKDF2, prf == kCCPRFHmacAlgSHA256, let derivedKey else { return kCCParamError }
    let passwordBytes = password.map { Data(bytes: $0, count: passwordLength) } ?? Data()
    let saltBytes = salt.map { Data(bytes: $0, count: saltLength) } ?? Data()
    guard let key = try? KDF.Insecure.PBKDF2.deriveKey(
        from: passwordBytes, salt: saltBytes, using: .sha256,
        outputByteCount: derivedKeyLength, unsafeUncheckedRounds: Int(rounds),
    ) else { return kCCParamError }
    key.withUnsafeBytes { raw in
        for index in 0 ..< derivedKeyLength {
            derivedKey[index] = raw[index]
        }
    }
    return kCCSuccess
}
