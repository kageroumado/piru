import SwiftUI

/// The edit-mode body of ``EntryDetailView``: the hero's facts turned into
/// editable controls, driven entirely by the shared ``EntryDraft``. The timeline
/// graph stays visible and live-previews the drafts; Done commits from the parent.
struct EntryEditContent: View {
    @Bindable var draft: EntryDraft
    let entry: DoseEntry
    let substance: Substance?
    let substanceColor: Color
    let colorHex: String
    @Binding var showColorPicker: Bool
    @Binding var showLocationPicker: Bool
    @Binding var showingDeleteConfirmation: Bool
    @FocusState private var amountFocused: Bool

    private let defaultUnits = ["mg", "g", "µg", "mL", "IU", "drops", "puffs"]

    var body: some View {
        Section {
            if byVolumeCapability != nil {
                Picker("Input", selection: $draft.byVolumeMode) {
                    Text("By Drink").tag(true)
                    Text("By Weight").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            if draft.byVolumeMode, let capability = byVolumeCapability {
                ByVolumeDoseInputView(
                    capability: capability,
                    volumeText: $draft.volumeText,
                    abvText: $draft.abvText,
                    volumeUnit: $draft.volumeUnit,
                    grams: draft.byVolumeGrams(capability: capability),
                    readoutColor: draftDoseLevel?.swiftUIColor,
                    name: $draft.drinkName,
                    onSelectPreset: draft.applyDrinkPreset,
                )
            } else {
                HStack {
                    TextField("Amount", text: $draft.amount)
                        .keyboardType(.decimalPad)
                        .focused($amountFocused)
                        .foregroundStyle(draftDoseLevel?.swiftUIColor ?? .primary)
                    if let level = draftDoseLevel {
                        DoseLevelBadge(level: level)
                            .transition(.opacity.combined(with: .scale))
                            .animation(.easeInOut(duration: 0.2), value: level)
                    }
                    Picker("Unit", selection: $draft.unit) {
                        ForEach(currentUnits, id: \.self) { Text($0) }
                    }
                    .labelsHidden()
                }
            }
            Picker("Route", selection: $draft.route) {
                ForEach(availableRoutes) { route in
                    Text(route.localizedName).tag(route)
                }
            }
            .onChange(of: draft.route) {
                SaltPicker.revalidate(&draft.saltForm, against: draftSaltForms)
                IsomerPicker.revalidate(&draft.isomer, against: draftIsomerOptions)
                if let sub = substance {
                    draft.unit = sub.unit(for: draft.route, saltForm: draft.saltForm, isomer: draft.isomer)
                }
            }
            SaltPicker(forms: draftSaltForms, selection: $draft.saltForm, style: .formRow)
                .onChange(of: draft.saltForm) {
                    if let sub = substance {
                        draft.unit = sub.unit(for: draft.route, saltForm: draft.saltForm, isomer: draft.isomer)
                    }
                }
            IsomerPicker(options: draftIsomerOptions, selection: $draft.isomer, style: .formRow)
                .onChange(of: draft.isomer) {
                    if let sub = substance {
                        draft.unit = sub.unit(for: draft.route, saltForm: draft.saltForm, isomer: draft.isomer)
                    }
                }
            DatePicker("Date & Time", selection: $draft.timestamp)
            Button {
                showColorPicker = true
            } label: {
                HStack {
                    Text("Color")
                        .foregroundStyle(.primary)
                    Spacer()
                    Circle()
                        .fill(substanceColor)
                        .frame(width: 16, height: 16)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
        }

        Section("Location") {
            if let location = draft.location {
                HStack(spacing: 8) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundStyle(Theme.accent)
                    Text(location.name)
                    Spacer()
                    Button {
                        draft.location = nil
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

        if let state = previewState {
            Section {
                EntryTimelineGraph(state: state, chartFrame: false)
                    .listRowInsets(EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6))
            } header: {
                Text("Timeline")
            }
        }

        if let sub = substance, sub.displayClass.showsDoseLadder {
            Section("Dose Reference") {
                DoseInfoView(
                    substance: sub,
                    route: draft.route,
                    saltForm: draft.saltForm,
                    isomer: draft.isomer,
                    currentDose: normalizedDraftAmount,
                )
                .padding(.vertical, 4)
            }
        }

        Section("Notes") {
            TextField("Notes", text: $draft.notes, axis: .vertical)
                .lineLimit(3 ... 6)
        }

        Section("Tags") {
            TagEditorView(tags: $draft.tags)
        }

        Section {
            Button("Delete Entry", role: .destructive) {
                showingDeleteConfirmation = true
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Derived

    private var byVolumeCapability: ByVolumeDosing? {
        substance?.byVolumeDosing
    }

    /// Draft amount converted to the substance's native unit, for accurate level comparison.
    private var normalizedDraftAmount: Double? {
        guard let parsed = draft.parsedAmount, let sub = substance else { return draft.parsedAmount }
        return sub.convert(amount: parsed, from: draft.unit, toRoute: draft.route, saltForm: draft.saltForm) ?? parsed
    }

    private var draftDoseLevel: DoseLevel? {
        guard let normalizedDraftAmount,
              let range = substance?.doseRange(for: draft.route, saltForm: draft.saltForm, isomer: draft.isomer) else { return nil }
        return range.level(for: normalizedDraftAmount)
    }

    /// Salt forms offered for the draft route — drives the edit-mode salt picker.
    private var draftSaltForms: [String] {
        substance?.saltForms(for: draft.route) ?? []
    }

    /// Named isomer options for the draft route — drives the edit-mode isomer picker.
    private var draftIsomerOptions: [IsomerPicker.Option] {
        (substance?.isomerOptions(for: draft.route) ?? []).map {
            IsomerPicker.Option(code: $0.code, displayName: $0.displayName)
        }
    }

    private var currentUnits: [String] {
        guard let sub = substance else { return defaultUnits }
        let routeUnits = sub.routes.map(\.unit)
        let aliasLabels = sub.unitAliases.map(\.label)
        let unique = Array(Set(routeUnits + aliasLabels + defaultUnits))
        let defaultUnit = sub.unit(for: draft.route)
        let ordered = [defaultUnit] + aliasLabels.filter { $0 != defaultUnit }
        return ordered + unique.filter { !ordered.contains($0) }
    }

    private var availableRoutes: [RouteOfAdministration] {
        substance?.orderedRoutes ?? RouteOfAdministration.allCases
    }

    /// A throwaway, uninserted entry mirroring the in-progress drafts so the graph
    /// tracks edits live; an unparseable amount falls back to the committed entry.
    private var previewEntry: DoseEntry? {
        guard let amount = draft.parsedAmount else { return nil }
        return DoseEntry(
            substance: entry.substance,
            amount: amount,
            unit: draft.unit,
            route: draft.route,
            timestamp: draft.timestamp,
        )
    }

    private var previewState: ActiveSubstanceState? {
        ActiveSubstanceState.from(entry: previewEntry ?? entry, colorHex: colorHex)
    }
}
