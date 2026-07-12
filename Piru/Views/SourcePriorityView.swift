import SwiftUI

/// Lets the user reorder and enable/disable the substance-data sources the
/// store consults when resolving fields. Highest priority is at the top — the
/// first enabled source with a value wins.
///
/// Mutations go through ``SubstanceStore`` which clears its resolved-substance
/// cache, so the rest of the app sees the new priority on the next lookup.
struct SourcePriorityView: View {
    @State private var states: [SubstanceStore.SourceState] = []

    var body: some View {
        List {
            Section {
                ForEach(Array(states.enumerated()), id: \.element.id) { index, state in
                    SourceRow(
                        state: state,
                        toggle: { toggle(state, enabled: $0) },
                    )
                    .accessibilityValue(
                        Text(state.enabled ? "On" : "Off")
                            + Text(verbatim: ", ")
                            + Text("Priority \(index + 1) of \(states.count)"),
                    )
                }
                .onMove(perform: move)
            } header: {
                Text("Priority Order")
            } footer: {
                Text("Sources at the top take precedence when a fact is reported by multiple sources. Disabled sources are hidden from resolved values but still searchable in advanced views.")
            }
        }
        .navigationTitle("Data Sources")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                EditButton()
            }
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        states = SubstanceStore.shared.sourceStates()
    }

    private func move(from offsets: IndexSet, to destination: Int) {
        states.move(fromOffsets: offsets, toOffset: destination)
        SubstanceStore.shared.setSourcePriority(orderedSlugs: states.map(\.slug))
        reload()
    }

    private func toggle(_ state: SubstanceStore.SourceState, enabled: Bool) {
        SubstanceStore.shared.setSource(state.slug, enabled: enabled)
        reload()
    }
}

private struct SourceRow: View {
    let state: SubstanceStore.SourceState
    let toggle: (Bool) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle(isOn: Binding(get: { state.enabled }, set: { toggle($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.displayName)
                        .font(.body)
                    if let description = state.description, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .toggleStyle(.switch)
        }
        .contentShape(Rectangle())
    }
}

#Preview {
    NavigationStack { SourcePriorityView() }
}
