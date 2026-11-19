import Foundation
import SwiftData

/// Takes a picked file as whatever it is — a Piru or PsychonautWiki JSON file
/// imports at once, an encrypted backup comes back locked — so every import
/// surface offers one picker rather than asking the user which kind of file
/// they have.
enum BackupFileImport {
    /// An encrypted backup read from a picked file, waiting to be unlocked.
    struct LockedBackup: Identifiable {
        let id = UUID()
        let envelope: Data
        /// Sealed with a passphrase, as opposed to this device's backup key.
        let needsPassphrase: Bool
    }

    enum Outcome {
        case imported
        case locked(LockedBackup)
        /// A PsychonautWiki file naming other people: nothing is imported until
        /// the people sheet says whose journal each person's doses go into.
        case needsPeople(PsyLogPendingImport)
        case failed(String)
    }

    /// Reads the picked file off the main actor and imports it, or returns it
    /// locked when it is an encrypted backup, or pending when it is a
    /// PsychonautWiki file that names other people.
    static func importPicked(_ result: Result<URL, Error>, context: ModelContext) async -> Outcome {
        let url: URL
        switch result {
        case let .success(picked): url = picked
        case let .failure(error): return .failed(error.localizedDescription)
        }
        guard url.startAccessingSecurityScopedResource() else {
            return .failed(String(localized: "Couldn't access the selected file."))
        }
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            let (data, people) = try await Task.detached {
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                guard size <= BackupCrypto.maxEnvelopeBytes else { throw BackupManager.ManagerError.fileTooLarge }
                let data = try Data(contentsOf: url)
                return (data, PsyLogPendingImport.inspect(data))
            }.value
            if let people { return .needsPeople(people) }
            do {
                try importJSON(data, context: context)
            } catch ImportFileError.encrypted {
                return await locked(data)
            }
            DataExportImport.refreshLiveStores(container: context.container)
            return .imported
        } catch {
            return .failed(DataExportImport.importErrorMessage(for: error))
        }
    }

    /// Adds a plain JSON file to the journals it holds, skipping entries
    /// already there. A Piru file carrying several profiles brings each back
    /// under its own id, into this device's profile with that id when there is
    /// one, as an encrypted backup's Merge does; any other file goes into the
    /// open journal (`context`).
    @MainActor
    static func importJSON(_ data: Data, context: ModelContext, directory: ProfileDirectory = .shared) throws {
        try BackupManager.shared.apply(plaintext: data, strategy: .merge, context: context, directory: directory)
    }

    /// Decrypts a locked backup off the main actor, returning the plaintext
    /// payload for ``BackupManager/apply(plaintext:strategy:context:)``. Throws
    /// ``BackupCrypto/BackupError/decryptionFailed`` for a wrong passphrase.
    static func unlock(_ backup: LockedBackup, passphrase: String?) async throws -> Data {
        let envelope = backup.envelope
        return try await Task.detached { try BackupCrypto.decrypt(envelope, passphrase: passphrase) }.value
    }

    private static func locked(_ data: Data) async -> Outcome {
        do {
            let kind = try await Task.detached { try BackupCrypto.inspect(data).kind }.value
            return .locked(LockedBackup(envelope: data, needsPassphrase: kind == .passphrase))
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
