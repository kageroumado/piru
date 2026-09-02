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
///
/// The screen itself owns nothing but presentation: every flow that can fail or
/// take time lives in ``DataStorageModel``, and each section is its own view.
struct DataStorageView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var model = DataStorageModel()

    /// Asks for a passphrase to seal a new encrypted backup.
    @State private var showingExportPassphrase = false

    /// Asks for the passphrase that opens a picked encrypted backup.
    @State private var showingRestorePassphrase = false
    /// Merge-or-replace, once the payload to restore is known.
    @State private var showingStrategyDialog = false

    /// The save panel for a plain (unencrypted) Piru or PsychonautWiki export.
    @State private var showingPlainExporter = false

    /// Which file the single shared importer should pick. SwiftUI only honours one
    /// `.fileImporter` per view, so the plain-JSON and encrypted-restore pickers
    /// are driven by this one enum rather than two competing modifiers.
    @State private var importKind: ImportKind?

    @State private var showingDeleteConfirmation = false

    @State private var pendingRestore: RecoverableStore?
    @State private var restoreComplete = false

    private enum ImportKind: Identifiable {
        case plainJSON
        case encrypted
        var id: Self {
            self
        }
    }

    var body: some View {
        List {
            LocalStorageSection()
            ICloudBackupSection()
            ExportImportSection(
                isGenerating: model.isGenerating,
                onExportPlain: exportPlain,
                onExportEncrypted: { showingExportPassphrase = true },
                onImportFile: { importKind = .plainJSON },
                onRestoreEncrypted: { importKind = .encrypted },
                onRestoreICloud: {
                    model.prepareICloudRestore()
                    showingStrategyDialog = true
                },
            )
            SubstanceDatabaseSection()
            HowEncryptionWorksSection()
            RecoverableCopiesSection(
                stores: model.recoverable,
                isLoading: model.loadingRecoverable,
                onSelect: { pendingRestore = $0 },
            )
            DeleteEverythingSection(onDelete: { showingDeleteConfirmation = true })
        }
        .themedPage()
        .navigationTitle("Data & Backup")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.loadRecoverable() }
        .fileExporter(
            isPresented: $showingPlainExporter,
            document: model.plainExportDocument,
            contentType: .json,
            defaultFilename: DataExportImport.exportFilename,
        ) { result in
            model.finishPlainExport(result)
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
                model.setRestorePassphrase(passphrase)
                showingRestorePassphrase = false
                showingStrategyDialog = true
            }
        }
        .sheet(item: $model.exported, onDismiss: { model.cleanupExportedFile() }) { item in
            ShareSheet(items: [item.url])
        }
        .confirmationDialog("Restore Backup", isPresented: $showingStrategyDialog, titleVisibility: .visible) {
            Button("Merge With Current Data") { executeRestore(.merge) }
            Button("Replace Everything", role: .destructive) { executeRestore(.replace) }
            Button("Cancel", role: .cancel) { model.clearPending() }
        } message: {
            Text("Merge keeps your current entries and adds the backup's. Replace deletes your current data first (a recovery snapshot is taken automatically) and restores only the backup.")
        }
        .alert(model.notice?.title ?? "", isPresented: noticeBinding, presenting: model.notice) { _ in
            Button("OK", role: .cancel) {}
        } message: { notice in
            Text(notice.message)
        }
        .alert("Delete Everything", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) { model.deleteAllData(context: modelContext) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete all your data? This action cannot be undone.")
        }
        .alert("Restore This Copy?", isPresented: restoreConfirmBinding, presenting: pendingRestore) { store in
            Button("Restore", role: .destructive) { restore(store) }
            Button("Cancel", role: .cancel) { pendingRestore = nil }
        } message: { store in
            Text("This replaces your current data with the \(DataStorageFormat.rowCountText(store.rowCount)) in this copy. A snapshot of your current data is taken first, so it's reversible. Restart Piru afterwards to load it.")
        }
        .alert("Restored", isPresented: $restoreComplete) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your data was restored. Please force-quit and reopen Piru to load it.")
        }
    }

    // MARK: - Bindings

    private var restoreConfirmBinding: Binding<Bool> {
        Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } })
    }

    private var noticeBinding: Binding<Bool> {
        Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })
    }

    private var importerBinding: Binding<Bool> {
        Binding(get: { importKind != nil }, set: { if !$0 { importKind = nil } })
    }

    // MARK: - Actions

    private func exportPlain(_ format: ExportFormat) {
        Task {
            if await model.generatePlainExport(format: format, context: modelContext) {
                showingPlainExporter = true
            }
        }
    }

    private func handlePlainImport(_ result: Result<URL, Error>) {
        Task { await model.importPlain(result, context: modelContext) }
    }

    private func runExport(passphrase: String) {
        showingExportPassphrase = false
        Task { await model.exportEncrypted(passphrase: passphrase, context: modelContext) }
    }

    private func handlePickedFile(_ result: Result<URL, Error>) {
        Task {
            switch await model.inspectPickedFile(result) {
            case .passphrase: showingRestorePassphrase = true
            case .strategy: showingStrategyDialog = true
            case .failed: break
            }
        }
    }

    private func executeRestore(_ strategy: BackupManager.RestoreStrategy) {
        Task { await model.executeRestore(strategy, context: modelContext) }
    }

    private func restore(_ store: RecoverableStore) {
        pendingRestore = nil
        restoreComplete = model.restoreRecoverable(store)
    }
}

