import SwiftUI

/// A license whose full text ships in the app bundle, and what in Piru it covers.
private struct BundledLicense: Identifiable {
    /// The license's own name, shown verbatim.
    let name: String
    let covers: LocalizedStringResource
    /// Bundle resource name, without the `.txt` extension.
    let resource: String

    var id: String {
        resource
    }

    static let all: [BundledLicense] = [
        BundledLicense(
            name: "GNU General Public License v3.0",
            covers: "Piru's source code.",
            resource: "License-GPL-3.0",
        ),
        BundledLicense(
            name: "Creative Commons Attribution-ShareAlike 4.0",
            covers: "Text from PsychonautWiki and FreeOD Wiki, as edited and merged in Piru.",
            resource: "License-CC-BY-SA-4.0",
        ),
        BundledLicense(
            name: "Creative Commons CC0 1.0",
            covers: "Data from dose.wiki, Wikidata and openFDA.",
            resource: "License-CC0-1.0",
        ),
        BundledLicense(
            name: "GNU Lesser General Public License v2.1",
            covers: "The SubFxOnEx effects vocabulary. Copyright © Di-lemma.",
            resource: "License-LGPL-2.1",
        ),
        BundledLicense(
            name: "MIT License",
            covers: "GRDB.swift. Copyright © Gwendal Roué.",
            resource: "License-MIT-GRDB",
        ),
        BundledLicense(
            name: "Apache License 2.0 with Runtime Library Exception",
            covers: "swift-collections and swift-async-algorithms. Copyright © Apple Inc. and the Swift project authors.",
            resource: "License-Apache-2.0-Swift",
        ),
    ]
}

/// Every license Piru ships under or with, each opening its full text.
struct AboutLicensesSection: View {
    var body: some View {
        Section {
            ForEach(BundledLicense.all) { license in
                NavigationLink {
                    LicenseTextView(title: license.name, resource: license.resource)
                } label: {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        // Verbatim: a license's name is a proper noun.
                        Text(verbatim: license.name)
                        Text(license.covers)
                            .captionSecondary()
                    }
                }
            }
        } header: {
            Text("Licenses")
        } footer: {
            Text("Other sources are listed above under their own terms, and each substance page names the source of each field.")
        }
    }
}

/// The full text of one bundled license, selectable.
struct LicenseTextView: View {
    let title: String
    let resource: String

    private var text: String {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "txt"),
              let contents = try? String(contentsOf: url, encoding: .utf8)
        else { return "" }
        return contents
    }

    var body: some View {
        ScrollView {
            Text(verbatim: text)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .themedPage()
        .navigationTitle(Text(verbatim: title))
        .inlineNavigationTitle()
    }
}
