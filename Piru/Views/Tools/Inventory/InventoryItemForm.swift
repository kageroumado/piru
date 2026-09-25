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
    var prefill: InventoryPrefill?

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        InventoryItemForm(
            existingItem: itemID.flatMap(resolve),
            prefillSubstance: prefillSubstance,
            prefillSalt: prefillSalt,
            prefill: prefill,
        )
    }

    private func resolve(_ id: UUID) -> InventoryItem? {
        var descriptor = FetchDescriptor<InventoryItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }
}

// MARK: - Amount draft

/// The stock a form states, in one of two shapes: a plain amount in a unit
/// ("500 mg", "30 mL"), or a count of pieces at a strength ("28 × 36 mg") —
/// the shape a box prints and the scanner reads. Counted stock keeps the count
/// as the item's unit (`tabs`, `caps`) with the strength alongside, so "28
/// tabs" stays 28 tabs rather than a flat 1,008 mg.
@MainActor @Observable
final class InventoryAmountDraft {
    enum Mode: Hashable {
        case amount
        case pieces
    }

    /// What the form commits: the stock in the unit it was stated in, with the
    /// per-piece strength when it was counted.
    struct Stated {
        let amount: Double
        let unit: String
        let unitStrengthMG: Double?
    }

    static let unitOptions = ["µg", "mg", "g", "mL", "caps", "tabs", "drops"]
    static let countUnitOptions = ["tabs", "caps"]

    var mode: Mode = .amount
    var amount: Double = 0
    var unit = "mg"
    var count: Double = 0
    var countUnit = "tabs"
    var strengthMG: Double = 0

    /// A restock opens pre-filled with what you last bought (the most recent
    /// restock / initial amount), falling back to ~10 strong doses; a fresh add
    /// starts at 0 until a substance is picked (`seed(from:)` then fills it).
    /// From the box scanner, a pack count opens the pieces shape with the
    /// count and any printed strength in place; a liquid ("30 mL") is a plain
    /// amount.
    init(prefill: InventoryPrefill?, existingItem: InventoryItem?) {
        if let existingItem {
            unit = existingItem.unit
            amount = Self.lastBuy(of: existingItem)
        }
        guard let prefill, let packCount = prefill.count, packCount > 0 else { return }
        if let packUnit = prefill.unit, !InventoryMath.isCountUnit(packUnit) {
            amount = packCount
            unit = packUnit
        } else {
            // A counted item restocks in its own unit, whatever noun the box
            // used for its pieces.
            mode = .pieces
            count = packCount
            if let itemUnit = existingItem?.unit, InventoryMath.isCountUnit(itemUnit) {
                countUnit = itemUnit
            } else {
                countUnit = prefill.unit ?? "tabs"
            }
            strengthMG = prefill.strengthMG ?? existingItem?.unitStrengthMG ?? 0
        }
    }

    var stated: Stated {
        switch mode {
        case .amount: Stated(amount: amount, unit: unit, unitStrengthMG: nil)
        case .pieces: Stated(amount: count, unit: countUnit, unitStrengthMG: strengthMG > 0 ? strengthMG : nil)
        }
    }

    /// The stated stock reconciled into `item`'s unit for a restock — a count
    /// meets a milligram item through its strength; `nil` when the two cannot
    /// be reconciled.
    func restockAmount(for item: InventoryItem) -> Double? {
        let stated = stated
        return InventoryMath.convert(
            stated.amount, from: stated.unit, to: item.unit,
            unitStrengthMG: item.unitStrengthMG ?? stated.unitStrengthMG,
        )
    }

    /// Adopt a picked library substance's dosing unit (peptides, etc. aren't
    /// oral) and, while the amount is still empty, seed it with roughly ten
    /// strong doses — a sensible "fresh supply" the user can adjust.
    func seed(from substance: Substance, saltForm: String?) {
        let resolved = substance.unit(for: substance.defaultRoute, saltForm: saltForm)
        unit = resolved.isEmpty ? "mg" : resolved
        if amount == 0,
           let strong = InventoryMath.representativeStrongDose(
               substance: substance.name, saltForm: saltForm, unit: unit,
           ) {
            amount = Self.roundToTwoSignificantFigures(strong * 10)
        }
    }

