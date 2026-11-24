import SwiftUI

/// The descriptor picker as a sheet over the note editor, with its own stack
/// and a Done button. Every tap writes straight to the note's draft, so Done
/// and a pull-down both keep what was picked.
struct DescriptorPickerSheet: View {
    @Binding var selection: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DescriptorPickerView(selection: $selection)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "checkmark").font(.body.weight(.semibold))
                        }
                        .skinButtonStyle(.prominent)
                        .tint(Theme.accent)
                        .accessibilityLabel(Text("Done"))
                    }
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

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
                        .listRowBackground(CardBackground())
                }
            } else {
                let groups = ontology.searchGrouped(query)
                if groups.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.hits) { hit in
                                DescriptorHitRow(
                                    hit: hit,
                                    isOn: selectedSet.contains(hit.concept.id),
                                    toggle: { toggle(hit.concept.id) },
                                )
                            }
                        } header: {
                            Text(verbatim: group.title.capitalizedFirst)
                        }
                        .listRowBackground(CardBackground())
                    }
                }
            }
        }
        .insetGroupedListStyle()
        .themedPage()
        .searchable(text: $query, placement: .automatic, prompt: Text("Search effects"))
        .navigationTitle("Descriptors")
        .inlineNavigationTitle()
        .toolbar {
            if !selection.isEmpty {
                ToolbarItem(placement: .platformTopBarTrailing) {
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
                        .foregroundStyle(Theme.tertiaryLabel)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .accessibilityHidden(true)
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

    private func toggle(_ id: String) {
        if let index = selection.firstIndex(of: id) {
            selection.remove(at: index)
        } else {
            selection.append(id)
        }
    }
}

/// One search hit with a selection mark: ``DescriptorHitLabel`` and a
/// trailing check that toggles the effect in or out of the note.
struct DescriptorHitRow: View {
    let hit: SubjectiveEffectHit
    let isOn: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: Spacing.lg) {
                DescriptorHitLabel(hit: hit, definitionLineLimit: 2)
                Spacer()
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.tertiary))
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// An effect's name, its definition, and the alias that matched when the
/// match came through one. The picker clips the definition to two lines; the
/// glossary passes `nil` and shows it whole.
struct DescriptorHitLabel: View {
    let hit: SubjectiveEffectHit
    var definitionLineLimit: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(verbatim: hit.concept.name)
                .foregroundStyle(.primary)
            if let definition = hit.concept.definition, !definition.isEmpty {
                Text(verbatim: definition)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryLabel)
                    .lineLimit(definitionLineLimit)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: definitionLineLimit == nil)
            }
            if let alias = hit.matchedAlias {
                Text("Matches “\(alias)”")
                    .font(.caption)
                    .foregroundStyle(Theme.tertiaryLabel)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

extension String {
    /// The string with its first character uppercased: the vocabulary stores
    /// names in lowercase ("body load").
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
