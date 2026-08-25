import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Everything about the bundled substance dataset: which sources win when they
/// disagree, how many substances ship, and opt-in database updates. The single
/// authoritative home for data-source information — there is no separate
/// "Sources & References" list elsewhere.
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
                    SubstanceDBUpdateRow()
                } footer: {
                    Text("All substance data ships with the app. Reorder sources to choose which one wins when they disagree on a fact. Updates are opt-in and verified by sha256.")
                }

                Section {
                    EmptyView()
                } footer: {
                    Text("Pharmacological data is compiled from the sources above — community databases, FDA labeling, and peer-reviewed literature. Provided for reference and educational purposes only. Always consult a qualified healthcare professional before making decisions about substance use.")
                }
            }
            .listRowBackground(CardBackground())
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Substance Database")
        .navigationBarTitleDisplayMode(.inline)
    }
}
