import SwiftData
import SwiftUI

// MARK: - Staged Dose Editor

/// Inline per-dose editor: rows directly on the tray surface — fields use
/// fills, never their own card, so the dock stays a single material. Amount,
/// unit, route, and note; time lives only on the tray's shared When chip.
///
/// Split out of `DoseTray.swift` (its one non-private symbol — the tray's
/// `TrayStagedListCard` renders it); the drink-preset menu and the
/// `CustomDrinkPreset` display helpers live here with it.
struct StagedDoseEditor: View {
    @Binding var item: StagedDose
    let namespace: Namespace.ID
    let onCollapse: () -> Void
    let onRemove: () -> Void

    @State private var amountText = ""
    /// Suppresses the text→amount sync when `amountText` is being set *from*
    /// the model (onAppear / stepper), so opening the editor never rewrites
    /// the staged amount through display rounding.
    @State private var suppressAmountSync = false
    @FocusState private var amountFocused: Bool

    /// The note row stays revealed once opened, even while still empty.
    @State private var noteExpanded = false
    @FocusState private var noteFocused: Bool

    /// Bumped on each stepper tap — drives the value-change pulse + haptic.
    @State private var stepTick = 0

    /// Whether this substance is CYP3A4-heavy — gates the per-dose grapefruit toggle (Stage 4c).
    /// Computed once on appear; the metabolism lookup shouldn't run every render.
    @State private var isGrapefruitSubstrate = false
    @State private var profileStore = UserProfileStore.shared
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // By-volume custom logger (alcohol): a two-tier strength + volume input with an
    // optional drink name. The By Drink / By Weight choice persists across doses.
    @AppStorage("alcoholEditorByDrink") private var byDrinkPreferred = true
    @State private var volumeText = ""
    @State private var abvText = ""
    @State private var drinkName = ""
    @State private var drinkEmoji = ""
    @State private var volumeUnit: UnitVolume = ByVolumeDefaults.preferredVolumeUnit
    /// Presents the drink-preset manager (add / edit / reorder / delete) as a
    /// proper sheet — the drink chip's menu opens it.
    @State private var showDrinkManager = false
    @FocusState private var abvFocused: Bool
    @FocusState private var volumeFocused: Bool

    private var enteredVolumeML: Double? {
        guard let v = Double(volumeText.replacingOccurrences(of: ",", with: ".")), v > 0 else { return nil }
        return Measurement(value: v, unit: volumeUnit).converted(to: .milliliters).value
    }

    private var enteredABV: Double? {
        guard let a = Double(abvText.replacingOccurrences(of: ",", with: ".")), a > 0 else { return nil }
        return a
    }

    private var customDrinkGrams: Double? {
        guard let cap = byVolumeCapability, let ml = enteredVolumeML, let abv = enteredABV else { return nil }
        let g = cap.canonicalAmount(volumeML: ml, strength: abv)
        return g > 0 ? g : nil
    }

    /// Millilitre step for the volume stepper, unit-aware: 10 mL, or 0.5 fl oz.
    private var volumeStep: Double {
        volumeUnit == .fluidOunces ? 0.5 : 10
    }

    /// Bump the ABV field by `delta`, clamped to a sane 0–95% and reformatted.
    private func adjustABV(_ delta: Double) {
        let current = Double(abvText.replacingOccurrences(of: ",", with: ".")) ?? 0
        let next = min(95, max(0, ((current + delta) * 10).rounded() / 10))
        abvText = next > 0 ? ByVolumeDefaults.format(next) : ""
        stepTick += 1
    }

    /// Bump the volume field by one `volumeStep` in the displayed unit, clamped ≥ 0.
    private func adjustVolume(_ steps: Double) {
        let current = Double(volumeText.replacingOccurrences(of: ",", with: ".")) ?? 0
        let next = max(0, current + steps * volumeStep)
        volumeText = next > 0 ? ByVolumeDefaults.format(next) : ""
        stepTick += 1
    }

