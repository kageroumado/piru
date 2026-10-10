// Automatic backup on Android, which has no iCloud: each time the app leaves the screen the
// journal is exported, sealed with the user's passphrase (BackupCrypto's passphrase envelope,
// the same file a manual encrypted export makes), and written into a folder the user picked
// through the Storage Access Framework (Skip/AndroidBackupFolder.kt). The folder can belong to
// any document provider: Google Drive, Dropbox, Nextcloud, OneDrive, or the phone itself.
// A new phone restores by picking the same folder and entering the passphrase.
// Wired into upstream by patches/0016-folder-backup.patch.

import CryptoKit
import Foundation
import os
import SkipBridge
import SwiftData
import SwiftUI

/// Runs the folder backup and holds its configuration: the folder's grant, its name, and the
/// passphrase every backup is sealed with.
@Observable
@MainActor
final class FolderBackupManager {
    static let shared = FolderBackupManager()

    /// A folder Piru holds a persisted grant on.
    struct Folder: Equatable {
        /// The tree URI the picker returned.
        let uri: String
        let name: String
    }

    nonisolated static let filename = BackupManager.backupFilename

    private static let folderURIKey = "backup.folder.uri"
    private static let folderNameKey = "backup.folder.name"
    private static let lastDateKey = "backup.folder.lastSuccessDate"
    private static let lastHashKey = "backup.folder.lastPlaintextHash"
    /// Coalesces rapid foreground/background transitions.
    private static let minInterval: TimeInterval = 30

    private let defaults = UserDefaults.androidAppGroup ?? .standard

    private(set) var status: BackupManager.Status = .idle
    private(set) var folder: Folder?
    private(set) var lastBackupDate: Date?

    private init() {
        if let uri = defaults.string(forKey: Self.folderURIKey) {
            folder = Folder(uri: uri, name: defaults.string(forKey: Self.folderNameKey) ?? uri)
        }
        let time = defaults.double(forKey: Self.lastDateKey)
        lastBackupDate = time > 0 ? Date(timeIntervalSince1970: time) : nil
    }

    /// Whether Piru still holds its grant on the folder.
    var folderAccessible: Bool {
        folder.map { AndroidBackupFolder.isAccessible($0.uri) } ?? false
    }

    var passphrase: String? {
        FolderBackupPassphrase.load()
    }

    // MARK: - Configuration

    /// Backs up into `folder` from now on, sealed with `passphrase`, and writes the first
    /// backup there at once. A previous folder's grant is given up.
    func enable(folder: Folder, passphrase: String, context: ModelContext) async {
        if let previous = self.folder, previous.uri != folder.uri {
            AndroidBackupFolder.release(previous.uri)
        }
        do {
            try FolderBackupPassphrase.save(passphrase)
        } catch {
            status = .failed(error.localizedDescription)
            return
        }
        self.folder = folder
        defaults.set(folder.uri, forKey: Self.folderURIKey)
        defaults.set(folder.name, forKey: Self.folderNameKey)
        setLastBackup(nil, hash: nil)
        await run(context: context, force: true)
    }

    /// Stops backing up. The backup file stays in the folder.
    func disable() {
        if let folder { AndroidBackupFolder.release(folder.uri) }
        folder = nil
        defaults.removeObject(forKey: Self.folderURIKey)
        defaults.removeObject(forKey: Self.folderNameKey)
        setLastBackup(nil, hash: nil)
        FolderBackupPassphrase.remove()
        status = .idle
    }

    // MARK: - Backup

