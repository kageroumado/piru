import SwiftUI

/// Published benzodiazepine amounts beside the source table's diazepam amounts.
struct DiazepamReferenceView: View {
    @State private var entries: [BenzoEquivalence] = []

    var body: some View {
        List {
            Section {
                Text("Published equivalences are approximate and vary between sources. A prescriber must assess any medication change.")
                    .font(.subheadline)
            }
            Section("Reference table") {
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text(entry.displayName).font(.headline)
                        if let reference = entry.equivalent.displayText {
                            Text(reference).font(.subheadline)
                        }
                        Text("Ashton Manual, Table 1")
                            .captionSecondary()
                    }
                    .padding(.vertical, Spacing.xxs)
                }
            }
        }
        .insetGroupedListStyle()
        .skinBackdrop()
        .appNavigationBar("Diazepam Equivalence")
        .task {
            await SubstanceStore.shared.ensureAllLoaded()
            entries = SubstanceStore.shared.benzoEquivalences()
                .filter(\.equivalent.isCited)
                .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        }
    }
}