    private static let unitChoices = ["µg", "mg", "g", "mL"]
    /// One shared height for the route/note pills — a TextField's intrinsic
    /// height differs from a Menu label's, so padding alone won't match them.
    /// Scaled with the pills' footnote type so they don't clip at
    /// accessibility sizes.
    @ScaledMetric(relativeTo: .footnote) private var pillHeight: CGFloat = 33
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var pillLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if byVolumeCapability != nil {
                byVolumeModeToggle
                if byDrinkPreferred {
                    byDrinkSteppers
                } else {
                    stepperBlock
                }
            } else {
                stepperBlock
            }

            // Pills side by side normally; stacked at accessibility sizes,
            // where they can't share the row without truncating each other
            // into unreadability (matching `TrayCommitBar`'s chips).
            pillLayout {
                if byVolumeCapability != nil, byDrinkPreferred {
                    drinkTypeChip
                }
                routeMenu
                SaltPicker(
                    forms: item.librarySubstance?.saltForms(for: item.route) ?? [],
                    selection: $item.saltForm,
                    style: .menuPill(namespace: namespace, id: "salt-\(item.id)", height: pillHeight),
                )
                notePill
                if profileStore.grapefruitLoggingEnabled, isGrapefruitSubstrate {
                    grapefruitPill
                }
            }

