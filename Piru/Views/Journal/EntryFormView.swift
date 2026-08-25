import ActivityKit
import SwiftData
import SwiftUI
import WidgetKit

struct EntryFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appNavigator) private var navigator

    var entry: DoseEntry?

    @State private var substance = ""
    /// The brand picked from search this session ("Concerta"), if any — so an edit
    /// that re-selects a product keeps it. `nil` until the user picks from search;
    /// the original ``entry`` product then still applies (see
    /// ``resolvedProductAndRelease(previousSubstanceName:)``).
    @State private var typedProductName: String?
    @State private var amount = ""
    @State private var unit = "mg"
    @State private var route: RouteOfAdministration = .oral
    /// Selected salt/ester form; `nil` unless the substance offers a choice.
    @State private var saltForm: String?
    @State private var isomer: String?
    @State private var timestamp = Date.now
    @State private var notes = ""
    @State private var entryTags: [String] = []
    @State private var location: PickedLocation?
    @State private var showLocationPicker = false
    @State private var isApproximate = false

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
    @State private var substanceLocked = false
    @FocusState private var amountFocused: Bool

    @AppStorage(QuickLogManager.fixedOrderDefaultsKey) private var quickLogFixedOrder = false

    @Query private var substanceColors: [SubstanceColor]
    /// Last 48 h of doses — feeds the harm-reduction reminder (re)scheduling on save.
    @Query private var recentEntries: [DoseEntry]
    @Query private var favorites: [FavoriteSubstance]

    init(entry: DoseEntry) {
        self.entry = entry
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
        selectedSubstance?.doseRange(for: route, saltForm: saltForm, isomer: isomer)
    }

    /// Salt forms offered for the current route; the picker shows only when >1.
    private var currentSaltForms: [String] {
        selectedSubstance?.saltForms(for: route) ?? []
    }

    /// Named isomer options for the current route; the picker shows only when >1.
    private var currentIsomerOptions: [IsomerPicker.Option] {
        (selectedSubstance?.isomerOptions(for: route) ?? []).map {
            IsomerPicker.Option(code: $0.code, displayName: $0.displayName)
        }
    }

    /// The form the edited name denotes, preserving the product the dose was
    /// logged under when the edit didn't rename it.
    ///
    /// `substance` here is the user's raw field text, not a canonical name — so a
    /// dose logged as Concerta stores `substance: "Methylphenidate"` and asking
    /// *that* about a release form answers `nil`, silently stripping the XR and
    /// handing the dose back its immediate-release curve. The product name is the
    /// only record of the form, so it has to be consulted first. Renaming the
    /// substance does drop it: the dose is no longer that product, and the new
    /// string re-derives its own facet (typing "Concerta" still yields XR).
    private func resolvedProductAndRelease(previousSubstanceName: String?) -> (product: String?, release: String?) {
        let renamed = previousSubstanceName?.lowercased() != substance.lowercased()
        // A brand picked from search this edit wins; otherwise keep the original
        // product unless the substance was renamed (a rename drops it — the dose is
        // no longer that product, and the new name re-derives its own facet).
        let product = typedProductName ?? (renamed ? nil : entry?.productName)
        return (product, SubstanceLibrary.releaseForm(for: product ?? substance))
    }

    /// The composed form title to snapshot — see ``DoseTitle/snapshot(canonicalName:isomer:releaseForm:)``.
    private func formDisplayNameSnapshot(release: String?) -> String? {
        DoseTitle.snapshot(canonicalName: substance, isomer: isomer, releaseForm: release)
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

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section("Substance") {
                        SubstanceSearchField(text: $substance, locked: substanceLocked, favoriteNames: Array(favorites).favoriteSet) { selected, product in
                            selectSubstance(selected, product: product)
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
                        Toggle(isOn: $isApproximate) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Approximate amount")
                                Text("Shows the dose with a ~; the estimate still drives the curves.")
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryLabel)
                            }
                        }
                        Picker("Route", selection: $route) {
                            ForEach(availableRoutes) { r in
                                Text(r.localizedName).tag(r)
                            }
                        }
                        .onChange(of: route) {
                            SaltPicker.revalidate(&saltForm, against: currentSaltForms)
                            IsomerPicker.revalidate(&isomer, against: currentIsomerOptions)
                            if let sub = selectedSubstance {
                                unit = sub.unit(for: route, saltForm: saltForm, isomer: isomer)
                            }
                        }
                        SaltPicker(forms: currentSaltForms, selection: $saltForm, style: .formRow)
                            .onChange(of: saltForm) {
                                if let sub = selectedSubstance {
                                    unit = sub.unit(for: route, saltForm: saltForm, isomer: isomer)
                                }
                            }
                        IsomerPicker(options: currentIsomerOptions, selection: $isomer, style: .formRow)
                            .onChange(of: isomer) {
                                if let sub = selectedSubstance {
                                    unit = sub.unit(for: route, saltForm: saltForm, isomer: isomer)
                                }
                            }
                    }

                    if let selectedSubstance {
                        Section("Dose Reference") {
                            DoseInfoView(
                                substance: selectedSubstance,
                                route: route,
                                saltForm: saltForm,
                                isomer: isomer,
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
                .listRowBackground(CardBackground())
            }
            // Keep `amount`/`unit` (which drive the dose badge, dose reference, and
            // save path) in sync with the by-volume fields while in drink mode.
            .onChange(of: byVolumeGrams) { syncByVolumeAmount() }
            .onChange(of: byVolumeMode) { if byVolumeMode { syncByVolumeAmount() } }
            .onChange(of: volumeUnit) { old, new in
                ByVolumeDefaults.preferredVolumeUnit = new
                guard let v = Double(volumeText.replacingOccurrences(of: ",", with: ".")), v > 0 else { return }
                volumeText = ByVolumeDefaults.format(Measurement(value: v, unit: old).converted(to: new).value)
            }
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
    }

    private func selectSubstance(_ sub: Substance, product: String? = nil) {
        // The search field's result comes straight from the ranked index, which
        // skips the custom overlay — re-resolve through the façade so user edits
        // and custom units ride along in the unit picker.
        let sub = SubstanceLibrary.resolveFull(sub.name) ?? sub
        selectedSubstance = sub
        let trimmed = product?.trimmingCharacters(in: .whitespaces)
        typedProductName = (trimmed?.isEmpty == false) ? trimmed : nil
        route = sub.defaultRoute
        saltForm = sub.saltForms(for: sub.defaultRoute).first
        // Seed the enantiomer the product names (a "Focalin" pick → D) rather than
        // the racemic default, mirroring the quick-log tray's `seedIsomer`.
        isomer = DoseTrayModel.seedIsomer(productName: typedProductName, librarySubstance: sub, route: sub.defaultRoute)
        unit = sub.unit(for: sub.defaultRoute, saltForm: saltForm, isomer: isomer)
        availableRoutes = sub.orderedRoutes
        // Default a new alcohol entry to the natural by-volume input. Editing an
        // existing entry leaves the mode at its manual default (Stage 2 round-trips).
        byVolumeMode = !isEditing && sub.byVolumeDosing != nil
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

    private func loadEntry() {
        if let entry {
            substance = entry.substance
            // Match EntryDraft.begin(from:): a whole-number amount renders "50", not "50.0".
            amount = entry.amount == entry.amount.rounded()
                ? String(Int(entry.amount))
                : String(entry.amount)
            unit = entry.unit
            route = entry.route
            saltForm = entry.saltForm
            isomer = entry.isomer
            timestamp = entry.timestamp
            notes = entry.notes ?? ""
            entryTags = entry.tags
            isApproximate = entry.isApproximate
            if let name = entry.locationName, let lat = entry.latitude, let lng = entry.longitude {
                location = PickedLocation(name: name, latitude: lat, longitude: lng)
            }

            if let match = SubstanceLibrary.lookup(entry.substance),
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
        }
    }

    private func hasColor(for name: String) -> Bool {
        Array(substanceColors).hasColor(for: name)
    }

    /// Persist the substance's stable deterministic color if it has none yet,
    /// so a first-time substance is colored the moment it's saved — no extra
    /// picker step. Editable later from the entry detail's color picker.
    private func ensureColor(for name: String) {
        guard !hasColor(for: name) else { return }
        modelContext.insert(SubstanceColor(substance: name, hexColor: PresetColor.deterministic(for: name).hex))
    }

    private func save() {
        guard let parsedAmount else { return }

        // If the user picked a colloquial alias (e.g. "drink" for alcohol),
        // normalize to the canonical physical unit at save time so cumulative
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

        // An edit can move the dose between substances; the deferred inventory
        // recompute must touch both the old and the new one.
        var editedPreviousSubstance: String?

        if let entry {
            let previousTimestamp = entry.timestamp
            let previousSubstanceName = entry.substance
            editedPreviousSubstance = previousSubstanceName
            entry.substance = substance
            entry.amount = storedAmount
            entry.unit = storedUnit
            entry.route = route
            entry.saltForm = saltForm
            entry.isomer = isomer
            // Re-derived, so renaming an entry off (or onto) a release-form brand
            // doesn't leave the old facet behind — while an edit that *didn't*
            // rename it keeps the product it was logged under.
            let form = resolvedProductAndRelease(previousSubstanceName: previousSubstanceName)
            entry.productName = form.product
            entry.releaseForm = form.release
            entry.substanceUID = selectedSubstance?.substanceUID
            entry.displayNameSnapshot = formDisplayNameSnapshot(release: form.release)
            entry.timestamp = timestamp
            entry.isApproximate = isApproximate
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
            // A new entry has no prior name, so nothing to preserve: the facet comes
            // from whatever the user typed.
            let release = SubstanceLibrary.releaseForm(for: substance)
            let newEntry = DoseEntry(
                substance: substance,
                amount: storedAmount,
                unit: storedUnit,
                route: route,
                saltForm: saltForm,
                isomer: isomer,
                // Derived from the name (no picker — see `DoseEntry.releaseForm`),
                // and recorded here because a committed dose gets its uid at log
                // time and so is never revisited by the backfill.
                releaseForm: release,
                substanceUID: selectedSubstance?.substanceUID,
                displayNameSnapshot: formDisplayNameSnapshot(release: release),
                timestamp: timestamp,
                notes: finalNotes,
                tags: allTags,
                locationName: location?.name,
                latitude: location?.latitude,
                longitude: location?.longitude,
                isApproximate: isApproximate,
                volumeML: byVolume.0,
                abv: byVolume.1,
                drinkName: byVolume.2,
            )
            modelContext.insert(newEntry)
            SessionService.assignSession(for: newEntry, in: modelContext)
            QuickLogManager.record(substance: substance, route: route, amount: storedAmount, unit: storedUnit, fixedOrder: quickLogFixedOrder, context: modelContext)
            savedEntry = newEntry
        }

        // Auto-assign a stable palette color for a brand-new substance up front
        // (the same color the graph already uses), so the live activity and
        // journal pick it up immediately — no follow-up color-picker sheet.
        ensureColor(for: substance)

        // Add to the active session immediately, now that the color exists.
        startLiveActivityIfNeeded()

        // Wake the derived caches (tolerance engine) — debounced + recomputed off-main.
        DoseLogService.shared.changed()

        // Defer the non-visible bookkeeping (scoped inventory recompute, harm-
        // reduction notifications, one widget reload) past the dismissal so it
        // never drops frames on the slide-down. A new dose fires its wellness
        // notifications here; an edit only needs the inventory/widget refresh —
        // its reminders were rescheduled immediately above.
        let isNewEntry = entry == nil
        let notifyEntry = savedEntry
        let recents = Array(recentEntries)
        var affected: Set<String> = [substance]
        if let editedPreviousSubstance { affected.insert(editedPreviousSubstance) }
        DoseLogService.shared.scheduleDeferredBookkeeping(forSubstances: affected, in: modelContext) {
            if isNewEntry, let notifyEntry {
                DoseNotificationManager.doseLogged(entry: notifyEntry, recentEntries: recents, in: modelContext)
            }
        }

        // A new-entry save completes the logging flow that may span multiple
        // sheets (e.g. QuickLog → "From Library" → EntryForm). Dismiss the
        // entire stack so the user lands back at root. An edit, by contrast,
        // should return to wherever the form was opened from.
        if isNewEntry {
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
                Text("\(warning.severity.label): \(warning.substanceA) + \(warning.substanceB)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(warning.severity.labelColor)
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
