import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Optional first-run import — the heaviest step, so it comes last. Lets a user arriving from
/// another tracker bring their history in from a Piru backup (plain or encrypted), PsychonautWiki,
/// or PsyLog JSON export. `BackupFileImport` works out which from the file. Skippable via "Start fresh".
struct OnboardingImportStep: View {
    @Environment(\.onboardingNav) private var nav
    @Environment(\.modelContext) private var modelContext

    @State private var picking = false
    @State private var imported = false
    @State private var error: String?
    @State private var lockedBackup: BackupFileImport.LockedBackup?

    var body: some View {
        OnboardingLayout(
            title: "Bring your history",
            subtitle: "Already keep a journal? Import a Piru backup, encrypted or not, or a PsyLog or DrugsPRO export — or start with a clean slate.",
        ) {
            OnboardingIconHero(symbol: "square.and.arrow.down")
        } mid: {
            VStack(spacing: 14) {
                if imported {
                    Label("Import complete. Your data is ready.", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.successText)
                        .onboardingGroupedCard()
                } else {
                    VStack(spacing: 18) {
                        OnboardingBulletRow(
                            symbol: "arrow.down.doc",
                            title: "Piru backup",
                            detail: "Restore a full journal you exported from Piru.",
                        )
                        OnboardingBulletRow(
                            symbol: "lock.doc",
                            title: "Encrypted backup",
                            detail: "Pick the .piruenc file and enter its passphrase.",
                        )
                        OnboardingBulletRow(
                            symbol: "doc.text",
                            title: "PsyLog format",
                            detail: "Import from PsyLog or any app that shares its format — both old and new versions.",
                        )
                    }
                    .onboardingGroupedCard()
                }
                if let error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Color.Semantic.Danger.text)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, Spacing.xxxl)
            .padding(.top, 28)
        } footer: {
            if imported {
                GlassPillButton(title: "Continue", action: nav.advance)
            } else {
                GlassPillButton(title: "Import Data") { picking = true }
                GlassPillButton(title: "Start Fresh", prominence: .neutral, action: nav.advance)
            }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.json, .data]) { result in
            handlePicked(result)
        }
        .backupPassphraseAlert(for: $lockedBackup, onUnlock: restore)
    }

    private func handlePicked(_ result: Result<URL, Error>) {
        Task {
            switch await BackupFileImport.importPicked(result, context: modelContext) {
            case .imported: succeed()
            case let .locked(backup): lockedBackup = backup
            case let .failed(message): error = message
            }
        }
    }

    /// Merges an unlocked backup: a new journal has nothing to replace.
    private func restore(_ plaintext: Data) {
        do {
            try BackupManager.shared.apply(plaintext: plaintext, strategy: .merge, context: modelContext)
            DataExportImport.refreshLiveStores(container: modelContext.container)
            succeed()
        } catch {
            self.error = DataExportImport.importErrorMessage(for: error)
        }
    }

    private func succeed() {
        error = nil
        withAnimation(.smooth) { imported = true }
    }
}

#Preview {
    OnboardingImportStep()
        .skinBackdrop()
}
