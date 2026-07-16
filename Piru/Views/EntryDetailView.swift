import MapKit
import SwiftData
import SwiftUI
import TipKit
import WidgetKit

/// Detail screen for a single logged dose, reached by tapping a journal intake
/// row. The session screen's language, scoped to one substance: the hero is the
/// large-title name + the timeline graph (the session's full-bleed treatment),
/// the dose card beneath explains the curve (amount / chips / when / where-am-I-
/// now), then body load, session context, journaling context, and — last — the
/// substance's reference card with a "Show All" hop to its full page.
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
    @State private var draftSaltForm: String?
    @State private var draftIsomer: String?
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

    /// The worst interaction among the parent session's substances, resolved
    /// once alongside ``substanceInfo`` — the "Part of Session" echo row. `nil`
    /// for a solo dose or an interaction-free combination.
    @State private var sessionInteraction: InteractionResult?

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
    /// the same way the dose ladder colors it. `nil` when the substance has no
    /// meaningful ladder.
    private var committedDoseLevel: DoseLevel? {
        // Classify against the ladder the dose was logged on — isomer included.
        // Omitting it here while `draftDoseLevel` includes it made the two modes
        // disagree about the same dose: a 10 mg Dexmethylphenidate entry read
        // "light" against the racemic ladder in view mode and "common" the instant
        // you tapped Edit, then flipped back on Cancel.
        guard let sub = substanceInfo, sub.displayClass.showsDoseLadder,
              let range = sub.doseRange(for: entry.route, saltForm: entry.saltForm, isomer: entry.isomer) else { return nil }
        let refUnit = sub.unit(for: entry.route, saltForm: entry.saltForm, isomer: entry.isomer)
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
              let range = substanceInfo?.doseRange(for: draftRoute, saltForm: draftSaltForm, isomer: draftIsomer) else { return nil }
        return range.level(for: normalizedDraftAmount)
    }

    /// Salt forms offered for the draft route — drives the edit-mode salt picker.
    private var draftSaltForms: [String] {
        substanceInfo?.saltForms(for: draftRoute) ?? []
    }

    /// Named isomer options for the draft route — drives the edit-mode isomer picker.
    private var draftIsomerOptions: [IsomerPicker.Option] {
        (substanceInfo?.isomerOptions(for: draftRoute) ?? []).map {
            IsomerPicker.Option(code: $0.code, displayName: $0.displayName)
        }
    }

    /// The draft's composed form title for the displayNameSnapshot. This view's
    /// edit can't rename the substance, so the dose keeps its release form and
    /// only the isomer is in play — but the snapshot still composes across both,
    /// so a Focalin XR dose stays "Dexmethylphenidate XR" after an edit rather
    /// than collapsing to "Dexmethylphenidate". See
    /// ``DoseTitle/snapshot(canonicalName:isomer:releaseForm:)``.
    private var draftDisplayNameSnapshot: String? {
        DoseTitle.snapshot(canonicalName: entry.substance, isomer: draftIsomer, releaseForm: entry.releaseForm)
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
        .contentMargins(.top, 0, for: .scrollContent)
        .listSectionSpacing(20)
        .background(Theme.background)
        // Keep the draft amount/unit synced with the by-volume fields in drink mode.
        .onChange(of: draftByVolumeGrams) { syncDraftByVolumeAmount() }
        .onChange(of: draftByVolumeMode) { if draftByVolumeMode { syncDraftByVolumeAmount() } }
        .onChange(of: draftVolumeUnit) { old, new in
            ByVolumeDefaults.preferredVolumeUnit = new
            guard let v = Double(draftVolumeText.replacingOccurrences(of: ",", with: ".")), v > 0 else { return }
            draftVolumeText = ByVolumeDefaults.format(Measurement(value: v, unit: old).converted(to: new).value)
        }
        .navigationTitle(DoseTitle.resolve(for: entry))
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
            // The session's worst interaction, for the "Part of Session" echo.
            // One batch check per screen — not per body pass.
            if sessionInteraction == nil, let doses = entry.session?.doses, doses.count >= 2 {
                let names = Array(Set(doses.map(\.substance)))
                if names.count >= 2 {
                    sessionInteraction = InteractionChecker.checkBatch(names, against: [])
                        .max { $0.severity.rawValue < $1.severity.rawValue }
                }
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
            // Two explicit trailing buttons in the same accent tint — the text
            // "Edit" (Apple's convention over a pencil glyph) on the leading side
            // and a separate ⋯ menu, split into their own glass groups by a
            // ToolbarSpacer so they read as distinct controls.
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { beginEditing() }
                    .tint(Theme.accent)
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                doseMenu
            }
        }
    }

    /// The ⋯ overflow: the Live Activity toggle (while the dose is live) and a
    /// destructive delete — the dose-level equivalents of the session menu.
    private var doseMenu: some View {
        Menu {
            if isSessionActive {
                liveActivityButton
            }
            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Label("Delete Entry", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .tint(Theme.accent)
        .accessibilityLabel(Text("More"))
    }

    // MARK: - Read mode

    @ViewBuilder
    private var readContent: some View {
        // Timeline graph — the session screen's bordered-chart treatment as a
        // headerless section of its own: no card fill, no gesture caption (the
        // one-time TipKit popover teaches pan/zoom/inspect). List rows clip
        // their content to the section's rounded-rect mask and there's no public
        // way to turn that off, so the row carries enough side/bottom margin
        // that the flat chart's corners and pan-extent track stay clear of the
        // corner rounding.
        if substanceState != nil {
            Section {
                timelineGraph(chartFrame: true)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .popoverTip(GraphGestureTip())
            }
            .listSectionSpacing(12)
        } else {
            Section {
                Label("No pharmacokinetic data available for this substance and route.", systemImage: "info.circle")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
                    .padding(.vertical, 4)
            }
        }

        // The dose card — the graph's explainer: amount, chips, when, and the
        // live phase rail (or the ended/cleared receipt). The chip cluster tucks
        // into the top-right corner concentrically, so the row's insets are the
        // corner gap; the leading text column keeps the standard 20pt.
        Section {
            readHero
                .listRowInsets(EdgeInsets(top: 14, leading: 20, bottom: 16, trailing: 20))
        }

        if isAlcoholEntry, UserProfileStore.shared.aldh2Deficient {
            AcetaldehydeCard(gramsEthanol: entryGramsEthanol)
        }

        if isOralCannabisEntry {
            ElevenHydroxyTHCCard()
        }

        // Body load, scoped to this dose. The section renders only while the
        // substance is actually still in the body — a cleared dose answers the
        // residual fact via the hero's receipt line instead.
        SessionBodyLoadSection(
            entries: [entry],
            colorMap: Array(substanceColors).colorMap,
            header: "In Your Body",
            activeOnly: true,
        )

        partOfSessionSection

        contextSection

        aboutSection

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

    // MARK: - Session context

    /// The session this dose belongs to: its title row (a link only when the
    /// session isn't already beneath us in the navigation path), the sibling
    /// doses taken alongside, and — when the combination warrants it — the
    /// session's worst interaction echoed with its severity chip. The echo names
    /// one pair only; the session screen holds the full list.
    @ViewBuilder
    private var partOfSessionSection: some View {
        if let session = entry.session {
            let siblings = session.orderedDoses.filter { $0.id != entry.id }
            Section("Part of Session") {
                sessionRow(session)
                let shown = siblings.prefix(Self.maxSiblingRows)
                ForEach(Array(shown), id: \.id) { sibling in
                    siblingRow(sibling, sessionActive: sessionIsActive(session))
                }
                if siblings.count > Self.maxSiblingRows {
                    Text("+ \(siblings.count - Self.maxSiblingRows) more")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryLabel)
                }
                if let warning = sessionInteraction {
                    interactionEchoRow(warning)
                }
            }
        }
    }

    private static let maxSiblingRows = 3

    @ViewBuilder
    private func sessionRow(_ session: Session) -> some View {
        if sessionInNavigationPath(session) {
            sessionRowLabel(session)
        } else {
            NavigationLink(value: PushRoute.session(id: session.id)) {
                sessionRowLabel(session)
            }
        }
    }

    private func sessionRowLabel(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(session.title ?? formattedSessionDate(session.startDate))
                .font(.body.weight(.semibold))
                .lineLimit(1)
            Text(sessionSubtitle(session))
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }

    /// "Saturday, July 11" — the session screen's untitled-session title, so the
    /// link previews exactly what pushing it shows.
    private func formattedSessionDate(_ date: Date) -> String {
        let base = Date.FormatStyle.dateTime.day().month(.wide)
        let sameYear = Calendar.current.isDate(date, equalTo: .now, toGranularity: .year)
        let dateTitle = date.formatted(sameYear ? base : base.year())
        return "\(date.formatted(.dateTime.weekday(.wide))), \(dateTitle)"
    }

    /// "2 doses · 3h 21m" for an ended session; "2 doses · 44m ago" (since the
    /// first dose) while it's still running.
    private func sessionSubtitle(_ session: Session) -> String {
        let doses = session.orderedDoses
        let countText = doses.count == 1
            ? String(localized: "1 dose")
            : String(localized: "\(doses.count) doses")
        if sessionIsActive(session) {
            return "\(countText) · \(relativeText(from: session.startDate, now: .now))"
        }
        guard let first = doses.first?.timestamp, let last = doses.last?.timestamp,
              last > first else { return countText }
        return "\(countText) · \(last.timeIntervalSince(first).durationHM)"
    }

    /// Whether any dose in the session is still inside its modeled effect window.
    private func sessionIsActive(_ session: Session) -> Bool {
        session.orderedDoses.contains { dose in
            guard let state = ActiveSubstanceState.from(entry: dose, colorHex: "000000") else { return false }
            let end = state.doseTimestamp.addingTimeInterval(state.totalMinutes * 60)
            return Date.now >= state.doseTimestamp && Date.now < end
        }
    }

    /// `true` when the session screen is already below us in this tab's push
    /// path — the usual arrival — so the row carries no link back to it. Deep
    /// links and search land here without the session, and get the link.
    private func sessionInNavigationPath(_ session: Session) -> Bool {
        navigator.path(for: navigator.selectedTab).contains(.session(id: session.id))
    }

    private func siblingRow(_ dose: DoseEntry, sessionActive: Bool) -> some View {
        let name = CustomSubstanceStore.shared.displayName(for: dose.substance)
        let time = sessionActive
            ? relativeText(from: dose.timestamp, now: .now)
            : dose.timestamp.formatted(date: .omitted, time: .shortened)
        let detail = "\(name) \(dose.amount.doseFormatted) \(dose.unit) · \(time)"
        return HStack(spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 9))
                .foregroundStyle(color(for: dose.substance))
                .accessibilityHidden(true)
            Text("with \(detail)")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }

    /// One interaction row in the session-safety anatomy: severity triangle in
    /// the dot slot, the pair in primary text, the severity as the only colored
    /// element, the explanation beneath.
    private func interactionEchoRow(_ warning: InteractionResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: warning.severity == .dangerous ? "exclamationmark.triangle.fill" : "exclamationmark.triangle")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(warning.severity.labelColor)
                    .accessibilityHidden(true)
                Text(verbatim: "\(warning.substanceA) + \(warning.substanceB)")
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(String(localized: warning.severity.label).lowercased())
                    .capsuleChip(tint: warning.severity.labelColor)
            }
            Text(warning.description)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func color(for substance: String) -> Color {
        Color(hex: substanceColors.first {
            $0.substance.lowercased() == substance.lowercased()
        }?.hexColor ?? PresetColor.defaultHex)
    }

    // MARK: - Journaling context

    /// The user's own words and place, merged into one card — notes, tags, and
    /// location were three separate one-row sections before.
    @ViewBuilder
    private var contextSection: some View {
        let notes = entry.notes ?? ""
        if !notes.isEmpty || !entry.tags.isEmpty || entry.locationName != nil {
            Section("Your Notes") {
                if !notes.isEmpty {
                    Text(notes)
                }
                if !entry.tags.isEmpty {
                    TagChipsView(tags: entry.tags)
                }
                if let locationName = entry.locationName {
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
                        .accessibilityHidden(true)
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
                    .accessibilityHint(Text("Opens in Maps"))
                }
            }
        }
    }

    // MARK: - Reference

    /// "About <substance>" — the substance screen's dose & duration card,
    /// verbatim (``RouteDosingCard``), filtered to this dose's route and salt
    /// form. No folding: the header's "Show All" hops to the full substance page
    /// for every other route, sources, and the rest.
    @ViewBuilder
    private var aboutSection: some View {
        if let info = substanceInfo {
            let showsLadder = info.displayClass.showsDoseLadder
            let durationVisible = info.displayClass.showsDuration
                && !(info.displayClass == .otc && info.durationImplausible)
            let doses = showsLadder ? info.doseRange(for: entry.route, saltForm: entry.saltForm) : nil
            let duration = durationVisible ? info.resolveDuration(for: entry.route) : nil
            if doses?.hasAnyValue == true || duration != nil {
                Section {
                    RouteDosingCard(
                        route: entry.route,
                        unit: info.unit(for: entry.route, saltForm: entry.saltForm),
                        doses: doses,
                        duration: duration,
                        releaseWindow: info.routes.first { $0.route == entry.route }?.durationOfAction?.formattedWindow,
                        elementalFraction: info.elementalFraction(for: entry.route, saltForm: entry.saltForm),
                        showsDoseLadder: showsLadder,
                        showsDuration: duration != nil,
                        showsTitle: false,
                    )
                } header: {
                    HStack {
                        // The card is route-specific (dose ladder + duration for
                        // this dose's ROA), so the header names the route: "About
                        // Kratom (Oral)".
                        Text("About \(CustomSubstanceStore.shared.displayName(for: entry.substance)) (\(entry.route.localizedName))")
                        Spacer()
                        NavigationLink(value: PushRoute.substance(name: info.name)) {
                            Text("Show All")
                        }
                    }
                }
            } else {
                // No dose/duration data for this route — keep the substance
                // page reachable through the familiar plain link.
                Section {
                    NavigationLink(value: PushRoute.substance(name: info.name)) {
                        Label("Substance Info", systemImage: "info.circle")
                    }
                }
            }
        }
    }

    /// "IPA · 568 mL · 6% ABV" for a dose logged by volume, else nil.
    private var byVolumeDisplayLine: String? {
        guard let ml = entry.volumeML, let abv = entry.abv else { return nil }
        return ByVolumeBreadcrumb.make(name: entry.drinkName, volumeML: ml, abv: abv)
    }

    private var readHero: some View {
        // Minute ticks keep the relative time, the phase rail, and the
        // ended/cleared receipt current while the screen stays open.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .top) {
                        // The dose row's number treatment (rounded numeral in the
                        // primary color, a smaller secondary unit) at hero scale —
                        // the tier is carried by the strength chip, not by tinting
                        // the figure.
                        MeasurementLabel(
                            amount: entry.amount,
                            unit: entry.unit,
                            numberStyle: .largeTitle,
                            numberWeight: .bold,
                            unitStyle: .title3,
                        )
                        Spacer(minLength: 8)
                        // Top-aligned and pulled 6pt past the text column so the
                        // capsules sit ~14pt off the card's top and trailing edges —
                        // concentric with its corner radius.
                        HStack(spacing: 6) {
                            if let saltForm = entry.saltForm {
                                // Chemical proper noun — not localized. Matches the
                                // ROA pill's regular metrics so the badges align.
                                Text(saltForm)
                                    .heroChip(tint: substanceColor)
                            }
                            ROAPill(route: entry.route, size: .regular)
                            strengthChip
                        }
                        .padding(.trailing, -6)
                    }
                    Text(verbatim: "\(entry.timestamp.formatted(date: .abbreviated, time: .shortened)) · \(relativeText(from: entry.timestamp, now: context.date))")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryLabel)
                        .monospacedDigit()
                    if let drinkLine = byVolumeDisplayLine {
                        Label(drinkLine, systemImage: "wineglass")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(substanceColor)
                    }
                }

                liveStatus(now: context.date)
            }
        }
    }

    /// The tier badge ("light"/"common"/"heavy"). Uses the hero chip metrics
    /// (matching ``ROAPill``'s `.regular` size) rather than the denser row
    /// ``capsuleChip`` so "common" and "oral" are the same height in the hero.
    @ViewBuilder
    private var strengthChip: some View {
        if let level = committedDoseLevel {
            Text(String(localized: level.displayName).lowercased())
                .heroChip(tint: level.labelColor)
        }
    }

    @ViewBuilder
    private func liveStatus(now: Date) -> some View {
        if let state = substanceState {
            let start = state.doseTimestamp
            let end = start.addingTimeInterval(state.totalMinutes * 60)

            if now >= start, now < end {
                DosePhaseProgressBar(state: state, now: now)
            } else if now >= end {
                endedReceipt(end: end)
            }
        }
    }

    /// The archival answer once effects have worn off: when they ended, and —
    /// when the PK model can say — when the body finished clearing the dose.
    /// Lives in the same slot as the live phase rail, so the hero's shape
    /// doesn't reflow between states.
    private func endedReceipt(end: Date) -> some View {
        Label {
            if let cleared = clearedDate, cleared > end {
                Text("Effects ended ~\(SessionBodyLoadModel.milestoneText(end)) · cleared ~\(SessionBodyLoadModel.milestoneText(cleared))")
            } else {
                Text("Effects ended ~\(SessionBodyLoadModel.milestoneText(end))")
            }
        } icon: {
            Image(systemName: "checkmark.circle")
        }
        .font(.caption)
        .foregroundStyle(Theme.secondaryLabel)
    }

    /// When this dose dropped below ~3% remaining — the same threshold the
    /// session's body-load projection uses. `nil` when no half-life is known.
    private var clearedDate: Date? {
        let halfLife = substanceInfo?.halfLifeMinutes ?? HalfLifeDatabase.halfLife(for: entry.substance)
        guard let halfLife, halfLife > 0 else { return nil }
        let ke = PKModel.ke(fromHalfLifeMinutes: halfLife)
        let ka = SubstanceEliminationCurve.estimateKa(for: entry.substance, ke: ke)
        let step = max(1.0, halfLife / 200)
        var minutes = 0.0
        var absorbed = false
        while minutes <= halfLife * 10 {
            let fraction = PKModel.fractionRemainingInBody(at: minutes, ke: ke, ka: ka)
            if fraction > 0.03 {
                absorbed = true
            } else if absorbed {
                return entry.timestamp.addingTimeInterval(minutes * 60)
            }
            minutes += step
        }
        return nil
    }

    /// "44m ago" / "3h 21m ago" / "2d ago" — the row grammar's relative time,
    /// reusing its localized keys.
    private func relativeText(from date: Date, now: Date) -> String {
        let elapsed = max(0, now.timeIntervalSince(date))
        let totalMinutes = Int(elapsed / 60)
        guard totalMinutes >= 1 else { return String(localized: "just now") }
        let hours = totalMinutes / 60
        if hours >= 24 {
            return String(localized: "\(hours / 24)d ago")
        }
        let minutes = totalMinutes % 60
        if hours > 0, minutes > 0 {
            return String(localized: "\(hours)h \(minutes)m ago")
        } else if hours > 0 {
            return String(localized: "\(hours)h ago")
        }
        return String(localized: "\(minutes)m ago")
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
                IsomerPicker.revalidate(&draftIsomer, against: draftIsomerOptions)
                if let sub = substanceInfo {
                    draftUnit = sub.unit(for: draftRoute, saltForm: draftSaltForm, isomer: draftIsomer)
                }
            }
            SaltPicker(forms: draftSaltForms, selection: $draftSaltForm, style: .formRow)
                .onChange(of: draftSaltForm) {
                    if let sub = substanceInfo {
                        draftUnit = sub.unit(for: draftRoute, saltForm: draftSaltForm, isomer: draftIsomer)
                    }
                }
            IsomerPicker(options: draftIsomerOptions, selection: $draftIsomer, style: .formRow)
                .onChange(of: draftIsomer) {
                    if let sub = substanceInfo {
                        draftUnit = sub.unit(for: draftRoute, saltForm: draftSaltForm, isomer: draftIsomer)
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
                timelineGraph(chartFrame: false)
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
                    isomer: draftIsomer,
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

    /// The dose's PK curve. Read mode draws it as the hero with the session
    /// screen's chart frame; edit mode keeps it in a plain card, live-previewing
    /// the drafts.
    @ViewBuilder
    private func timelineGraph(chartFrame: Bool) -> some View {
        if let state = substanceState {
            TimelineGraphView(
                substances: [state],
                currentTime: .now,
                compact: false,
                chartFrame: chartFrame,
                synchronous: chartFrame,
            )
            .frame(height: chartFrame ? 176 : 160)
        }
    }

    /// Toolbar Live Activity toggle — the session screen keeps this in its ⋯
    /// menu, so the hero graph carries no chrome of its own.
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
            Label(
                isRunning ? "Stop Live Activity" : "Start Live Activity",
                systemImage: isRunning ? "stop.fill" : "dot.radiowaves.up.forward",
            )
        }
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
        draftIsomer = entry.isomer
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

        // Normalize a colloquial alias (e.g. "drink") to its canonical physical
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
        entry.isomer = draftIsomer
        entry.substanceUID = substanceInfo?.substanceUID
        entry.displayNameSnapshot = draftDisplayNameSnapshot
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