            if noteExpanded {
                noteEditor
            }
        }
        .sensoryFeedback(.increase, trigger: stepTick)
        .onAppear {
            if item.amount > 0 {
                suppressAmountSync = true
                amountText = item.amount.doseFormatted
            }
            // Don't pop the keyboard for by-volume substances — the drink presets
            // are the primary action, not manual amount entry.
            if item.amount <= 0, byVolumeCapability == nil { amountFocused = true }
            if profileStore.grapefruitLoggingEnabled {
                isGrapefruitSubstrate = MetabolicModulation
                    .majorEnzymes(metabolism: SubstanceStore.shared.metabolism(forSubstanceName: item.substanceName))
                    .contains(.cyp3a4)
            }
            // Seed the custom-drink fields from a dose already logged by volume, so
            // re-opening it shows its strength/volume/name.
            if let capability = byVolumeCapability {
                CustomDrinkPreset.seedIfNeeded(for: item.substanceName, capability: capability, context: modelContext)
                seedByDrinkFieldsIfNeeded()
                drinkName = item.drinkName ?? ""
                drinkEmoji = item.emoji ?? ""
            }
        }
        .onChange(of: noteFocused) {
            // Fold an untouched note row back into the pill.
            if !noteFocused, item.note.isEmpty {
                withAnimation(.snappy) { noteExpanded = false }
            }
        }
        // Keep the staged grams + by-volume metadata synced with the custom logger.
        .onChange(of: customDrinkGrams) { if byDrinkPreferred { syncCustomDrink() } }
        .onChange(of: drinkName) { if byDrinkPreferred { syncCustomDrink() } }
        // In By Weight, editing grams re-projects the volume (holding ABV) so the
        // By Drink fields stay consistent when the user flips back — never zeroed.
        .onChange(of: item.amount) {
            guard byVolumeCapability != nil, !byDrinkPreferred else { return }
            reprojectVolumeFromGrams()
        }
        .onChange(of: byDrinkPreferred) {
            if byDrinkPreferred {
                // Re-derive the drink fields from the (possibly grams-edited) dose
                // so By Drink is never blank, then re-sync the metadata.
                seedByDrinkFieldsIfNeeded(force: true)
                syncCustomDrink()
            } else {
                // Show the current grams in the weight field (the drink dials may
                // have set item.amount without touching amountText).
                suppressAmountSync = true
                amountText = item.amount > 0 ? item.amount.doseFormatted : ""
            }
        }
        .onChange(of: volumeUnit) { old, new in
            ByVolumeDefaults.preferredVolumeUnit = new
            guard let v = Double(volumeText.replacingOccurrences(of: ",", with: ".")), v > 0 else { return }
            volumeText = ByVolumeDefaults.format(Measurement(value: v, unit: old).converted(to: new).value)
        }
        // Switching a staged row's unit to the canonical by-volume unit ("g")
        // reveals the drink editor mid-edit — the `.onAppear` seeding above
        // has long since run, so re-seed here or it opens blank (0% / 0 mL).
        .onChange(of: item.unit) {
            guard let capability = byVolumeCapability else { return }
            CustomDrinkPreset.seedIfNeeded(for: item.substanceName, capability: capability, context: modelContext)
            seedByDrinkFieldsIfNeeded()
            if drinkName.isEmpty { drinkName = item.drinkName ?? "" }
            if drinkEmoji.isEmpty { drinkEmoji = item.emoji ?? "" }
        }
        .sheet(isPresented: $showDrinkManager) {
            DrinkPresetManagerView(substanceName: item.substanceName)
        }
    }

    private var header: some View {
        // 8pt chevron→text gap, matching the collapsed row exactly so the
        // matched-geometry morph doesn't shift the leading column.
        HStack(spacing: 8) {
            // The title + chevron are the collapse target — merged into ONE
            // element carrying the "Collapses the editor" hint. Keeping the
            // trash a separate sibling stops that hint from bleeding onto it
            // (it used to read "trash … Collapses the editor").
            HStack(spacing: 8) {
                // Same glyph as the collapsed row, rotated to point down
                // (expanded, per Apple's disclosure convention) — the matched-
                // geometry swap morphs it in place like a rotation.
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(90))
                    .frame(width: 16)
                    .trayMorph(id: "chevron-\(item.id)", in: namespace)
                    .accessibilityHidden(true)
                Text(CustomSubstanceStore.shared.displayName(for: item.substanceName))
                    .font(.body.weight(.semibold))
                    .trayMorph(id: "title-\(item.id)", in: namespace)
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onCollapse)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Collapses the editor")

            // 42pt — the stepper-button size, so the trash sits on the same
            // vertical line as the + button below it.
            Button(action: onRemove) {
                Image(systemName: "trash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                    .frame(width: 42, height: 42)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove dose")
        }
    }

    /// Behaves like the location chip: neutral "Note" when empty, accent-
    /// tinted with the note's first words once one exists. Toggles the
    /// multi-line editor below.
    private var notePill: some View {
        Button {
            withAnimation(.snappy) { noteExpanded.toggle() }
            if noteExpanded { noteFocused = true }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "note.text")
                    .imageScale(.small)
                Text(item.note.isEmpty ? String(localized: "Note") : item.note)
                    .lineLimit(1)
            }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 11)
            .frame(height: pillHeight)
            .background(
                item.note.isEmpty ? AnyShapeStyle(Color(.secondarySystemFill)) : AnyShapeStyle(Theme.accent.opacity(0.15)),
                in: Capsule(),
            )
            .foregroundStyle(item.note.isEmpty ? AnyShapeStyle(.primary) : AnyShapeStyle(Theme.accent))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 180, alignment: .leading)
        .accessibilityLabel("Note")
        .accessibilityValue(item.note.isEmpty ? Text("None") : Text(item.note))
        .accessibilityHint("Adds a note to this dose")
    }

    /// By-volume capability for this staged substance (alcohol), gated on the
    /// canonical "g" unit so the drink chips show only when the dose is in grams.
    private var byVolumeCapability: ByVolumeDosing? {
        guard item.unit == "g" else { return nil }
        return item.librarySubstance?.byVolumeDosing
    }

    /// The amount +/− stepper and its breakdown/level readout — the default for
    /// every substance, and the "By Weight" mode for alcohol.
    private var stepperBlock: some View {
        VStack(alignment: .center, spacing: 5) {
            HStack(spacing: 8) {
                stepButton(systemImage: "minus") {
                    setAmount(max(0, item.amount - amountStep))
                }
                .accessibilityLabel("Decrease amount")
                amountField
                stepButton(systemImage: "plus") {
                    setAmount(item.amount + amountStep)
                }
                .accessibilityLabel("Increase amount")
            }
            .phaseAnimator(reduceMotion ? [1.0] : [1.0, 1.03], trigger: stepTick) { content, scale in
                content.scaleEffect(scale)
            } animation: { _ in
                .snappy(duration: 0.15)
            }
            if item.breakdownLabel != nil || item.doseLevel != nil {
                HStack(spacing: 5) {
                    if let breakdown = item.breakdownLabel {
                        Text(verbatim: "= \(breakdown) \(item.unit)")
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                    if item.breakdownLabel != nil, item.doseLevel != nil {
                        Middot().foregroundStyle(.tertiary)
                    }
                    if let level = item.doseLevel {
                        Text(level.displayName)
                            .textCase(.lowercase)
                            .foregroundStyle(level.labelColor)
                    }
                }
                .font(.caption.weight(.medium))
                .frame(maxWidth: .infinity)
                // One spoken element ("13 mg, light") instead of a fragmented
                // run that includes a lone "·" stop.
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// By Drink (the two-tier strength + volume logger) vs By Weight (the grams
    /// stepper). The choice persists across doses via `byDrinkPreferred`.
    private var byVolumeModeToggle: some View {
        Picker("Input", selection: $byDrinkPreferred) {
            Text("By Drink").tag(true)
            Text("By Weight").tag(false)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    // MARK: By Drink (strength + volume steppers)

    /// Strength (%ABV) and Volume steppers — the exact grams-picker control
    /// (42pt capsule, centered number, unit as a trailing overlay) — plus a
    /// live grams / standard-drinks readout. Tap the number to type; use −/+
    /// to nudge without the keyboard.
    private var byDrinkSteppers: some View {
        VStack(alignment: .leading, spacing: 10) {
            byDrinkRow(
                label: "Strength",
                text: $abvText,
                focus: $abvFocused,
                trailing: Text(verbatim: "%")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.secondaryLabel),
                onDec: { adjustABV(-0.5) },
                onInc: { adjustABV(0.5) },
                decLabel: "Lower strength",
                incLabel: "Raise strength",
            )
            byDrinkRow(
                label: "Volume",
                text: $volumeText,
                focus: $volumeFocused,
                trailing: volumeUnitMenu,
                onDec: { adjustVolume(-1) },
                onInc: { adjustVolume(1) },
                decLabel: "Lower volume",
                incLabel: "Raise volume",
            )
            byDrinkReadout
        }
    }

    /// One stepper row in the grams-picker shape: the number is centered in the
    /// capsule itself; the unit is a trailing overlay so it never shifts the
    /// number off-center (mirrors `amountField`).
    private func byDrinkRow(
        label: LocalizedStringKey,
        text: Binding<String>,
        focus: FocusState<Bool>.Binding,
        trailing: some View,
        onDec: @escaping () -> Void,
        onInc: @escaping () -> Void,
        decLabel: LocalizedStringKey,
        incLabel: LocalizedStringKey,
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryLabel)
            HStack(spacing: 8) {
                stepButton(systemImage: "minus", action: onDec)
                    .accessibilityLabel(decLabel)
                TextField("0", text: text)
                    .keyboardType(.decimalPad)
                    .focused(focus)
                    .multilineTextAlignment(.center)
                    .font(.title3.weight(.semibold))
                    .frame(height: 42)
                    .frame(maxWidth: .infinity)
                    .background(Color(.secondarySystemFill), in: Capsule())
                    // Label before the overlay so it scopes to the field, not
                    // the unit menu / "%" composited on top of it.
                    .accessibilityLabel(label)
                    .overlay(alignment: .trailing) {
                        trailing
                            .padding(.trailing, 12)
                    }
                stepButton(systemImage: "plus", action: onInc)
                    .accessibilityLabel(incLabel)
            }
        }
    }

    private var volumeUnitMenu: some View {
        Menu {
            Picker("Volume unit", selection: $volumeUnit) {
                Text(verbatim: "mL").tag(UnitVolume.milliliters)
                Text(verbatim: "fl oz").tag(UnitVolume.fluidOunces)
            }
        } label: {
            HStack(spacing: 2) {
                Text(volumeUnit == .fluidOunces ? "fl oz" : "mL")
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.secondaryLabel)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Volume unit")
    }

    @ViewBuilder
    private var byDrinkReadout: some View {
        if let grams = customDrinkGrams {
            let drinks = ByVolumeDosing.standardDrinks(grams: grams)
            HStack(spacing: 6) {
                Text("\(Int(grams.rounded())) g")
                    .fontWeight(.semibold)
                    .foregroundStyle(item.doseLevel?.labelColor ?? .primary)
                    .contentTransition(.numericText())
                Text("· \(drinks, format: .number.precision(.fractionLength(1))) std drinks")
                    .foregroundStyle(Theme.secondaryLabel)
                if let level = item.doseLevel {
                    Middot().foregroundStyle(.tertiary)
                    Text(level.displayName)
                        .textCase(.lowercase)
                        .foregroundStyle(level.labelColor)
                }
            }
            .font(.subheadline.weight(.medium))
            .frame(maxWidth: .infinity)
            // One spoken element instead of a run broken by a lone "·" stop.
            .accessibilityElement(children: .combine)
        }
        // No placeholder when empty — the strength/volume steppers are right above.
    }

    /// The drink-type chip in the Route·Note row: a native Menu — the same
    /// affordance as the route pill beside it — listing the saved presets
    /// (with strength/volume details) plus "Edit Drinks…" for the manager.
    private var drinkTypeChip: some View {
        DrinkPresetMenu(
            substanceName: item.substanceName,
            selectedName: item.drinkName,
            currentName: drinkName,
            currentEmoji: drinkEmoji,
            pillHeight: pillHeight,
            onSelect: { apply(preset: $0) },
            onManage: { showDrinkManager = true },
        )
    }

    // MARK: By Drink ⇄ By Weight sync

    /// Fill the ABV/volume fields from the staged dose's structured metadata (or,
    /// if it only has grams from a By-Weight edit, derive a volume at a default
    /// strength) so By Drink is never blank. `force` overwrites existing text.
    private func seedByDrinkFieldsIfNeeded(force: Bool = false) {
        guard byVolumeCapability != nil else { return }
        if !force, !(volumeText.isEmpty && abvText.isEmpty) { return }
        if let abv = item.abv, let ml = item.volumeML {
            abvText = ByVolumeDefaults.format(abv)
            volumeText = ByVolumeDefaults.format(Measurement(value: ml, unit: .milliliters).converted(to: volumeUnit).value)
        } else if item.amount > 0 {
            // Grams-only dose: hold a default strength and back-derive the volume.
            let abv = item.abv ?? 5
            abvText = ByVolumeDefaults.format(abv)
            let ml = ByVolumeDosing.volumeML(grams: item.amount, abv: abv)
            volumeText = ByVolumeDefaults.format(Measurement(value: ml, unit: .milliliters).converted(to: volumeUnit).value)
        }
    }

    /// In By Weight, keep `item.volumeML` consistent with the edited grams by
    /// re-deriving volume at the held ABV — so flipping back to By Drink shows a
    /// matching volume rather than a stale or zeroed one.
    private func reprojectVolumeFromGrams() {
        let abv = item.abv ?? 5
        item.abv = abv
        item.volumeML = item.amount > 0 ? ByVolumeDosing.volumeML(grams: item.amount, abv: abv) : nil
    }

    /// Push the custom drink's grams + metadata onto the staged dose. Only writes
    /// once a usable volume + strength is entered, so opening the logger on a dose
    /// already staged from a chip never wipes its grams.
    private func syncCustomDrink() {
        guard byDrinkPreferred, byVolumeCapability != nil, let grams = customDrinkGrams else { return }
        item.components = [StagedDose.Component(amount: (grams * 10).rounded() / 10)]
        item.unit = byVolumeCapability?.canonicalUnit ?? "g"
        item.volumeML = enteredVolumeML
        item.abv = enteredABV
        let trimmed = drinkName.trimmingCharacters(in: .whitespacesAndNewlines)
        item.drinkName = trimmed.isEmpty ? nil : trimmed
        item.emoji = drinkEmoji.isEmpty ? nil : drinkEmoji
    }

    // MARK: Preset select

    /// Fill the dials from a chosen preset. A volume-less preset fills only
    /// the strength, leaving the current volume to dial.
    private func apply(preset: CustomDrinkPreset) {
        abvText = ByVolumeDefaults.format(preset.strengthABV)
        if let ml = preset.volumeML {
            volumeText = ByVolumeDefaults.format(Measurement(value: ml, unit: .milliliters).converted(to: volumeUnit).value)
        }
        drinkName = preset.name
        drinkEmoji = preset.emoji
        syncCustomDrink()
    }

    /// Per-dose "had grapefruit" toggle (Stage 4c) — shown only for CYP3A4-heavy substrates when
    /// grapefruit logging is enabled in Settings. Tinted when on; recorded on the committed dose.
    private var grapefruitPill: some View {
        Button {
            withAnimation(.snappy) { item.hadGrapefruit.toggle() }
        } label: {
            Image(systemName: "carrot")
                .imageScale(.small)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 11)
                .frame(height: pillHeight)
                .background(
                    item.hadGrapefruit ? AnyShapeStyle(Theme.accent.opacity(0.15)) : AnyShapeStyle(Color(.secondarySystemFill)),
                    in: Capsule(),
                )
                .foregroundStyle(item.hadGrapefruit ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.primary))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Had grapefruit with this dose"))
        .accessibilityAddTraits(item.hadGrapefruit ? [.isSelected] : [])
    }

    /// Multi-line note editor — a single line that grows with its content,
    /// with an explicit close.
    private var noteEditor: some View {
        HStack(alignment: .top, spacing: 8) {
            TextField("Add note…", text: $item.note, axis: .vertical)
                .font(.footnote.weight(.medium))
                .lineLimit(1 ... 6)
                .focused($noteFocused)
            Button {
                noteFocused = false
                withAnimation(.snappy) { noteExpanded = false }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Theme.secondaryLabel)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.inputBackground, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }

    /// The amount is centered in the pill itself; the unit menu is a trailing
    /// overlay so it never shifts the number off-center.
    private var amountField: some View {
        TextField("0", text: $amountText)
            .keyboardType(.decimalPad)
            .focused($amountFocused)
            .multilineTextAlignment(.center)
            .font(.title3.weight(.semibold))
            .onChange(of: amountText) {
                if suppressAmountSync {
                    suppressAmountSync = false
                    return
                }
                // String binding (not value:format:) is deliberate — the staged
                // amount must update per keystroke for the live dose-level /
                // breakdown reclassification, and the suppress-flag sync above
                // relies on owning the text. Invariant dot-decimal first (the
                // field is populated from `doseFormatted`, which always emits
                // "."), then a locale-aware parse for locale keyboards.
                item.amount = Double(amountText.replacingOccurrences(of: ",", with: "."))
                    ?? (try? Double(amountText, format: .number))
                    ?? 0
            }
            .frame(height: 42)
            .frame(maxWidth: .infinity)
            // Same fill as the −/+ buttons — one control system, one shade.
            .background(Color(.secondarySystemFill), in: Capsule())
            // Label the field *before* the overlay, so the "Amount" label
            // sticks to the text field and doesn't shadow the unit menu
            // composited on top (which keeps its own "Dose unit" label).
            .accessibilityLabel("Amount")
            .overlay(alignment: .trailing) {
                unitMenu
                    .padding(.trailing, 12)
            }
            .trayMorph(id: "amount-\(item.id)", in: namespace)
    }

    private var unitMenu: some View {
        Menu {
            ForEach(unitMenuChoices, id: \.self) { unit in
                Button {
                    item.unit = unit
                } label: {
                    if unit == item.unit {
                        Label(unit, systemImage: "checkmark")
                    } else {
                        Text(unit)
                    }
                }
            }
        } label: {
            HStack(spacing: 2) {
                Text(item.unit)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.secondaryLabel)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dose unit")
        .accessibilityValue(item.unit)
    }

    private var unitMenuChoices: [String] {
        Self.unitChoices.contains(item.unit) ? Self.unitChoices : [item.unit] + Self.unitChoices
    }

    /// 42pt circles — the same height as the amount field, so the stepper
    /// row reads as one control at one size.
    private func stepButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 42, height: 42)
                .background(Color(.secondarySystemFill), in: Circle())
        }
        .buttonStyle(.plain)
    }

    /// Stepper increment anchored to the substance's reference dose when the
    /// library knows one (LSD → 10 µg, pregabalin → 25 mg), falling back to a
    /// magnitude table for unknowns.
    private var amountStep: Double {
        if let reference = item.referenceDose {
            return DoseStepping.niceStep(for: reference)
        }
        return switch item.amount {
        case ..<2: 0.25
        case ..<10: 1
        case ..<100: 5
        case ..<1_000: 25
        default: 100
        }
    }

    private func setAmount(_ value: Double) {
        stepTick += 1
        item.amount = value
        let newText = value > 0 ? value.doseFormatted : ""
        // Only arm the suppress flag when onChange will actually fire,
        // otherwise it would stay latched and swallow the next keystroke.
        if newText != amountText {
            suppressAmountSync = true
            amountText = newText
        }
    }

    private var routeMenu: some View {
        Menu {
            ForEach(RouteOfAdministration.allCases) { route in
                Button {
                    item.route = route
                    SaltPicker.revalidate(&item.saltForm, against: item.librarySubstance?.saltForms(for: route) ?? [])
                } label: {
                    if route == item.route {
                        Label(String(localized: route.localizedName), systemImage: "checkmark")
                    } else {
                        Text(route.localizedName)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.down.circle")
                    .imageScale(.small)
                Text(item.route.localizedName)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 11)
            .frame(height: pillHeight)
            .background(Color(.secondarySystemFill), in: Capsule())
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .trayMorph(id: "route-\(item.id)", in: namespace)
        .accessibilityLabel("Route")
        .accessibilityValue(item.route.localizedName)
    }
}

// MARK: - Drink Preset Menu

/// The drink chip's menu for a by-volume substance (alcohol): the saved
/// presets — emoji + name with a strength/volume subtitle — plus "Edit
/// Drinks…" opening the full manager sheet. Same affordance as the route
/// pill beside it, so no bespoke inline surface to discover.
private struct DrinkPresetMenu: View {
    let selectedName: String?
    let currentName: String
    let currentEmoji: String
    let pillHeight: CGFloat
    let onSelect: (CustomDrinkPreset) -> Void
    let onManage: () -> Void

    @Query private var presets: [CustomDrinkPreset]

    init(
        substanceName: String,
        selectedName: String?,
        currentName: String,
        currentEmoji: String,
        pillHeight: CGFloat,
        onSelect: @escaping (CustomDrinkPreset) -> Void,
        onManage: @escaping () -> Void,
    ) {
        self.selectedName = selectedName
        self.currentName = currentName
        self.currentEmoji = currentEmoji
        self.pillHeight = pillHeight
        self.onSelect = onSelect
        self.onManage = onManage
        let lower = substanceName.lowercased()
        _presets = Query(
            filter: #Predicate { $0.substanceName == lower },
            sort: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)],
        )
    }

    var body: some View {
        Menu {
            ForEach(presets) { preset in
                Button {
                    onSelect(preset)
                } label: {
                    // Details ride in the title: pull-down menus don't render
                    // subtitles (UIMenuElement.subtitle is context-menu-only),
                    // so a second Text is silently dropped here.
                    if selectedName?.caseInsensitiveCompare(preset.name) == .orderedSame {
                        Label {
                            Text(verbatim: "\(preset.emoji) \(preset.name) · \(preset.detailLabel)")
                        } icon: {
                            Image(systemName: "checkmark")
                        }
                    } else {
                        Text(verbatim: "\(preset.emoji) \(preset.name) · \(preset.detailLabel)")
                    }
                }
            }
            Divider()
            Button(action: onManage) {
                Label("Edit Drinks…", systemImage: "pencil")
            }
        } label: {
            HStack(spacing: 5) {
                if !currentEmoji.isEmpty { Text(currentEmoji) }
                Text(currentName.isEmpty ? String(localized: "Drink") : currentName)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 11)
            .frame(height: pillHeight)
            .background(Theme.accent.opacity(0.15), in: Capsule())
            .foregroundStyle(Theme.accent)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(currentName.isEmpty ? Text("Choose drink") : Text("Drink: \(currentName)"))
        .accessibilityHint("Opens your drink presets")
    }
}

extension CustomDrinkPreset {
    /// "330 mL · 5%" for a fixed-volume preset, or just "5%" for strength-only.
    /// Volume renders in the user's preferred unit (mL / fl oz), like the editor.
    @MainActor var detailLabel: String {
        let strength = "\(ByVolumeDosing.formatTrimmed(strengthABV))%"
        guard let volumeML else { return strength }
        let unit = ByVolumeDefaults.preferredVolumeUnit
        let volume = Measurement(value: volumeML, unit: UnitVolume.milliliters).converted(to: unit)
        let formatted = volume.formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0 ... 1))))
        return "\(formatted) · \(strength)"
    }
}
