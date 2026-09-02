import SwiftUI

/// A single Settings row that surfaces the substance-database update state
/// from ``SubstanceDBUpdater``. Designed to live inside the existing
/// "Substance Database" section in ``SettingsView``.
///
/// Renders three states:
/// - **Idle**: shows the installed `content_version` + a "Check" button.
/// - **Checking / downloading**: progress UI.
/// - **Update available**: download CTA with size + release notes.
/// - **Applied**: "Restart Piru to use the new database".
struct SubstanceDBUpdateRow: View {
    @State private var updater = SubstanceDBUpdater.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            switch updater.state {
            case .idle:
                idleRow

            case .checking:
                HStack(spacing: Spacing.md) {
                    ProgressView().controlSize(.small)
                    Text("Checking…")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryLabel)
                }

            case let .upToDate(local):
                upToDateRow(local: local)

            case let .updateAvailable(local, remote):
                updateAvailableRow(local: local, remote: remote)

            case let .downloading(progress):
                downloadingRow(progress: progress)

            case let .appliedNeedsRestart(applied):
                appliedRow(applied: applied)

            case let .error(message):
                errorRow(message: message)
            }
        }
        .padding(.vertical, Spacing.xxs)
    }

    // MARK: - Sub-rows

    private var idleRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Label("Database Build", systemImage: "shippingbox")
                    .font(.subheadline)
                Text(updater.currentManifest?.contentVersion ?? "—")
                    .font(.caption.monospaced())
                    .foregroundStyle(Theme.secondaryLabel)
            }
            .accessibilityElement(children: .combine)
            Spacer()
            Button("Check for Updates") {
                Task { await updater.checkForUpdates() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func upToDateRow(local: SubstanceDBManifest) -> some View {
        HStack {
            Label("Up to date", systemImage: "checkmark.seal.fill")
                .foregroundStyle(Color.successText)
                .font(.subheadline)
            Spacer()
            Text(local.contentVersion)
                .font(.caption.monospaced())
                .foregroundStyle(Theme.secondaryLabel)
        }
        .accessibilityElement(children: .combine)
    }

    private func updateAvailableRow(local: SubstanceDBManifest, remote: SubstanceDBManifest) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Label("Update Available", systemImage: "arrow.down.circle.fill")
                    .foregroundStyle(Theme.accent)
                    .sectionLabel()
                Spacer()
                Text("\(local.contentVersion) → \(remote.contentVersion)")
                    .font(.caption.monospaced())
                    .foregroundStyle(Theme.secondaryLabel)
            }
            .accessibilityElement(children: .combine)
            HStack {
                Text(formattedSize(remote.sqliteSizeBytes))
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryLabel)
                Spacer()
                Button("Download") {
                    Task { await updater.downloadAndApply() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }

    private func downloadingRow(progress: Double) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label("Downloading…", systemImage: "arrow.down.circle")
                .font(.subheadline)
            ProgressView(value: progress)
        }
        .accessibilityElement(children: .combine)
    }

    private func appliedRow(applied: SubstanceDBManifest) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Label("Update Applied", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Color.successText)
                    .sectionLabel()
                Spacer()
                Text(applied.contentVersion)
                    .font(.caption.monospaced())
                    .foregroundStyle(Theme.secondaryLabel)
            }
            Text("Restart Piru to use the new database.")
                .captionSecondary()
        }
    }

    private func errorRow(message: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Label("Update Failed", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.Semantic.Caution.text)
                    .sectionLabel()
                Spacer()
                Button("Retry") {
                    Task { await updater.checkForUpdates() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Text(message)
                .captionSecondary()
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func formattedSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
