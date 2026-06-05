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
    @Environment(\.appNavigator) private var navigator
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
    @State private var draftTimestamp = Date.now
    @State private var draftNotes = ""
    @State private var draftTags: [String] = []
    @State private var draftLocation: PickedLocation?
    @State private var showLocationPicker = false
    @FocusState private var amountFocused: Bool

    private let defaultUnits = ["mg", "g", "µg", "mL", "IU", "drops", "puffs"]

    // MARK: - Derived

    private var substanceInfo: Substance? {
        SubstanceLibrary.lookupByNameOrAlias(entry.substance)
    }

    private var resolvedDuration: DurationProfile? {
        substanceInfo?.resolveDuration(for: entry.route)
    }

    private var hasActiveRampDown: Bool {
        RampDownScheduler.isActive(for: entry.persistentModelID.hashValue)
    }

    private var currentColorHex: String {
        substanceColors.first {
            $0.substance.lowercased() == entry.substance.lowercased()
        }?.hexColor ?? "007AFF"
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
              let range = sub.doseRange(for: entry.route) else { return nil }
        let refUnit = sub.unit(for: entry.route)
        let amount = entry.unit.caseInsensitiveCompare(refUnit) == .orderedSame
            ? entry.amount
            : (sub.convert(amount: entry.amount, from: entry.unit, toRoute: entry.route) ?? entry.amount)
        return range.level(for: amount)
    }

    // MARK: - Draft helpers (edit mode)

    private var parsedDraftAmount: Double? {
        guard let value = Double(draftAmount.replacingOccurrences(of: ",", with: ".")),
              value > 0 else { return nil }
        return value
    }

    /// Draft amount converted to the substance's native unit, for accurate level comparison.
    private var normalizedDraftAmount: Double? {
        guard let parsedDraftAmount, let sub = substanceInfo else { return parsedDraftAmount }
        return sub.convert(amount: parsedDraftAmount, from: draftUnit, toRoute: draftRoute) ?? parsedDraftAmount
    }

    private var draftDoseLevel: DoseLevel? {
        guard let normalizedDraftAmount, let range = substanceInfo?.doseRange(for: draftRoute) else { return nil }
        return range.level(for: normalizedDraftAmount)
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
            .listRowBackground(Theme.cardBackground)
        }
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
        .background(Theme.background)
        .navigationTitle(entry.substance)
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
            Text("\(entry.amount.doseFormatted) \(entry.unit) \(entry.substance) on \(entry.timestamp.formatted(date: .abbreviated, time: .shortened))")
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

        if let info = substanceInfo {
            if info.displayClass.showsDoseLadder, let doses = info.doseRange(for: entry.route) {
                let refUnit = info.unit(for: entry.route)
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

        if let duration = resolvedDuration {
            Section {
                NavigationLink {
                    RampDownView(entry: entry, duration: duration)
                } label: {
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

    private var readHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .center) {
                    Text("\(entry.amount.doseFormatted) \(entry.unit)")
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .foregroundStyle(committedDoseLevel?.swiftUIColor ?? .primary)
                        .contentTransition(.numericText())
                    Spacer(minLength: 8)
                    Text(entry.route.localizedName)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(substanceColor.opacity(0.16), in: Capsule())
                        .foregroundStyle(substanceColor)
                }
                Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
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
            Picker("Route", selection: $draftRoute) {
                ForEach(availableRoutes) { route in
                    Text(route.localizedName).tag(route)
                }
            }
            .onChange(of: draftRoute) {
                if let sub = substanceInfo {
                    draftUnit = sub.unit(for: draftRoute)
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
        draftTimestamp = entry.timestamp
        draftNotes = entry.notes ?? ""
        draftTags = entry.tags
        if let name = entry.locationName, let lat = entry.latitude, let lng = entry.longitude {
            draftLocation = PickedLocation(name: name, latitude: lat, longitude: lng)
        } else {
            draftLocation = nil
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
        entry.timestamp = draftTimestamp
        entry.notes = draftNotes.isEmpty ? nil : draftNotes
        entry.tags = Array(Set(draftTags + TagExtractor.extractTags(from: draftNotes)))
        entry.locationName = draftLocation?.name
        entry.latitude = draftLocation?.latitude
        entry.longitude = draftLocation?.longitude

        // This screen is keyed by timestamp; if the edit moved the dose in time,
        // repoint the originating push route so it doesn't go blank on dismiss.
        navigator.remapEntryRoute(from: previousTimestamp, to: draftTimestamp)

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

        WidgetCenter.shared.reloadAllTimelines()
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
        let name = entry.substance
        let timestamp = entry.timestamp
        modelContext.delete(entry)
        // Tear the dose out of the active session / Live Activity too; otherwise
        // a deleted "taking now" dose leaves the Live Activity and progress
        // accessory stuck on screen, uncancellable even after the app is quit.
        ActiveSessionManager.shared.removeDose(
            substanceName: name,
            timestamp: timestamp,
            allColors: Array(substanceColors),
        )
        WidgetCenter.shared.reloadAllTimelines()
        dismiss()
    }
}
