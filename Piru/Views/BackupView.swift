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
    /// The temporary encrypted file handed to the share sheet, removed once the
    /// share sheet is dismissed so ciphertext doesn't linger in /tmp.
    @State private var exportedFileToClean: URL?

    // Restore flow
    @State private var showingFileImporter = false
    @State private var showingRestorePassphrase = false
    @State private var pendingData: Data?
    @State private var pendingIsICloud = false
    @State private var pendingPassphrase: String?
    @State private var showingStrategyDialog = false

    @State private var notice: Notice?

    // Plain (unencrypted) export/import — Piru-native & PsychonautWiki JSON.
    @State private var plainExportDocument: PiruDocument?
    @State private var showingPlainExporter = false
    @State private var showingPlainImporter = false
    @State private var generatingFormat: ExportFormat?

    // Journal data — report + delete.
    @State private var showingReport = false
    @State private var showingDeleteConfirmation = false

    var body: some View {
        List {
            automaticSection
            exportSection
            importRestoreSection
            reportSection
            howItWorksSection
            deleteSection
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Data & Backup")
        .navigationBarTitleDisplayMode(.inline)
        .fileExporter(
            isPresented: $showingPlainExporter,
            document: plainExportDocument,
            contentType: .json,
            defaultFilename: DataExportImport.exportFilename,
        ) { result in
            plainExportDocument = nil
            if case let .failure(error) = result {
                notice = Notice(title: String(localized: "Export Failed"), message: error.localizedDescription)
            }
        }
        .fileImporter(isPresented: $showingPlainImporter, allowedContentTypes: [.json]) { result in
            handlePlainImport(result)
        }
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
        .sheet(item: $exported, onDismiss: cleanupExportedFile) { item in
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
        .sheet(isPresented: $showingReport) {
            ReportView()
        }
        .alert("Delete Everything", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) { deleteAllData() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete all your data? This action cannot be undone.")
        }
    }

    // MARK: - Automatic iCloud

    private var automaticSection: some View {
        Section {
            Toggle(isOn: autoBindng) {
                Label("iCloud Backup", systemImage: "icloud")
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

    // MARK: - Export

    private var exportSection: some View {
        Section {
            dataRow(
                title: "Piru Backup",
                subtitle: "A complete backup you can restore into Piru",
                systemImage: "arrow.up.doc",
                showSpinner: generatingFormat == .piru,
            ) { exportPlain(.piru) }
            dataRow(
                title: "PsychonautWiki Format",
                subtitle: "For importing into the PsychonautWiki app",
                systemImage: "arrow.up.doc",
                showSpinner: generatingFormat == .psyLog,
            ) { exportPlain(.psyLog) }
            dataRow(
                title: "Encrypted Backup…",
                subtitle: "Passphrase-protected — save or send it anywhere",
                systemImage: "lock.doc",
            ) { showingExportPassphrase = true }
        } header: {
            Text("Export")
        } footer: {
            Text("Piru and PsychonautWiki files are plain, unencrypted JSON. An encrypted backup is protected by a passphrase you choose — **if you forget it, the file cannot be opened, not even by us.**")
        }
        .disabled(generatingFormat != nil)
    }

    // MARK: - Import & Restore

    private var importRestoreSection: some View {
        Section {
            dataRow(
                title: "Import from a File…",
                subtitle: "A Piru or PsychonautWiki JSON file",
                systemImage: "arrow.down.doc",
            ) { showingPlainImporter = true }
            dataRow(
                title: "Restore Encrypted Backup…",
                subtitle: "A passphrase-protected .piruenc file",
                systemImage: "lock.doc",
            ) { showingFileImporter = true }
            if manager.iCloudAvailable {
                dataRow(
                    title: "Restore Latest iCloud Backup",
                    subtitle: "From your automatic iCloud backups",
                    systemImage: "arrow.clockwise.icloud",
                ) {
                    pendingIsICloud = true
                    pendingPassphrase = nil
                    showingStrategyDialog = true
                }
            }
        } header: {
            Text("Import & Restore")
        } footer: {
            Text("Imported entries are added to your journal (duplicates are skipped). Encrypted restores can merge or replace; iCloud and your own passphrase backups unlock automatically or prompt for the passphrase.")
        }
    }

    /// A list row with an accent icon, a title, an optional one-line description,
    /// and an optional trailing spinner. Used for both export and import actions.
    private func dataRow(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        systemImage: String,
        showSpinner: Bool = false,
        action: @escaping () -> Void,
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if showSpinner { ProgressView() }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Theme.cardBackground)
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

    // MARK: - Report & delete

    private var reportSection: some View {
        Section {
            dataRow(
                title: "Generate Medical Report",
                subtitle: "A PDF summary to share with a clinician",
                systemImage: "doc.richtext",
            ) { showingReport = true }
        } header: {
            Text("Report")
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Label("Delete Everything", systemImage: "trash")
            }
            .listRowBackground(Theme.cardBackground)
        } footer: {
            Text("Permanently removes every dose, session, and setting. A recoverable snapshot is taken first.")
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

    /// Export plain (unencrypted) JSON in the given format. Encodes off the main
    /// actor behind a spinner, then presents the save sheet.
    private func exportPlain(_ format: ExportFormat) {
        generatingFormat = format
        Task {
            defer { generatingFormat = nil }
            do {
                let data = try await DataExportImport.exportJSONInBackground(format: format, context: modelContext)
                plainExportDocument = PiruDocument(data: data)
                showingPlainExporter = true
            } catch {
                notice = Notice(title: String(localized: "Export Failed"), message: error.localizedDescription)
            }
        }
    }

    /// Import a plain Piru/PsychonautWiki JSON file (merges, de-duped).
    private func handlePlainImport(_ result: Result<URL, Error>) {
        switch result {
        case let .success(url):
            guard url.startAccessingSecurityScopedResource() else {
                notice = Notice(title: String(localized: "Import Failed"), message: String(localized: "Couldn't access the selected file."))
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                let data = try Data(contentsOf: url)
                try DataExportImport.importJSON(data: data, context: modelContext)
                notice = Notice(title: String(localized: "Import Complete"), message: String(localized: "Your data was imported."))
            } catch {
                notice = Notice(title: String(localized: "Import Failed"), message: error.localizedDescription)
            }
        case let .failure(error):
            notice = Notice(title: String(localized: "Import Failed"), message: error.localizedDescription)
        }
    }

    private func runExport(passphrase: String) {
        showingExportPassphrase = false
        Task {
            do {
                let url = try await manager.exportEncrypted(context: modelContext, passphrase: passphrase)
                exportedFileToClean = url
                exported = ExportedBackup(url: url)
            } catch {
                notice = Notice(title: String(localized: "Export Failed"), message: error.localizedDescription)
            }
        }
    }

    private func cleanupExportedFile() {
        guard let url = exportedFileToClean else { return }
        try? FileManager.default.removeItem(at: url)
        exportedFileToClean = nil
    }

    private func handlePickedFile(_ result: Result<URL, Error>) {
        switch result {
        case let .success(url):
            Task {
                guard url.startAccessingSecurityScopedResource() else {
                    notice = Notice(title: String(localized: "Restore Failed"), message: String(localized: "Couldn't access the selected file."))
                    return
                }
                defer { url.stopAccessingSecurityScopedResource() }
                do {
                    // Read + inspect off the main actor: a large file shouldn't be
                    // pulled into memory or JSON-decoded on the UI thread, and the
                    // size guard runs before we read a byte.
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
                        showingRestorePassphrase = true
                    } else {
                        pendingPassphrase = nil
                        showingStrategyDialog = true
                    }
                } catch {
                    notice = Notice(title: String(localized: "Restore Failed"), message: error.localizedDescription)
                }
            }
        case let .failure(error):
            notice = Notice(title: String(localized: "Restore Failed"), message: error.localizedDescription)
        }
    }

    private func executeRestore(_ strategy: BackupManager.RestoreStrategy) {
        let passphrase = pendingPassphrase
        let isICloud = pendingIsICloud
        let data = pendingData
        Task {
            do {
                if isICloud {
                    try await manager.restoreFromICloud(passphrase: passphrase, strategy: strategy, context: modelContext)
                } else if let data {
                    try await manager.restore(data: data, passphrase: passphrase, strategy: strategy, context: modelContext)
                }
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

    private func deleteAllData() {
        // Never delete without a recoverable copy: snapshot the populated store
        // aside first, so an accidental "Delete Everything" can be restored.
        StoreRecovery.snapshotStore(reason: "predelete")
        do {
            try DataExportImport.deleteAll(context: modelContext)
        } catch {
            notice = Notice(title: String(localized: "Delete Failed"), message: error.localizedDescription)
        }
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

    /// Minimum length for a *new* passphrase. A backup file is offline-attackable
    /// forever, so the floor is deliberately above the 8-char minimum; 600k-round
    /// PBKDF2 raises the cost-per-guess on top of this.
    private static let minLength = 12

    @Environment(\.dismiss) private var dismiss
    @State private var passphrase = ""
    @State private var confirmation = ""

    private var isValid: Bool {
        switch mode {
        case .create:
            passphrase.count >= Self.minLength && passphrase == confirmation
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
            Text("Use at least \(Self.minLength) characters. A phrase of several words is stronger and easier to remember than a short password.")
        } else if passphrase.count < Self.minLength {
            Text("Too short — use at least \(Self.minLength) characters.")
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
