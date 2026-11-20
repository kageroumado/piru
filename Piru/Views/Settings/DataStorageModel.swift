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

    var notice: Notice?

    /// The encrypted export waiting to be shared.
    var exported: ExportedBackup?

    /// The temporary encrypted file handed to the share sheet, removed once the
    /// share sheet is dismissed so ciphertext doesn't linger in /tmp.
    private var exportedFileToClean: URL?

    private(set) var plainExportDocument: PiruDocument?
    /// Named when the document is built, so the file carries the export's own
    /// time rather than the moment the screen was first drawn.
    private(set) var plainExportFilename: String?
    /// The file type of the document waiting for the save panel.
    private(set) var plainExportContentType = ExportFormat.piru.contentType
    private(set) var generatingFormat: ExportFormat?

    /// Recoverable copies — loaded async (enumerating sidecars opens each store).
    private(set) var recoverable: [RecoverableStore] = []
    private(set) var loadingRecoverable = true

    /// The restore payload, filled by whichever route the user took.
    /// What the merge-or-replace choice will restore: a decrypted payload, or
    /// the latest automatic iCloud backup.
    private enum PendingRestore {
        case plaintext(Data)
        case iCloud
    }

    private var pendingRestore: PendingRestore?

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
            plainExportFilename = DataExportImport.exportFilename
            plainExportContentType = format.contentType
            return true
        } catch {
            notice = Notice(title: String(localized: "Export Failed"), message: error.localizedDescription)
            return false
        }
    }

    func finishPlainExport(_ result: Result<URL, Error>) {
        plainExportDocument = nil
        plainExportFilename = nil
        if case let .failure(error) = result {
            notice = Notice(title: String(localized: "Export Failed"), message: error.localizedDescription)
        }
    }

    /// Imports a picked file, returning the backup to unlock when it is encrypted.
    func importPickedFile(_ result: Result<URL, Error>, context: ModelContext) async -> BackupFileImport.LockedBackup? {
        switch await BackupFileImport.importPicked(result, context: context) {
        case .imported:
            notice = Notice(
                title: String(localized: "Import Complete"),
                message: String(localized: "Your data was imported."),
            )
        case let .locked(backup):
            return backup
        case let .needsPeople(pending):
            PsyLogImportRequest.present(pending) { [weak self] outcome in
                self?.finishPeopleImport(outcome)
            }
        case .cancelled:
            break
        case let .failed(message):
            notice = Notice(title: String(localized: "Import Failed"), message: message)
        }
        return nil
    }

    private func finishPeopleImport(_ outcome: PsyLogImportRequest.Outcome) {
        switch outcome {
        case .imported:
            notice = Notice(
                title: String(localized: "Import Complete"),
                message: String(localized: "Your data was imported."),
            )
        case .cancelled:
            break
        case let .failed(message):
            notice = Notice(title: String(localized: "Import Failed"), message: message)
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

    /// Holds an unlocked backup's payload for the merge-or-replace choice.
    func prepareRestore(plaintext: Data) {
        pendingRestore = .plaintext(plaintext)
    }

    /// Points the pending restore at the latest automatic iCloud backup.
    func prepareICloudRestore() {
        pendingRestore = .iCloud
    }

    func executeRestore(_ strategy: BackupManager.RestoreStrategy, context: ModelContext) async {
        guard let pending = pendingRestore else { return }
        pendingRestore = nil
        do {
            let restored = switch pending {
            case let .plaintext(data):
                try await manager.restore(plaintext: data, strategy: strategy, context: context)
            case .iCloud:
                try await manager.restoreFromICloud(passphrase: nil, strategy: strategy, context: context)
            }
            guard restored else { return }
            DataExportImport.refreshLiveStores(container: context.container)
            notice = Notice(
                title: String(localized: "Restore Complete"),
                message: String(localized: "Your backup was restored."),
            )
        } catch {
            notice = Notice(title: String(localized: "Restore Failed"), message: error.localizedDescription)
        }
    }

    func clearPending() {
        pendingRestore = nil
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

    private(set) var isDeleting = false

    func deleteAllData(context: ModelContext) async {
        guard !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }
        do {
            try AllDataDeletion.deleteJournal(context: context)
        } catch {
            notice = Notice(title: String(localized: "Delete Failed"), message: error.localizedDescription)
            return
        }
        clearPending()
        cleanupExportedFile()
        exported = nil
        plainExportDocument = nil
        plainExportFilename = nil
        recoverable = []
        let cleanupErrors = await AllDataDeletion.resetEverythingElse(context: context)
        await loadRecoverable()
        if !cleanupErrors.isEmpty {
            notice = Notice(title: String(localized: "Delete Failed"), message: cleanupErrors.joined(separator: "\n"))
        }
    }
}
