import SwiftUI

/// The form's edit state: one draft object instead of two dozen `@State`
/// fields, so the view is a thin renderer and the seeding / validation /
/// build logic is testable in one place. Mirrors `MedFormDraft` /
/// `EntryDraft`. Seeded once in `init` (held via `State(initialValue:)`,
/// so it resets with the sheet's identity, matching form semantics).
@Observable @MainActor
private final class CustomSubstanceDraft {
    /// Dose tiers — nil means "leave blank / keep library value".
    struct DoseTierFields {
        var threshold: Double?
        var lightMin: Double?
        var lightMax: Double?
        var commonMin: Double?
        var commonMax: Double?
        var strongMin: Double?
        var strongMax: Double?
        var heavy: Double?
    }

    struct DurationFields {
        var hasDuration = false
        var onsetMin: Double?
        var onsetMax: Double?
        var comeupMin: Double?
        var comeupMax: Double?
        var peakMin: Double?
        var peakMax: Double?
        var offsetMin: Double?
        var offsetMax: Double?
    }

    var name: String
    var displayName: String
    var category: SubstanceCategory
    var defaultRoute: RouteOfAdministration
    var unit: String
    var notes: String
    var doses = DoseTierFields()
    var halfLifeMinutes: Double?
    var duration = DurationFields()

    init(existing: CustomSubstanceEntry?, initialName: String?, personalizing: Substance?) {
        // Shipped route to seed personalize defaults from.
        let baseRoute = personalizing.flatMap { sub in
            sub.routes.first { $0.route == sub.defaultRoute } ?? sub.routes.first
        }

        name = personalizing?.name ?? existing?.name ?? initialName ?? ""
        displayName = existing?.displayName ?? ""
        category = existing?.category ?? personalizing?.category ?? .other
        defaultRoute = existing?.defaultRoute ?? personalizing?.defaultRoute ?? .oral
        unit = existing?.unit ?? baseRoute?.unit ?? "mg"
        notes = existing?.notes ?? ""

        let seedDoses = existing?.doses ?? (existing == nil ? baseRoute?.doses : nil)
        doses.threshold = Self.positive(seedDoses?.threshold)
        doses.lightMin = Self.positive(seedDoses?.light?.lowerBound)
        doses.lightMax = Self.positive(seedDoses?.light?.upperBound)
        doses.commonMin = Self.positive(seedDoses?.common?.lowerBound)
        doses.commonMax = Self.positive(seedDoses?.common?.upperBound)
        doses.strongMin = Self.positive(seedDoses?.strong?.lowerBound)
        doses.strongMax = Self.positive(seedDoses?.strong?.upperBound)
        doses.heavy = Self.positive(seedDoses?.heavy)

        let halfLife = existing?.halfLifeMinutes ?? (existing == nil ? personalizing?.halfLifeMinutes : nil)
        halfLifeMinutes = Self.positive(halfLife)

        let seedDuration = existing?.duration ?? (existing == nil ? baseRoute?.duration : nil)
        duration.hasDuration = seedDuration != nil
        duration.onsetMin = Self.positive(seedDuration?.onset?.min)
        duration.onsetMax = Self.positive(seedDuration?.onset?.max)
        duration.comeupMin = Self.positive(seedDuration?.comeup?.min)
        duration.comeupMax = Self.positive(seedDuration?.comeup?.max)
        duration.peakMin = Self.positive(seedDuration?.peak?.min)
        duration.peakMax = Self.positive(seedDuration?.peak?.max)
        duration.offsetMin = Self.positive(seedDuration?.offset?.min)
        duration.offsetMax = Self.positive(seedDuration?.offset?.max)
    }

    /// Non-positive shipped values render as an empty field, matching the
    /// old "blank means unset" semantics.
    private static func positive(_ value: Double?) -> Double? {
        guard let value, value > 0 else { return nil }
        return value
    }

    // MARK: - Derived

