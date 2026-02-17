import SwiftUI

private struct SubstanceEntry: Identifiable {
    let id = UUID()
    var name: String = ""
}

struct InteractionCheckerView: View {
    @State private var entries: [SubstanceEntry] = [SubstanceEntry(), SubstanceEntry()]
    @State private var results: [InteractionResult] = []
    @State private var hasChecked = false

    private var filledNames: [String] {
        entries.map(\.name).filter { !$0.isEmpty }
    }

    var body: some View {
            List {
                Section {
                    ForEach(entries) { entry in
                        SubstanceSearchField(text: nameBinding(for: entry.id)) { selected in
                            if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
                                entries[idx].name = selected.name
                            }
                            recheckInteractions()
                        } onCustom: {
                            recheckInteractions()
                        }
                        .id(entry.id)
                    }
                    .onDelete { offsets in
                        guard entries.count > 2 else { return }
                        entries.remove(atOffsets: offsets)
                        recheckInteractions()
                    }

                    if entries.count < 8 {
                        Button {
                            entries.append(SubstanceEntry())
                        } label: {
                            Label("Add Substance", systemImage: "plus.circle")
                        }
                    }
                } header: {
                    Text("Substances to check")
                } footer: {
                    Text("Enter 2 or more substances to check for interactions.")
                }

                if hasChecked {
                    if results.isEmpty {
                        Section {
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.title3)
                                Text("No known interactions found between these substances.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    } else {
                        Section {
                            ForEach(Array(results.enumerated()), id: \.offset) { _, warning in
                                InteractionWarningRow(warning: warning)
                            }
                        } header: {
                            Label(
                                results.count == 1 ? "1 Interaction Found" : "\(results.count) Interactions Found",
                                systemImage: results.first?.severity == .dangerous
                                    ? "exclamationmark.triangle.fill" : "exclamationmark.triangle"
                            )
                            .foregroundStyle((results.first?.severity ?? .caution).color)
                        }
                    }
                }
            }
            .navigationTitle("Interactions")
    }

    private func nameBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: {
                entries.first { $0.id == id }?.name ?? ""
            },
            set: { newValue in
                if let idx = entries.firstIndex(where: { $0.id == id }) {
                    entries[idx].name = newValue
                    recheckInteractions()
                }
            }
        )
    }

    private func recheckInteractions() {
        let filled = filledNames
        guard filled.count >= 2 else {
            results = []
            hasChecked = false
            return
        }
        results = InteractionChecker.checkBatch(filled, against: [])
        hasChecked = true
    }

}