    /// Export → seal with the passphrase → write into the folder. Skips when no folder is
    /// set, when nothing changed since the last backup, or when called again within
    /// ``minInterval``; `force` skips only the interval.
    func run(context: ModelContext, force: Bool = false) async {
        guard let folder, let passphrase else { return }
        if case .running = status { return }
        if !force, let last = lastBackupDate, Date().timeIntervalSince(last) < Self.minInterval { return }

        status = .running
        do {
            let plaintext = try DataExportImport.exportJSON(context: context)
            let hash = SHA256.hash(data: plaintext).map { String(format: "%02x", $0) }.joined()
            if hash == defaults.string(forKey: Self.lastHashKey), lastBackupDate != nil {
                status = .idle
                return
            }
            // Key derivation (600 000 PBKDF2 rounds) and the provider's IO run off the main actor.
            let uri = folder.uri
            try await Task.detached(name: "Folder backup") {
                let envelope = try BackupCrypto.encryptWithPassphrase(plaintext, passphrase: passphrase)
                let staging = FileManager.default.temporaryDirectory.appendingPathComponent(Self.filename)
                defer { try? FileManager.default.removeItem(at: staging) }
                try envelope.write(to: staging, options: .atomic)
                if let failure = AndroidBackupFolder.write(tree: uri, name: Self.filename, source: staging) {
                    throw FolderBackupError.failed(failure)
                }
            }.value
            // Turned off or moved to another folder while this one was being written.
            guard self.folder == folder else { return }
            let now = Date()
            setLastBackup(now, hash: hash)
            status = .success(now)
            Logger.backupManager.notice("Folder backup written.")
        } catch {
            Logger.backupManager.error("Folder backup failed: \(error.localizedDescription, privacy: .public)")
            status = .failed(error.localizedDescription)
        }
    }

    /// The backup already in `folder`, or `nil` when it holds none.
    nonisolated static func existingBackup(in folder: Folder) async throws -> Data? {
        try await Task.detached(name: "Read folder backup") {
            guard AndroidBackupFolder.exists(tree: folder.uri, name: filename) else { return nil }
            let staging = FileManager.default.temporaryDirectory.appendingPathComponent("restore-\(filename)")
            defer { try? FileManager.default.removeItem(at: staging) }
            if let failure = AndroidBackupFolder.read(tree: folder.uri, name: filename, destination: staging) {
                throw FolderBackupError.failed(failure)
            }
            let size = (try? staging.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard size <= BackupCrypto.maxEnvelopeBytes else { throw BackupManager.ManagerError.fileTooLarge }
            return try Data(contentsOf: staging)
        }.value
    }

    private func setLastBackup(_ date: Date?, hash: String?) {
        lastBackupDate = date
        defaults.set(date?.timeIntervalSince1970 ?? 0, forKey: Self.lastDateKey)
        defaults.set(hash, forKey: Self.lastHashKey)
    }
}

enum FolderBackupError: LocalizedError {
    case unavailable
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: String(localized: "The folder picker could not be opened.")
        case let .failed(message): message
        }
    }
}

/// The passphrase folder backups are sealed with, in a file in the app's private directory,
/// where the keychain stand-in (Android/Platform/Security+Android.swift) keeps its items and
/// under the same rules: Android sandboxes it per app, and no cloud backup or device transfer
/// carries it.
private nonisolated enum FolderBackupPassphrase {
    private static var file: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "keychain", directoryHint: .isDirectory)
            .appending(path: "folder-backup.passphrase")
    }

    static func load() -> String? {
        guard let file, let data = try? Data(contentsOf: file) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ passphrase: String) throws {
        guard let file else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(passphrase.utf8).write(to: file, options: .atomic)
    }

    static func remove() {
        guard let file else { return }
        try? FileManager.default.removeItem(at: file)
    }
}

// MARK: - Kotlin bridge

/// Receives the folder picker's result from Kotlin.
/* SKIP @bridge */ public final class AndroidBackupFolderResults: @unchecked Sendable {
    /* SKIP @bridge */ public static let shared = AndroidBackupFolderResults()

    /// `nil` when the user cancelled.
    var onPick: ((FolderBackupManager.Folder?) -> Void)?

    private init() {}

    /* SKIP @bridge */ public func didPick(_ uri: String?, _ name: String?) {
        let completion = onPick
        onPick = nil
        completion?(uri.map { FolderBackupManager.Folder(uri: $0, name: name ?? $0) })
    }
}

