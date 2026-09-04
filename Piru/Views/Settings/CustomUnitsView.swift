import SwiftUI

/// Management surface for user-defined per-substance units — the "1 capsule =
/// 30 mg" table. Pushed from Settings. Each row is one ``CustomUnitPreset``;
/// they're grouped by substance so a person with several pill sizes sees them
/// together. Adding or editing pushes ``CustomUnitEditorView``.
///
/// A custom unit is pure input convenience: it appears in the dose form's unit
/// picker and resolves to its mass when logged, so the substance keeps every
/// bit of its pharmacology (unlike making a whole custom substance).
struct CustomUnitsView: View {
    @State private var store = CustomUnitStore.shared

    /// The store's flat list regrouped into `(substance, its units)` sections,
    /// preserving the store's substance-then-order sort.
    private var groups: [(substance: String, units: [CustomUnitPreset])] {
        var order: [String] = []
        var byName: [String: [CustomUnitPreset]] = [:]
        for preset in store.all {
            if byName[preset.substanceName] == nil { order.append(preset.substanceName) }
            byName[preset.substanceName, default: []].append(preset)
        }
        return order.map { ($0, byName[$0] ?? []) }
    }

    var body: some View {
        List {
            if store.all.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No Custom Units", systemImage: "ruler")
                    } description: {
                        Text("Define a unit like \"1 capsule = 30 mg\" and it appears in the dose picker for that substance — log half a capsule, get 15 mg.")
                    }
                }
            } else {
                ForEach(groups, id: \.substance) { group in
                    Section(displayName(for: group.substance)) {
                        ForEach(group.units) { preset in
                            NavigationLink {
                                CustomUnitEditorView(editing: preset)
                            } label: {
                                unitRow(preset)
                            }
                        }
                        .onDelete { store.delete(at: $0, forSubstanceNamed: group.substance) }
                    }
                }
            }

            Section {
                NavigationLink {
                    CustomUnitEditorView()
                } label: {
                    Label("Add Custom Unit", systemImage: "plus")
                }
            }
        }
        .navigationTitle("Custom Units")
        .inlineNavigationTitle()
    }

    private func unitRow(_ preset: CustomUnitPreset) -> some View {
        // User/data content (label, unit) — verbatim so it mints no catalog key.
        Text(verbatim: "1 \(preset.label) = \(preset.amountPerUnit.doseFormatted) \(preset.unit)")
    }

    /// The substance's personal display name if the user relabelled it, else the
    /// canonical name they defined the unit against.
    private func displayName(for canonicalLowercased: String) -> String {
        CustomSubstanceStore.shared.displayName(for: canonicalLowercased)
    }
}

/// Add or edit one custom unit. Adding starts with a substance search; editing
/// locks the substance (a unit is scoped to it) and pre-fills the fields.
struct CustomUnitEditorView: View {
    private let editing: CustomUnitPreset?

    @State private var store = CustomUnitStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var substanceQuery = ""
    @State private var canonicalName: String?
    @State private var label = ""
    @State private var amountText = ""
    @State private var unit = "mg"

    private static let baseUnits = ["mg", "µg", "g"]

    init(editing: CustomUnitPreset? = nil) {
        self.editing = editing
    }

    private var parsedAmount: Double? {
        guard let value = Double(amountText.replacingOccurrences(of: ",", with: ".")), value > 0 else { return nil }
        return value
    }

    private var trimmedLabel: String {
        label.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var duplicateLabel: Bool {
        guard let canonicalName, !trimmedLabel.isEmpty else { return false }
        // An unchanged label on the row being edited is not a duplicate of itself.
        if let editing, editing.label.lowercased() == trimmedLabel.lowercased() { return false }
        return store.hasLabel(trimmedLabel, forSubstanceNamed: canonicalName)
    }

    private var canSave: Bool {
        canonicalName != nil && !trimmedLabel.isEmpty && parsedAmount != nil && !duplicateLabel
    }

    var body: some View {
        Form {
            Section("Substance") {
                if let canonicalName, editing != nil {
                    Text(CustomSubstanceStore.shared.displayName(for: canonicalName))
                        .foregroundStyle(Theme.secondaryLabel)
                } else if let canonicalName {
                    HStack {
                        Text(CustomSubstanceStore.shared.displayName(for: canonicalName))
                        Spacer()
                        Button("Change") { self.canonicalName = nil; substanceQuery = "" }
                            .font(.subheadline)
                    }
                } else {
                    SubstanceSearchField(text: $substanceQuery) { substance, _ in
                        canonicalName = substance.name
                    }
                }
            }

            Section {
                TextField("Unit label (e.g. capsule)", text: $label)
                    .autocorrectionDisabled()
                HStack {
                    Text("1 \(trimmedLabel.isEmpty ? String(localized: "unit") : trimmedLabel) =")
                        .foregroundStyle(Theme.secondaryLabel)
                    TextField("Amount", text: $amountText)
                        .decimalKeyboard()
                    Picker("Unit", selection: $unit) {
                        ForEach(Self.baseUnits, id: \.self) { Text($0) }
                    }
                    .labelsHidden()
                }
            } footer: {
                if duplicateLabel {
                    Text("This substance already has a \"\(trimmedLabel)\" unit.")
                        .foregroundStyle(Color.Semantic.Danger.text)
                } else {
                    Text("Logs in this unit convert to the mass automatically.")
                }
            }
        }
        .navigationTitle(editing == nil ? "Add Custom Unit" : "Edit Custom Unit")
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save).disabled(!canSave)
            }
        }
        .onAppear(perform: seed)
    }

    private func seed() {
        guard let editing else { return }
        canonicalName = editing.substanceName
        label = editing.label
        amountText = editing.amountPerUnit.doseFormatted
        unit = editing.unit
    }

    private func save() {
        guard let canonicalName, let amount = parsedAmount, !trimmedLabel.isEmpty else { return }
        if let editing {
            store.update(editing, label: trimmedLabel, amountPerUnit: amount, unit: unit)
        } else {
            store.add(substanceName: canonicalName, label: trimmedLabel, amountPerUnit: amount, unit: unit)
        }
        dismiss()
    }
}
