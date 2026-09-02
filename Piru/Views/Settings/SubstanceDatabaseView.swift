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
                    Text("Data from peer-reviewed literature, FDA labels, and community databases. Not medical advice — talk to a doctor before making decisions about substance use.")
                }
            }
            .listRowBackground(CardBackground())
        }
        .themedPage()
        .navigationTitle("Substance Database")
        .navigationBarTitleDisplayMode(.inline)
    }
}
