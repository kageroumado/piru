import SwiftData
import SwiftUI

// MARK: - Staged Dose Editor

/// Inline per-dose editor: rows directly on the tray surface — fields use
/// fills, never their own card, so the dock stays a single material. Amount,
/// unit, route, and note; time lives only on the tray's shared When chip.
///
/// A coordinator: the sections are separate views in
/// `StagedDoseEditorSections.swift` and everything the editor types into lives on
/// ``StagedDoseEditorModel``. Only the genuine UI toggles stay here.
struct StagedDoseEditor: View {
    @Binding var item: StagedDose
    let namespace: Namespace.ID
    let onCollapse: () -> Void
    let onRemove: () -> Void

    @State private var model = StagedDoseEditorModel()

    /// The note row stays revealed once opened, even while still empty.
    @State private var noteExpanded = false
    /// Presents the drink-preset manager (add / edit / reorder / delete) as a
    /// proper sheet — the drink chip's menu opens it.
    @State private var showDrinkManager = false
    @State private var profileStore = UserProfileStore.shared

    /// The By Drink / By Weight choice persists across doses.
    @AppStorage("alcoholEditorByDrink") private var byDrinkPreferred = true

    @FocusState private var amountFocused: Bool
    @FocusState private var noteFocused: Bool
    @FocusState private var abvFocused: Bool
    @FocusState private var volumeFocused: Bool

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// One shared height for the route/note pills — a TextField's intrinsic
    /// height differs from a Menu label's, so padding alone won't match them.
    /// Scaled with the pills' footnote type so they don't clip at
    /// accessibility sizes.
    @ScaledMetric(relativeTo: .footnote) private var pillHeight: CGFloat = 33