    var unitLabel: String {
        unit.trimmingCharacters(in: .whitespaces).isEmpty ? "mg" : unit
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    var trimmedDisplayName: String {
        displayName.trimmingCharacters(in: .whitespaces)
    }

    var canSave: Bool {
        !trimmedName.isEmpty
    }

    // MARK: - Builders

    func buildDoses() -> DoseRange? {
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
            threshold: val(doses.threshold),
            light: range(doses.lightMin, doses.lightMax),
            common: range(doses.commonMin, doses.commonMax),
            strong: range(doses.strongMin, doses.strongMax),
            heavy: val(doses.heavy),
        )
        return dr.hasAnyValue ? dr : nil
    }

    func buildDuration() -> DurationProfile? {
        guard duration.hasDuration else { return nil }
        func range(_ min: Double?, _ max: Double?) -> DurationRange? {
            guard let lo = min, lo > 0 else { return nil }
            let hi = max ?? lo
            guard hi >= lo else { return nil }
            return DurationRange(min: lo, max: hi)
        }
        let onset = range(duration.onsetMin, duration.onsetMax)
        let comeup = range(duration.comeupMin, duration.comeupMax)
        let peak = range(duration.peakMin, duration.peakMax)
        let offset = range(duration.offsetMin, duration.offsetMax)
        guard onset != nil || comeup != nil || peak != nil || offset != nil else { return nil }
        return DurationProfile(onset: onset, comeup: comeup, peak: peak, offset: offset, afterglow: nil, total: nil)
    }

    func buildHalfLife() -> Double? {
        guard let v = halfLifeMinutes, v > 0 else { return nil }
        return v
    }