// MARK: - On this device

private struct LocalStorageSection: View {
    @Query private var doses: [DoseEntry]
    @Query private var sessions: [Session]
    @Query private var dailyItems: [DailyDoseItem]
    @Query private var favorites: [FavoriteSubstance]
    @Query private var substanceColors: [SubstanceColor]
    @Query private var userColors: [UserColor]
    @Query private var quickLogDoses: [QuickLogDose]
    @Query private var inventoryItems: [InventoryItem]

    var body: some View {
        Section {
            CountRow(title: "Doses", systemImage: "pills", count: doses.count)
            CountRow(title: "Sessions", systemImage: "calendar.day.timeline.left", count: sessions.count)
            CountRow(title: "Daily Medications", systemImage: "cross.case", count: dailyItems.count)
            CountRow(title: "Quick-Log Shortcuts", systemImage: "bolt", count: quickLogDoses.count)
            CountRow(title: "Favorites", systemImage: "star", count: favorites.count)
            CountRow(title: "Inventory", systemImage: "shippingbox", count: inventoryItems.count)
            CountRow(
                title: "Custom Colors",
                systemImage: "paintpalette",
                count: substanceColors.count + userColors.count,
            )
            LabeledContent {
                Text(DataStorageFormat.byteString(StoreRecovery.canonicalStoreBytes()))
                    .foregroundStyle(Theme.secondaryLabel)
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
}

private struct CountRow: View {
    let title: LocalizedStringKey
    let systemImage: String
    let count: Int

    var body: some View {
        LabeledContent {
            Text("\(count)").foregroundStyle(Theme.secondaryLabel)
        } label: {
            Label(title, systemImage: systemImage)
        }
        .listRowBackground(CardBackground())
    }
}

// MARK: - Backup (automatic iCloud)

private struct ICloudBackupSection: View {
    @Environment(\.modelContext) private var modelContext
    @State private var manager = BackupManager.shared

    var body: some View {
        Section {
            Toggle(isOn: autoBinding) {
                Label("iCloud Backup", systemImage: "icloud")
            }
            .tint(Theme.accent)
            .disabled(!manager.iCloudAvailable)
            .listRowBackground(CardBackground())

            BackupStatusRow(manager: manager).listRowBackground(CardBackground())
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

    private var autoBinding: Binding<Bool> {
        Binding(
            get: { manager.autoICloudEnabled },
            set: { newValue in
                manager.autoICloudEnabled = newValue
                if newValue { Task { await manager.runAutomaticBackup(context: modelContext) } }
            },
        )
    }
}

private struct BackupStatusRow: View {
    let manager: BackupManager

    var body: some View {
        switch manager.status {
        case .running:
            Label { Text("Backing up…") } icon: { ProgressView() }
                .foregroundStyle(Theme.secondaryLabel)
        case let .failed(message):
            Label { Text("Last backup failed: \(message)") } icon: {
                Image(systemName: "exclamationmark.icloud").foregroundStyle(.cautionAccent).accessibilityHidden(true)
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

// MARK: - Export & Import

private struct ExportImportSection: View {
    let isGenerating: Bool
    let onExportPlain: (ExportFormat) -> Void
    let onExportEncrypted: () -> Void
    let onImportFile: () -> Void
    let onRestoreEncrypted: () -> Void
    let onRestoreICloud: () -> Void

    @State private var manager = BackupManager.shared
    @State private var showingExportOptions = false
    @State private var showingImportOptions = false

    var body: some View {
        Section {
            DataActionRow(
                title: "Export…",
                subtitle: "Piru, PsychonautWiki, or an encrypted backup",
                systemImage: "square.and.arrow.up",
                showSpinner: isGenerating,
            ) {
                showingExportOptions = true
            }
            .popover(isPresented: $showingExportOptions) { exportOptions }

            DataActionRow(
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
        .disabled(isGenerating)
    }

    /// Choices inside the Export popover.
    private var exportOptions: some View {
        ChooserPopover {
            OptionRow(
                title: "Piru Backup",
                subtitle: "A complete backup you can restore into Piru",
                systemImage: "arrow.up.doc",
            ) { afterPopoverDismiss { onExportPlain(.piru) } }
            OptionRow(
                title: "PsychonautWiki Format",
                subtitle: "For importing into the PsychonautWiki app",
                systemImage: "arrow.up.doc",
            ) { afterPopoverDismiss { onExportPlain(.psyLog) } }
            OptionRow(
                title: "Encrypted Backup…",
                subtitle: "Passphrase-protected — save or send it anywhere",
                systemImage: "lock.doc",
            ) { afterPopoverDismiss(onExportEncrypted) }
        }
    }

    /// Choices inside the Import & Restore popover.
    private var importOptions: some View {
        ChooserPopover {
            OptionRow(
                title: "Import from a File…",
                subtitle: "A Piru or PsychonautWiki JSON file",
                systemImage: "arrow.down.doc",
            ) { afterPopoverDismiss(onImportFile) }
            OptionRow(
                title: "Restore Encrypted Backup…",
                subtitle: "A passphrase-protected .piruenc file",
                systemImage: "lock.doc",
            ) { afterPopoverDismiss(onRestoreEncrypted) }
            if manager.iCloudAvailable {
                OptionRow(
                    title: "Restore Latest iCloud Backup",
                    subtitle: "From your automatic iCloud backups",
                    systemImage: "arrow.clockwise.icloud",
                ) { afterPopoverDismiss(onRestoreICloud) }
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
}

/// Compact popover container (a real popover even on iPhone) holding option rows.
private struct ChooserPopover<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(.vertical, Spacing.md)
            .frame(minWidth: 300)
            .presentationCompactAdaptation(.popover)
    }
}

/// A single tappable option inside a chooser popover.
private struct OptionRow: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: Spacing.xl) {
                Image(systemName: systemImage)
                    .font(.title3).foregroundStyle(Theme.accent).frame(width: IconSize.iconSmall)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).foregroundStyle(.primary)
                    Text(subtitle).captionSecondary()
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, Spacing.xxl).padding(.vertical, Spacing.lg)
        }
        .buttonStyle(.plain)
    }
}

/// A list row with an accent icon, a title, a one-line description, and an
/// optional trailing spinner. Used for the Export/Import and Report entries.
private struct DataActionRow: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let systemImage: String
    var showSpinner: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: Spacing.xl) {
                Image(systemName: systemImage)
                    .font(.title3).foregroundStyle(Theme.accent).frame(width: IconSize.iconSmall)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).foregroundStyle(.primary)
                    Text(subtitle).captionSecondary()
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
}

// MARK: - Substance database

/// The bundled substance data — source priority and opt-in updates — lives
/// in `SubstanceDatabaseView`; this row keeps it one tap from the data tool.
private struct SubstanceDatabaseSection: View {
    var body: some View {
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
}

// MARK: - How encryption works

private struct HowEncryptionWorksSection: View {
    var body: some View {
        Section {
            HowItWorksRow(
                icon: "lock.shield",
                title: "Strong encryption",
                detail: "Every backup is sealed with AES-256-GCM — the same authenticated encryption used by modern secure messengers. Tampering is detected and refused.",
            )
            HowItWorksRow(
                icon: "key.icloud",
                title: "Your key, your device",
                detail: "Automatic backups use a random key kept in your iCloud Keychain. It never leaves your devices in readable form, so iCloud only ever holds an unreadable blob.",
            )
            HowItWorksRow(
                icon: "key.horizontal",
                title: "Passphrase backups",
                detail: "Manual exports turn your passphrase into a key with 600,000 rounds of PBKDF2. The passphrase is never saved or sent. Choose one you won't forget — there's no recovery.",
            )
            HowItWorksRow(
                icon: "checkmark.shield",
                title: "Nothing is deleted by surprise",
                detail: "Replacing your data on restore takes a recoverable snapshot first. Backups are always optional and off until you turn them on.",
            )
        } header: {
            Text("How Encryption Works")
        }
    }
}

private struct HowItWorksRow: View {
    let icon: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.xl) {
            Image(systemName: icon).font(.title3).foregroundStyle(Theme.accent).frame(width: IconSize.iconSmall)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title).sectionLabel()
                Text(detail).captionSecondary()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, Spacing.xxs)
        .listRowBackground(CardBackground())
    }
}

// MARK: - Recoverable copies

private struct RecoverableCopiesSection: View {
    let stores: [RecoverableStore]
    let isLoading: Bool
    let onSelect: (RecoverableStore) -> Void

    var body: some View {
        Section {
            if isLoading {
                HStack { ProgressView(); Text("Checking for recoverable copies…").foregroundStyle(Theme.secondaryLabel) }
                    .listRowBackground(CardBackground())
            } else if stores.isEmpty {
                Label("No recoverable copies on this device.", systemImage: "checkmark.shield")
                    .foregroundStyle(Theme.secondaryLabel).font(.footnote)
                    .listRowBackground(CardBackground())
            } else {
                ForEach(stores) { store in
                    RecoverableRow(store: store) { onSelect(store) }
                }
            }
        } header: {
            Text("Recoverable Copies")
        } footer: {
            Text("Piru never deletes a store outright. Copies set aside automatically (after an upgrade hiccup) or before you deleted or restored data appear here, ready to restore.")
        }
    }
}

private struct RecoverableRow: View {
    let store: RecoverableStore
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: Spacing.xl) {
                Image(systemName: store.isIntentional ? "clock.arrow.circlepath" : "exclamationmark.arrow.circlepath")
                    .font(.title3)
                    .foregroundStyle(store.isIntentional ? Theme.secondaryLabel : .cautionAccent)
                    .frame(width: IconSize.iconSmall)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(DataStorageFormat.reasonTitle(store.reason)).foregroundStyle(.primary)
                    Text(DataStorageFormat.subtitle(for: store)).captionSecondary()
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(DataStorageFormat.subtitle(for: store, separator: ", "))
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
}

// MARK: - Delete

private struct DeleteEverythingSection: View {
    let onDelete: () -> Void

    var body: some View {
        Section {
            Button(role: .destructive, action: onDelete) {
                Label("Delete Everything", systemImage: "trash")
            }
            .listRowBackground(CardBackground())
        } footer: {
            Text("Permanently removes every dose, session, and setting. A recoverable snapshot is taken first.")
        }
    }
}

// MARK: - Formatting

/// The screen's shared row copy: how a set-aside store names itself, and how
/// sizes and record counts read.
private enum DataStorageFormat {
    static func reasonTitle(_ reason: String) -> LocalizedStringKey {
        switch reason {
        case "corrupt": "Auto-recovered Data"
        case "predelete": "Before You Deleted Everything"
        case "prerestore", "before-manual-restore": "Before a Restore"
        case "empty-before-recovery": "Recovered Data"
        default: "Saved Copy"
        }
    }

    static func subtitle(for store: RecoverableStore, separator: String = " · ") -> String {
        let rows = store.rowCount > 0 ? rowCountText(store.rowCount) : String(localized: "unreadable")
        let when = store.timestamp?.formatted(date: .abbreviated, time: .shortened) ?? String(localized: "unknown date")
        return [rows, byteString(store.bytes), when].joined(separator: separator)
    }

    static func rowCountText(_ count: Int) -> String {
        String(localized: "\(count) records")
    }

    static func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
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
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.cautionAccent).accessibilityHidden(true)
                        }
                        .font(.footnote)
                    }
                    .listRowBackground(CardBackground())
                }
            }
            .themedPage()
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
            Text("Too short — use at least \(Self.minLength) characters.").foregroundStyle(.cautionText)
        } else if passphrase != confirmation {
            Text("Passphrases don't match yet.").foregroundStyle(Theme.secondaryLabel)
        } else {
            Label("Passphrases match.", systemImage: "checkmark.circle.fill").foregroundStyle(Color.successText)
        }
    }
}
