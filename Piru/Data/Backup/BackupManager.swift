import CryptoKit
import Foundation
import os
import SwiftData

private let backupLogger = Logger(subsystem: "dev.yumeji.piru", category: "BackupManager")

/// Orchestrates Piru's two backup paths on top of ``BackupCrypto`` and the
/// existing ``DataExportImport`` (PsyLog JSON) and ``StoreRecovery`` machinery:
///
/// - **Automatic iCloud backup** (opt-in, off by default): on each backgrounding
///   the journal is exported, encrypted with the device's iCloud-Keychain key,
///   and written to the app's iCloud Drive container. End-to-end encrypted —
///   the key lives only in the user's iCloud Keychain.
/// - **Manual encrypted export**: the user picks a passphrase; the export is
///   sealed with a passphrase-derived key and handed to the share sheet.
///
/// Restores accept either a merge (add to existing data) or a replace (snapshot
/// the current store via ``StoreRecovery`` first, then delete-all + import) —
/// so a restore can never silently destroy data without a recoverable copy.
@Observable
@MainActor
final class BackupManager {
    static let shared = BackupManager()

    nonisolated static let backupFilename = "Piru-Backup.piruenc"
    /// File extension for manual exports; also the iCloud backup's suffix.
    nonisolated static let fileExtension = "piruenc"

    enum RestoreStrategy {
        /// Add the backup's entries to the current data (de-duped by the import layer).
        case merge
        /// Snapshot + wipe the current data, then import only the backup's entries.
        case replace
    }

    enum Status: Equatable {
        case idle
        case running
        case success(Date)
        case failed(String)
    }

    enum ManagerError: Error, LocalizedError {
        case iCloudUnavailable
        case noBackupFound
        case fileTooLarge

        var errorDescription: String? {
            switch self {
            case .iCloudUnavailable:
                String(localized: "iCloud Drive isn't available. Check that you're signed in to iCloud and that iCloud Drive is on.")
            case .noBackupFound:
                String(localized: "No iCloud backup was found for this account yet.")
            case .fileTooLarge:
                String(localized: "This file is too large to be a Piru backup.")
            }
        }
    }

    private let defaults = UserDefaults(suiteName: "group.dev.yumeji.piru") ?? .standard
    private static let autoEnabledKey = "backup.autoICloudEnabled"
    private static let lastDateKey = "backup.lastSuccessDate"
    private static let lastHashKey = "backup.lastPlaintextHash"
    /// Coalesce rapid foreground/background transitions.
    private static let minInterval: TimeInterval = 30

    private(set) var status: Status = .idle

    private init() {}

    // MARK: - State

    /// Whether automatic iCloud backups are enabled. Off by default.
    var autoICloudEnabled: Bool {
        get { defaults.bool(forKey: Self.autoEnabledKey) }
        set {
            defaults.set(newValue, forKey: Self.autoEnabledKey)
        }
    }

