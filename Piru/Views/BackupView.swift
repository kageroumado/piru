import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Backup & Security

struct BackupView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var manager = BackupManager.shared

    // Export flow
    @State private var showingExportPassphrase = false
    @State private var exported: ExportedBackup?

    // Restore flow
    @State private var showingFileImporter = false
    @State private var showingRestorePassphrase = false
    @State private var pendingData: Data?
    @State private var pendingIsICloud = false
    @State private var pendingPassphrase: String?
    @State private var showingStrategyDialog = false

    @State private var notice: Notice?

    var body: some View {
        List {
            automaticSection
            exportSection
            restoreSection
            howItWorksSection
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Backup & Security")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingExportPassphrase) {
            PassphraseSheet(mode: .create) { passphrase in
                runExport(passphrase: passphrase)
            }
        }
        .sheet(isPresented: $showingRestorePassphrase) {
            PassphraseSheet(mode: .enter) { passphrase in
                pendingPassphrase = passphrase
                showingRestorePassphrase = false
                showingStrategyDialog = true
            }
        }
        .sheet(item: $exported) { item in
            ShareSheet(items: [item.url])
        }
        .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.data]) { result in
            handlePickedFile(result)
        }
        .confirmationDialog(
            "Restore Backup",
            isPresented: $showingStrategyDialog,
            titleVisibility: .visible,
        ) {
            Button("Merge With Current Data") { executeRestore(.merge) }
            Button("Replace Everything", role: .destructive) { executeRestore(.replace) }
            Button("Cancel", role: .cancel) { clearPending() }
        } message: {
            Text("Merge keeps your current entries and adds the backup's. Replace deletes your current data first (a recovery snapshot is taken automatically) and restores only the backup.")
        }
        .alert(item: $notice) { notice in
            Alert(title: Text(notice.title), message: Text(notice.message), dismissButton: .default(Text("OK")))
        }
    }

    // MARK: - Automatic iCloud

    private var automaticSection: some View {
        Section {
            Toggle(isOn: autoBindng) {
                Label("Back Up to iCloud", systemImage: "icloud")
            }
            .tint(Theme.accent)
            .disabled(!manager.iCloudAvailable)

            statusRow
        } header: {
            Text("Automatic Backup")
        } footer: {
            if manager.iCloudAvailable {
                Text("When on, Piru encrypts your journal and saves it to your private iCloud Drive each time you leave the app. The encryption key is stored only in your iCloud Keychain, so the backup is end-to-end encrypted — **neither Apple nor Piru can read it**, and it restores automatically on your other devices signed in to the same Apple Account.")
            } else {
                Text("Sign in to iCloud and turn on iCloud Drive to enable automatic encrypted backups.")
            }
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch manager.status {
        case .running:
            Label {
                Text("Backing up…")
            } icon: {
                ProgressView()
            }
            .foregroundStyle(Theme.secondaryLabel)
        case let .failed(message):
            Label {
                Text("Last backup failed: \(message)")
            } icon: {
                Image(systemName: "exclamationmark.icloud").foregroundStyle(.orange)
            }
            .font(.footnote)
        default:
            LabeledContent("Last Backup") {
                if let date = manager.lastBackupDate {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(Theme.secondaryLabel)
                } else {
                    Text("Never").foregroundStyle(Theme.secondaryLabel)
                }
            }
        }
    }

    // MARK: - Manual export

    private var exportSection: some View {
        Section {
            Button {
                showingExportPassphrase = true
            } label: {
                Label("Export Encrypted Backup…", systemImage: "lock.doc")
                    .foregroundStyle(Theme.accent)
            }
        } header: {
            Text("Manual Backup")
        } footer: {
            Text("Create a single encrypted file protected by a passphrase you choose, then save or send it anywhere. You'll need the same passphrase to restore it. **If you forget the passphrase, the file cannot be opened — not even by us.**")
        }
    }

    // MARK: - Restore

    private var restoreSection: some View {
        Section {
            Button {
                showingFileImporter = true
            } label: {
                Label("Restore From a File…", systemImage: "arrow.down.doc")
                    .foregroundStyle(Theme.accent)
            }
            if manager.iCloudAvailable {
                Button {
                    pendingIsICloud = true
                    pendingPassphrase = nil
                    showingStrategyDialog = true
                } label: {
                    Label("Restore Latest iCloud Backup", systemImage: "arrow.clockwise.icloud")
                        .foregroundStyle(Theme.accent)
                }
            }
        } header: {
            Text("Restore")
        } footer: {
            Text("Restoring reads an encrypted backup and adds its entries back. Passphrase backups will ask for the passphrase; iCloud backups unlock automatically on your own devices.")
        }
    }

    // MARK: - How it works

    private var howItWorksSection: some View {
        Section {
            howItWorksRow(
                icon: "lock.shield",
                title: "Strong encryption",
                detail: "Every backup is sealed with AES-256-GCM — the same authenticated encryption used by modern secure messengers. Tampering is detected and refused.",
            )
            howItWorksRow(
                icon: "key.icloud",
                title: "Your key, your device",
                detail: "Automatic backups use a random key kept in your iCloud Keychain. It never leaves your devices in readable form, so iCloud only ever holds an unreadable blob.",
            )
            howItWorksRow(
                icon: "key.horizontal",
                title: "Passphrase backups",
                detail: "Manual exports turn your passphrase into a key with 600,000 rounds of PBKDF2. The passphrase is never saved or sent. Choose one you won't forget — there's no recovery.",
            )
            howItWorksRow(
                icon: "checkmark.shield",
                title: "Nothing is deleted by surprise",
                detail: "Replacing your data on restore takes a recoverable snapshot first. Backups are always optional and off until you turn them on.",
            )
        } header: {
            Text("How Encryption Works")
        }
    }

    private func howItWorksRow(icon: String, title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
        .listRowBackground(Theme.cardBackground)
    }

    // MARK: - Bindings

    private var autoBindng: Binding<Bool> {
        Binding(
            get: { manager.autoICloudEnabled },
            set: { newValue in
                manager.autoICloudEnabled = newValue
                if newValue {
                    Task { await manager.runAutomaticBackup(context: modelContext) }
                }
            },
        )
    }

    // MARK: - Actions

    private func runExport(passphrase: String) {
        showingExportPassphrase = false
        do {
            let url = try manager.exportEncrypted(context: modelContext, passphrase: passphrase)
            exported = ExportedBackup(url: url)
        } catch {
            notice = Notice(title: String(localized: "Export Failed"), message: error.localizedDescription)
        }
    }

    private func handlePickedFile(_ result: Result<URL, Error>) {
        switch result {
        case let .success(url):
            guard url.startAccessingSecurityScopedResource() else {
                notice = Notice(title: String(localized: "Restore Failed"), message: String(localized: "Couldn't access the selected file."))
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                let data = try Data(contentsOf: url)
                let envelope = try BackupCrypto.inspect(data)
                pendingData = data
                pendingIsICloud = false
                if envelope.kind == .passphrase {
                    showingRestorePassphrase = true
                } else {
                    pendingPassphrase = nil
                    showingStrategyDialog = true
                }
            } catch {
                notice = Notice(title: String(localized: "Restore Failed"), message: error.localizedDescription)
            }
        case let .failure(error):
            notice = Notice(title: String(localized: "Restore Failed"), message: error.localizedDescription)
        }
    }

    private func executeRestore(_ strategy: BackupManager.RestoreStrategy) {
        let passphrase = pendingPassphrase
        if pendingIsICloud {
            Task {
                do {
                    try await manager.restoreFromICloud(passphrase: passphrase, strategy: strategy, context: modelContext)
                    notice = Notice(title: String(localized: "Restore Complete"), message: String(localized: "Your backup was restored."))
                } catch {
                    notice = Notice(title: String(localized: "Restore Failed"), message: error.localizedDescription)
                }
                clearPending()
            }
        } else if let data = pendingData {
            do {
                try manager.restore(data: data, passphrase: passphrase, strategy: strategy, context: modelContext)
                notice = Notice(title: String(localized: "Restore Complete"), message: String(localized: "Your backup was restored."))
            } catch {
                notice = Notice(title: String(localized: "Restore Failed"), message: error.localizedDescription)
            }
            clearPending()
        }
    }

    private func clearPending() {
        pendingData = nil
        pendingIsICloud = false
        pendingPassphrase = nil
    }
}