/// Calls into Skip/AndroidBackupFolder.kt. The file calls block on the provider, so they run
/// off the main actor.
nonisolated enum AndroidBackupFolder {
    private static var kotlin: AnyDynamicObject? {
        try? AnyDynamicObject(forStaticsOfClassName: "piru.module.AndroidBackupFolder")
    }

    @MainActor
    static func pick(_ completion: @escaping (FolderBackupManager.Folder?) -> Void) -> Bool {
        AndroidBackupFolderResults.shared.onPick = completion
        guard (try? kotlin?.pick() as Bool?) == true else {
            AndroidBackupFolderResults.shared.onPick = nil
            return false
        }
        return true
    }

    static func isAccessible(_ tree: String) -> Bool {
        (try? kotlin?.isAccessible(tree) as Bool?) == true
    }

    static func release(_ tree: String) {
        _ = try? kotlin?.release(tree) as Void?
    }

    static func exists(tree: String, name: String) -> Bool {
        (try? kotlin?.exists(tree, name) as Bool?) == true
    }

    /// `nil` on success, else why it failed.
    static func read(tree: String, name: String, destination: URL) -> String? {
        guard let kotlin else { return String(localized: "The backup folder could not be reached.") }
        do {
            return try kotlin.read(tree, name, destination.path) as String?
        } catch {
            return error.localizedDescription
        }
    }

    /// `nil` on success, else why it failed.
    static func write(tree: String, name: String, source: URL) -> String? {
        guard let kotlin else { return String(localized: "The backup folder could not be reached.") }
        do {
            return try kotlin.write(tree, name, source.path) as String?
        } catch {
            return error.localizedDescription
        }
    }
}

// MARK: - Settings section

/// Data & Backup's backup section on Android, where ICloudBackupSection would be on iOS.
struct FolderBackupSection: View {
    @Environment(\.modelContext) private var modelContext
    @State private var manager = FolderBackupManager.shared

    /// A picked folder, until its passphrase is settled.
    @State private var pendingFolder: FolderBackupManager.Folder?
    @State private var showingPassphraseSheet = false
    /// The backup found in a picked folder, until its passphrase opens it.
    @State private var foundBackup: Data?
    @State private var showingUnlockPrompt = false
    @State private var unlockPassphrase = ""
    @State private var unlockFailure: String?
    @State private var notice: String?

