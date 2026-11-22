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

    @State private var model = StagedDoseEditorModel()

    /// The note row stays revealed once opened, even while still empty.
    @State private var noteExpanded = false
    /// Presents the drink-preset manager (add / edit / reorder / delete) as a
    /// proper sheet — the drink chip's menu opens it.
    @State private var showDrinkManager = false
    @State private var profileStore = UserProfileStore.shared

    /// The volume-vs-mass choice persists across doses, separately per kind:
    /// alcohol defaults to By Volume (it has drink presets), an injectable ester
    /// to By Mass (concentration is user-entered, so typing mg is the
    /// low-friction path).
    @AppStorage("alcoholEditorByDrink") private var alcoholByVolume = true
    @AppStorage("esterEditorByVolume") private var esterByVolume = false
    /// Any other substance taken as a solution: per dose, By Mass unless the
    /// row was staged by volume (seeded on appear), since most doses of most
    /// substances are weighed, not drawn.
    @State private var solutionByVolume = false

    /// Whether the current dose edits by volume rather than mass, reading the
    /// preference that matches this substance's concentration kind.
    private var byDrinkPreferred: Bool {
        if isSolution { return solutionByVolume }
        return byVolumeCapability?.isMassPerVolume == true ? esterByVolume : alcoholByVolume
    }

    private var byDrinkBinding: Binding<Bool> {
        Binding(
            get: { byDrinkPreferred },
            set: { newValue in
                if isSolution { solutionByVolume = newValue }
                else if byVolumeCapability?.isMassPerVolume == true { esterByVolume = newValue }
                else { alcoholByVolume = newValue }
            },
        )
    }

    @FocusState private var amountFocused: Bool
    @FocusState private var noteFocused: Bool
    @FocusState private var deviationFocused: Bool
    @FocusState private var abvFocused: Bool
    @FocusState private var volumeFocused: Bool

    @Environment(\.modelContext) private var modelContext

    /// One shared height for the route/note pills — a TextField's intrinsic
    /// height differs from a Menu label's, so padding alone won't match them.
    /// Scaled with the pills' footnote type so they don't clip at
    /// accessibility sizes.
    @ScaledMetric(relativeTo: .footnote) private var pillHeight: CGFloat = 33

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            StagedDoseEditorHeader(
                title: item.displayTitle,
                subtitle: recognitionSubtitle,
                morphID: item.id,
                namespace: namespace,
                onCollapse: onCollapse,
            )

            inputBlock

            // Pills wrap onto further rows as they run out of width — nine of
            // them can be live at once (drink, route, salt, ester, brand,
            // isomer, approximate, note, grapefruit), and at accessibility sizes
            // even two won't share a row without truncating each other.
            FlowLayout(spacing: Spacing.md) {
                if byVolumeCapability != nil, byDrinkPreferred, !isSolution {
                    drinkTypeChip
                }
                StagedDoseRouteMenu(item: $item, pillHeight: pillHeight, namespace: namespace)
                if InjectionSite.applies(to: item.route) {
                    StagedDoseInjectionSiteMenu(
                        site: $item.injectionSite,
                        touched: $item.injectionSiteTouched,
                        route: item.route,
                        suggested: model.suggestedInjectionSite,
                        pillHeight: pillHeight,
                    )
                }
                SaltPicker(
                    forms: item.librarySubstance?.saltForms(for: item.route) ?? [],
                    selection: $item.saltForm,
                    style: .menuPill(namespace: namespace, id: "salt-\(item.id)", height: pillHeight),
                )
                EsterPicker(
                    forms: item.esterForms(for: item.route),
                    selection: $item.saltForm,
                    style: .menuPill(namespace: namespace, id: "ester-\(item.id)", height: pillHeight),
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
                // An unknown amount has no number to be approximate about.
                if !item.isUnknownAmount {
                    StagedDoseApproximatePill(
                        isOn: item.isApproximate,
                        deviation: item.amountDeviation,
                        unit: item.unit,
                        pillHeight: pillHeight,
                    ) {
                        withAnimation(.snappy) {
                            item.isApproximate.toggle()
                            if !item.isApproximate { item.amountDeviation = nil }
                        }
                        if item.isApproximate { deviationFocused = true }
                    }
                }
                StagedDoseNotePill(note: item.note, pillHeight: pillHeight) {
                    withAnimation(.snappy) { noteExpanded.toggle() }
                    if noteExpanded { noteFocused = true }
                }
                if profileStore.grapefruitLoggingEnabled, model.isGrapefruitSubstrate {
                    StagedDoseGrapefruitPill(isOn: $item.hadGrapefruit, pillHeight: pillHeight)
                }
            }

            if item.isApproximate, !item.isUnknownAmount {
                StagedDoseDeviationEditor(deviation: $item.amountDeviation, unit: item.unit, focus: $deviationFocused)
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
        .onChange(of: item.route) { seedInjectionSite() }
        .onChange(of: noteFocused) {
            // Fold an untouched note row back into the pill.
            if !noteFocused, item.note.isEmpty {
                withAnimation(.snappy) { noteExpanded = false }
            }
        }
        // Keep the staged grams + by-volume metadata synced with the custom logger.
        .onChange(of: customDrinkGrams) { if byDrinkPreferred { syncCustomDrink() } }
        .onChange(of: model.drinkName) { if byDrinkPreferred { syncCustomDrink() } }
        // In By Mass, editing grams re-projects the volume (holding ABV) so the
        // By Volume fields stay consistent when the user flips back — never zeroed.
        .onChange(of: item.amount) {
            guard let capability = byVolumeCapability, !byDrinkPreferred else { return }
            model.reprojectVolumeFromGrams(item: &item, capability: capability)
        }
        .onChange(of: byDrinkPreferred) {
            if byDrinkPreferred {
                // A solution opens on the concentration it was last logged at:
                // the bottle's strength is the durable fact.
                if isSolution { model.seedSolution(item: &item, context: modelContext) }
                // Re-derive the drink fields from the (possibly grams-edited) dose
                // so By Volume is never blank, then re-sync the metadata.
                model.seedByDrinkFieldsIfNeeded(from: item, capability: byVolumeCapability, force: true)
                syncCustomDrink()
            } else {
                // A solution weighed instead records no volume: the entry would
                // otherwise claim a draw nobody measured.
                if isSolution { model.clearSolution(item: &item) }
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
            guard !isSolution, let capability = byVolumeCapability else { return }
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
    /// plain −/+ stepper. An unknown amount is a state *of* the stepper's field —
    /// emptied text, an "Unknown" placeholder — not a surface of its own.
    @ViewBuilder
    private var inputBlock: some View {
        if let capability = byVolumeCapability {
            // The concentration+volume logger vs the plain mass stepper: one
            // label pair for a drink and a vial alike.
            let modes = ByVolumeDosing.modeLabels
            Picker("Input", selection: byDrinkBinding) {
                Text(modes.volume).tag(true)
                Text(modes.mass).tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if byDrinkPreferred {
                StagedDoseByDrinkBlock(
                    model: model,
                    capability: capability,
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
            isMassPerVolume: byVolumeCapability?.isMassPerVolume ?? false,
            pillHeight: pillHeight,
            onSelect: { apply(preset: $0) },
            onManage: { showDrinkManager = true },
        )
    }

    // MARK: - Item-derived gates

    /// The by-volume input for this staged dose: the substance's own (alcohol,
    /// an injectable ester), else a plain solution in the dose's unit per mL
    /// (``ByVolumeDosing/solution(in:)``), so any substance can be logged as a
    /// volume × concentration. A branded pill keeps its strength picker, and
    /// a substance whose own input is gated off here (estradiol by mouth)
    /// stays a mass log.
    private var byVolumeCapability: ByVolumeDosing? {
        if let capability = libraryVolumeCapability { return capability }
        guard item.librarySubstance?.byVolumeDosing == nil, tabletProduct == nil,
              ByVolumeDosing.solutionUnits.contains(item.unit) else { return nil }
        return .solution(in: item.unit)
    }

    /// Whether this dose's by-volume input is the generic solution rather than
    /// the substance's own.
    private var isSolution: Bool {
        libraryVolumeCapability == nil && byVolumeCapability != nil
    }

    /// The substance's own by-volume capability (alcohol), gated on the
    /// canonical "g" unit so the drink chips show only when the dose is in grams.
    private var libraryVolumeCapability: ByVolumeDosing? {
        guard let cap = item.librarySubstance?.byVolumeDosing,
              item.unit == cap.canonicalUnit else { return nil }
        return cap.offersVolumeInput(on: item.route) ? cap : nil
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
        guard item.unit == "mg", libraryVolumeCapability == nil,
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
        if isSolution {
            // A row staged by volume reopens by volume; anything else is weighed.
            solutionByVolume = item.volumeML != nil && item.abv != nil
            if solutionByVolume { model.seedByDrinkFieldsIfNeeded(from: item, capability: byVolumeCapability) }
        }
        focusAmountIfWanted()
        seedInjectionSite()
        if profileStore.grapefruitLoggingEnabled {
            model.resolveGrapefruitSubstrate(substanceName: item.substanceName)
        }
        // Seed the custom-drink fields from a dose already logged by volume, so
        // re-opening it shows its strength/volume/name; a fresh draft takes the
        // substance's last by-volume log instead of opening on 0 / 0.
        if let capability = libraryVolumeCapability {
            CustomDrinkPreset.seedIfNeeded(for: item.substanceName, capability: capability, context: modelContext)
            model.seedFromLastByVolumeLog(item: &item, capability: capability, context: modelContext)
            model.seedByDrinkFieldsIfNeeded(from: item, capability: capability)
            model.drinkName = item.drinkName ?? ""
            model.drinkEmoji = item.emoji ?? ""
            syncCustomDrink()
        }
    }

    /// Offer the rotation's next site for an injected route, and fill it in
    /// until the user picks or clears one. A site whose area the new route
    /// doesn't offer (the abdomen on an intramuscular dose) is dropped.
    private func seedInjectionSite() {
        guard InjectionSite.applies(to: item.route) else {
            model.suggestedInjectionSite = nil
            return
        }
        let suggestion = InjectionSiteHistory.suggestedNext(
            substance: item.substanceName, route: item.route, in: modelContext,
        )
        model.suggestedInjectionSite = suggestion
        if let site = item.injectionSite, !InjectionSite.Area.offered(for: item.route).contains(site.area) {
            item.injectionSite = nil
        }
        if !item.injectionSiteTouched, item.injectionSite == nil {
            item.injectionSite = suggestion
        }
    }

    /// Raise the keyboard on the amount field when it is on screen and the row
    /// is one the user opened to type into (``StagedDose/wantsAmountFocus``),
    /// or when it opened empty. The field is absent for a branded pill (tap a
    /// strength chip) and the drink logger (presets are the primary action) — an
    /// ester in By Mass shows it and gets the focus.
    private func focusAmountIfWanted() {
        let fieldShown = tabletProduct == nil
            && (byVolumeCapability == nil || !byDrinkPreferred)
        let wanted = item.wantsAmountFocus || (item.amount <= 0 && libraryVolumeCapability == nil)
        if item.wantsAmountFocus { item.wantsAmountFocus = false }
        if fieldShown, wanted { amountFocused = true }
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

/// The chip's menu for a by-volume substance: the saved presets — emoji + name
/// with a strength/volume subtitle — plus an edit item opening the full manager
/// sheet. Same affordance as the route pill beside it, so no bespoke inline
/// surface to discover. Copy is kind-aware: alcohol saves *drinks*, an injectable
/// ester saves *concentrations*, so the placeholder and edit item read accordingly.
private struct DrinkPresetMenu: View {
    let selectedName: String?
    let currentName: String
    let currentEmoji: String
    let isMassPerVolume: Bool
    let pillHeight: CGFloat
    let onSelect: (CustomDrinkPreset) -> Void
    let onManage: () -> Void

    @Query private var presets: [CustomDrinkPreset]

    init(
        substanceName: String,
        selectedName: String?,
        currentName: String,
        currentEmoji: String,
        isMassPerVolume: Bool,
        pillHeight: CGFloat,
        onSelect: @escaping (CustomDrinkPreset) -> Void,
        onManage: @escaping () -> Void,
    ) {
        self.selectedName = selectedName
        self.currentName = currentName
        self.currentEmoji = currentEmoji
        self.isMassPerVolume = isMassPerVolume
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
                // A Toggle, so the menu draws the selection in its own checkmark
                // column; name as the title and the details as a subtitle, so a
                // long "Beer · 330 mL · 5%" doesn't wrap mid-detail.
                Toggle(isOn: Binding(
                    get: { selectedName?.caseInsensitiveCompare(preset.name) == .orderedSame },
                    set: { _ in onSelect(preset) },
                )) {
                    Text(verbatim: "\(preset.emoji) \(preset.name)")
                    Text(verbatim: preset.detailLabel)
                }
            }
            Divider()
            Button(action: onManage) {
                Label(
                    isMassPerVolume ? String(localized: "Edit concentrations…") : String(localized: "Edit Drinks…"),
                    systemImage: "pencil",
                )
            }
        } label: {
            HStack(spacing: 5) {
                if !currentEmoji.isEmpty { Text(currentEmoji) }
                Text(currentName.isEmpty
                    ? (isMassPerVolume ? String(localized: "Concentration") : String(localized: "Drink"))
                    : currentName)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 11)
            .frame(height: pillHeight)
            // Neutral until a preset is chosen, like the note pill: an accent
            // fill on the placeholder read as a selection that had not happened.
            .background(
                currentName.isEmpty ? AnyShapeStyle(Color.platformSecondarySystemFill) : AnyShapeStyle(Theme.accent.opacity(Theme.Opacity.tint)),
                in: skinChipShape(),
            )
            .foregroundStyle(currentName.isEmpty ? AnyShapeStyle(.primary) : AnyShapeStyle(Theme.accent))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(currentName.isEmpty ? Text("Choose drink") : Text("Drink: \(currentName)"))
        .accessibilityHint("Opens your drink presets")
    }
}

extension CustomDrinkPreset {
    /// "330 mL · 5%" for an alcohol preset, "40 mg/mL" for an ester concentration
    /// preset (usually strength-only). Volume renders in the user's preferred unit.
    @MainActor var detailLabel: String {
        let strengthUnit = SubstanceLibrary.lookup(substanceName)?.byVolumeDosing?.strengthUnitLabel ?? "%"
        let sep = strengthUnit == "%" ? "" : " "
        let strength = "\(ByVolumeDosing.formatTrimmed(strengthABV))\(sep)\(strengthUnit)"
        guard let volumeML else { return strength }
        let unit = ByVolumeDefaults.preferredVolumeUnit
        let volume = Measurement(value: volumeML, unit: UnitVolume.milliliters).converted(to: unit)
        let formatted = volume.formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0 ... 1))))
        return "\(formatted) · \(strength)"
    }
}