    /// Write every draft field onto an entry — the one assignment block all
    /// three save modes share.
    func apply(to entry: inout CustomSubstanceEntry) {
        entry.name = trimmedName
        entry.displayName = trimmedDisplayName.isEmpty ? nil : trimmedDisplayName
        entry.category = category
        entry.defaultRoute = defaultRoute
        entry.unit = unit
        entry.notes = notes
        entry.doses = buildDoses()
        entry.duration = buildDuration()
        entry.halfLifeMinutes = buildHalfLife()
    }
}

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

    @State private var draft: CustomSubstanceDraft
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
        _draft = State(initialValue: CustomSubstanceDraft(
            existing: existing, initialName: initialName, personalizing: personalizing,
        ))
    }

    // MARK: - Rows

    private func rangeRow(_ label: LocalizedStringResource, min: Binding<Double?>, max: Binding<Double?>, suffix: LocalizedStringResource) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("min", value: min, format: .number)
            #if canImport(UIKit)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 56)
            #endif
            Text("–").foregroundStyle(Theme.secondaryLabel)
                .accessibilityHidden(true)
            TextField("max", value: max, format: .number)
            #if canImport(UIKit)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 56)
            #endif
            Text(suffix).foregroundStyle(Theme.secondaryLabel)
        }
    }

    private func singleRow(_ label: LocalizedStringResource, value: Binding<Double?>, suffix: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("amount", value: value, format: .number)
            #if canImport(UIKit)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 56)
            #endif
            Text(suffix).foregroundStyle(Theme.secondaryLabel)
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                if isPersonalizing {
                    Section {
                        LabeledContent("Substance", value: draft.name)
                        TextField("Display as (e.g. joint)", text: $draft.displayName)
                            .autocorrectionDisabled()
                    } header: {
                        Text("Display name")
                    } footer: {
                        Text("Shown everywhere in place of \"\(draft.name)\". Leave blank to keep the original name. Your dose history is unaffected.")
                    }
                } else {
                    Section("Name") {
                        TextField("Substance name", text: $draft.name)
                            .autocorrectionDisabled()
                    }
                }

                Section("Classification") {
                    Picker("Category", selection: $draft.category) {
                        ForEach(SubstanceCategory.allCases) { cat in
                            Label(cat.displayName, systemImage: cat.icon).tag(cat)
                        }
                    }
                }

                Section("Dosing Defaults") {
                    Picker("Default Route", selection: $draft.defaultRoute) {
                        ForEach(RouteOfAdministration.allCases) { route in
                            Text(route.localizedName).tag(route)
                        }
                    }
                    TextField("Unit (e.g. mg, ml, µg)", text: $draft.unit)
                        .autocorrectionDisabled()
                }

                Section {
                    singleRow("Threshold", value: $draft.doses.threshold, suffix: draft.unitLabel)
                    rangeRow("Light", min: $draft.doses.lightMin, max: $draft.doses.lightMax, suffix: "\(draft.unitLabel)")
                    rangeRow("Common", min: $draft.doses.commonMin, max: $draft.doses.commonMax, suffix: "\(draft.unitLabel)")
                    rangeRow("Strong", min: $draft.doses.strongMin, max: $draft.doses.strongMax, suffix: "\(draft.unitLabel)")
                    singleRow("Heavy", value: $draft.doses.heavy, suffix: draft.unitLabel)
                } header: {
                    Text("Dose Ranges")
                } footer: {
                    Text("Optional dose tiers, in your chosen unit. Leave blank to keep the library values.")
                }

                Section {
                    HStack {
                        Text("Half-life")
                        Spacer()
                        TextField("minutes", value: $draft.halfLifeMinutes, format: .number)
                        #if canImport(UIKit)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
                        #endif
                        Text("minutes").foregroundStyle(Theme.secondaryLabel)
                    }
                } header: {
                    Text("Half-life")
                } footer: {
                    Text("Optional. Feeds the active-substance and clearance estimates.")
                }

                Section {
                    Toggle("Custom duration", isOn: $draft.duration.hasDuration.animation())
                    if draft.duration.hasDuration {
                        rangeRow("Onset", min: $draft.duration.onsetMin, max: $draft.duration.onsetMax, suffix: "minutes")
                        rangeRow("Come-up", min: $draft.duration.comeupMin, max: $draft.duration.comeupMax, suffix: "minutes")
                        rangeRow("Peak", min: $draft.duration.peakMin, max: $draft.duration.peakMax, suffix: "minutes")
                        rangeRow("Offset", min: $draft.duration.offsetMin, max: $draft.duration.offsetMax, suffix: "minutes")
                    }
                } header: {
                    Text("Duration")
                } footer: {
                    Text(
                        draft.duration.hasDuration
                            ? "Minutes for each phase. Leave a phase blank to skip it; the timeline will interpolate from what you provide."
                            : "Add per-phase timing so this substance gets a Live-Activity timeline like library substances.",
                    )
                }

                Section {
                    TextField("Notes", text: $draft.notes, axis: .vertical)
                        .lineLimit(3 ... 6)
                } header: {
                    Text("Notes")
                } footer: {
                    Text("Optional notes about this substance for your reference.")
                }
            }
            .themedPage()
            .navigationTitle(navTitle)
            .inlineNavigationTitle()
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
                    .disabled(!draft.canSave)
                    .accessibilityLabel(isEditing || isPersonalizing ? "Save" : "Add")
                }
            }
            .alert("Duplicate Name", isPresented: $showDuplicateAlert) {
                Button("OK") {}
            } message: {
                Text("A custom substance named \"\(draft.trimmedName)\" already exists.")
            }
        }
    }

    private var navTitle: LocalizedStringResource {
        if isPersonalizing { return "Personalize" }
        return isEditing ? "Edit Substance" : "New Custom Substance"
    }

    // MARK: - Save

    private func save() {
        guard draft.canSave else { return }

        let saved: CustomSubstanceEntry

        if isPersonalizing {
            // Personalize mode: the entry is keyed by the canonical name. Update
            // an existing override or create one; never a rename, so no collision.
            var entry = existing ?? CustomSubstanceEntry(name: draft.trimmedName)
            draft.apply(to: &entry)
            if existing != nil { store.update(entry) } else { store.add(entry) }
            saved = entry
        } else if let existing {
            // Editing a net-new custom: allow rename unless it collides.
            if let collision = store.first(whereName: draft.trimmedName), collision.id != existing.id {
                showDuplicateAlert = true
                return
            }
            var updated = existing
            draft.apply(to: &updated)
            store.update(updated)
            saved = updated
        } else {
            if store.contains(name: draft.trimmedName) {
                showDuplicateAlert = true
                return
            }
            var entry = CustomSubstanceEntry(name: draft.trimmedName)
            draft.apply(to: &entry)
            store.add(entry)
            saved = entry
        }

        onSaved?(saved)
        dismiss()
    }
}