    /// When the last successful backup completed (`nil` if never).
    var lastBackupDate: Date? {
        get {
            let t = defaults.double(forKey: Self.lastDateKey)
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set { defaults.set(newValue?.timeIntervalSince1970 ?? 0, forKey: Self.lastDateKey) }
    }

    /// Whether the user has an iCloud account available (does not guarantee the
    /// Drive container is provisioned — that's surfaced when a backup runs).
    var iCloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    private var lastBackupHash: String? {
        get { defaults.string(forKey: Self.lastHashKey) }
        set { defaults.set(newValue, forKey: Self.lastHashKey) }
    }

    // MARK: - Automatic iCloud backup

    /// Export → encrypt with the device key → write to iCloud. Skips when
    /// disabled, when no iCloud account is present, when nothing changed since
    /// the last backup, or when called again within ``minInterval``.
    func runAutomaticBackup(context: ModelContext) async {
        guard autoICloudEnabled, iCloudAvailable else { return }
        if case .running = status { return }
        if let last = lastBackupDate, Date().timeIntervalSince(last) < Self.minInterval { return }

        status = .running
        do {
            let plaintext = try DataExportImport.exportJSON(context: context)
            let hash = Self.sha256Hex(plaintext)
            if hash == lastBackupHash, lastBackupDate != nil {
                status = .idle // nothing changed — no needless iCloud write
                return
            }
            // Encrypt (PBKDF2-free here, but still keychain IO) and write off the
            // main actor so the UI never blocks on it.
            let byteCount = try await Task.detached {
                let envelope = try BackupCrypto.encryptWithDeviceKey(plaintext)
                try Self.writeICloud(envelope)
                return envelope.count
            }.value
            lastBackupHash = hash
            let now = Date()
            lastBackupDate = now
            status = .success(now)
            backupLogger.notice("Automatic iCloud backup written (\(byteCount, privacy: .public) bytes).")
        } catch {
            backupLogger.error("Automatic backup failed: \(error.localizedDescription, privacy: .public)")
            status = .failed(error.localizedDescription)
        }
    }

    // MARK: - Manual encrypted export

    /// Export the journal and seal it with a passphrase-derived key. Returns a
    /// temporary `.piruenc` file URL suitable for a `ShareLink`. Key derivation
    /// (600 000 PBKDF2 rounds) and sealing run off the main actor.
    func exportEncrypted(context: ModelContext, passphrase: String) async throws -> URL {
        let plaintext = try DataExportImport.exportJSON(context: context)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(DataExportImport.exportFilename)
            .appendingPathExtension(Self.fileExtension)
        try await Task.detached {
            let envelope = try BackupCrypto.encryptWithPassphrase(plaintext, passphrase: passphrase)
            try envelope.write(to: url, options: .atomic)
        }.value
        return url
    }

    // MARK: - Restore

    /// Restore from already-loaded backup bytes.
    func restore(data: Data, passphrase: String?, strategy: RestoreStrategy, context: ModelContext) async throws {
        try await applyRestore(envelope: data, passphrase: passphrase, strategy: strategy, context: context)
    }

    /// Restore from a user-selected `.piruenc` file (e.g. via the document picker).
    func restore(fromFileAt url: URL, passphrase: String?, strategy: RestoreStrategy, context: ModelContext) async throws {
        let data = try Self.boundedContents(of: url)
        try await applyRestore(envelope: data, passphrase: passphrase, strategy: strategy, context: context)
    }

    /// Restore from the latest automatic iCloud backup, downloading it first if
    /// it's not yet local.
    func restoreFromICloud(passphrase: String?, strategy: RestoreStrategy, context: ModelContext) async throws {
        guard let data = try await Task.detached(operation: { try Self.readICloud() }).value else {
            throw ManagerError.noBackupFound
        }
        try await applyRestore(envelope: data, passphrase: passphrase, strategy: strategy, context: context)
    }

    private func applyRestore(envelope data: Data, passphrase: String?, strategy: RestoreStrategy, context: ModelContext) async throws {
        // Decrypt off the main actor — passphrase restores run PBKDF2. Crucially
        // this happens *before* any destructive store mutation, so a wrong
        // passphrase or unavailable device key can never wipe data.
        let plaintext = try await Task.detached { try BackupCrypto.decrypt(data, passphrase: passphrase) }.value
        switch strategy {
        case .merge:
            try DataExportImport.importJSON(data: plaintext, context: context)
        case .replace:
            // Never wipe without a recoverable copy first.
            StoreRecovery.snapshotStore(reason: "prerestore")
            try DataExportImport.deleteAll(context: context)
            try DataExportImport.importJSON(data: plaintext, context: context)
        }
        try context.save()
        backupLogger.notice("Restore (\(String(describing: strategy), privacy: .public)) completed.")
    }

    // MARK: - iCloud file IO (off the main actor)

    private nonisolated static func iCloudDocumentsURL() throws -> URL {
        guard let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            throw ManagerError.iCloudUnavailable
        }
        return container.appendingPathComponent("Documents", isDirectory: true)
    }

    private nonisolated static func writeICloud(_ data: Data) throws {
        let docs = try iCloudDocumentsURL()
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        let dst = docs.appendingPathComponent(backupFilename)

        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        var writeError: Error?
        coordinator.coordinate(writingItemAt: dst, options: .forReplacing, error: &coordError) { url in
            do { try data.write(to: url, options: .atomic) } catch { writeError = error }
        }
        if let coordError { throw coordError }
        if let writeError { throw writeError }
    }

    private nonisolated static func readICloud() throws -> Data? {
        let src = try iCloudDocumentsURL().appendingPathComponent(backupFilename)
        // Trigger a download if only a placeholder is present locally.
        try? FileManager.default.startDownloadingUbiquitousItem(at: src)

        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        var result: Data?
        var readError: Error?
        coordinator.coordinate(readingItemAt: src, options: [], error: &coordError) { url in
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            do { result = try boundedContents(of: url) } catch { readError = error }
        }
        if let coordError { throw coordError }
        if let readError { throw readError }
        return result
    }

    // MARK: - Helpers

    /// Read a file into memory only if it's within the envelope size ceiling, so
    /// a hostile (or corrupt) `.piruenc` can't OOM the app before parsing.
    private nonisolated static func boundedContents(of url: URL) throws -> Data {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= BackupCrypto.maxEnvelopeBytes else { throw ManagerError.fileTooLarge }
        return try Data(contentsOf: url)
    }

    private nonisolated static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
