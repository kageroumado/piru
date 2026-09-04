import SwiftData
import SwiftUI

/// Every piece of work behind **Data & Backup** that takes time or can fail:
/// generating an export, validating a picked file, enumerating the recoverable
/// stores on disk, and running a restore or a delete.
///
/// The view keeps the presentation toggles; this keeps the results. Nothing here
/// presents anything — a method that needs a follow-up sheet says so in its
/// return value and leaves the choice of surface to the caller.
@Observable
@MainActor
final class DataStorageModel {
    /// The finished encrypted backup, carried to the share sheet by identity so
    /// re-exporting raises a fresh sheet.
    struct ExportedBackup: Identifiable {
        let id = UUID()
        let url: URL
    }

    /// A one-shot result alert: an export that failed, an import that landed.
    struct Notice: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    /// What a picked encrypted file still needs before a restore strategy can be chosen.
    enum RestorePrompt {
        /// Passphrase-sealed: ask for the passphrase first.
        case passphrase
        /// Key-sealed: go straight to merge-or-replace.
        case strategy
        /// Unreadable — ``notice`` carries the reason.
        case failed
    }

    var notice: Notice?

    /// The encrypted export waiting to be shared.
    var exported: ExportedBackup?

    /// The temporary encrypted file handed to the share sheet, removed once the
    /// share sheet is dismissed so ciphertext doesn't linger in /tmp.
    private var exportedFileToClean: URL?

    private(set) var plainExportDocument: PiruDocument?
    private(set) var generatingFormat: ExportFormat?

    /// Recoverable copies — loaded async (enumerating sidecars opens each store).
    private(set) var recoverable: [RecoverableStore] = []
    private(set) var loadingRecoverable = true

    // The restore payload, filled by whichever route the user took.
    private var pendingData: Data?
    private var pendingIsICloud = false
    private var pendingPassphrase: String?

    private var manager: BackupManager {
        BackupManager.shared
    }

    var isGenerating: Bool {
        generatingFormat != nil
    }

    // MARK: - Plain (unencrypted) export & import

    /// Builds the plain JSON document off the main actor. `true` means it is
    /// ready and the caller should raise the file exporter.
    func generatePlainExport(format: ExportFormat, context: ModelContext) async -> Bool {
        generatingFormat = format
        defer { generatingFormat = nil }
        do {
            let data = try await DataExportImport.exportJSONInBackground(format: format, context: context)
            plainExportDocument = PiruDocument(data: data)
            return true
        } catch {
            notice = Notice(title: String(localized: "Export Failed"), message: error.localizedDescription)
            return false
        }
    }

    func finishPlainExport(_ result: Result<URL, Error>) {
        plainExportDocument = nil
        if case let .failure(error) = result {
            notice = Notice(title: String(localized: "Export Failed"), message: error.localizedDescription)
        }
    }

    func importPlain(_ result: Result<URL, Error>, context: ModelContext) async {
        switch result {
        case let .success(url):
            guard url.startAccessingSecurityScopedResource() else {
                notice = Notice(
                    title: String(localized: "Import Failed"),
                    message: String(localized: "Couldn't access the selected file."),
                )
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                let data = try await Task.detached { try Data(contentsOf: url) }.value
                try DataExportImport.importJSON(data: data, context: context)
                notice = Notice(
                    title: String(localized: "Import Complete"),
                    message: String(localized: "Your data was imported."),
                )
            } catch {
                notice = Notice(
                    title: String(localized: "Import Failed"),
                    message: DataExportImport.importErrorMessage(for: error),
                )
            }
        case let .failure(error):
            notice = Notice(title: String(localized: "Import Failed"), message: error.localizedDescription)
        }
    }

    // MARK: - Encrypted export

    func exportEncrypted(passphrase: String, context: ModelContext) async {
        do {
            let url = try await manager.exportEncrypted(context: context, passphrase: passphrase)
            exportedFileToClean = url
            exported = ExportedBackup(url: url)
        } catch {
            notice = Notice(title: String(localized: "Export Failed"), message: error.localizedDescription)
        }
    }

    func cleanupExportedFile() {
        guard let url = exportedFileToClean else { return }
        try? FileManager.default.removeItem(at: url)
        exportedFileToClean = nil
    }

    // MARK: - Restore