    private var pillLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.md))
            : AnyLayout(HStackLayout(spacing: Spacing.md))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            StagedDoseEditorHeader(
                title: item.displayTitle,
                subtitle: recognitionSubtitle,
                morphID: item.id,
                namespace: namespace,
                onCollapse: onCollapse,
                onRemove: onRemove,
            )

            inputBlock

            // Pills side by side normally; stacked at accessibility sizes,
            // where they can't share the row without truncating each other
            // into unreadability (matching `TrayCommitBar`'s chips).
            pillLayout {
                if byVolumeCapability != nil, byDrinkPreferred {
                    drinkTypeChip
                }
                StagedDoseRouteMenu(item: $item, pillHeight: pillHeight, namespace: namespace)
                SaltPicker(
                    forms: item.librarySubstance?.saltForms(for: item.route) ?? [],
                    selection: $item.saltForm,
                    style: .menuPill(namespace: namespace, id: "salt-\(item.id)", height: pillHeight),
                )
                BrandPicker(
                    brands: brandProducts,
                    productName: $item.productName,
                    releaseForm: $item.releaseForm,
                    isomer: $item.isomer,
                    style: .menuPill(namespace: namespace, id: "brand-\(item.id)", height: pillHeight),
                )
                if showsIsomerPill {
                    IsomerPicker(
                        options: isomerPickerOptions,
                        selection: $item.isomer,
                        style: .menuPill(namespace: namespace, id: "isomer-\(item.id)", height: pillHeight),
                    )
                }
                StagedDoseNotePill(note: item.note, pillHeight: pillHeight) {
                    withAnimation(.snappy) { noteExpanded.toggle() }
                    if noteExpanded { noteFocused = true }
                }
                if profileStore.grapefruitLoggingEnabled, model.isGrapefruitSubstrate {
                    StagedDoseGrapefruitPill(isOn: $item.hadGrapefruit, pillHeight: pillHeight)
                }
            }

            if noteExpanded {
                StagedDoseNoteEditor(note: $item.note, focus: $noteFocused) {
                    noteFocused = false
                    withAnimation(.snappy) { noteExpanded = false }
                }
            }
        }
        .sensoryFeedback(.increase, trigger: model.stepTick)
        .onAppear(perform: seedOnAppear)
        .onChange(of: noteFocused) {
            // Fold an untouched note row back into the pill.
            if !noteFocused, item.note.isEmpty {
                withAnimation(.snappy) { noteExpanded = false }
            }
        }
        // Keep the staged grams + by-volume metadata synced with the custom logger.
        .onChange(of: customDrinkGrams) { if byDrinkPreferred { syncCustomDrink() } }
        .onChange(of: model.drinkName) { if byDrinkPreferred { syncCustomDrink() } }
        // In By Weight, editing grams re-projects the volume (holding ABV) so the
        // By Drink fields stay consistent when the user flips back — never zeroed.
        .onChange(of: item.amount) {
            guard byVolumeCapability != nil, !byDrinkPreferred else { return }
            model.reprojectVolumeFromGrams(item: &item)
        }
        .onChange(of: byDrinkPreferred) {
            if byDrinkPreferred {
                // Re-derive the drink fields from the (possibly grams-edited) dose
                // so By Drink is never blank, then re-sync the metadata.
                model.seedByDrinkFieldsIfNeeded(from: item, capability: byVolumeCapability, force: true)
                syncCustomDrink()
            } else {
                // Show the current grams in the weight field (the drink dials may
                // have set item.amount without touching the text).
                model.showAmount(item.amount)
            }
        }
        .onChange(of: model.volumeUnit) { old, new in
            model.convertVolumeText(from: old, to: new)
        }
        // Switching a staged row's unit to the canonical by-volume unit ("g")
        // reveals the drink editor mid-edit — the `.onAppear` seeding above
        // has long since run, so re-seed here or it opens blank (0% / 0 mL).
        .onChange(of: item.unit) {
            guard let capability = byVolumeCapability else { return }
            CustomDrinkPreset.seedIfNeeded(for: item.substanceName, capability: capability, context: modelContext)
            model.seedByDrinkFieldsIfNeeded(from: item, capability: capability)
            if model.drinkName.isEmpty { model.drinkName = item.drinkName ?? "" }
            if model.drinkEmoji.isEmpty { model.drinkEmoji = item.emoji ?? "" }
        }
        .sheet(isPresented: $showDrinkManager) {
            DrinkPresetManagerView(substanceName: item.substanceName)
        }
    }

    /// The amount surface: the alcohol logger, the branded-pill picker, or the
    /// plain −/+ stepper.
    @ViewBuilder
    private var inputBlock: some View {
        if byVolumeCapability != nil {
            // By Drink (the two-tier strength + volume logger) vs By Weight (the
            // grams stepper).
            Picker("Input", selection: $byDrinkPreferred) {
                Text("By Drink").tag(true)
                Text("By Weight").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if byDrinkPreferred {
                StagedDoseByDrinkBlock(
                    model: model,
                    grams: customDrinkGrams,
                    level: item.doseLevel,
                    abvFocus: $abvFocused,
                    volumeFocus: $volumeFocused,
                )
            } else {
                StagedDoseStepperBlock(
                    item: $item,
                    model: model,
                    namespace: namespace,
                    amountFocus: $amountFocused,
                )
            }
        } else if let product = tabletProduct {
            StagedDosePillBlock(
                item: $item,
                model: model,
                product: product,
                pillHeight: pillHeight,
                namespace: namespace,
                amountFocus: $amountFocused,
            )
        } else {
            StagedDoseStepperBlock(
                item: $item,
                model: model,
                namespace: namespace,
                amountFocus: $amountFocused,
            )
        }
    }

    /// The drink-type chip in the Route·Note row: a native Menu — the same
    /// affordance as the route pill beside it — listing the saved presets
    /// (with strength/volume details) plus "Edit Drinks…" for the manager.
    private var drinkTypeChip: some View {
        DrinkPresetMenu(
            substanceName: item.substanceName,
            selectedName: item.drinkName,
            currentName: model.drinkName,
            currentEmoji: model.drinkEmoji,
            pillHeight: pillHeight,
            onSelect: { apply(preset: $0) },
            onManage: { showDrinkManager = true },
        )
    }

    // MARK: - Item-derived gates

    /// By-volume capability for this staged substance (alcohol), gated on the
    /// canonical "g" unit so the drink chips show only when the dose is in grams.
    private var byVolumeCapability: ByVolumeDosing? {
        guard item.unit == "g" else { return nil }
        return item.librarySubstance?.byVolumeDosing
    }

    private var customDrinkGrams: Double? {
        model.customDrinkGrams(capability: byVolumeCapability)
    }

    /// The branded product's tablet/capsule strengths, when this staged dose is a
    /// known branded pill logged in mg — gates the pill picker. This is the med
    /// analogue of ``byVolumeCapability``: a real strength is picked as a chip and
    /// logged as a *pill*, rather than typed as raw milligrams. Nil for canonical
    /// logs, non-mg units, or brands with no curated strengths (→ plain mg stepper).
    private var tabletProduct: ProductStrengths? {
        guard item.unit == "mg", byVolumeCapability == nil,
              let product = item.productName, !product.isEmpty else { return nil }
        return SubstanceLibrary.productStrengths(for: product)
    }

    /// The substance's branded products, for the brand picker. Empty (pill hidden)
    /// for substances with no brands.
    private var brandProducts: [SubstanceStore.BrandProduct] {
        guard let uid = item.librarySubstance?.substanceUID else { return [] }
        return SubstanceLibrary.brandProducts(forUID: uid)
    }

    /// The route's isomer options, for the isomer picker.
    private var isomerPickerOptions: [IsomerPicker.Option] {
        (item.librarySubstance?.isomerOptions(for: item.route) ?? []).map {
            IsomerPicker.Option(code: $0.code, displayName: $0.displayName)
        }
    }

    /// Whether to surface the isomer pill alongside the brand pill. The enantiomer
    /// axis is its own control: shown for a substance with no branded release form
    /// (Ketamine → Esketamine, Modafinil → Armodafinil) always, but on a *branded*
    /// substance only once a distinct enantiomer is active (Focalin searched into a
    /// D dose) — so a plain Methylphenidate log shows just the brand pill, not two.
    private var showsIsomerPill: Bool {
        guard isomerPickerOptions.count > 1 else { return false }
        return !brandProducts.contains(where: \.isExtendedRelease) || item.isomer != nil
    }

    /// "Methylphenidate · extended-release" — the recognition beat shown under a
    /// branded title (Concerta). Only when the product actually resolves to a
    /// *different* canonical substance, so a plain-name log stays unadorned.
    private var recognitionSubtitle: String? {
        guard let product = item.productName, !product.isEmpty else { return nil }
        let canonical = item.librarySubstance?.displayTitle ?? item.substanceName
        guard product.caseInsensitiveCompare(canonical) != .orderedSame else { return nil }
        if let phrase = releasePhrase(for: item.releaseForm) {
            return "\(canonical) · \(phrase)"
        }
        return canonical
    }

    private func releasePhrase(for code: String?) -> String? {
        switch code {
        case "XR": String(localized: "extended-release")
        case "IR": String(localized: "immediate-release")
        case "DEP": String(localized: "depot")
        default: nil
        }
    }

    // MARK: - Actions

    private func seedOnAppear() {
        if let product = tabletProduct {
            model.seedPillIfNeeded(product, item: &item)
        }
        if item.amount > 0 {
            model.showAmount(item.amount)
        }
        // Don't pop the keyboard for by-volume substances (drink presets are
        // the primary action) or branded pills (tap a strength chip, don't type).
        if item.amount <= 0, byVolumeCapability == nil, tabletProduct == nil { amountFocused = true }
        if profileStore.grapefruitLoggingEnabled {
            model.resolveGrapefruitSubstrate(substanceName: item.substanceName)
        }
        // Seed the custom-drink fields from a dose already logged by volume, so
        // re-opening it shows its strength/volume/name.
        if let capability = byVolumeCapability {
            CustomDrinkPreset.seedIfNeeded(for: item.substanceName, capability: capability, context: modelContext)
            model.seedByDrinkFieldsIfNeeded(from: item, capability: capability)
            model.drinkName = item.drinkName ?? ""
            model.drinkEmoji = item.emoji ?? ""
        }
    }

    private func syncCustomDrink() {
        let capability = byVolumeCapability
        model.syncCustomDrink(item: &item, capability: capability, byDrinkPreferred: byDrinkPreferred)
    }

    private func apply(preset: CustomDrinkPreset) {
        let capability = byVolumeCapability
        model.apply(preset: preset, item: &item, capability: capability, byDrinkPreferred: byDrinkPreferred)
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
                    .accessibilityHidden(true)
            }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 11)
            .frame(height: pillHeight)
            .background(Theme.accent.opacity(Theme.Opacity.tint), in: Capsule())
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
