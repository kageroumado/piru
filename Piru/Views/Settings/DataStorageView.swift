import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// One scrollable home for everything about the user's data: what's stored on
/// this device, automatic iCloud backup, manual export/import, how the encryption
/// works, and — at the bottom — recoverable copies and the destructive "delete
/// everything" action.
///
/// Import/export lives here rather than a separate Backup screen, alongside
/// local-storage transparency and on-device recovery for stores set aside
/// automatically (an upgrade hiccup) or before a deliberate delete/restore.
struct DataStorageView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var manager = BackupManager.shared

    // Local storage counts.
    @Query private var doses: [DoseEntry]
    @Query private var sessions: [Session]
    @Query private var dailyItems: [DailyDoseItem]
    @Query private var favorites: [FavoriteSubstance]
    @Query private var substanceColors: [SubstanceColor]
    @Query private var userColors: [UserColor]
    @Query private var quickLogDoses: [QuickLogDose]
    @Query private var inventoryItems: [InventoryItem]

    // Encrypted export flow.
    @State private var showingExportPassphrase = false
    @State private var exported: ExportedBackup?
    /// The temporary encrypted file handed to the share sheet, removed once the
    /// share sheet is dismissed so ciphertext doesn't linger in /tmp.
    @State private var exportedFileToClean: URL?

    // Restore flow.
    @State private var showingRestorePassphrase = false
    @State private var pendingData: Data?
    @State private var pendingIsICloud = false
    @State private var pendingPassphrase: String?
    @State private var showingStrategyDialog = false

    @State private var notice: Notice?

    // Plain (unencrypted) export/import — Piru-native & PsychonautWiki JSON.
    @State private var plainExportDocument: PiruDocument?
    @State private var showingPlainExporter = false
    @State private var generatingFormat: ExportFormat?

    /// Which file the single shared importer should pick. SwiftUI only honours one
    /// `.fileImporter` per view, so the plain-JSON and encrypted-restore pickers
    /// are driven by this one enum rather than two competing modifiers.
    @State private var importKind: ImportKind?

    private enum ImportKind: Identifiable {
        case plainJSON
        case encrypted
        var id: Self {
            self
        }
    }

    // Export / import option popovers.
    @State private var showingExportOptions = false
    @State private var showingImportOptions = false

    @State private var showingDeleteConfirmation = false

    // Recoverable copies — loaded async (enumerating sidecars opens each store).
    @State private var recoverable: [RecoverableStore] = []
    @State private var loadingRecoverable = true
    @State private var pendingRestore: RecoverableStore?
    @State private var restoreComplete = false

    var body: some View {
        List {
            storageSection
            backupSection
            exportImportSection
            substanceDatabaseSection
            howItWorksSection
            recoverableSection
            deleteSection
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Data & Backup")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadRecoverable() }
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
        .fileImporter(
            isPresented: importerBinding,
            allowedContentTypes: importKind == .encrypted ? [.data] : [.json],
        ) { result in
            let kind = importKind
            importKind = nil
            switch kind {
            case .encrypted: handlePickedFile(result)
            case .plainJSON, .none: handlePlainImport(result)
            }
        }
        .sheet(isPresented: $showingExportPassphrase) {
            PassphraseSheet(mode: .create) { passphrase in runExport(passphrase: passphrase) }
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
        .confirmationDialog("Restore Backup", isPresented: $showingStrategyDialog, titleVisibility: .visible) {
            Button("Merge With Current Data") { executeRestore(.merge) }
            Button("Replace Everything", role: .destructive) { executeRestore(.replace) }
            Button("Cancel", role: .cancel) { clearPending() }
        } message: {
            Text("Merge keeps your current entries and adds the backup's. Replace deletes your current data first (a recovery snapshot is taken automatically) and restores only the backup.")
        }
        .alert(notice?.title ?? "", isPresented: noticeBinding, presenting: notice) { _ in
            Button("OK", role: .cancel) {}
        } message: { notice in
            Text(notice.message)
        }
        .alert("Delete Everything", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) { deleteAllData() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete all your data? This action cannot be undone.")
        }
        .alert("Restore This Copy?", isPresented: restoreConfirmBinding, presenting: pendingRestore) { store in
            Button("Restore", role: .destructive) { restore(store) }
            Button("Cancel", role: .cancel) { pendingRestore = nil }
        } message: { store in
            Text("This replaces your current data with the \(rowCountText(store.rowCount)) in this copy. A snapshot of your current data is taken first, so it's reversible. Restart Piru afterwards to load it.")
        }
        .alert("Restored", isPresented: $restoreComplete) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your data was restored. Please force-quit and reopen Piru to load it.")
        }
    }

    // MARK: - On this device

    private var storageSection: some View {
        Section {
            countRow("Doses", systemImage: "pills", count: doses.count)
            countRow("Sessions", systemImage: "calendar.day.timeline.left", count: sessions.count)
            countRow("Daily Medications", systemImage: "cross.case", count: dailyItems.count)
            countRow("Quick-Log Shortcuts", systemImage: "bolt", count: quickLogDoses.count)
            countRow("Favorites", systemImage: "star", count: favorites.count)
            countRow("Inventory", systemImage: "shippingbox", count: inventoryItems.count)
            countRow("Custom Colors", systemImage: "paintpalette", count: substanceColors.count + userColors.count)
            LabeledContent {
                Text(byteString(StoreRecovery.canonicalStoreBytes())).foregroundStyle(Theme.secondaryLabel)
            } label: {
                Label("Store Size", systemImage: "internaldrive")
            }
            .listRowBackground(CardBackground())
        } header: {
            Text("On This Device")
        } footer: {
            Text("Everything Piru stores locally. Your dose data lives only on this device unless you turn on iCloud backup.")
        }
    }

    // MARK: - Backup (automatic iCloud)

    private var backupSection: some View {
        Section {
            Toggle(isOn: autoBinding) {
                Label("iCloud Backup", systemImage: "icloud")
            }
            .tint(Theme.accent)
            .disabled(!manager.iCloudAvailable)
            .listRowBackground(CardBackground())

            statusRow.listRowBackground(CardBackground())
        } header: {
            Text("Backup")
        } footer: {
            if manager.iCloudAvailable {
                Text("When on, Piru encrypts your journal and saves it to your private iCloud Drive each time you leave the app. The key is stored only in your iCloud Keychain, so it's end-to-end encrypted — **neither Apple nor Piru can read it** — and it restores on your other devices signed in to the same Apple Account.")
            } else {
                Text("Sign in to iCloud and turn on iCloud Drive to enable automatic encrypted backups.")
            }
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch manager.status {
        case .running:
            Label { Text("Backing up…") } icon: { ProgressView() }
                .foregroundStyle(Theme.secondaryLabel)
        case let .failed(message):
            Label { Text("Last backup failed: \(message)") } icon: {
                Image(systemName: "exclamationmark.icloud").foregroundStyle(.orange).accessibilityHidden(true)
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

    // MARK: - Export & Import

    private var exportImportSection: some View {
        Section {
            dataRow(
                title: "Export…",
                subtitle: "Piru, PsychonautWiki, or an encrypted backup",
                systemImage: "square.and.arrow.up",
                showSpinner: generatingFormat != nil,
            ) {
                showingExportOptions = true
            }
            .popover(isPresented: $showingExportOptions) { exportOptions }

            dataRow(
                title: "Import & Restore…",
                subtitle: "From a file, an encrypted backup, or iCloud",
                systemImage: "square.and.arrow.down",
            ) {
                showingImportOptions = true
            }
            .popover(isPresented: $showingImportOptions) { importOptions }
        } header: {
            Text("Export & Import")
        } footer: {
            Text("Piru and PsychonautWiki files are plain, unencrypted JSON. Imported entries are added to your journal (duplicates are skipped). Encrypted restores can merge or replace. Inventory is included in Piru and encrypted backups, but not PsychonautWiki files.")
        }
        .disabled(generatingFormat != nil)
    }

    /// Choices inside the Export popover.
    private var exportOptions: some View {
        chooser {
            optionRow(
                title: "Piru Backup",
                subtitle: "A complete backup you can restore into Piru",
                systemImage: "arrow.up.doc",
            ) { afterPopoverDismiss { exportPlain(.piru) } }
            optionRow(
                title: "PsychonautWiki Format",
                subtitle: "For importing into the PsychonautWiki app",
                systemImage: "arrow.up.doc",
            ) { afterPopoverDismiss { exportPlain(.psyLog) } }
            optionRow(
                title: "Encrypted Backup…",
                subtitle: "Passphrase-protected — save or send it anywhere",
                systemImage: "lock.doc",
            ) { afterPopoverDismiss { showingExportPassphrase = true } }
        }
    }

    /// Choices inside the Import & Restore popover.
    private var importOptions: some View {
        chooser {
            optionRow(
                title: "Import from a File…",
                subtitle: "A Piru or PsychonautWiki JSON file",
                systemImage: "arrow.down.doc",
            ) { afterPopoverDismiss { importKind = .plainJSON } }
            optionRow(
                title: "Restore Encrypted Backup…",
                subtitle: "A passphrase-protected .piruenc file",
                systemImage: "lock.doc",
            ) { afterPopoverDismiss { importKind = .encrypted } }
            if manager.iCloudAvailable {
                optionRow(
                    title: "Restore Latest iCloud Backup",
                    subtitle: "From your automatic iCloud backups",
                    systemImage: "arrow.clockwise.icloud",
                ) {
                    afterPopoverDismiss {
                        pendingIsICloud = true
                        pendingPassphrase = nil
                        showingStrategyDialog = true
                    }
                }
            }
        }
    }

    /// Dismisses whichever option popover is open, then runs `action` once the
    /// popover's dismissal animation has finished.
    ///
    /// Presenting a file importer/exporter (or confirmation dialog) in the *same*
    /// update cycle that dismisses the popover makes SwiftUI swallow the new
    /// presentation — both target the same anchor, and the popover dismissal
    /// wins. Waiting one dismissal out lets the follow-up present reliably.
    private func afterPopoverDismiss(_ action: @escaping () -> Void) {
        showingExportOptions = false
        showingImportOptions = false
        Task { @MainActor in
            try? await Task.sleep(for: UITiming.presentationTeardown)
            action()
        }
    }

    /// Compact popover container (a real popover even on iPhone) holding option rows.
    private func chooser(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(.vertical, 8)
            .frame(minWidth: 300)
            .presentationCompactAdaptation(.popover)
    }

    /// A single tappable option inside a chooser popover.
    private func optionRow(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        systemImage: String,
        action: @escaping () -> Void,
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3).foregroundStyle(Theme.accent).frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(Theme.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    /// A list row with an accent icon, a title, a one-line description, and an
    /// optional trailing spinner. Used for the Export/Import and Report entries.
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
                    .font(.title3).foregroundStyle(Theme.accent).frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(Theme.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if showSpinner { ProgressView() }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(CardBackground())
    }

    // MARK: - How encryption works

    /// The bundled substance data — source priority and opt-in updates — lives
    /// in `SubstanceDatabaseView`; this row keeps it one tap from the data tool.
    private var substanceDatabaseSection: some View {
        Section {
            NavigationLink {
                SubstanceDatabaseView()
            } label: {
                LabeledContent {
                    Text("\(SubstanceStore.shared.count)")
                        .foregroundStyle(Theme.secondaryLabel)
                } label: {
                    Label("Substance Database", systemImage: "books.vertical")
                }
            }
            .listRowBackground(CardBackground())
        } footer: {
            Text("Which source wins when they disagree, and opt-in updates to the bundled substance data.")
        }
    }

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
            Image(systemName: icon).font(.title3).foregroundStyle(Theme.accent).frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(Theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
        .listRowBackground(CardBackground())
    }

    // MARK: - Recoverable copies

    private var recoverableSection: some View {
        Section {
            if loadingRecoverable {
                HStack { ProgressView(); Text("Checking for recoverable copies…").foregroundStyle(Theme.secondaryLabel) }
                    .listRowBackground(CardBackground())
            } else if recoverable.isEmpty {
                Label("No recoverable copies on this device.", systemImage: "checkmark.shield")
                    .foregroundStyle(Theme.secondaryLabel).font(.footnote)
                    .listRowBackground(CardBackground())
            } else {
                ForEach(recoverable) { store in recoverableRow(store) }
            }
        } header: {
            Text("Recoverable Copies")
        } footer: {
            Text("Piru never deletes a store outright. Copies set aside automatically (after an upgrade hiccup) or before you deleted or restored data appear here, ready to restore.")
        }
    }

    private func recoverableRow(_ store: RecoverableStore) -> some View {
        Button { pendingRestore = store } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: store.isIntentional ? "clock.arrow.circlepath" : "exclamationmark.arrow.circlepath")
                    .font(.title3)
                    .foregroundStyle(store.isIntentional ? Theme.secondaryLabel : .orange)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(reasonTitle(store.reason)).foregroundStyle(.primary)
                    Text(subtitle(for: store)).font(.caption).foregroundStyle(Theme.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(subtitle(for: store, separator: ", "))
                }
                Spacer(minLength: 0)
                if store.rowCount > 0 {
                    Text("Restore").font(.callout.weight(.medium)).foregroundStyle(Theme.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(store.rowCount <= 0)
        .listRowBackground(CardBackground())
    }

    // MARK: - Delete

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) { showingDeleteConfirmation = true } label: {
                Label("Delete Everything", systemImage: "trash")
            }
            .listRowBackground(CardBackground())
        } footer: {
            Text("Permanently removes every dose, session, and setting. A recoverable snapshot is taken first.")
        }
    }

    // MARK: - Rows & formatting

    private func countRow(_ title: LocalizedStringKey, systemImage: String, count: Int) -> some View {
        LabeledContent {
            Text("\(count)").foregroundStyle(Theme.secondaryLabel)
        } label: {
            Label(title, systemImage: systemImage)
        }
        .listRowBackground(CardBackground())
    }

    private func reasonTitle(_ reason: String) -> LocalizedStringKey {
        switch reason {
        case "corrupt": "Auto-recovered Data"
        case "predelete": "Before You Deleted Everything"
        case "prerestore", "before-manual-restore": "Before a Restore"
        case "empty-before-recovery": "Recovered Data"
        default: "Saved Copy"
        }
    }

    private func subtitle(for store: RecoverableStore, separator: String = " · ") -> String {
        let rows = store.rowCount > 0 ? rowCountText(store.rowCount) : String(localized: "unreadable")
        let when = store.timestamp?.formatted(date: .abbreviated, time: .shortened) ?? String(localized: "unknown date")
        return [rows, byteString(store.bytes), when].joined(separator: separator)
    }

    private func rowCountText(_ count: Int) -> String {
        String(localized: "\(count) records")
    }

    private func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: - Bindings

    private var autoBinding: Binding<Bool> {
        Binding(
            get: { manager.autoICloudEnabled },
            set: { newValue in
                manager.autoICloudEnabled = newValue
                if newValue { Task { await manager.runAutomaticBackup(context: modelContext) } }
            },
        )
    }

    private var restoreConfirmBinding: Binding<Bool> {
        Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } })
    }

    private var noticeBinding: Binding<Bool> {
        Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })
    }

    private var importerBinding: Binding<Bool> {
        Binding(get: { importKind != nil }, set: { if !$0 { importKind = nil } })
    }

    // MARK: - Actions

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

    private func handlePlainImport(_ result: Result<URL, Error>) {
        switch result {
        case let .success(url):
            Task {
                guard url.startAccessingSecurityScopedResource() else {
                    notice = Notice(title: String(localized: "Import Failed"), message: String(localized: "Couldn't access the selected file."))
                    return
                }
                defer { url.stopAccessingSecurityScopedResource() }
                do {
                    let data = try await Task.detached { try Data(contentsOf: url) }.value
                    try DataExportImport.importJSON(data: data, context: modelContext)
                    notice = Notice(title: String(localized: "Import Complete"), message: String(localized: "Your data was imported."))
                } catch {
                    notice = Notice(title: String(localized: "Import Failed"), message: DataExportImport.importErrorMessage(for: error))
                }
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
        StoreRecovery.snapshotStore(reason: "predelete")
        do {
            try DataExportImport.deleteAll(context: modelContext)
        } catch {
            notice = Notice(title: String(localized: "Delete Failed"), message: error.localizedDescription)
        }
    }

    // MARK: - Recoverable copies loading

    private func loadRecoverable() async {
        loadingRecoverable = true
        recoverable = await Task.detached { StoreRecovery.recoverableStores() }.value
        loadingRecoverable = false
    }

    private func restore(_ store: RecoverableStore) {
        pendingRestore = nil
        do {
            try StoreRecovery.restore(from: store.url)
            restoreComplete = true
        } catch {
            notice = Notice(title: String(localized: "Restore Failed"), message: error.localizedDescription)
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
        case .create: passphrase.count >= Self.minLength && passphrase == confirmation
        case .enter: !passphrase.isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SecureField("Passphrase", text: $passphrase)
                        .textContentType(.password).autocorrectionDisabled().textInputAutocapitalization(.never)
                    if mode == .create {
                        SecureField("Confirm Passphrase", text: $confirmation)
                            .textContentType(.password).autocorrectionDisabled().textInputAutocapitalization(.never)
                    }
                } footer: {
                    if mode == .create { strengthFooter }
                }
                .listRowBackground(CardBackground())

                if mode == .create {
                    Section {
                        Label {
                            Text("If you lose this passphrase, the backup can't be recovered. There is no reset.")
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).accessibilityHidden(true)
                        }
                        .font(.footnote)
                    }
                    .listRowBackground(CardBackground())
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(mode == .create ? Text("Set a Passphrase") : Text("Enter Passphrase"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode == .create ? "Encrypt" : "Restore") { onSubmit(passphrase) }
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
            Text("Too short — use at least \(Self.minLength) characters.").foregroundStyle(.orange)
        } else if passphrase != confirmation {
            Text("Passphrases don't match yet.").foregroundStyle(Theme.secondaryLabel)
        } else {
            Label("Passphrases match.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        }
    }
}
