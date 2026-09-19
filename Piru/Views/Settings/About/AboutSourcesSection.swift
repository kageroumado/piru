import SwiftUI

private enum AboutSourceLinks {
    static let ccBySa = URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")!
}

/// Attribution for the sources Piru bundles: one outbound row per source, the
/// full list the database records, and the terms the wiki text is used under.
struct AboutSourcesSection: View {
    let sources: [SourceInfo]

    var body: some View {
        Section {
            ForEach(sources, id: \.name) { source in
                AboutSourceRow(source: source)
            }

            NavigationLink {
                DatabaseSourcesView()
            } label: {
                CaptionedRowLabel(
                    title: "All Database Sources",
                    systemImage: "cylinder.split.1x2",
                    caption: Text("Every source recorded in the substance database that ships with Piru."),
                )
            }
        } header: {
            Text("Data Sources & Licenses")
        } footer: {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Each substance page names the source of each field. Text from PsychonautWiki and FreeOD Wiki is used under CC BY-SA 4.0, edited and merged with other sources, and remains available under that license.")
                Text("Content outside those licenses — quotations from published books, manufacturers' label text, and figures from reference tables — belongs to its owners, and is shown for reference under their terms. Piru makes no claim to the correctness of any source.")
                Link(destination: AboutSourceLinks.ccBySa) {
                    // Verbatim: a license identifier is a proper noun.
                    Text(verbatim: "CC BY-SA 4.0 ↗")
                }
            }
        }
    }
}

// MARK: - Row

/// One source: its name, what it is, and its license
/// when Piru bundles its content. The whole row opens the source's site.
private struct AboutSourceRow: View {
    let source: SourceInfo

    var body: some View {
        if let url = URL(string: source.url) {
            Link(destination: url) {
                AboutSourceRowContent(source: source, isLinked: true)
            }
        } else {
            AboutSourceRowContent(source: source, isLinked: false)
        }
    }
}

private struct AboutSourceRowContent: View {
    let source: SourceInfo
    let isLinked: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                Text(verbatim: source.name)
                    .foregroundStyle(Color.primary)
                if isLinked {
                    Image(systemName: "arrow.up.right")
                        .font(.caption2)
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                }
            }
            Text(source.detail)
                .captionSecondary()
            Text(source.description)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryLabel)
            if let license = source.license {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                    Text("License")
                    // Verbatim: a license identifier is a proper noun.
                    Text(verbatim: license)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.secondaryLabel)
            }
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}
