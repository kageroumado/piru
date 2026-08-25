import SwiftUI

/// Create/edit a net-new custom substance, or *personalize* a shipped one.
///
/// When `personalizing` is set, the form edits a personal override of that
/// library substance: the canonical `name` is fixed (it stays the logging/lookup
/// identity), a "Display as" field relabels it everywhere, and the dose / duration
/// / half-life fields pre-fill from the shipped values so the user edits from real
/// numbers. Both modes persist a `CustomSubstanceEntry` (keyed by canonical name).
struct CustomSubstanceFormView: View {
    /// Presented as a *local* sheet (quick-log search, custom list) as well as
    /// a navigator route — the environment dismiss targets whichever
    /// presentation actually owns it, where `navigator.dismiss()` would pop
    /// the navigator's top sheet out from under a local one.
    @Environment(\.dismiss) private var dismiss
    @State private var store = CustomSubstanceStore.shared

    var existing: CustomSubstanceEntry?
    /// The shipped substance being personalized. Nil for net-new customs.
    var personalizing: Substance?
    var onSaved: ((CustomSubstanceEntry) -> Void)?

    @State private var name: String
    @State private var displayName: String
    @State private var category: SubstanceCategory
    @State private var defaultRoute: RouteOfAdministration
    @State private var unit: String
    @State private var notes: String

    // Dose tiers — nil means "leave blank / keep library value"
    @State private var threshold: Double?
    @State private var lightMin: Double?
    @State private var lightMax: Double?
    @State private var commonMin: Double?
    @State private var commonMax: Double?
    @State private var strongMin: Double?
    @State private var strongMax: Double?
    @State private var heavy: Double?

    @State private var halfLifeMinutes: Double?

    @State private var hasDuration: Bool
    @State private var onsetMin: Double?
    @State private var onsetMax: Double?
    @State private var comeupMin: Double?
    @State private var comeupMax: Double?
    @State private var peakMin: Double?
    @State private var peakMax: Double?
    @State private var offsetMin: Double?
    @State private var offsetMax: Double?
    @State private var showDuplicateAlert = false

    private var isEditing: Bool {
        existing != nil
    }
    private var isPersonalizing: Bool {
        personalizing != nil
    }

    init(
        existing: CustomSubstanceEntry? = nil,
        initialName: String? = nil,
        personalizing: Substance? = nil,
        onSaved: ((CustomSubstanceEntry) -> Void)? = nil,
    ) {
        self.existing = existing
        self.personalizing = personalizing
        self.onSaved = onSaved

        // Shipped route to seed personalize defaults from.
        let baseRoute = personalizing.flatMap { sub in
            sub.routes.first { $0.route == sub.defaultRoute } ?? sub.routes.first
        }

        _name = State(initialValue: personalizing?.name ?? existing?.name ?? initialName ?? "")
        _displayName = State(initialValue: existing?.displayName ?? "")
        _category = State(initialValue: existing?.category ?? personalizing?.category ?? .other)
        _defaultRoute = State(initialValue: existing?.defaultRoute ?? personalizing?.defaultRoute ?? .oral)
        _unit = State(initialValue: existing?.unit ?? baseRoute?.unit ?? "mg")
        _notes = State(initialValue: existing?.notes ?? "")

        let doses = existing?.doses ?? (existing == nil ? baseRoute?.doses : nil)
        _threshold = State(initialValue: Self.positive(doses?.threshold))
        _lightMin = State(initialValue: Self.positive(doses?.light?.lowerBound))
        _lightMax = State(initialValue: Self.positive(doses?.light?.upperBound))
        _commonMin = State(initialValue: Self.positive(doses?.common?.lowerBound))
        _commonMax = State(initialValue: Self.positive(doses?.common?.upperBound))
        _strongMin = State(initialValue: Self.positive(doses?.strong?.lowerBound))
        _strongMax = State(initialValue: Self.positive(doses?.strong?.upperBound))
        _heavy = State(initialValue: Self.positive(doses?.heavy))

        let halfLife = existing?.halfLifeMinutes ?? (existing == nil ? personalizing?.halfLifeMinutes : nil)
        _halfLifeMinutes = State(initialValue: Self.positive(halfLife))

        let duration = existing?.duration ?? (existing == nil ? baseRoute?.duration : nil)
        _hasDuration = State(initialValue: duration != nil)
        _onsetMin = State(initialValue: Self.positive(duration?.onset?.min))
        _onsetMax = State(initialValue: Self.positive(duration?.onset?.max))
        _comeupMin = State(initialValue: Self.positive(duration?.comeup?.min))
        _comeupMax = State(initialValue: Self.positive(duration?.comeup?.max))
        _peakMin = State(initialValue: Self.positive(duration?.peak?.min))
        _peakMax = State(initialValue: Self.positive(duration?.peak?.max))
        _offsetMin = State(initialValue: Self.positive(duration?.offset?.min))
        _offsetMax = State(initialValue: Self.positive(duration?.offset?.max))
    }

