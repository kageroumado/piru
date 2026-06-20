import SwiftData
import SwiftUI
import WidgetKit

// MARK: - Host

/// Resolves the optional item id and hosts the add/restock form as a navigator
/// sheet (so `navigator.dismiss()` works).
struct InventoryItemFormHost: View {
    let itemID: UUID?
    let prefillSubstance: String?
    let prefillSalt: String?

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        InventoryItemForm(
            existingItem: itemID.flatMap(resolve),
            prefillSubstance: prefillSubstance,
            prefillSalt: prefillSalt,
        )
    }

    private func resolve(_ id: UUID) -> InventoryItem? {
        var descriptor = FetchDescriptor<InventoryItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }
}

// MARK: - Form

/// Add a new tracked item or restock an existing one. With an `existingItem` it's
/// a restock (Substance omitted, unit fixed); otherwise it's the add form. When
/// opened from a substance screen the substance is prefilled and fixed.
///
/// Uses ✕ / ✓ nav icons with the ✓ as the commit — no bottom button.
struct InventoryItemForm: View {
    let existingItem: InventoryItem?
    let prefillSubstance: String?
    let prefillSalt: String?

    @Environment(\.appNavigator) private var navigator
    @Environment(\.modelContext) private var modelContext

    @State private var substanceName: String
    @State private var unit: String
    @State private var amount: Double = 0
    @State private var useBaseline = false
    @State private var note = ""
    @State private var showNote = false
    /// The library match for the typed name, when one was picked. `nil` for a
    /// custom (off-library) substance — still trackable, just no unit default.
    @State private var selectedSubstance: Substance?

    private static let unitOptions = ["µg", "mg", "g", "mL", "caps", "tabs", "drops"]

    init(existingItem: InventoryItem?, prefillSubstance: String?, prefillSalt: String?) {
        self.existingItem = existingItem
        self.prefillSubstance = prefillSubstance
        self.prefillSalt = prefillSalt
        _substanceName = State(initialValue: existingItem?.substance ?? prefillSubstance ?? "")
        _unit = State(initialValue: existingItem?.unit ?? "mg")
    }

    private var isRestock: Bool { existingItem != nil }
    private var substanceFixed: Bool { existingItem != nil || prefillSubstance != nil }

    /// The picker's choices, always including the currently-selected unit so a
    /// substance whose unit isn't in the common list (peptides dosed in `IU`,
    /// `mcg`, etc.) never renders a blank picker.
    private var unitChoices: [String] {
        var options = Self.unitOptions
        let current = unit.trimmingCharacters(in: .whitespaces)
        if !current.isEmpty, !options.contains(current) {
            options.insert(current, at: 0)
        }
        return options
    }

    /// "Set as new baseline" once an item already has one, else "Use as baseline".
    private var baselineLabel: LocalizedStringKey {
        (existingItem?.hasBaseline ?? false) ? "Set as new baseline" : "Use as baseline"
    }

    private var canCommit: Bool {
        if isRestock { return amount > 0 }
        return !substanceName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                substanceSection
                amountSection
                baselineSection
                noteSection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(isRestock ? "Restock" : "Track Substance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { navigator.dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { commit() } label: { Image(systemName: "checkmark") }
                        .accessibilityLabel("Save")
                        .disabled(!canCommit)
                }
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var substanceSection: some View {
        if !substanceFixed {
            Section {
                SubstanceSearchField(text: $substanceName) { selected in
                    selectSubstance(selected)
                } onCustom: {
                    selectedSubstance = nil
                }
                if selectedSubstance == nil, !substanceName.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                        Text("Custom substance — its doses count by exact name match.")
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
                }
            } header: {
                Text("Substance")
            }
        } else {
            Section {
                LabeledContent("Substance") {
                    Text(displaySubstance).foregroundStyle(Theme.secondaryLabel)
                }
            }
        }
    }

    /// Adopt a picked library substance: lock in its canonical name and default
    /// the unit from its primary route (peptides, etc. aren't oral), which the
    /// user can still change.
    private func selectSubstance(_ substance: Substance) {
        selectedSubstance = substance
        substanceName = substance.name
        let resolved = substance.unit(for: substance.defaultRoute, saltForm: prefillSalt)
        unit = resolved.isEmpty ? "mg" : resolved
    }

    private var amountSection: some View {
        Section {
            HStack {
                Text(isRestock ? "Amount added" : "Starting amount")
                Spacer()
                TextField("0", value: $amount, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120)
                if isRestock {
                    Text(unit).foregroundStyle(Theme.secondaryLabel)
                } else {
                    Picker("", selection: $unit) {
                        ForEach(unitChoices, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                }
            }
        }
    }

    private var baselineSection: some View {
        Section {
            Toggle(baselineLabel, isOn: $useBaseline)
        } footer: {
            Text("Marks the amount after this as a full supply, so the bar can show how full you are. Leave off if this isn't a full restock.")
        }
    }

    @ViewBuilder
    private var noteSection: some View {
        Section {
            if showNote {
                TextField("Note", text: $note, axis: .vertical)
                    .lineLimit(1...3)
            } else {
                Button {
                    withAnimation { showNote = true }
                } label: {
                    Label("Add Note", systemImage: "text.alignleft")
                }
            }
        }
    }

    private var displaySubstance: String {
        let resolved = SubstanceLibrary.lookup(substanceName)?.displayTitle ?? substanceName
        if let salt = prefillSalt ?? existingItem?.saltForm, !salt.isEmpty {
            return "\(resolved) · \(salt)"
        }
        return resolved
    }

    // MARK: - Commit

    private func commit() {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if let item = existingItem {
            InventoryService.restock(
                item,
                amount: amount,
                note: trimmedNote.isEmpty ? nil : trimmedNote,
                setBaseline: useBaseline,
                in: modelContext,
            )
        } else {
            InventoryService.create(
                substance: substanceName.trimmingCharacters(in: .whitespaces),
                saltForm: prefillSalt,
                unit: unit,
                initial: amount,
                threshold: nil,
                setBaseline: useBaseline,
                in: modelContext,
            )
        }
        WidgetCenter.shared.reloadAllTimelines()
        navigator.dismiss()
    }
}
