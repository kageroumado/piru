import SwiftUI

/// Every row of the bundled database's `sources` table, by name. Names and
/// descriptions are the database's own text, so they render verbatim.
struct DatabaseSourcesView: View {
    @State private var sources: [SubstanceStore.SourceState] = []

    var body: some View {
        List {
            Section {
                ForEach(sources) { source in
                    DatabaseSourceRow(name: source.displayName, summary: source.description)
                }
            } footer: {
                Text("Each substance page lists which of these supplied each field.")
            }
            .listRowBackground(CardBackground())
        }
        .themedPage()
        .navigationTitle("Database Sources")
        .inlineNavigationTitle()
        .onAppear(perform: reload)
    }

    private func reload() {
        sources = SubstanceStore.shared.sourceStates()
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }
}

private struct DatabaseSourceRow: View {
    let name: String
    let summary: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(verbatim: name)
            if let summary, !summary.isEmpty {
                Text(verbatim: summary)
                    .captionSecondary()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
