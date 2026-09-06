import Foundation
import SwiftUI

// MARK: - Staged Dose Editor Model

/// Everything ``StagedDoseEditor`` types into: the amount field's text↔value
/// sync, the branded-pill picker's selection, and the by-volume (alcohol)
/// calculator's dials.
///
/// The staged dose itself stays a `@Binding` on the view. This model deliberately
/// keeps no copy of it — every method that has to write the dose takes it `inout`,
/// so there is exactly one source of truth for the amount and the editor's text
/// fields can never disagree with it.
@Observable
@MainActor
final class StagedDoseEditorModel {
    // MARK: Amount field

    var amountText = ""

    /// Suppresses the text→amount sync when `amountText` is being set *from* the
    /// dose (onAppear / stepper), so opening the editor never rewrites the staged
    /// amount through display rounding.
    var suppressAmountSync = false

    /// Bumped on each stepper tap — drives the value-change pulse + haptic.
    var stepTick = 0

    // MARK: Pill picker (branded fixed-strength meds)

    /// The chosen per-unit strength, or `nil` when the user dropped to free-form
    /// mg via the "mg…" chip.
    var pillStrength: Double?
    var pillCount = 1
    /// Guards the one-time seed of pill state from the staged amount on appear.
    var pillSeeded = false

    // MARK: By-volume custom logger (alcohol)

    var volumeText = ""
    var abvText = ""
    var drinkName = ""
    var drinkEmoji = ""
    var volumeUnit: UnitVolume = ByVolumeDefaults.preferredVolumeUnit

    // MARK: Grapefruit

    /// Whether this substance is CYP3A4-heavy — gates the per-dose grapefruit
    /// toggle. Resolved once on appear; the metabolism lookup shouldn't run every
    /// render.
    var isGrapefruitSubstrate = false

    private static let unitChoices = ["µg", "mg", "g", "mL"]

    // MARK: - Derived values

    var enteredVolumeML: Double? {
        guard let v = Double(volumeText.replacingOccurrences(of: ",", with: ".")), v > 0 else { return nil }
        return Measurement(value: v, unit: volumeUnit).converted(to: .milliliters).value
    }

    var enteredABV: Double? {
        guard let a = Double(abvText.replacingOccurrences(of: ",", with: ".")), a > 0 else { return nil }
        return a
    }

    /// Grams of ethanol implied by the dialed strength + volume, or `nil` until
    /// both are usable.
    func customDrinkGrams(capability: ByVolumeDosing?) -> Double? {
        guard let cap = capability, let ml = enteredVolumeML, let abv = enteredABV else { return nil }
        let g = cap.canonicalAmount(volumeML: ml, strength: abv)
        return g > 0 ? g : nil
    }

    /// Millilitre step for the volume stepper, unit-aware: 10 mL, or 0.5 fl oz.
    var volumeStep: Double {
        volumeUnit == .fluidOunces ? 0.5 : 10
    }

    func unitMenuChoices(current: String) -> [String] {
        Self.unitChoices.contains(current) ? Self.unitChoices : [current] + Self.unitChoices
    }

    // MARK: - Amount

    func setAmount(_ value: Double, item: inout StagedDose) {
        stepTick += 1
        item.amount = value
        let newText = value > 0 ? value.doseFormatted : ""
        // Only arm the suppress flag when onChange will actually fire, otherwise
        // it would stay latched and swallow the next keystroke.
        if newText != amountText {
            suppressAmountSync = true
            amountText = newText
        }
    }

    /// Apply a keystroke in the amount field to the staged dose.
    ///
    /// String binding (not `value:format:`) is deliberate — the staged amount must
    /// update per keystroke for the live dose-level / breakdown reclassification,
    /// and the suppress flag relies on owning the text. Invariant dot-decimal
    /// first (the field is populated from `doseFormatted`, which always emits
    /// "."), then a locale-aware parse for locale keyboards.
    func commitAmountText(to item: inout StagedDose) {
        if suppressAmountSync {
            suppressAmountSync = false
            return
        }
        item.amount = Double(amountText.replacingOccurrences(of: ",", with: "."))
            ?? (try? Double(amountText, format: .number))
            ?? 0
    }

