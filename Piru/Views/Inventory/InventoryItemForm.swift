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
    @State private var amount: Double
    @State private var useBaseline = false
    @State private var note = ""
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
        _amount = State(initialValue: Self.initialAmount(for: existingItem))
    }

    /// A restock opens pre-filled with what you last bought (the most recent
    /// restock / initial amount), falling back to ~10 strong doses; a fresh add
    /// starts at 0 until a substance is picked (`selectSubstance` then seeds it).
    @MainActor
    private static func initialAmount(for item: InventoryItem?) -> Double {
        guard let item else { return 0 }
        let lastBuy = item.manualEvents
            .filter { $0.kind == .restock || $0.kind == .initial }
            .max { $0.date < $1.date }?.amount
        if let lastBuy, lastBuy > 0 { return lastBuy }
        if let strong = InventoryMath.representativeStrongDose(
            substance: item.substance, saltForm: item.saltForm, unit: item.unit,
        ) {
            return roundToTwoSignificantFigures(strong * 10)
        }
        return 0
    }

    /// Round a seed amount to two significant figures so the default reads as a
    /// clean number (3,250 → 3,300) rather than a noisy midpoint.
    private static func roundToTwoSignificantFigures(_ value: Double) -> Double {
        guard value > 0 else { return value }
        let magnitude = pow(10, floor(log10(value)) - 1)
        return (value / magnitude).rounded() * magnitude
    }

    private var isRestock: Bool {
        existingItem != nil
    }
    private var substanceFixed: Bool {
        existingItem != nil || prefillSubstance != nil
    }
    private var itemSalt: String? {
        existingItem?.saltForm ?? prefillSalt
    }

    /// The dose-anchored stepper increment for this substance + unit.
    private var stepBasis: Double? {
        InventoryMath.referenceDose(substance: substanceName, saltForm: itemSalt, unit: unit)
    }

    /// Resolved substance name (no salt) for the nav title.
    private var titleName: String {
        SubstanceLibrary.lookup(substanceName)?.displayTitle ?? substanceName
    }

    /// "Restock · Caffeine" / "Track · Caffeine" / "Track Substance".
    private var navTitle: String {
        if isRestock { return String(localized: "Restock · \(titleName)") }
        if substanceFixed { return String(localized: "Track · \(titleName)") }
        return String(localized: "Track Substance")
    }

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
            .navigationTitle(navTitle)
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

    /// Only the generic add-from-manager form shows a substance picker; opened
    /// from a substance (track or restock) the substance lives in the nav title.
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
                            .accessibilityHidden(true)
                        Text("Custom substance — its doses count by exact name match.")
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
                }
            } header: {
                Text("Substance")
            }
            .listRowBackground(CardBackground())
        }
    }

    /// Adopt a picked library substance: lock in its canonical name, default the
    /// unit from its primary route (peptides, etc. aren't oral), and seed the
    /// starting amount with roughly ten strong doses — a sensible "fresh supply"
    /// the user can adjust. Both stay user-editable.
    private func selectSubstance(_ substance: Substance) {
        selectedSubstance = substance
        substanceName = substance.name
        let route = substance.defaultRoute
        let resolved = substance.unit(for: route, saltForm: prefillSalt)
        unit = resolved.isEmpty ? "mg" : resolved
        if amount == 0,
           let strong = InventoryMath.representativeStrongDose(
               substance: substance.name, saltForm: prefillSalt, unit: unit,
           ) {
            amount = Self.roundToTwoSignificantFigures(strong * 10)
        }
    }

    private var amountSection: some View {
        Section {
            InventoryStepperRow(
                value: $amount,
                unit: unit,
                label: isRestock ? "Amount added" : "Starting amount",
                stepBasis: stepBasis,
                unitChoices: isRestock ? nil : unitChoices,
                onUnitChange: isRestock ? nil : { unit = $0 },
            )
        } header: {
            Text(isRestock ? "Amount added" : "Starting amount")
        }
        .listRowBackground(CardBackground())
    }

    private var baselineSection: some View {
        Section {
            Toggle(baselineLabel, isOn: $useBaseline)
                .tint(Theme.accent)
        } footer: {
            Text("Marks the amount after this as a full supply, so the bar can show how full you are. Leave off if this isn't a full restock.")
        }
        .listRowBackground(CardBackground())
    }

    /// The note field is always present; an empty note simply isn't saved.
    private var noteSection: some View {
        Section {
            TextField("Add note…", text: $note, axis: .vertical)
                .lineLimit(1 ... 4)
        } header: {
            Text("Note")
        }
        .listRowBackground(CardBackground())
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
