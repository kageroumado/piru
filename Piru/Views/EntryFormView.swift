import ActivityKit
import SwiftData
import SwiftUI
import WidgetKit

struct EntryFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appNavigator) private var navigator

    var entry: DoseEntry?
    private var prefillSubstanceName: String?
    private var prefillRoute: RouteOfAdministration?
    private var prefillUnit: String?

    @State private var substance = ""
    @State private var amount = ""
    @State private var unit = "mg"
    @State private var route: RouteOfAdministration = .oral
    /// Selected salt/ester form; `nil` unless the substance offers a choice.
    @State private var saltForm: String?
    @State private var timestamp = Date.now
    @State private var notes = ""
    @State private var entryTags: [String] = []
    @State private var location: PickedLocation?
    @State private var showLocationPicker = false

    // By-volume input (alcohol %ABV → grams). When `byVolumeMode`, the panel owns
    // these and syncs the computed grams into `amount`/`unit` so the dose badge,
    // dose reference, and save path stay unchanged.
    @State private var byVolumeMode = false
    @State private var volumeText = ""
    @State private var abvText = ""
    @State private var drinkName = ""
    @State private var volumeUnit: UnitVolume = ByVolumeDefaults.preferredVolumeUnit

    @State private var selectedSubstance: Substance?
    @State private var availableRoutes: [RouteOfAdministration] = RouteOfAdministration.allCases
    @State private var savedEntry: DoseEntry?
    @State private var interactionWarnings: [InteractionResult] = []
    @State private var combinedDepression: CombinedDepressionResult?
    @State private var attenuations: [EffectAttenuationResult] = []
    @State private var crossTolerance: [CrossToleranceReadout] = []
    @State private var metabolicEffects: [MetabolicModulation.Effect] = []
    @State private var combinationMetabolites: [CombinationMetabolite.Formation] = []
    @State private var substanceLocked = false
    @FocusState private var amountFocused: Bool

    @AppStorage(QuickLogManager.fixedOrderDefaultsKey) private var quickLogFixedOrder = false

    @Query private var substanceColors: [SubstanceColor]
    @Query private var recentEntries: [DoseEntry]
    @Query private var favorites: [FavoriteSubstance]

    init(entry: DoseEntry? = nil) {
        self.entry = entry
        self.prefillSubstanceName = nil
        self.prefillRoute = nil
        self.prefillUnit = nil
        let cutoff = Date.now.addingTimeInterval(-48 * 3_600)
        _recentEntries = Query(
            filter: #Predicate<DoseEntry> { e in
                e.timestamp >= cutoff
            },
            sort: \DoseEntry.timestamp,
        )
    }

    init(prefillSubstance: String, prefillRoute: RouteOfAdministration? = nil, prefillUnit: String? = nil) {
        self.entry = nil
        self.prefillSubstanceName = prefillSubstance
        self.prefillRoute = prefillRoute
        self.prefillUnit = prefillUnit
        let cutoff = Date.now.addingTimeInterval(-48 * 3_600)
        _recentEntries = Query(
            filter: #Predicate<DoseEntry> { e in
                e.timestamp >= cutoff
            },
            sort: \DoseEntry.timestamp,
        )
    }

    private var isEditing: Bool {
        entry != nil
    }

    private let defaultUnits = ["mg", "g", "µg", "mL", "IU", "drops", "puffs"]

    private var currentUnits: [String] {
        if let sub = selectedSubstance {
            let routeUnits = sub.routes.map(\.unit)
            let aliasLabels = sub.unitAliases.map(\.label)
            let unique = Array(Set(routeUnits + aliasLabels + defaultUnits))
            let defaultUnit = sub.unit(for: route)
            // Native unit first, then substance-specific aliases (so a drink/joint
            // sits near the natural unit, not buried under mg/IU/etc.), then the rest.
            let ordered = [defaultUnit] + aliasLabels.filter { $0 != defaultUnit }
            return ordered + unique.filter { !ordered.contains($0) }
        }
        return defaultUnits
    }

    /// The amount field keeps a String binding (not `value:format:`) so the
    /// dose-level tint, badge, and dose reference update per keystroke.
    /// Invariant dot-decimal first (`loadEntry` populates the field with
    /// dot-decimal text), then a locale-aware parse for locale keyboards.
    private var parsedAmount: Double? {
        let parsed = Double(amount.replacingOccurrences(of: ",", with: "."))
            ?? (try? Double(amount, format: .number))
        guard let value = parsed, value > 0 else { return nil }
        return value
    }

    private var currentDoseRange: DoseRange? {
        selectedSubstance?.doseRange(for: route, saltForm: saltForm)
    }

    /// Salt forms offered for the current route; the picker shows only when >1.
    private var currentSaltForms: [String] {
        selectedSubstance?.saltForms(for: route) ?? []
    }

    /// The user's input converted to the substance's native unit for accurate dose level comparison.
    private var normalizedAmount: Double? {
        guard let parsedAmount, let sub = selectedSubstance else { return parsedAmount }
        return sub.convert(amount: parsedAmount, from: unit, toRoute: route, saltForm: saltForm) ?? parsedAmount
    }

    private var currentDoseLevel: DoseLevel? {
        guard let normalizedAmount, let currentDoseRange else { return nil }
        return currentDoseRange.level(for: normalizedAmount)
    }

    // MARK: By-volume input

    /// Whether the selected substance offers by-volume dosing (alcohol).
    private var byVolumeAvailable: Bool {
        selectedSubstance?.byVolumeDosing != nil
    }

    /// Entered volume normalized to millilitres (the canonical unit the grams math
    /// works in), regardless of the display unit.
    private var enteredVolumeML: Double? {
        guard let v = Double(volumeText.replacingOccurrences(of: ",", with: ".")), v > 0 else { return nil }
        return Measurement(value: v, unit: volumeUnit).converted(to: .milliliters).value
    }

    private var enteredABV: Double? {
        guard let a = Double(abvText.replacingOccurrences(of: ",", with: ".")), a > 0 else { return nil }
        return a
    }

    /// Canonical grams for the current volume + strength, via the capability's own
    /// density. nil until both fields hold usable values.
    private var byVolumeGrams: Double? {
        guard let cap = selectedSubstance?.byVolumeDosing,
              let ml = enteredVolumeML, let abv = enteredABV else { return nil }
        let g = cap.canonicalAmount(volumeML: ml, strength: abv)
        return g > 0 ? g : nil
    }

    /// Trimmed drink name, nil when blank.
    private var trimmedDrinkName: String? {
        let t = drinkName.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private var worstSeverity: InteractionSeverity? {
        interactionWarnings.first?.severity
    }

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    if let combinedDepression, combinedDepression.hasMeaningfulLoad {
                        Section {
                            CombinedDepressionBanner(result: combinedDepression)
                        }
                    }

                    if !attenuations.isEmpty {
                        Section {
                            ForEach(attenuations) { attenuation in
                                EffectAttenuationBanner(result: attenuation)
                            }
                        }
                    }

                    if !crossTolerance.isEmpty {
                        Section {
                            ForEach(crossTolerance) { readout in
                                CrossToleranceBanner(readout: readout)
                            }
                        }
                    }

                    if !metabolicEffects.isEmpty {
                        Section {
                            ForEach(metabolicEffects) { effect in
                                MetabolicModulationBanner(effect: effect)
                            }
                        }
                    }

                    if !combinationMetabolites.isEmpty {
                        Section {
                            ForEach(combinationMetabolites) { formation in
                                CombinationMetaboliteBanner(formation: formation)
                            }
                        }
                    }

                    // Interaction warnings — shown at top
                    if !interactionWarnings.isEmpty {
                        Section {
                            ForEach(Array(interactionWarnings.enumerated()), id: \.offset) { _, warning in
                                InteractionWarningRow(warning: warning)
                            }
                        } header: {
                            Label(
                                interactionWarnings.count == 1 ? "Interaction Warning" : "\(interactionWarnings.count) Interaction Warnings",
                                systemImage: worstSeverity == .dangerous ? "exclamationmark.triangle.fill" : "exclamationmark.triangle",
                            )
                            .foregroundStyle((worstSeverity ?? .caution).color)
                        }
                    }

                    Section("Substance") {
                        SubstanceSearchField(text: $substance, locked: substanceLocked, favoriteNames: Array(favorites).favoriteSet) { selected in
                            selectSubstance(selected)
                        } onCustom: {
                            useCustomSubstance()
                        }
                        if selectedSubstance == nil, !substance.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "info.circle")
                                Text("Custom substance - enter dose details manually")
                            }
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryLabel)
                        }
                    }

                    Section("Dosage") {
                        if byVolumeAvailable {
                            Picker("Input", selection: $byVolumeMode) {
                                Text("By Drink").tag(true)
                                Text("By Weight").tag(false)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                        if byVolumeMode, let capability = selectedSubstance?.byVolumeDosing {
                            ByVolumeDoseInputView(
                                capability: capability,
                                volumeText: $volumeText,
                                abvText: $abvText,
                                volumeUnit: $volumeUnit,
                                grams: byVolumeGrams,
                                readoutColor: currentDoseLevel?.swiftUIColor,
                                name: $drinkName,
                                onSelectPreset: applyDrinkPreset,
                            )
                        } else {
                            HStack {
                                TextField("Amount", text: $amount)
                                    .keyboardType(.decimalPad)
                                    .focused($amountFocused)
                                    .foregroundStyle(currentDoseLevel?.swiftUIColor ?? .primary)
                                if let level = currentDoseLevel {
                                    DoseLevelBadge(level: level)
                                        .transition(.opacity.combined(with: .scale))
                                        .animation(.easeInOut(duration: 0.2), value: level)
                                }
                                Picker("Unit", selection: $unit) {
                                    ForEach(currentUnits, id: \.self) { Text($0) }
                                }
                                .labelsHidden()
                            }
                        }
                        Picker("Route", selection: $route) {
                            ForEach(availableRoutes) { r in
                                Text(r.localizedName).tag(r)
                            }
                        }
                        .onChange(of: route) {
                            SaltPicker.revalidate(&saltForm, against: currentSaltForms)
                            if let sub = selectedSubstance {
                                unit = sub.unit(for: route, saltForm: saltForm)
                            }
                        }
                        SaltPicker(forms: currentSaltForms, selection: $saltForm, style: .formRow)
                            .onChange(of: saltForm) {
                                if let sub = selectedSubstance {
                                    unit = sub.unit(for: route, saltForm: saltForm)
                                }
                            }
                    }

                    if let selectedSubstance {
                        Section("Dose Reference") {
                            DoseInfoView(
                                substance: selectedSubstance,
                                route: route,
                                saltForm: saltForm,
                                currentDose: normalizedAmount,
                            )
                            .padding(.vertical, 4)
                        }
                    }

                    Section("Timing") {
                        DatePicker("Date & Time", selection: $timestamp)
                    }

                    Section("Location") {
                        if let location {
                            HStack(spacing: 8) {
                                Image(systemName: "mappin.circle.fill")
                                    .foregroundStyle(Theme.accent)
                                Text(location.name)
                                Spacer()
                                Button {
                                    self.location = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(Theme.secondaryLabel)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text("Remove location"))
                            }
                            Button("Change Location") { showLocationPicker = true }
                        } else {
                            Button {
                                showLocationPicker = true
                            } label: {
                                Label("Add Location", systemImage: "mappin.and.ellipse")
                            }
                        }
                    }

                    Section("Notes") {
                        TextField("Notes", text: $notes, axis: .vertical)
                            .lineLimit(3 ... 6)
                    }

                    Section("Tags") {
                        TagEditorView(tags: $entryTags)
                    }
                }
                .listRowBackground(Theme.cardBackground)
            }
            .onChange(of: substance) { checkInteractions() }
            // Keep `amount`/`unit` (which drive the dose badge, dose reference, and
            // save path) in sync with the by-volume fields while in drink mode.
            .onChange(of: byVolumeGrams) { syncByVolumeAmount() }
            .onChange(of: byVolumeMode) { if byVolumeMode { syncByVolumeAmount() } }
            .onChange(of: volumeUnit) { old, new in
                ByVolumeDefaults.preferredVolumeUnit = new
                guard let v = Double(volumeText.replacingOccurrences(of: ",", with: ".")), v > 0 else { return }
                volumeText = ByVolumeDefaults.format(Measurement(value: v, unit: old).converted(to: new).value)
            }
            // Cross-tolerance + effect-attenuation need history beyond 48 h, so they run off the
            // synchronous interaction path and only re-run when the substance changes (not per keystroke).
            .task(id: isEditing ? "" : substance) { refreshPharmacologyReadouts() }
            .onChange(of: notes) {
                let extracted = TagExtractor.extractTags(from: notes)
                for tag in extracted where !entryTags.contains(tag) {
                    entryTags.append(tag)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(isEditing ? "Edit Entry" : "New Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { navigator.dismiss() } label: { Image(systemName: "xmark") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: { Image(systemName: "checkmark").fontWeight(.semibold) }
                        .disabled(substance.isEmpty || amount.isEmpty)
                }
            }
            .onAppear(perform: loadEntry)
            .sheet(isPresented: $showLocationPicker) {
                LocationPickerView { picked in location = picked }
            }
        }
    }

    private func useCustomSubstance() {
        selectedSubstance = nil
        availableRoutes = RouteOfAdministration.allCases
        byVolumeMode = false
        checkInteractions()
    }

    private func selectSubstance(_ sub: Substance) {
        selectedSubstance = sub
        route = sub.defaultRoute
        saltForm = sub.saltForms(for: sub.defaultRoute).first
        unit = sub.unit(for: sub.defaultRoute, saltForm: saltForm)
        availableRoutes = sub.orderedRoutes
        // Default a new alcohol entry to the natural by-volume input. Editing an
        // existing entry leaves the mode at its manual default (Stage 2 round-trips).
        byVolumeMode = !isEditing && sub.byVolumeDosing != nil
        checkInteractions()
    }

    /// Pre-fill the volume + strength from a tapped preset, converting the preset's
    /// canonical millilitres into the currently-selected display unit.
    private func applyDrinkPreset(_ preset: DrinkPreset) {
        volumeText = ByVolumeDefaults.format(preset.volume.converted(to: volumeUnit).value)
        abvText = ByVolumeDefaults.format(preset.defaultABV)
    }

    /// Push the computed by-volume grams into `amount`/`unit` so every downstream
    /// consumer (dose badge, dose reference, save) sees a normal gram dose.
    private func syncByVolumeAmount() {
        guard byVolumeMode else { return }
        unit = selectedSubstance?.byVolumeDosing?.canonicalUnit ?? "g"
        amount = byVolumeGrams.map { ByVolumeDefaults.format($0) } ?? ""
    }

    private func checkInteractions() {
        guard !substance.isEmpty, !isEditing else {
            interactionWarnings = []
            combinedDepression = nil
            return
        }
        let active = InteractionChecker.activeEntries(from: recentEntries)
        interactionWarnings = InteractionChecker.check(substance, against: active)

        // Combined CNS/respiratory-depression index over the active depressant stack + this dose.
        let prospective = DoseEntry(substance: substance, amount: parsedAmount ?? 0, unit: unit, route: route, timestamp: .now)
        let depression = CombinedDepression.analyze(entries: active + [prospective])
        combinedDepression = (depression?.totalCount ?? 0) >= 2 ? depression : nil
    }

    /// Pharmacology readouts that need history beyond the 48 h interaction window, computed off the
    /// synchronous interaction path and keyed on the substance alone (neither depends on the dose's
    /// amount): the cross-tolerance state, and the effect-attenuation blunting from blockers still
    /// pharmacologically onboard (half-life-gated, so a chronic SSRI taken days ago still counts).
    private func refreshPharmacologyReadouts() {
        guard !substance.isEmpty, !isEditing else {
            crossTolerance = []
            attenuations = []
            metabolicEffects = []
            combinationMetabolites = []
            return
        }
        crossTolerance = ToleranceStore.shared.crossToleranceReadouts(forSubstance: substance)

        // Metabolic modulation (Stage 4c, readout-only): co-active CYP inhibitors/inducers onboard, the
        // smoking profile flag, and the substance's own auto-modulation. Grapefruit is a per-dose flag
        // set in the quick-log tray, so it is not part of this form's banner.
        let coPresent = InteractionChecker.activeEntries(from: Array(recentEntries)).map(\.substance)
        let context = MetabolicModulation.Context(smokes: UserProfileStore.shared.smokesTobacco)
        metabolicEffects = MetabolicModulation.activeEffects(
            loggingSubstance: substance,
            coPresentSubstances: coPresent,
            context: context,
        )

        // Combination-generated active species (Stage 4d): gated on the precursors being concurrently
        // onboard (the prospective dose + what `activeEntries` says is still active). v1 = cocaethylene.
        combinationMetabolites = CombinationMetabolite.formed(among: [substance] + coPresent)

        // A 30-day window covers even long-half-life antidepressants (norfluoxetine), then the half-life
        // presence gate in `EffectAttenuation` decides what is still onboard.
        let cutoff = Date.now.addingTimeInterval(-30 * 86_400)
        let descriptor = FetchDescriptor<DoseEntry>(predicate: #Predicate<DoseEntry> { $0.timestamp >= cutoff })
        let history = (try? modelContext.fetch(descriptor)) ?? []
        let prospective = DoseEntry(substance: substance, amount: 1, unit: unit, route: route, timestamp: .now)
        attenuations = EffectAttenuation.analyze(entries: history + [prospective])
    }

    private func loadEntry() {
        if let entry {
            substance = entry.substance
            amount = String(entry.amount)
            unit = entry.unit
            route = entry.route
            saltForm = entry.saltForm
            timestamp = entry.timestamp
            notes = entry.notes ?? ""
            entryTags = entry.tags
            if let name = entry.locationName, let lat = entry.latitude, let lng = entry.longitude {
                location = PickedLocation(name: name, latitude: lat, longitude: lng)
            }

            if let match = SubstanceLibrary.search(entry.substance).first,
               match.name.lowercased() == entry.substance.lowercased() {
                selectedSubstance = match
                availableRoutes = match.orderedRoutes

                // By-volume round-trip: if this entry was logged by volume, restore
                // the drink-mode fields from the notes breadcrumb and hide it from
                // the visible note. On save the breadcrumb is regenerated, so it
                // never duplicates.
                if match.byVolumeDosing != nil, let ml = entry.volumeML, let abv = entry.abv {
                    byVolumeMode = true
                    // Display the stored millilitres in the current unit without
                    // mutating `volumeUnit` (which would fire the conversion
                    // onChange on the already-seeded text).
                    volumeText = ByVolumeDefaults.format(
                        Measurement(value: ml, unit: .milliliters).converted(to: volumeUnit).value,
                    )
                    abvText = ByVolumeDefaults.format(abv)
                    drinkName = entry.drinkName ?? ""
                }
            }
            return
        }

        if let prefillName = prefillSubstanceName, !prefillName.isEmpty {
            substance = prefillName
            if let match = SubstanceLibrary.search(prefillName).first,
               match.name.lowercased() == prefillName.lowercased() {
                selectSubstance(match)
            }
            if let r = prefillRoute { route = r }
            if let u = prefillUnit { unit = u }
            substanceLocked = true
            checkInteractions()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                amountFocused = true
            }
        }
    }

    private func hasColor(for name: String) -> Bool {
        Array(substanceColors).hasColor(for: name)
    }

    /// Persist the substance's stable deterministic colour if it has none yet,
    /// so a first-time substance is coloured the moment it's saved — no extra
    /// picker step. Editable later from the entry detail's colour picker.
    private func ensureColor(for name: String) {
        guard !hasColor(for: name) else { return }
        modelContext.insert(SubstanceColor(substance: name, hexColor: PresetColor.deterministic(for: name).hex))
    }

    private func save() {
        guard let parsedAmount else { return }

        // If the user picked a colloquial alias (e.g. "drink" for alcohol),
        // normalise to the canonical physical unit at save time so cumulative
        // dose, dose-level chips, and PK scaling all see the right number.
        let (storedAmount, storedUnit): (Double, String) = {
            if let sub = selectedSubstance,
               let alias = sub.unitAliases.first(where: { $0.label == unit }) {
                return (parsedAmount * alias.amountPerUnit, alias.unit)
            }
            return (parsedAmount, unit)
        }()

        let finalNotes: String? = notes.isEmpty ? nil : notes
        // By-volume metadata (alcohol logged as a drink) — stored structured
        // alongside the canonical grams, or cleared when not in drink mode.
        let byVolume = byVolumeMode ? (enteredVolumeML, enteredABV, trimmedDrinkName) : (nil, nil, nil)

        if let entry {
            let previousTimestamp = entry.timestamp
            let previousSubstanceName = entry.substance
            entry.substance = substance
            entry.amount = storedAmount
            entry.unit = storedUnit
            entry.route = route
            entry.saltForm = saltForm
            entry.timestamp = timestamp
            entry.notes = finalNotes
            entry.volumeML = byVolume.0
            entry.abv = byVolume.1
            entry.drinkName = byVolume.2
            let allTags = Array(Set(entryTags + TagExtractor.extractTags(from: notes)))
            entry.tags = allTags
            entry.locationName = location?.name
            entry.latitude = location?.latitude
            entry.longitude = location?.longitude

            // The session accessory & Live Activity read from ActiveSessionManager's
            // snapshot, not SwiftData — without this, the bottom mini-graph keeps
            // showing the dose's pre-edit time/amount.
            let colorHex = SubstancePalette.hex(for: substance, hexMap: Array(substanceColors).hexColorMap)
            ActiveSessionManager.shared.updateDose(
                previousSubstanceName: previousSubstanceName,
                previousTimestamp: previousTimestamp,
                entry: entry,
                substance: selectedSubstance,
                colorHex: colorHex,
                allColors: Array(substanceColors),
            )

            // Pending reminders are keyed to the old timestamp — a moved dose
            // must drop them and reschedule from its new time.
            DoseNotificationManager.doseRescheduled(
                entry: entry,
                previousTimestamp: previousTimestamp,
                recentEntries: Array(recentEntries),
            )
        } else {
            let allTags = Array(Set(entryTags + TagExtractor.extractTags(from: notes)))
            let newEntry = DoseEntry(
                substance: substance,
                amount: storedAmount,
                unit: storedUnit,
                route: route,
                saltForm: saltForm,
                timestamp: timestamp,
                notes: finalNotes,
                tags: allTags,
                locationName: location?.name,
                latitude: location?.latitude,
                longitude: location?.longitude,
                volumeML: byVolume.0,
                abv: byVolume.1,
                drinkName: byVolume.2,
            )
            modelContext.insert(newEntry)
            SessionService.assignSession(for: newEntry, in: modelContext)
            QuickLogManager.record(substance: substance, route: route, amount: storedAmount, unit: storedUnit, fixedOrder: quickLogFixedOrder, context: modelContext)
            savedEntry = newEntry

            // Schedule wellness notifications & check cumulative dose
            DoseNotificationManager.doseLogged(entry: newEntry, recentEntries: Array(recentEntries))
        }

        InventoryService.recomputeAll(in: modelContext)
        WidgetCenter.shared.reloadAllTimelines()

        // Auto-assign a stable palette colour for a brand-new substance up front
        // (the same colour the graph already uses), so the live activity and
        // journal pick it up immediately — no follow-up colour-picker sheet.
        ensureColor(for: substance)

        // Add to the active session immediately, now that the colour exists.
        startLiveActivityIfNeeded()

        // A new-entry save completes the logging flow that may span multiple
        // sheets (e.g. QuickLog → "From Library" → EntryForm). Dismiss the
        // entire stack so the user lands back at root. An edit, by contrast,
        // should return to wherever the form was opened from.
        if entry == nil {
            navigator.dismissAll()
        } else {
            navigator.dismiss()
        }
    }

    private func startLiveActivityIfNeeded() {
        guard let savedEntry, entry == nil else { return }
        let colorHex = SubstancePalette.hex(for: savedEntry.substance, hexMap: Array(substanceColors).hexColorMap)

        ActiveSessionManager.shared.addDose(
            entry: savedEntry,
            substance: selectedSubstance,
            colorHex: colorHex,
            allColors: Array(substanceColors),
        )
    }
}

// MARK: - Interaction Warning Row

struct InteractionWarningRow: View {
    let warning: InteractionResult

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Fixed 16pt column — in the dose tray this puts the icon on the
            // same vertical line as the row chevrons and the add-more plus.
            Image(systemName: warning.severity == .dangerous ? "exclamationmark.triangle.fill" : "exclamationmark.triangle")
                .foregroundStyle(warning.severity.labelColor)
                .font(.body)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("\(warning.severity.label): \(warning.substanceA) + \(warning.substanceB)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(warning.severity.labelColor)
                    if warning.source != .classRule {
                        Text(warning.source.label)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(warning.severity.color.opacity(0.15), in: Capsule())
                            .foregroundStyle(warning.severity.labelColor)
                    }
                }
                Text(warning.description)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