    /// Non-positive shipped values render as an empty field, matching the
    /// old "blank means unset" semantics.
    private static func positive(_ value: Double?) -> Double? {
        guard let value, value > 0 else { return nil }
        return value
    }

    private var unitLabel: String {
        unit.trimmingCharacters(in: .whitespaces).isEmpty ? "mg" : unit
    }

    // MARK: - Rows

    private func rangeRow(_ label: LocalizedStringResource, min: Binding<Double?>, max: Binding<Double?>, suffix: LocalizedStringResource) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("min", value: min, format: .number)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 56)
            Text("–").foregroundStyle(Theme.secondaryLabel)
                .accessibilityHidden(true)
            TextField("max", value: max, format: .number)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 56)
            Text(suffix).foregroundStyle(Theme.secondaryLabel)
        }
    }

    private func singleRow(_ label: LocalizedStringResource, value: Binding<Double?>, suffix: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("amount", value: value, format: .number)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 56)
            Text(suffix).foregroundStyle(Theme.secondaryLabel)
        }
    }

    // MARK: - Builders

    private func buildDoses() -> DoseRange? {
        func val(_ v: Double?) -> Double? {
            guard let v, v > 0 else { return nil }
            return v
        }
        func range(_ lo: Double?, _ hi: Double?) -> ClosedRange<Double>? {
            guard let l = val(lo) else { return nil }
            let h = val(hi) ?? l
            guard h >= l else { return nil }
            return l ... h
        }
        let dr = DoseRange(
            threshold: val(threshold),
            light: range(lightMin, lightMax),
            common: range(commonMin, commonMax),
            strong: range(strongMin, strongMax),
            heavy: val(heavy),
        )
        return dr.hasAnyValue ? dr : nil
    }

    private func buildDuration() -> DurationProfile? {
        guard hasDuration else { return nil }
        func range(_ min: Double?, _ max: Double?) -> DurationRange? {
            guard let lo = min, lo > 0 else { return nil }
            let hi = max ?? lo
            guard hi >= lo else { return nil }
            return DurationRange(min: lo, max: hi)
        }
        let onset = range(onsetMin, onsetMax)
        let comeup = range(comeupMin, comeupMax)
        let peak = range(peakMin, peakMax)
        let offset = range(offsetMin, offsetMax)
        guard onset != nil || comeup != nil || peak != nil || offset != nil else { return nil }
        return DurationProfile(onset: onset, comeup: comeup, peak: peak, offset: offset, afterglow: nil, total: nil)
    }

    private func buildHalfLife() -> Double? {
        guard let v = halfLifeMinutes, v > 0 else { return nil }
        return v
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                if isPersonalizing {
                    Section {
                        LabeledContent("Substance", value: name)
                        TextField("Display as (e.g. joint)", text: $displayName)
                            .autocorrectionDisabled()
                    } header: {
                        Text("Display name")
                    } footer: {
                        Text("Shown everywhere in place of \"\(name)\". Leave blank to keep the original name. Your dose history is unaffected.")
                    }
                } else {
                    Section("Name") {
                        TextField("Substance name", text: $name)
                            .autocorrectionDisabled()
                    }
                }

                Section("Classification") {
                    Picker("Category", selection: $category) {
                        ForEach(SubstanceCategory.allCases) { cat in
                            Label(cat.displayName, systemImage: cat.icon).tag(cat)
                        }
                    }
                }

                Section("Dosing Defaults") {
                    Picker("Default Route", selection: $defaultRoute) {
                        ForEach(RouteOfAdministration.allCases) { route in
                            Text(route.localizedName).tag(route)
                        }
                    }
                    TextField("Unit (e.g. mg, ml, µg)", text: $unit)
                        .autocorrectionDisabled()
                }

                Section {
                    singleRow("Threshold", value: $threshold, suffix: unitLabel)
                    rangeRow("Light", min: $lightMin, max: $lightMax, suffix: "\(unitLabel)")
                    rangeRow("Common", min: $commonMin, max: $commonMax, suffix: "\(unitLabel)")
                    rangeRow("Strong", min: $strongMin, max: $strongMax, suffix: "\(unitLabel)")
                    singleRow("Heavy", value: $heavy, suffix: unitLabel)
                } header: {
                    Text("Dose Ranges")
                } footer: {
                    Text("Optional dose tiers, in your chosen unit. Leave blank to keep the library values.")
                }

                Section {
                    HStack {
                        Text("Half-life")
                        Spacer()
                        TextField("minutes", value: $halfLifeMinutes, format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
                        Text("minutes").foregroundStyle(Theme.secondaryLabel)
                    }
                } header: {
                    Text("Half-life")
                } footer: {
                    Text("Optional. Feeds the active-substance and clearance estimates.")
                }

                Section {
                    Toggle("Custom duration", isOn: $hasDuration.animation())
                    if hasDuration {
                        rangeRow("Onset", min: $onsetMin, max: $onsetMax, suffix: "minutes")
                        rangeRow("Come-up", min: $comeupMin, max: $comeupMax, suffix: "minutes")
                        rangeRow("Peak", min: $peakMin, max: $peakMax, suffix: "minutes")
                        rangeRow("Offset", min: $offsetMin, max: $offsetMax, suffix: "minutes")
                    }
                } header: {
                    Text("Duration")
                } footer: {
                    Text(
                        hasDuration
                            ? "Minutes for each phase. Leave a phase blank to skip it; the timeline will interpolate from what you provide."
                            : "Add per-phase timing so this substance gets a Live-Activity timeline like library substances.",
                    )
                }

                Section {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3 ... 6)
                } header: {
                    Text("Notes")
                } footer: {
                    Text("Optional notes about this substance for your reference.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                    .accessibilityLabel(isEditing || isPersonalizing ? "Save" : "Add")
                }
            }
            .alert("Duplicate Name", isPresented: $showDuplicateAlert) {
                Button("OK") {}
            } message: {
                Text("A custom substance named \"\(name.trimmingCharacters(in: .whitespaces))\" already exists.")
            }
        }
    }

    private var navTitle: LocalizedStringResource {
        if isPersonalizing { return "Personalize" }
        return isEditing ? "Edit Substance" : "New Custom Substance"
    }

    // MARK: - Save

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        let trimmedDisplay = displayName.trimmingCharacters(in: .whitespaces)

        let saved: CustomSubstanceEntry

        if isPersonalizing {
            // Personalize mode: the entry is keyed by the canonical name. Update
            // an existing override or create one; never a rename, so no collision.
            var entry = existing ?? CustomSubstanceEntry(name: trimmedName)
            entry.name = trimmedName
            entry.displayName = trimmedDisplay.isEmpty ? nil : trimmedDisplay
            entry.category = category
            entry.defaultRoute = defaultRoute
            entry.unit = unit
            entry.notes = notes
            entry.doses = buildDoses()
            entry.duration = buildDuration()
            entry.halfLifeMinutes = buildHalfLife()
            if existing != nil { store.update(entry) } else { store.add(entry) }
            saved = entry
        } else if let existing {
            // Editing a net-new custom: allow rename unless it collides.
            if let collision = store.first(whereName: trimmedName), collision.id != existing.id {
                showDuplicateAlert = true
                return
            }
            var updated = existing
            updated.name = trimmedName
            updated.displayName = trimmedDisplay.isEmpty ? nil : trimmedDisplay
            updated.category = category
            updated.defaultRoute = defaultRoute
            updated.unit = unit
            updated.notes = notes
            updated.doses = buildDoses()
            updated.duration = buildDuration()
            updated.halfLifeMinutes = buildHalfLife()
            store.update(updated)
            saved = updated
        } else {
            if store.contains(name: trimmedName) {
                showDuplicateAlert = true
                return
            }
            let entry = CustomSubstanceEntry(
                name: trimmedName,
                displayName: trimmedDisplay.isEmpty ? nil : trimmedDisplay,
                category: category,
                defaultRoute: defaultRoute,
                unit: unit,
                notes: notes,
                doses: buildDoses(),
                duration: buildDuration(),
                halfLifeMinutes: buildHalfLife(),
            )
            store.add(entry)
            saved = entry
        }

        onSaved?(saved)
        dismiss()
    }
}
