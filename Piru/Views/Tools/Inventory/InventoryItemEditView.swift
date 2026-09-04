import SwiftData
import SwiftUI
import WidgetKit

// MARK: - Host

/// Resolves the item id and hosts the Edit screen as a navigator sheet.
struct InventoryItemEditHost: View {
    let itemID: UUID

    @Environment(\.modelContext) private var modelContext
    @Environment(\.appNavigator) private var navigator

    var body: some View {
        if let item = resolve() {
            InventoryItemEditView(item: item)
        } else {
            // Item vanished (deleted elsewhere) — close rather than show a blank.
            Color.clear.onAppear { navigator.dismiss() }
        }
    }

    private func resolve() -> InventoryItem? {
        let id = itemID
        var descriptor = FetchDescriptor<InventoryItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }
}

// MARK: - Edit screen

/// Edit an item's exact amount, baseline, single-dose size, and low-stock
/// threshold. On-hand and Baseline are independent fields (a recount vs. the
/// "full" reference). `0` disables baseline, single dose, and the threshold.
///
/// Uses ✕ / ✓ nav icons with the ✓ as the commit — no bottom button.
struct InventoryItemEditView: View {
    @Bindable var item: InventoryItem

    @Environment(\.appNavigator) private var navigator
    @Environment(\.modelContext) private var modelContext

    @State private var unit: String
    @State private var onHand: Double
    @State private var baseline: Double
    @State private var doseSize: Double
    @State private var threshold: Double

    private static let unitOptions = ["µg", "mg", "g", "mL", "caps", "tabs", "drops"]

    /// Always include the item's current unit so a peptide/IU unit not in the
    /// common list doesn't render a blank picker.
    private var unitChoices: [String] {
        var options = Self.unitOptions
        let current = unit.trimmingCharacters(in: .whitespaces)
        if !current.isEmpty, !options.contains(current) {
            options.insert(current, at: 0)
        }
        return options
    }

    /// Dose-anchored stepper increment for this substance + the unit being edited.
    private var stepBasis: Double? {
        InventoryMath.referenceDose(substance: item.substance, saltForm: item.saltForm, unit: unit)
    }

    init(item: InventoryItem) {
        self.item = item
        _unit = State(initialValue: item.unit)
        _onHand = State(initialValue: item.currentQuantity)
        _baseline = State(initialValue: item.baselineQuantity ?? 0)
        _doseSize = State(initialValue: item.doseSize ?? 0)
        _threshold = State(initialValue: item.lowStockThreshold ?? 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    InventoryStepperRow(
                        value: $onHand,
                        unit: unit,
                        label: "On hand",
                        stepBasis: stepBasis,
                        unitChoices: unitChoices,
                        onUnitChange: { unit = $0 },
                    )
                } header: {
                    Text("On hand")
                } footer: {
                    Text("The exact amount you have now. Changing it is logged as a correction.")
                }
                .listRowBackground(CardBackground())

                Section {
                    InventoryStepperRow(value: $baseline, unit: unit, label: "Baseline (100%)", stepBasis: stepBasis)
                } header: {
                    Text("Baseline (100%)")
                } footer: {
                    Text("The amount that counts as a full supply for the bar. Set to 0 to hide the bar.")
                }
                .listRowBackground(CardBackground())

                Section {
                    InventoryStepperRow(value: $doseSize, unit: unit, label: "Single dose", stepBasis: stepBasis)
                } header: {
                    Text("Single dose")
                } footer: {
                    Text("Used to show how many doses you have left. Set to 0 to disable.")
                }
                .listRowBackground(CardBackground())

                Section {
                    InventoryStepperRow(value: $threshold, unit: unit, label: "Warn when below", stepBasis: stepBasis)
                } header: {
                    Text("Warn when below")
                } footer: {
                    Text("Your remaining amount stands out once it drops below this. Set to 0 to disable.")
                }
                .listRowBackground(CardBackground())
            }
            .themedPage()
            .navigationTitle("Edit")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { navigator.dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { commit() } label: { Image(systemName: "checkmark") }
                        .accessibilityLabel("Save")
                }
            }
        }
    }

    // MARK: - Commit

    private func commit() {
        // Unit first: converts manual events + any stored derived fields so the
        // replay stays consistent. The user's typed scalar values below are
        // already expressed in the (new) unit shown on screen, so they overwrite.
        if unit != item.unit {
            InventoryService.changeUnit(item, to: unit, in: modelContext)
        }

        // Only log a correction when the on-hand figure actually moved.
        let current = InventoryMath.quantity(for: item, in: modelContext)
        if abs(onHand - current) > 0.0001 {
            InventoryService.correctTo(item, exact: onHand, note: nil, in: modelContext)
        }

        InventoryService.setBaseline(item, value: baseline, in: modelContext)
        InventoryService.setDoseSize(item, value: doseSize)
        item.lowStockThreshold = threshold > 0 ? threshold : nil

        InventoryService.recompute(item, in: modelContext)
        WidgetCenter.shared.reloadAllTimelines()
        navigator.dismiss()
    }
}