    /// Show `amount` in the field without letting the sync write it back.
    func showAmount(_ amount: Double) {
        suppressAmountSync = true
        amountText = amount > 0 ? amount.doseFormatted : ""
    }

    // MARK: - By-volume dials

    /// Bump the strength field by `delta`, reformatted. Alcohol %ABV clamps to
    /// 0–95; a mg/mL concentration has no upper bound.
    func adjustStrength(_ delta: Double, capability: ByVolumeDosing) {
        let current = Double(abvText.replacingOccurrences(of: ",", with: ".")) ?? 0
        let raw = max(0, ((current + delta) * 10).rounded() / 10)
        let next = capability.isMassPerVolume ? raw : min(95, raw)
        abvText = next > 0 ? ByVolumeDefaults.format(next) : ""
        stepTick += 1
    }

    /// Bump the volume field by one `volumeStep` in the displayed unit, clamped ≥ 0.
    func adjustVolume(_ steps: Double) {
        let current = Double(volumeText.replacingOccurrences(of: ",", with: ".")) ?? 0
        let next = max(0, current + steps * volumeStep)
        volumeText = next > 0 ? ByVolumeDefaults.format(next) : ""
        stepTick += 1
    }

    /// Re-render the volume field after the displayed unit changes.
    func convertVolumeText(from old: UnitVolume, to new: UnitVolume) {
        ByVolumeDefaults.preferredVolumeUnit = new
        guard let v = Double(volumeText.replacingOccurrences(of: ",", with: ".")), v > 0 else { return }
        volumeText = ByVolumeDefaults.format(Measurement(value: v, unit: old).converted(to: new).value)
    }

    /// Fill the ABV/volume fields from the staged dose's structured metadata (or,
    /// if it only has grams from a By-Weight edit, derive a volume at a default
    /// strength) so By Drink is never blank. `force` overwrites existing text.
    func seedByDrinkFieldsIfNeeded(from item: StagedDose, capability: ByVolumeDosing?, force: Bool = false) {
        guard let capability else { return }
        if !force, !(volumeText.isEmpty && abvText.isEmpty) { return }
        if let abv = item.abv, let ml = item.volumeML {
            abvText = ByVolumeDefaults.format(abv)
            volumeText = ByVolumeDefaults.format(Measurement(value: ml, unit: .milliliters).converted(to: volumeUnit).value)
        } else if item.amount > 0, !capability.isMassPerVolume {
            // Alcohol grams-only dose: hold a default 5% ABV and back-derive volume
            // so By Drink is never blank. An ester has no default concentration to
            // assume — leave the fields blank for the user to enter the vial's mg/mL.
            let abv = item.abv ?? 5
            abvText = ByVolumeDefaults.format(abv)
            let ml = ByVolumeDosing.volumeML(grams: item.amount, abv: abv)
            volumeText = ByVolumeDefaults.format(Measurement(value: ml, unit: .milliliters).converted(to: volumeUnit).value)
        }
    }

    /// In By Weight, keep `item.volumeML` consistent with the edited grams by
    /// re-deriving volume at the held ABV — so flipping back to By Drink shows a
    /// matching volume rather than a stale or zeroed one.
    func reprojectVolumeFromGrams(item: inout StagedDose, capability: ByVolumeDosing) {
        if capability.isMassPerVolume {
            // Only reproject against a concentration the user actually entered —
            // there is no default mg/mL to assume.
            guard let strength = item.abv, strength > 0 else { return }
            item.volumeML = item.amount > 0 ? capability.volumeML(forAmount: item.amount, strength: strength) : nil
        } else {
            let abv = item.abv ?? 5
            item.abv = abv
            item.volumeML = item.amount > 0 ? ByVolumeDosing.volumeML(grams: item.amount, abv: abv) : nil
        }
    }

