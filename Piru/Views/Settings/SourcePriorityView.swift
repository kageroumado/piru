import SwiftUI

/// Lets the user rank the handful of sources that actually compete for the data
/// on a substance card (dose, duration, effects, category, mechanism). The first
/// source that has a value for a field wins it. Niche / identifier-only sources
/// aren't listed — they resolve at their bundled priority but never realistically
/// win a displayed field, so exposing them only adds noise.
///
/// Reorder-only: there's no enable/disable here. Mutations go through
/// ``SubstanceStore`` which clears its resolved-substance cache, so the rest of
/// the app sees the new order on the next lookup.
struct SourcePriorityView: View {
    @State private var states: [SubstanceStore.SourceState] = []

    var body: some View {
        List {
            Section {
                ForEach(Array(states.enumerated()), id: \.element.id) { index, state in
                    SourceRow(rank: index + 1, state: state)
                }
                .onMove(perform: move)
            } footer: {
                Text("When several sources report the same fact — a dose, a duration — Piru shows the one nearest the top. Drag to set which you trust most.")
            }
        }
        // Permanent edit mode: the reorder grips are always visible, and with no
        // delete/toggle the row is unmistakably about order.
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Source Priority")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Reset") {
                    SubstanceStore.shared.resetSourcePriorityToDefaults()
                    reload()
                }
            }
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        states = SubstanceStore.shared.primarySourceStates()
    }

    private func move(from offsets: IndexSet, to destination: Int) {
        states.move(fromOffsets: offsets, toOffset: destination)
        SubstanceStore.shared.setPrimarySourcePriority(orderedPrimarySlugs: states.map(\.slug))
        reload()
    }
}

private struct SourceRow: View {
    let rank: Int
    let state: SubstanceStore.SourceState

    var body: some View {
        HStack(spacing: 14) {
            Text("\(rank)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(Theme.accent)
                .frame(width: 20, alignment: .center)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(state.displayName)
                    .font(.body)
                if let description = state.description, !description.isEmpty {
                    Text(description)
                        .captionSecondary()
                        .lineLimit(2)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(state.displayName), priority \(rank)"))
    }
}

#Preview {
    NavigationStack { SourcePriorityView() }
}
