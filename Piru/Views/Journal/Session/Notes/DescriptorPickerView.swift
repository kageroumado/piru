import SwiftUI

/// Multi-select over the SubFxOnEx vocabulary: the 21 rollups as collapsible
/// groups, each expanding to its atomic concepts as chips; a search field
/// matching names and aliases flattens the list into hits. Selection is by
/// concept id — the note stores ids, never names.
struct DescriptorPickerView: View {
    @Binding var selection: [String]
    @State private var query = ""
    @State private var expanded: Set<String> = []
    @State private var ontology = SubjectiveEffectOntology.shared

    private var selectedSet: Set<String> {
        Set(selection)
    }

    var body: some View {
        List {
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                ForEach(ontology.rollups) { rollup in
                    rollupSection(rollup)
                }
            } else {
                let hits = ontology.search(query)
                if hits.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    Section {
                        ForEach(hits) { hit in
                            hitRow(hit)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Search effects"))
        .navigationTitle("Descriptors")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !selection.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") { selection.removeAll() }
                }
            }
        }
        .task { ontology.load() }
    }

    // MARK: - Group

    private func rollupSection(_ rollup: SubjectiveEffectConcept) -> some View {
        let atomics = ontology.atomics(under: rollup)
        let chosen = atomics.filter { selectedSet.contains($0.id) }.count + (selectedSet.contains(rollup.id) ? 1 : 0)
        let isOpen = expanded.contains(rollup.id)
        return Section {
            Button {
                withAnimation(.snappy(duration: 0.22)) {
                    if isOpen { expanded.remove(rollup.id) } else { expanded.insert(rollup.id) }
                }
            } label: {
                HStack(spacing: Spacing.lg) {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(rollup.name.capitalizedFirst)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(verbatim: "\(rollup.domain) · \(atomics.count)")
                            .captionSecondary()
                    }
                    Spacer()
                    if chosen > 0 {
                        Text("\(chosen)")
                            .capsuleChip(text: Theme.accent, fill: Theme.accent)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text(isOpen ? "Collapses the group" : "Expands the group"))
            if isOpen {
                FlowLayout(spacing: Spacing.sm) {
                    chip(rollup, isGroup: true)
                    ForEach(atomics) { concept in
                        chip(concept, isGroup: false)
                    }
                }
                .padding(.vertical, Spacing.xs)
            }
        }
    }

    // MARK: - Chip

    private func chip(_ concept: SubjectiveEffectConcept, isGroup: Bool) -> some View {
        let isOn = selectedSet.contains(concept.id)
        return Button {
            toggle(concept.id)
        } label: {
            HStack(spacing: Spacing.xs) {
                if isGroup {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 9, weight: .bold))
                }
                Text(concept.name)
                    .font(.caption.weight(isOn ? .semibold : .regular))
                    .lineLimit(1)
            }
            .selectableCapsule(isSelected: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityLabel(Text(concept.name))
        .accessibilityHint(concept.definition.map { Text(verbatim: $0) } ?? Text(""))
    }

    // MARK: - Search hit

    private func hitRow(_ hit: SubjectiveEffectHit) -> some View {
        let isOn = selectedSet.contains(hit.concept.id)
        let parent = ontology.rollup(of: hit.concept)
        return Button {
            toggle(hit.concept.id)
        } label: {
            HStack(spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(hit.concept.name)
                        .foregroundStyle(.primary)
                    HStack(spacing: Spacing.xs) {
                        if let alias = hit.matchedAlias {
                            Text(verbatim: "“\(alias)” · ")
                        }
                        Text(verbatim: parent?.name ?? hit.concept.domain)
                    }
                    .captionSecondary()
                    .lineLimit(1)
                }
                Spacer()
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.tertiary))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func toggle(_ id: String) {
        if let index = selection.firstIndex(of: id) {
            selection.remove(at: index)
        } else {
            selection.append(id)
        }
    }
}

private extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