    /// Push the custom drink's grams + metadata onto the staged dose. Only writes
    /// once a usable volume + strength is entered, so opening the logger on a dose
    /// already staged from a chip never wipes its grams.
    func syncCustomDrink(item: inout StagedDose, capability: ByVolumeDosing?, byDrinkPreferred: Bool) {
        guard byDrinkPreferred, let capability, let grams = customDrinkGrams(capability: capability) else { return }
        item.components = [StagedDose.Component(amount: (grams * 10).rounded() / 10)]
        item.unit = capability.canonicalUnit
        item.volumeML = enteredVolumeML
        item.abv = enteredABV
        let trimmed = drinkName.trimmingCharacters(in: .whitespacesAndNewlines)
        item.drinkName = trimmed.isEmpty ? nil : trimmed
        item.emoji = drinkEmoji.isEmpty ? nil : drinkEmoji
    }

    /// Fill the dials from a chosen preset. A volume-less preset fills only the
    /// strength, leaving the current volume to dial.
    func apply(preset: CustomDrinkPreset, item: inout StagedDose, capability: ByVolumeDosing?, byDrinkPreferred: Bool) {
        abvText = ByVolumeDefaults.format(preset.strengthABV)
        if let ml = preset.volumeML {
            volumeText = ByVolumeDefaults.format(Measurement(value: ml, unit: .milliliters).converted(to: volumeUnit).value)
        }
        drinkName = preset.name
        drinkEmoji = preset.emoji
        syncCustomDrink(item: &item, capability: capability, byDrinkPreferred: byDrinkPreferred)
    }

    // MARK: - Pill picker

    /// Adopt a strength chip: the dose becomes `pillCount` units of this strength.
    func selectStrength(_ mg: Double, item: inout StagedDose) {
        if pillCount < 1 { pillCount = 1 }
        pillStrength = mg
        item.components = [StagedDose.Component(amount: mg, count: pillCount)]
        stepTick += 1
    }

    /// Drop to free-form mg (the "mg…" chip): keep the current amount and seed the
    /// stepper's text field so it opens populated rather than blank.
    func selectFreeForm(item: StagedDose) {
        pillStrength = nil
        showAmount(item.amount)
        stepTick += 1
    }

    func setPillCount(_ newCount: Int, item: inout StagedDose) {
        let clamped = max(1, newCount)
        pillCount = clamped
        if let strength = pillStrength {
            item.components = [StagedDose.Component(amount: strength, count: clamped)]
        }
        stepTick += 1
    }

    /// Seed the picker once from the staged amount: if it already factors as a
    /// whole number of a catalog strength, adopt that; otherwise pre-select the
    /// strength nearest the staged/reference amount (one pill) so the picker opens
    /// meaningful.
    func seedPillIfNeeded(_ product: ProductStrengths, item: inout StagedDose) {
        guard !pillSeeded else { return }
        pillSeeded = true
        // Largest strength first, so a 10 mg dose seeds as one 10 mg tablet rather
        // than two 5 mg — matching how a person actually holds their pills (the box
        // is 20 mg tablets, not four 5s).
        for strength in product.strengths.sorted(by: >) where strength > 0 {
            let ratio = item.amount / strength
            let rounded = ratio.rounded()
            if rounded >= 1, abs(ratio - rounded) < 0.001 {
                pillStrength = strength
                pillCount = Int(rounded)
                return
            }
        }
        let target = item.amount > 0 ? item.amount : (item.referenceDose ?? product.strengths.first ?? 0)
        if let nearest = product.strengths.min(by: { abs($0 - target) < abs($1 - target) }) {
            pillStrength = nearest
            pillCount = 1
            item.components = [StagedDose.Component(amount: nearest, count: 1)]
        }
    }

    // MARK: - Grapefruit

    func resolveGrapefruitSubstrate(substanceName: String) {
        isGrapefruitSubstrate = MetabolicModulation
            .majorEnzymes(metabolism: SubstanceStore.shared.metabolism(forSubstanceName: substanceName))
            .contains(.cyp3a4)
    }
}