    var body: some View {
        Section {
            if let folder = manager.folder {
                LabeledContent {
                    Text(folder.name).foregroundStyle(Theme.secondaryLabel)
                } label: {
                    Label("Folder", systemImage: "folder")
                }
                .listRowBackground(CardBackground())

                if manager.folderAccessible {
                    FolderBackupStatusRow(manager: manager).listRowBackground(CardBackground())
                    Button {
                        Task { await manager.run(context: modelContext, force: true) }
                    } label: {
                        Label("Back Up Now", systemImage: "arrow.clockwise")
                    }
                    .disabled(manager.status == .running)
                    .listRowBackground(CardBackground())
                } else {
                    Label {
                        Text("Piru can no longer reach this folder. Choose it again to keep backing up.")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.cautionAccent).accessibilityHidden(true)
                    }
                    .font(.footnote)
                    .listRowBackground(CardBackground())
                }

                Button { pickFolder() } label: {
                    Label("Choose Another Folder…", systemImage: "folder.badge.plus")
                }
                .listRowBackground(CardBackground())

                Button(role: .destructive) { manager.disable() } label: {
                    Label("Turn Off Folder Backup", systemImage: "xmark.circle")
                }
                .listRowBackground(CardBackground())
            } else {
                Button { pickFolder() } label: {
                    Label("Back Up to a Folder…", systemImage: "folder.badge.plus")
                }
                .listRowBackground(CardBackground())
            }
        } header: {
            Text("Backup")
        } footer: {
            if manager.folder == nil {
                Text("Pick a folder, on this phone or in Google Drive, Dropbox or another cloud app, and Piru saves an encrypted copy of your journal there each time you leave the app. Only your passphrase opens it, and the cloud app does the uploading: Piru itself never goes online. To restore on a new phone, choose the same folder here.")
            } else {
                Text("Saved each time you leave the app, encrypted with your passphrase. Turning this off leaves the last backup in the folder.")
            }
        }
        .sheet(isPresented: $showingPassphraseSheet, onDismiss: abandonPendingFolder) {
            PassphraseSheet { passphrase in
                showingPassphraseSheet = false
                if let folder = pendingFolder {
                    pendingFolder = nil
                    Task { await manager.enable(folder: folder, passphrase: passphrase, context: modelContext) }
                }
            }
        }
        .alert("Backup Found", isPresented: $showingUnlockPrompt) {
            SecureField("Passphrase", text: $unlockPassphrase)
            Button("Cancel", role: .cancel) {
                foundBackup = nil
                abandonPendingFolder()
            }
            Button("Unlock") { unlockFoundBackup() }
                .disabled(unlockPassphrase.isEmpty)
        } message: {
            Text(unlockFailure ?? String(localized: "This folder already holds a Piru backup. Enter its passphrase to merge it with your journal; later backups use the same passphrase."))
        }
        .alert("Backup", isPresented: noticeBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(notice ?? "")
        }
    }

    private var noticeBinding: Binding<Bool> {
        Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })
    }

    private func pickFolder() {
        let opened = AndroidBackupFolder.pick { folder in
            guard let folder else { return }
            Task { await folderPicked(folder) }
        }
        if !opened { notice = FolderBackupError.unavailable.localizedDescription }
    }

    /// A folder that already holds a backup asks for that backup's passphrase and merges it;
    /// an empty one keeps the current passphrase, or asks for a new one on first setup.
    private func folderPicked(_ folder: FolderBackupManager.Folder) async {
        pendingFolder = folder
        do {
            if let backup = try await FolderBackupManager.existingBackup(in: folder) {
                foundBackup = backup
                unlockPassphrase = ""
                unlockFailure = nil
                showingUnlockPrompt = true
            } else if let passphrase = manager.passphrase, manager.folder != nil {
                pendingFolder = nil
                await manager.enable(folder: folder, passphrase: passphrase, context: modelContext)
            } else {
                showingPassphraseSheet = true
            }
        } catch {
            abandonPendingFolder()
            notice = error.localizedDescription
        }
    }

    private func unlockFoundBackup() {
        guard let envelope = foundBackup, let folder = pendingFolder else { return }
        let passphrase = unlockPassphrase
        Task {
            do {
                let plaintext = try await Task.detached { try BackupCrypto.decrypt(envelope, passphrase: passphrase) }.value
                try BackupManager.shared.apply(plaintext: plaintext, strategy: .merge, context: modelContext)
                DataExportImport.refreshLiveStores(container: modelContext.container)
                foundBackup = nil
                pendingFolder = nil
                await manager.enable(folder: folder, passphrase: passphrase, context: modelContext)
                notice = String(localized: "The backup was merged with your journal.")
            } catch BackupCrypto.BackupError.decryptionFailed {
                unlockPassphrase = ""
                unlockFailure = String(localized: "That passphrase didn't open the backup. Try again.")
                showingUnlockPrompt = true
            } catch {
                foundBackup = nil
                abandonPendingFolder()
                notice = DataExportImport.importErrorMessage(for: error)
            }
        }
    }

    /// Gives up the grant on a picked folder that never became the backup folder.
    private func abandonPendingFolder() {
        guard let folder = pendingFolder else { return }
        pendingFolder = nil
        if folder.uri != manager.folder?.uri { AndroidBackupFolder.release(folder.uri) }
    }
}

private struct FolderBackupStatusRow: View {
    let manager: FolderBackupManager

    var body: some View {
        switch manager.status {
        case .running:
            Label { Text("Backing up…") } icon: { ProgressView() }
                .foregroundStyle(Theme.secondaryLabel)
        case let .failed(message):
            Label { Text("Last backup failed: \(message)") } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.cautionAccent).accessibilityHidden(true)
            }
            .font(.footnote)
        default:
            LabeledContent {
                if let date = manager.lastBackupDate {
                    Text(date.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(Theme.secondaryLabel)
                } else {
                    Text("Never").foregroundStyle(Theme.secondaryLabel)
                }
            } label: {
                Label("Last Backup", systemImage: "clock.arrow.circlepath")
            }
        }
    }
}