    private static func lastBuy(of item: InventoryItem) -> Double {
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
}

// MARK: - Form

/// Add a new tracked item or restock an existing one. With an `existingItem` it's
/// a restock (Substance omitted, unit fixed); otherwise it's the add form. When
/// opened from a substance screen the substance is prefilled and fixed. From
/// the box scanner, `prefill` fills in what the box stated (see
/// ``InventoryAmountDraft``); with no count read, the amount opens empty and
/// focused.
///
/// Uses ✕ / ✓ nav icons with the ✓ as the commit — no bottom button.
struct InventoryItemForm: View {
    let existingItem: InventoryItem?
    let prefillSubstance: String?
    let prefillSalt: String?
    let prefill: InventoryPrefill?

    @Environment(\.appNavigator) private var navigator
    @Environment(\.modelContext) private var modelContext

    @State private var substanceName: String
    @State private var draft: InventoryAmountDraft
    @State private var useBaseline = false
    @State private var note: String
    /// The library match for the typed name, when one was picked. `nil` for a
    /// custom (off-library) substance — still trackable, just no unit default.
    @State private var selectedSubstance: Substance?

    init(existingItem: InventoryItem?, prefillSubstance: String?, prefillSalt: String?, prefill: InventoryPrefill? = nil) {
        self.existingItem = existingItem
        self.prefillSubstance = prefillSubstance
        self.prefillSalt = prefillSalt
        self.prefill = prefill
        _substanceName = State(initialValue: existingItem?.substance ?? prefillSubstance ?? "")
        _draft = State(initialValue: InventoryAmountDraft(prefill: prefill, existingItem: existingItem))
        _note = State(initialValue: prefill?.note ?? "")
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

    /// "Set as new baseline" once an item already has one, else "Use as baseline".
    private var baselineLabel: LocalizedStringKey {
        (existingItem?.hasBaseline ?? false) ? "Set as new baseline" : "Use as baseline"
    }

    private var canCommit: Bool {
        if let existingItem { return (draft.restockAmount(for: existingItem) ?? 0) > 0 }
        return !substanceName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                substanceSection
                InventoryAmountSection(
                    draft: draft,
                    isRestock: isRestock,
                    // A counted item restocks in its own unit; the pieces shape
                    // is for stating a box against a plain amount.
                    allowsPieces: !InventoryMath.isCountUnit(existingItem?.unit ?? ""),
                    substanceName: substanceName,
                    saltForm: itemSalt,
                    focusesOnOpen: prefill != nil,
                )
                baselineSection
                noteSection
            }
            .scrollDismissesKeyboard(.interactively)
            .themedPage()
            .navigationTitle(navTitle)
            .inlineNavigationTitle()
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
                SubstanceSearchField(text: $substanceName) { selected, _ in
                    selectSubstance(selected)
                } onCustom: {
                    selectedSubstance = nil
                }
                if selectedSubstance == nil, !substanceName.isEmpty {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "info.circle")
                            .accessibilityHidden(true)
                        Text("Custom substance — its doses count by exact name match.")
                    }
                    .captionSecondary()
                }
            } header: {
                Text("Substance")
            }
            .listRowBackground(CardBackground())
        }
    }

    /// Adopt a picked library substance: lock in its canonical name and let the
    /// draft take its unit and a seed amount. Both stay user-editable.
    private func selectSubstance(_ substance: Substance) {
        selectedSubstance = substance
        substanceName = substance.name
        draft.seed(from: substance, saltForm: prefillSalt)
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
                .accessibilityLabel(Text("Note"))
                .lineLimit(1 ... 4)
        } header: {
            Text("Note")
        }
        .listRowBackground(CardBackground())
    }

    // MARK: - Commit

    private func commit() {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = trimmedNote.isEmpty ? nil : trimmedNote
        if let item = existingItem {
            InventoryService.restock(
                item,
                amount: draft.restockAmount(for: item) ?? 0,
                note: note,
                setBaseline: useBaseline,
                unitStrengthMG: draft.stated.unitStrengthMG,
                in: modelContext,
            )
        } else {
            let stated = draft.stated
            InventoryService.create(
                substance: substanceName.trimmingCharacters(in: .whitespaces),
                saltForm: prefillSalt,
                unit: stated.unit,
                initial: stated.amount,
                threshold: nil,
                setBaseline: useBaseline,
                note: note,
                unitStrengthMG: stated.unitStrengthMG,
                in: modelContext,
            )
        }
        WidgetCenter.shared.reloadAllTimelines()
        navigator.dismiss()
    }
}

