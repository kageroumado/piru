import MapKit
import SwiftData
import SwiftUI
import WidgetKit

/// Detail screen for a single logged dose, reached by tapping a journal intake
/// row. Leads with a **hero** that answers what / how much / when / where-am-I-now
/// at a glance, then the timeline graph, then demoted reference material (dose
/// ranges, duration phases, notes, tags, comedown).
///
/// Editing is **in place**: the toolbar's *Edit* flips the hero's facts into
/// editable controls (the graph stays visible and live-previews the drafts) and
/// *Done* commits through the same session/notification sync path the edit sheet
/// used. This keeps the heavy re-sync at a single deliberate commit point.
struct EntryDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var substanceColors: [SubstanceColor]

    let entry: DoseEntry

    @State private var isEditing = false
    @State private var showingDeleteConfirmation = false
    @State private var showColorPicker = false

    // Draft state — seeded on entering edit mode, committed on Done, discarded
    // on Cancel (re-seeded next time, so stale drafts never leak).
    @State private var draftAmount = ""
    @State private var draftUnit = "mg"
    @State private var draftRoute: RouteOfAdministration = .oral
    @State private var draftSaltForm: String?
    @State private var draftTimestamp = Date.now
    @State private var draftNotes = ""
    @State private var draftTags: [String] = []
    @State private var draftLocation: PickedLocation?
    @State private var showLocationPicker = false
    @FocusState private var amountFocused: Bool

    // By-volume editing (alcohol %ABV → grams) — mirror of EntryFormView's state.
    @State private var draftByVolumeMode = false
    @State private var draftVolumeText = ""
    @State private var draftABVText = ""
    @State private var draftDrinkName = ""
    @State private var draftVolumeUnit: UnitVolume = ByVolumeDefaults.preferredVolumeUnit

    private let defaultUnits = ["mg", "g", "µg", "mL", "IU", "drops", "puffs"]

    // MARK: - Derived

    /// The substance record for this entry, resolved **once** on appear. The
    /// dose-ladder tint, unit list, salt forms, route list, and live-preview all
    /// read it; `entry.substance` never changes here, so caching it avoids a
    /// blocking `lookupByNameOrAlias` per body pass (3–5× per keystroke in edit
    /// mode, each a heavy resolve).
    @State private var substanceInfo: Substance?

    private var resolvedDuration: DurationProfile? {
        substanceInfo?.resolveDuration(for: entry.route)
    }

    private var hasActiveRampDown: Bool {
        RampDownScheduler.isActive(for: RampDownScheduler.entryKey(for: entry))
    }

    private var currentColorHex: String {
        substanceColors.first {
            $0.substance.lowercased() == entry.substance.lowercased()
        }?.hexColor ?? PresetColor.defaultHex
    }

    private var substanceColor: Color {
        Color(hex: currentColorHex)
    }

    /// PK state driving the graph (and, in read mode, the hero's live progress).
    /// While editing it reflects the in-progress drafts via a throwaway,
    /// uninserted ``DoseEntry`` so the graph tracks edits live; an unparseable
    /// amount falls back to the committed entry.
    private var substanceState: ActiveSubstanceState? {
        let source = (isEditing ? previewEntry : nil) ?? entry
        return ActiveSubstanceState.from(entry: source, colorHex: currentColorHex)
    }

    private var previewEntry: DoseEntry? {
        guard let amt = parsedDraftAmount else { return nil }
        return DoseEntry(
            substance: entry.substance,
            amount: amt,
            unit: draftUnit,
            route: draftRoute,
            timestamp: draftTimestamp,
        )
    }

    /// Whether the dose's effect window still includes the current moment.
    private var isSessionActive: Bool {
        guard let state = substanceState else { return false }
        return Date.now < state.doseTimestamp.addingTimeInterval(state.totalMinutes * 60)
    }

    /// Dose level of the committed entry, used to tint the hero's dose figure
    /// the same way the dose ladder colours it. `nil` when the substance has no
    /// meaningful ladder.
    private var committedDoseLevel: DoseLevel? {
        guard let sub = substanceInfo, sub.displayClass.showsDoseLadder,
              let range = sub.doseRange(for: entry.route, saltForm: entry.saltForm) else { return nil }
        let refUnit = sub.unit(for: entry.route, saltForm: entry.saltForm)
        let amount = entry.unit.caseInsensitiveCompare(refUnit) == .orderedSame
            ? entry.amount
            : (sub.convert(amount: entry.amount, from: entry.unit, toRoute: entry.route, saltForm: entry.saltForm) ?? entry.amount)
        return range.level(for: amount)
    }

    // MARK: - Draft helpers (edit mode)

    /// The draft amount keeps a String binding (not `value:format:`) so the
    /// dose-level tint and badge update per keystroke. Invariant dot-decimal
    /// first (`beginEditing` populates the field with dot-decimal text), then
    /// a locale-aware parse for locale keyboards.
    private var parsedDraftAmount: Double? {
        let parsed = Double(draftAmount.replacingOccurrences(of: ",", with: "."))
            ?? (try? Double(draftAmount, format: .number))
        guard let value = parsed, value > 0 else { return nil }
        return value
    }

    /// Draft amount converted to the substance's native unit, for accurate level comparison.
    private var normalizedDraftAmount: Double? {
        guard let parsedDraftAmount, let sub = substanceInfo else { return parsedDraftAmount }
        return sub.convert(amount: parsedDraftAmount, from: draftUnit, toRoute: draftRoute, saltForm: draftSaltForm) ?? parsedDraftAmount
    }

    private var draftDoseLevel: DoseLevel? {
        guard let normalizedDraftAmount,
              let range = substanceInfo?.doseRange(for: draftRoute, saltForm: draftSaltForm) else { return nil }
        return range.level(for: normalizedDraftAmount)
    }

    /// Salt forms offered for the draft route — drives the edit-mode salt picker.
    private var draftSaltForms: [String] {
        substanceInfo?.saltForms(for: draftRoute) ?? []
    }

    // MARK: By-volume draft helpers

    private var byVolumeCapability: ByVolumeDosing? {
        substanceInfo?.byVolumeDosing
    }

    /// The substance is alcohol. Matched on the entry's own name (not the async-loaded `substanceInfo`,
    /// which can be nil) so the acetaldehyde readout doesn't depend on substance resolution — the same
    /// predicate the zero-order timeline curve uses.
    private var isAlcoholEntry: Bool {
        let name = entry.substance.trimmingCharacters(in: .whitespaces).lowercased()
        return name == "alcohol" || name == "ethanol"
    }

    /// The entry is cannabis taken **orally** (an edible/oil/capsule). Matched on the entry's own name
    /// + route — the only place the 11-OH-THC first-pass story is the dominant, actionable effect.
    /// Inhaled cannabis is deliberately excluded (little first-pass conversion, no slow-onset redose trap).
    private var isOralCannabisEntry: Bool {
        guard entry.route == .oral else { return false }
        let name = entry.substance.trimmingCharacters(in: .whitespaces).lowercased()
        return name == "cannabis" || name == "thc" || name == "marijuana" || name == "weed"
            || name == "edible" || name == "edibles" || name == "delta-9-thc" || name == "δ9-thc"
    }

    /// Grams of ethanol in this committed dose, when the unit is a mass; drives the acetaldehyde load.
    private var entryGramsEthanol: Double? {
        guard isAlcoholEntry else { return nil }
        switch entry.unit.trimmingCharacters(in: .whitespaces).lowercased() {
        case "g", "gram", "grams": return entry.amount
        case "mg", "milligram", "milligrams": return entry.amount / 1_000
        default: return nil
        }
    }

    private var draftEnteredVolumeML: Double? {
        guard let v = Double(draftVolumeText.replacingOccurrences(of: ",", with: ".")), v > 0 else { return nil }
        return Measurement(value: v, unit: draftVolumeUnit).converted(to: .milliliters).value
    }

    private var draftEnteredABV: Double? {
        guard let a = Double(draftABVText.replacingOccurrences(of: ",", with: ".")), a > 0 else { return nil }
        return a
    }

    private var draftByVolumeGrams: Double? {
        guard let cap = byVolumeCapability, let ml = draftEnteredVolumeML, let abv = draftEnteredABV else { return nil }
        let g = cap.canonicalAmount(volumeML: ml, strength: abv)
        return g > 0 ? g : nil
    }

    private var draftTrimmedDrinkName: String? {
        let t = draftDrinkName.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private func applyDraftDrinkPreset(_ preset: DrinkPreset) {
        draftVolumeText = ByVolumeDefaults.format(preset.volume.converted(to: draftVolumeUnit).value)
        draftABVText = ByVolumeDefaults.format(preset.defaultABV)
    }

    private func syncDraftByVolumeAmount() {
        guard draftByVolumeMode else { return }
        draftUnit = byVolumeCapability?.canonicalUnit ?? "g"
        draftAmount = draftByVolumeGrams.map { ByVolumeDefaults.format($0) } ?? ""
    }

    private var currentUnits: [String] {
        guard let sub = substanceInfo else { return defaultUnits }
        let routeUnits = sub.routes.map(\.unit)
        let aliasLabels = sub.unitAliases.map(\.label)
        let unique = Array(Set(routeUnits + aliasLabels + defaultUnits))
        let defaultUnit = sub.unit(for: draftRoute)
        let ordered = [defaultUnit] + aliasLabels.filter { $0 != defaultUnit }
        return ordered + unique.filter { !ordered.contains($0) }
    }

    private var availableRoutes: [RouteOfAdministration] {
        substanceInfo?.orderedRoutes ?? RouteOfAdministration.allCases
    }

    // MARK: - Body

    var body: some View {
        List {
            Group {
                if isEditing {
                    editContent
                } else {
                    readContent
                }
            }
            .listRowBackground(CardBackground())
        }
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
        .background(Theme.background)
        // Keep the draft amount/unit synced with the by-volume fields in drink mode.
        .onChange(of: draftByVolumeGrams) { syncDraftByVolumeAmount() }
        .onChange(of: draftByVolumeMode) { if draftByVolumeMode { syncDraftByVolumeAmount() } }
        .onChange(of: draftVolumeUnit) { old, new in
            ByVolumeDefaults.preferredVolumeUnit = new
            guard let v = Double(draftVolumeText.replacingOccurrences(of: ",", with: ".")), v > 0 else { return }
            draftVolumeText = ByVolumeDefaults.format(Measurement(value: v, unit: old).converted(to: new).value)
        }
        .navigationTitle(CustomSubstanceStore.shared.displayName(for: entry.substance))
        .navigationBarTitleDisplayMode(.large)
        .animation(.snappy(duration: 0.28), value: isEditing)
        .toolbar { toolbarContent }
        .confirmationDialog(
            "Delete this entry?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible,
        ) {
            Button("Delete", role: .destructive) {
                deleteEntry()
            }
        } message: {
            Text("\(entry.amount.doseFormatted) \(entry.unit) \(CustomSubstanceStore.shared.displayName(for: entry.substance)) on \(entry.timestamp.formatted(date: .abbreviated, time: .shortened))")
        }
        .sheet(isPresented: $showColorPicker) {
            SubstanceColorPickerView(
                substanceName: entry.substance,
                takenColors: Array(substanceColors).takenColorMap,
            ) { hex in
                if let existing = substanceColors.first(where: { $0.substance.lowercased() == entry.substance.lowercased() }) {
                    existing.hexColor = hex
                } else {
                    modelContext.insert(SubstanceColor(substance: entry.substance, hexColor: hex))
                }
                showColorPicker = false
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showLocationPicker) {
            LocationPickerView { picked in draftLocation = picked }
        }
        .task {
            // Resolve the full substance record once — it feeds the dose ladder,
            // unit/route/salt lists, and live preview. Re-running it per body
            // (and per keystroke while editing) was a heavy blocking lookup.
            if substanceInfo == nil {
                substanceInfo = SubstanceLibrary.lookupByNameOrAlias(entry.substance)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isEditing {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { isEditing = false }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { commitEdits() }
                    .fontWeight(.semibold)
                    .disabled(parsedDraftAmount == nil)
            }
        } else {
            ToolbarItem(placement: .primaryAction) {
                Button { beginEditing() } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("Edit")
            }
        }
    }

    // MARK: - Read mode

    @ViewBuilder
    private var readContent: some View {
        Section {
            readHero
        }

        if substanceState != nil {
            Section {
                graph
                    .listRowInsets(EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6))
            } header: {
                HStack {
                    Text("Timeline")
                    Spacer()
                    if isSessionActive {
                        liveActivityButton
                    }
                }
            } footer: {
                Text("Pinch to zoom in or out")
            }
        } else {
            Section {
                Label("No pharmacokinetic data available for this substance and route.", systemImage: "info.circle")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
                    .padding(.vertical, 4)
            } header: {
                Text("Timeline")
            }
        }

        if isAlcoholEntry, UserProfileStore.shared.aldh2Deficient {
            AcetaldehydeCard(gramsEthanol: entryGramsEthanol)
        }

        if isOralCannabisEntry {
            ElevenHydroxyTHCCard()
        }

        if let info = substanceInfo {
            if info.displayClass.showsDoseLadder, let doses = info.doseRange(for: entry.route, saltForm: entry.saltForm) {
                let refUnit = info.unit(for: entry.route, saltForm: entry.saltForm)
                Section("Dose Ranges") {
                    DoseLevelIndicator(
                        doseRange: doses,
                        currentDose: entry.unit.caseInsensitiveCompare(refUnit) == .orderedSame ? entry.amount : nil,
                    )
                    .padding(.vertical, 4)
                    DoseRangeRows(doseRange: doses, unit: refUnit)
                }
            }

            if info.displayClass.showsDuration,
               !(info.displayClass == .otc && info.durationImplausible),
               let duration = info.resolveDuration(for: entry.route) {
                Section("Duration") {
                    DurationInfoView(duration: duration)
                }
            }

            Section {
                NavigationLink(value: PushRoute.substance(name: info.name)) {
                    Label("Substance Info", systemImage: "info.circle")
                }
            }
        }

        if let notes = entry.notes, !notes.isEmpty {
            Section("Notes") {
                Text(notes)
            }
        }

        if let locationName = entry.locationName {
            Section("Location") {
                if let coordinate = entry.coordinate {
                    Map(initialPosition: .region(MKCoordinateRegion(
                        center: coordinate,
                        latitudinalMeters: 400,
                        longitudinalMeters: 400,
                    ))) {
                        Marker(locationName, coordinate: coordinate)
                            .tint(Theme.accent)
                    }
                    .frame(height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .allowsHitTesting(false)
                    .listRowInsets(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))
                }
                Button {
                    openInMaps(name: locationName, coordinate: entry.coordinate)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundStyle(Theme.accent)
                        Text(locationName)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.forward.app")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                }
            }
        }

        if !entry.tags.isEmpty {
            Section("Tags") {
                TagChipsView(tags: entry.tags)
            }
        }

        if resolvedDuration != nil {
            Section {
                NavigationLink(value: PushRoute.rampDown(timestamp: entry.timestamp, id: entry.id)) {
                    HStack {
                        Label("Comedown Alert", systemImage: "bell.badge")
                        Spacer()
                        if hasActiveRampDown {
                            Text("Active")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                }
            } footer: {
                Text("Get care reminders as effects fade — hydration, rest, and recovery tips.")
            }
        }
    }

    /// "IPA · 568 mL · 6% ABV" for a dose logged by volume, else nil.
    private var byVolumeDisplayLine: String? {
        guard let ml = entry.volumeML, let abv = entry.abv else { return nil }
        return ByVolumeBreadcrumb.make(name: entry.drinkName, volumeML: ml, abv: abv)
    }

    private var readHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .center) {
                    Text("\(entry.amount.doseFormatted) \(entry.unit)")
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .foregroundStyle(committedDoseLevel?.swiftUIColor ?? .primary)
                        .contentTransition(.numericText())
                    Spacer(minLength: 8)
                    HStack(spacing: 6) {
                        if let saltForm = entry.saltForm {
                            // Chemical proper noun — not localized.
                            Text(saltForm)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(substanceColor.opacity(0.16), in: Capsule())
                                .foregroundStyle(substanceColor)
                        }
                        Text(entry.route.localizedName)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(substanceColor.opacity(0.16), in: Capsule())
                            .foregroundStyle(substanceColor)
                    }
                }
                Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
                if let drinkLine = byVolumeDisplayLine {
                    Label(drinkLine, systemImage: "wineglass")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(substanceColor)
                }
            }

            liveStatus
        }
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var liveStatus: some View {
        if let state = substanceState {
            let now = Date.now
            let start = state.doseTimestamp
            let end = start.addingTimeInterval(state.totalMinutes * 60)

            if now >= start, now < end {
                DosePhaseProgressBar(state: state, now: now)
            } else if now >= end {
                Label("Effects ended", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
            }
        }
    }

    // MARK: - Edit mode

    @ViewBuilder
    private var editContent: some View {
        Section {
            if byVolumeCapability != nil {
                Picker("Input", selection: $draftByVolumeMode) {
                    Text("By Drink").tag(true)
                    Text("By Weight").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            if draftByVolumeMode, let capability = byVolumeCapability {
                ByVolumeDoseInputView(
                    capability: capability,
                    volumeText: $draftVolumeText,
                    abvText: $draftABVText,
                    volumeUnit: $draftVolumeUnit,
                    grams: draftByVolumeGrams,
                    readoutColor: draftDoseLevel?.swiftUIColor,
                    name: $draftDrinkName,
                    onSelectPreset: applyDraftDrinkPreset,
                )
            } else {
                HStack {
                    TextField("Amount", text: $draftAmount)
                        .keyboardType(.decimalPad)
                        .focused($amountFocused)
                        .foregroundStyle(draftDoseLevel?.swiftUIColor ?? .primary)
                    if let level = draftDoseLevel {
                        DoseLevelBadge(level: level)
                            .transition(.opacity.combined(with: .scale))
                            .animation(.easeInOut(duration: 0.2), value: level)
                    }
                    Picker("Unit", selection: $draftUnit) {
                        ForEach(currentUnits, id: \.self) { Text($0) }
                    }
                    .labelsHidden()
                }
            }
            Picker("Route", selection: $draftRoute) {
                ForEach(availableRoutes) { route in
                    Text(route.localizedName).tag(route)
                }
            }
            .onChange(of: draftRoute) {
                SaltPicker.revalidate(&draftSaltForm, against: draftSaltForms)
                if let sub = substanceInfo {
                    draftUnit = sub.unit(for: draftRoute, saltForm: draftSaltForm)
                }
            }
            SaltPicker(forms: draftSaltForms, selection: $draftSaltForm, style: .formRow)
                .onChange(of: draftSaltForm) {
                    if let sub = substanceInfo {
                        draftUnit = sub.unit(for: draftRoute, saltForm: draftSaltForm)
                    }
                }
            DatePicker("Date & Time", selection: $draftTimestamp)
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
            if let draftLocation {
                HStack(spacing: 8) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundStyle(Theme.accent)
                    Text(draftLocation.name)
                    Spacer()
                    Button {
                        self.draftLocation = nil
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

        if substanceState != nil {
            Section {
                graph
                    .listRowInsets(EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6))
            } header: {
                Text("Timeline")
            }
        }

        if let sub = substanceInfo, sub.displayClass.showsDoseLadder {
            Section("Dose Reference") {
                DoseInfoView(
                    substance: sub,
                    route: draftRoute,
                    saltForm: draftSaltForm,
                    currentDose: normalizedDraftAmount,
                )
                .padding(.vertical, 4)
            }
        }

        Section("Notes") {
            TextField("Notes", text: $draftNotes, axis: .vertical)
                .lineLimit(3 ... 6)
        }

        Section("Tags") {
            TagEditorView(tags: $draftTags)
        }

        Section {
            Button("Delete Entry", role: .destructive) {
                showingDeleteConfirmation = true
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Shared

    @ViewBuilder
    private var graph: some View {
        if let state = substanceState {
            TimelineGraphView(
                substances: [state],
                currentTime: .now,
                compact: false,
            )
            .frame(height: 160)
        }
    }

    private var liveActivityButton: some View {
        let isRunning = LiveActivityManager.shared.isLiveActivityRunning
        return Button {
            if isRunning {
                LiveActivityManager.shared.hideLiveActivity()
            } else {
                ActiveSessionManager.shared.restartFromEntries(
                    [entry],
                    allColors: Array(substanceColors),
                )
                LiveActivityManager.shared.startLiveActivity()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isRunning ? "stop.fill" : "dot.radiowaves.up.forward")
                Text(isRunning ? "Stop Live Activity" : "Start Live Activity")
            }
            .font(.caption2.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.mini)
        .tint(Theme.accent)
    }

    // MARK: - Phases

    // MARK: - Actions

    private func beginEditing() {
        draftAmount = entry.amount == entry.amount.rounded()
            ? String(Int(entry.amount))
            : String(entry.amount)
        draftUnit = entry.unit
        draftRoute = entry.route
        draftSaltForm = entry.saltForm
        draftTimestamp = entry.timestamp
        draftNotes = entry.notes ?? ""
        draftTags = entry.tags
        if let name = entry.locationName, let lat = entry.latitude, let lng = entry.longitude {
            draftLocation = PickedLocation(name: name, latitude: lat, longitude: lng)
        } else {
            draftLocation = nil
        }

        // By-volume round-trip: if this entry was logged by volume, restore the
        // drink-mode fields from its structured volume/ABV/name.
        draftByVolumeMode = false
        if byVolumeCapability != nil, let ml = entry.volumeML, let abv = entry.abv {
            draftByVolumeMode = true
            // Display the stored millilitres in the current unit without mutating
            // `draftVolumeUnit` (which would fire the conversion onChange on the
            // already-seeded text).
            draftVolumeText = ByVolumeDefaults.format(
                Measurement(value: ml, unit: .milliliters).converted(to: draftVolumeUnit).value,
            )
            draftABVText = ByVolumeDefaults.format(abv)
            draftDrinkName = entry.drinkName ?? ""
        }

        isEditing = true
    }

    /// Commit drafts to the entry and re-sync the active session / Live Activity
    /// + widgets, mirroring the edit branch of the former edit sheet's `save()`.
    private func commitEdits() {
        guard let parsed = parsedDraftAmount else { return }
        let sub = substanceInfo

        // Normalise a colloquial alias (e.g. "drink") to its canonical physical
        // unit so cumulative dose, level chips, and PK scaling see the right number.
        let (storedAmount, storedUnit): (Double, String) = {
            if let sub, let alias = sub.unitAliases.first(where: { $0.label == draftUnit }) {
                return (parsed * alias.amountPerUnit, alias.unit)
            }
            return (parsed, draftUnit)
        }()

        let previousTimestamp = entry.timestamp
        let previousSubstanceName = entry.substance

        entry.amount = storedAmount
        entry.unit = storedUnit
        entry.route = draftRoute
        entry.saltForm = draftSaltForm
        entry.timestamp = draftTimestamp
        entry.notes = draftNotes.isEmpty ? nil : draftNotes
        // By-volume metadata, set when logged as a drink, cleared otherwise.
        entry.volumeML = draftByVolumeMode ? draftEnteredVolumeML : nil
        entry.abv = draftByVolumeMode ? draftEnteredABV : nil
        entry.drinkName = draftByVolumeMode ? draftTrimmedDrinkName : nil
        entry.tags = Array(Set(draftTags + TagExtractor.extractTags(from: draftNotes)))
        entry.locationName = draftLocation?.name
        entry.latitude = draftLocation?.latitude
        entry.longitude = draftLocation?.longitude

        // The session accessory & Live Activity read ActiveSessionManager's
        // snapshot, not SwiftData — sync it so they reflect the edit immediately.
        let colorHex = SubstancePalette.hex(for: entry.substance, hexMap: Array(substanceColors).hexColorMap)
        ActiveSessionManager.shared.updateDose(
            previousSubstanceName: previousSubstanceName,
            previousTimestamp: previousTimestamp,
            entry: entry,
            substance: sub,
            colorHex: colorHex,
            allColors: Array(substanceColors),
        )

        // Pending reminders are keyed to the old timestamp — a moved dose
        // must drop them and reschedule from its new time.
        DoseNotificationManager.doseRescheduled(entry: entry, previousTimestamp: previousTimestamp)

        // Inventory recompute (scoped to the old + new substance) and the widget
        // reload are deferred off the edit-commit path — neither is on screen.
        DoseLogService.shared.scheduleDeferredBookkeeping(
            forSubstances: [entry.substance, previousSubstanceName],
            in: modelContext,
        )
        isEditing = false
    }

    /// Open the dose's saved place in Maps. No-op if it has a name but no
    /// coordinate (which our picker never produces).
    private func openInMaps(name: String, coordinate: CLLocationCoordinate2D?) {
        guard let coordinate else { return }
        let item = MKMapItem(
            location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
            address: nil,
        )
        item.name = name
        item.openInMaps()
    }

    private func deleteEntry() {
        // Capture before delete — the entry is invalid afterwards.
        let id = entry.id
        let name = entry.substance
        let timestamp = entry.timestamp
        DoseNotificationManager.doseDeleted(timestamp: timestamp)
        modelContext.delete(entry)
        // Tear the dose out of the active session / Live Activity too; otherwise
        // a deleted "taking now" dose leaves the Live Activity and progress
        // accessory stuck on screen, uncancellable even after the app is quit.
        ActiveSessionManager.shared.removeDose(
            id: id,
            substanceName: name,
            timestamp: timestamp,
            allColors: Array(substanceColors),
        )
        DoseLogService.shared.changed()
        // Scoped inventory recompute + widget reload deferred past the dismissal.
        DoseLogService.shared.scheduleDeferredBookkeeping(forSubstances: [name], in: modelContext)
        dismiss()
    }
}