// MARK: - Supporting types

private struct ExportedBackup: Identifiable {
    let id = UUID()
    let url: URL
}

private struct Notice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

// MARK: - Passphrase Sheet

private struct PassphraseSheet: View {
    enum Mode {
        case create // new backup: passphrase + confirmation
        case enter // restoring: single passphrase
    }

    let mode: Mode
    let onSubmit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var passphrase = ""
    @State private var confirmation = ""

    private var isValid: Bool {
        switch mode {
        case .create:
            passphrase.count >= 8 && passphrase == confirmation
        case .enter:
            !passphrase.isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SecureField("Passphrase", text: $passphrase)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    if mode == .create {
                        SecureField("Confirm Passphrase", text: $confirmation)
                            .textContentType(.password)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                } footer: {
                    if mode == .create {
                        strengthFooter
                    }
                }
                .listRowBackground(Theme.cardBackground)

                if mode == .create {
                    Section {
                        Label {
                            Text("If you lose this passphrase, the backup can't be recovered. There is no reset.")
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        }
                        .font(.footnote)
                    }
                    .listRowBackground(Theme.cardBackground)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(mode == .create ? Text("Set a Passphrase") : Text("Enter Passphrase"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode == .create ? "Encrypt" : "Restore") {
                        onSubmit(passphrase)
                    }
                    .disabled(!isValid)
                }
            }
        }
        .presentationDetents([.medium])
    }

    @ViewBuilder
    private var strengthFooter: some View {
        if passphrase.isEmpty {
            Text("Use at least 8 characters. A longer phrase of several words is stronger and easier to remember.")
        } else if passphrase.count < 8 {
            Text("Too short — use at least 8 characters.")
                .foregroundStyle(.orange)
        } else if passphrase != confirmation {
            Text("Passphrases don't match yet.")
                .foregroundStyle(Theme.secondaryLabel)
        } else {
            Label("Passphrases match.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }
}
