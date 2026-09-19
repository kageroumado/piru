import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// The controls for the bundled substance dataset: which sources win when they
/// disagree, and how many substances ship. Attribution
/// and licenses for the same sources are listed in ``AboutView``.
struct SubstanceDatabaseView: View {
    var body: some View {
        List {
            Group {
                Section {
                    NavigationLink {
                        SourcePriorityView()
                    } label: {
                        Label("Source Priority", systemImage: "arrow.up.arrow.down")
                    }
                    LabeledContent("Substances", value: "\(SubstanceStore.shared.count)")
                } footer: {
                    Text("All substance data ships with the app. Reorder sources to choose which one wins when they disagree on a fact.")
                }

                Section {
                    EmptyView()
                } footer: {
                    Text("Data from published literature, product labels, and community databases, provided as is and without warranty. Not medical advice.")
                }
            }
            .listRowBackground(CardBackground())
        }
        .themedPage()
        .navigationTitle("Substance Database")
        .inlineNavigationTitle()
    }
}
