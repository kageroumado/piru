import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Optional first-run import — the heaviest step, so it comes last. Lets a user arriving from
/// another tracker bring their history in from a Piru backup, PsychonautWiki, or PsyLog JSON
/// export. `DataExportImport.importJSON` auto-detects the format. Skippable via "Start fresh".
struct OnboardingImportStep: View {
    @Environment(\.onboardingNav) private var nav
    @Environment(\.modelContext) private var modelContext

    @State private var picking = false
    @State private var imported = false
    @State private var error: String?

    var body: some View {
        OnboardingLayout(
            title: "Bring your history",
            subtitle: "Already keep a journal? Import a Piru backup or a PsyLog-format export — or start with a clean slate.",
        ) {
            OnboardingIconHero(symbol: "square.and.arrow.down")
        } mid: {
            VStack(spacing: 14) {
                if imported {
                    Label("Import complete. Your data is ready.", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.green)
                        .onboardingGroupedCard()
                } else {
                    VStack(spacing: 18) {
                        OnboardingBulletRow(
                            symbol: "arrow.down.doc",
                            title: "Piru backup",
                            detail: "Restore a full journal you exported from Piru.",
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
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
        } footer: {
            if imported {
                OnboardingPrimaryButton(title: "Continue", action: nav.advance)
            } else {
                OnboardingPrimaryButton(title: "Import Data") { picking = true }
                OnboardingSecondaryButton(title: "Start Fresh", action: nav.advance)
            }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.json]) { result in
            handleImport(result)
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case let .success(url):
            Task {
                guard url.startAccessingSecurityScopedResource() else {
                    error = String(localized: "Couldn't access the selected file.")
                    return
                }
                defer { url.stopAccessingSecurityScopedResource() }
                do {
                    let data = try await Task.detached { try Data(contentsOf: url) }.value
                    try DataExportImport.importJSON(data: data, context: modelContext)
                    error = nil
                    withAnimation(.smooth) { imported = true }
                } catch {
                    self.error = DataExportImport.importErrorMessage(for: error)
                }
            }
        case let .failure(failure):
            error = failure.localizedDescription
        }
    }
}

#Preview {
    OnboardingImportStep()
        .background(Theme.background)
}