    /// Reads and validates a picked encrypted file off the main actor, keeping
    /// its bytes as the pending restore payload.
    func inspectPickedFile(_ result: Result<URL, Error>) async -> RestorePrompt {
        switch result {
        case let .success(url):
            guard url.startAccessingSecurityScopedResource() else {
                notice = Notice(
                    title: String(localized: "Restore Failed"),
                    message: String(localized: "Couldn't access the selected file."),
                )
                return .failed
            }
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                let (data, kind) = try await Task.detached { () -> (Data, BackupCrypto.Envelope.Kind) in
                    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    guard size <= BackupCrypto.maxEnvelopeBytes else { throw BackupManager.ManagerError.fileTooLarge }
                    let data = try Data(contentsOf: url)
                    let envelope = try BackupCrypto.inspect(data)
                    return (data, envelope.kind)
                }.value
                pendingData = data
                pendingIsICloud = false
                if kind == .passphrase {
                    return .passphrase
                }
                pendingPassphrase = nil
                return .strategy
            } catch {
                notice = Notice(title: String(localized: "Restore Failed"), message: error.localizedDescription)
                return .failed
            }
        case let .failure(error):
            notice = Notice(title: String(localized: "Restore Failed"), message: error.localizedDescription)
            return .failed
        }
    }

    /// Points the pending restore at the latest automatic iCloud backup.
    func prepareICloudRestore() {
        pendingIsICloud = true
        pendingPassphrase = nil
    }

    func setRestorePassphrase(_ passphrase: String) {
        pendingPassphrase = passphrase
    }

    func executeRestore(_ strategy: BackupManager.RestoreStrategy, context: ModelContext) async {
        let passphrase = pendingPassphrase
        let isICloud = pendingIsICloud
        let data = pendingData
        do {
            if isICloud {
                try await manager.restoreFromICloud(passphrase: passphrase, strategy: strategy, context: context)
            } else if let data {
                try await manager.restore(data: data, passphrase: passphrase, strategy: strategy, context: context)
            }
            notice = Notice(
                title: String(localized: "Restore Complete"),
                message: String(localized: "Your backup was restored."),
            )
        } catch {
            notice = Notice(title: String(localized: "Restore Failed"), message: error.localizedDescription)
        }
        clearPending()
    }

    func clearPending() {
        pendingData = nil
        pendingIsICloud = false
        pendingPassphrase = nil
    }

    // MARK: - Recoverable copies

    func loadRecoverable() async {
        loadingRecoverable = true
        recoverable = await Task.detached { StoreRecovery.recoverableStores() }.value
        loadingRecoverable = false
    }

    /// Swaps one recoverable copy into place. `true` means the caller should
    /// raise the "restart Piru" confirmation.
    func restoreRecoverable(_ store: RecoverableStore) -> Bool {
        do {
            try StoreRecovery.restore(from: store.url)
            return true
        } catch {
            notice = Notice(title: String(localized: "Restore Failed"), message: error.localizedDescription)
            return false
        }
    }

    // MARK: - Delete

    func deleteAllData(context: ModelContext) {
        do {
            try DataExportImport.deleteAll(context: context)
        } catch {
            notice = Notice(title: String(localized: "Delete Failed"), message: error.localizedDescription)
            return
        }
        Task { await BackupManager.shared.disableAndRemoveBackup() }
    }

    // MARK: - iCloud conflict resolution

    func checkICloudBackupExists() async -> Bool {
        await Task.detached { BackupManager.iCloudBackupExists() }.value
    }

    func mergeICloudBackup(context: ModelContext) async {
        do {
            try await manager.restoreFromICloud(passphrase: nil, strategy: .merge, context: context)
            manager.autoICloudEnabled = true
            notice = Notice(
                title: String(localized: "Backup Merged"),
                message: String(localized: "The iCloud backup was merged with your data. Automatic backups are now on."),
            )
        } catch {
            notice = Notice(title: String(localized: "Merge Failed"), message: error.localizedDescription)
        }
    }

    func removeICloudBackupOnly() async {
        do {
            try await manager.removeICloudBackup()
            notice = Notice(
                title: String(localized: "Backup Removed"),
                message: String(localized: "The existing iCloud backup was removed."),
            )
        } catch {
            notice = Notice(title: String(localized: "Removal Failed"), message: error.localizedDescription)
        }
    }
}