// MARK: - Amount section

/// The amount editor: a shape picker (plain amount, or count × strength) over
/// the stepper rows for the chosen shape. Its own view so a keystroke in the
/// amount re-renders the steppers, not the whole form.
private struct InventoryAmountSection: View {
    @Bindable var draft: InventoryAmountDraft
    let isRestock: Bool
    let allowsPieces: Bool
    let substanceName: String
    let saltForm: String?
    /// Open with the keyboard on the first empty figure — for a form that
    /// arrived from the scanner with everything but that number filled in.
    let focusesOnOpen: Bool

    private var header: LocalizedStringResource {
        isRestock ? "Amount added" : "Starting amount"
    }

    /// The dose-anchored stepper increment for this substance in `unit`.
    private func stepBasis(in unit: String) -> Double? {
        InventoryMath.referenceDose(substance: substanceName, saltForm: saltForm, unit: unit)
    }

    /// The picker's choices, always including the currently-selected unit so a
    /// substance whose unit isn't in the common list (peptides dosed in `IU`,
    /// `mcg`, etc.) never renders a blank picker.
    private var unitChoices: [String] {
        var options = InventoryAmountDraft.unitOptions
        let current = draft.unit.trimmingCharacters(in: .whitespaces)
        if !current.isEmpty, !options.contains(current) {
            options.insert(current, at: 0)
        }
        return options
    }

    var body: some View {
        Section {
            if allowsPieces {
                Picker("Entry", selection: $draft.mode) {
                    Text("Amount").tag(InventoryAmountDraft.Mode.amount)
                    Text("Count × strength").tag(InventoryAmountDraft.Mode.pieces)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            switch draft.mode {
            case .amount:
                InventoryStepperRow(
                    value: $draft.amount,
                    unit: draft.unit,
                    label: header,
                    stepBasis: stepBasis(in: draft.unit),
                    unitChoices: isRestock ? nil : unitChoices,
                    onUnitChange: isRestock ? nil : { draft.unit = $0 },
                    focusOnAppear: focusesOnOpen && draft.amount == 0,
                )
            case .pieces:
                InventoryStepperRow(
                    value: $draft.count,
                    unit: draft.countUnit,
                    label: "Count",
                    unitChoices: InventoryAmountDraft.countUnitOptions,
                    onUnitChange: { draft.countUnit = $0 },
                    focusOnAppear: focusesOnOpen && draft.count == 0,
                )
                InventoryStepperRow(
                    value: $draft.strengthMG,
                    unit: "mg",
                    label: "Strength",
                    stepBasis: stepBasis(in: "mg"),
                    focusOnAppear: focusesOnOpen && draft.count > 0 && draft.strengthMG == 0,
                )
            }
        } header: {
            Text(header)
        } footer: {
            if draft.mode == .pieces, isRestock {
                Text("Added at this strength, in the item's unit.")
            } else if draft.mode == .pieces {
                Text("Counted in \(draft.countUnit). A dose logged in mg is taken off at this strength.")
            }
        }
        .listRowBackground(CardBackground())
    }
}
