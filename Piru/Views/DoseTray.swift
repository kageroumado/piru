import SwiftUI

// MARK: - Staged Dose

/// A dose staged in the quick-log tray, not yet committed. Doses of the same
/// substance + route + unit merge into one staged row; each distinct chip
/// amount stays a component inside it so the chips can mirror staged state.
/// A staged chip is already a complete dose; everything else here is optional
/// enrichment.
struct StagedDose: Identifiable, Equatable {
    /// One tapped chip (or typed amount) inside a staged dose. Re-tapping the
    /// same chip bumps `count` ("took two pills"); tapping a different amount
    /// adds a component ("a 150 and a 182").
    struct Component: Identifiable, Equatable {
        let id = UUID()
        var amount: Double
        var count: Int = 1
    }

    let id = UUID()
    var substanceName: String
    var components: [Component]
    var unit: String
    var route: RouteOfAdministration
    /// Selected salt/ester form (Citrate, Glycinate…). `nil` for the vast
    /// majority of substances, which have a single unspecified form.
    var saltForm: String?
    var note: String = ""
    var colorHex: String?
    var librarySubstance: Substance?
    /// Staged from the Daily routine card. Daily items keep their own surface,
    /// so they don't mint quick-log chips on commit.
    var isFromDailySet = false
    /// Carried from `DailyDoseItem.isBackgroundMed` onto the committed entry.
    var isBackgroundMed = false
    /// Per-dose "had grapefruit" flag (Stage 4c). Only ever toggled for CYP3A4-heavy
    /// substrates when grapefruit logging is enabled; carried onto the committed entry.
    var hadGrapefruit = false
    /// By-volume metadata recorded when a custom drink is logged (alcohol),
    /// carried onto the committed entry's structured fields so it round-trips on
    /// edit. `nil` for preset/grams doses.
    var volumeML: Double?
    var abv: Double?
    var drinkName: String?

    init(
        substanceName: String,
        amount: Double,
        unit: String,
        route: RouteOfAdministration,
        saltForm: String? = nil,
        colorHex: String? = nil,
        librarySubstance: Substance? = nil,
        isFromDailySet: Bool = false,
        isBackgroundMed: Bool = false,
    ) {
        self.substanceName = substanceName
        self.components = [Component(amount: amount)]
        self.unit = unit
        self.route = route
        self.saltForm = saltForm
        self.colorHex = colorHex
        self.librarySubstance = librarySubstance
        self.isFromDailySet = isFromDailySet
        self.isBackgroundMed = isBackgroundMed
    }

    /// Commits as one entry — PK superposition is linear, so 150 + 182 mg is
    /// equivalent to a single 332 mg dose.
    var totalAmount: Double {
        components.reduce(0) { $0 + $1.amount * Double($1.count) }
    }

    /// Editor-facing amount: reads the merged total; writing collapses the
    /// components into a single custom amount.
    var amount: Double {
        get { totalAmount }
        set { components = [Component(amount: newValue)] }
    }

    /// "2 × 150" / "150 + 182" — shown wherever the merged total alone would
    /// hide how the dose was assembled.
    var breakdownLabel: String? {
        guard components.count > 1 || (components.first?.count ?? 1) > 1 else { return nil }
        return components
            .map { $0.count > 1 ? "\($0.count) × \($0.amount.doseFormatted)" : $0.amount.doseFormatted }
            .joined(separator: " + ")
    }

    var color: Color {
        colorHex.map { Color(hex: $0) } ?? .gray
    }

    /// Where the merged total lands on the substance's dose ladder — `nil`
    /// when the library has no meaningful ladder for this route. Amounts in
    /// a different unit are converted to the route's reference unit first.
    var doseLevel: DoseLevel? {
        guard let librarySubstance, librarySubstance.displayClass.showsDoseLadder,
              let range = librarySubstance.doseRange(for: route, saltForm: saltForm) else { return nil }
        let referenceUnit = librarySubstance.unit(for: route, saltForm: saltForm)
        let normalized = unit.caseInsensitiveCompare(referenceUnit) == .orderedSame
            ? totalAmount
            : (librarySubstance.convert(amount: totalAmount, from: unit, toRoute: route, saltForm: saltForm) ?? totalAmount)
        return range.level(for: normalized)
    }

    /// The library's reference dose for this item's route, in this item's
    /// unit — anchors stepper increments and draft prefills to what a person
    /// actually takes (LSD steps in 10 µg, not 0.25 µg).
    var referenceDose: Double? {
        Self.lookupReferenceDose(substance: librarySubstance, route: route, unit: unit, saltForm: saltForm)
    }

    static func lookupReferenceDose(substance: Substance?, route: RouteOfAdministration, unit: String, saltForm: String? = nil) -> Double? {
        guard let substance,
              let doses = substance.doseRange(for: route, saltForm: saltForm),
              substance.unit(for: route, saltForm: saltForm) == unit
        else { return nil }
        return doses.common?.lowerBound
            ?? doses.light?.upperBound
            ?? doses.strong?.lowerBound
            ?? doses.threshold
            ?? doses.heavy
    }
}

// MARK: - Tray Time

/// The tray-wide "When" — the *only* time control in the quick-log flow,
/// applied to every staged dose. Offsets resolve at commit time, so a tray
/// left open doesn't drift. A staggered stack is two commits.
enum TrayTime: Equatable {
    case now
    case offset(minutes: Int)
    case custom(Date)

    static let offsetChoices = [15, 30, 60, 120]

    var isNow: Bool {
        self == .now
    }

    var resolved: Date {
        switch self {
        case .now: .now
        case let .offset(minutes): .now.addingTimeInterval(-Double(minutes) * 60)
        case let .custom(date): date
        }
    }

    static func offsetLabel(minutes: Int) -> String {
        minutes < 60
            ? String(localized: "\(minutes) min ago")
            : String(localized: "\(minutes / 60)h ago")
    }

    /// Short label for the When chip.
    var chipLabel: String {
        switch self {
        case .now:
            String(localized: "Now")
        case let .offset(minutes):
            Self.offsetLabel(minutes: minutes)
        case let .custom(date):
            date.formatted(
                Calendar.current.isDateInToday(date)
                    ? .dateTime.hour().minute()
                    : .dateTime.month(.abbreviated).day().hour().minute(),
            )
        }
    }
}

// MARK: - Staged Chip Counts

/// A staged chip's identity within one substance: route + unit + the amount at
/// display resolution (so the editor's `31.700000000000003 → "31.7"` round-trip
/// still matches its chip). Keys a value snapshot of staged counts.
struct StagedChipKey: Hashable {
    let route: RouteOfAdministration
    let unit: String
    let amountKey: Int
}

/// A value snapshot of one substance's staged chip counts. Passed to
/// ``SubstanceCardView`` so a card reflects staged state through a *comparable*
/// input instead of reading the live `DoseTrayModel` — reading the model would
/// re-render **every** card on any staging change, re-diffing thousands of chip
/// buttons and context menus per logging session. With a value snapshot, only
/// the card whose slice actually changed re-renders (its `.equatable()` skips
/// the rest).
struct StagedChipCounts: Equatable {
    fileprivate let counts: [StagedChipKey: Int]
    static let empty = StagedChipCounts(counts: [:])

    /// Staged count for one chip, matched at display resolution.
    func count(route: RouteOfAdministration, amount: Double, unit: String) -> Int {
        counts[StagedChipKey(route: route, unit: unit, amountKey: DoseTrayModel.displayKey(amount))] ?? 0
    }
}

// MARK: - Tray Model

/// Staging state for the quick-log tray. Owned by `QuickLogView` so dose chips
/// can reflect what's staged; rendered by `DoseTrayView`.
@Observable
final class DoseTrayModel {
    var staged: [StagedDose] = []
    var time: TrayTime = .now
    var tags: Set<String> = []
    var location: PickedLocation?
    /// Every staged dose the user has opened inline — multiple can stay
    /// expanded at once, so a complex stack can be composed in one pass.
    var expandedItemIDs: Set<UUID> = []
    var sharedDetailsExpanded = false

    /// Haptic triggers — bumped on discrete staging events so the view can
    /// attach `.sensoryFeedback` without coupling feedback to every tap.
    private(set) var stageTick = 0
    private(set) var incrementTick = 0

    var isEmpty: Bool {
        staged.isEmpty
    }

    var isCommittable: Bool {
        !staged.isEmpty && staged.allSatisfy { $0.totalAmount > 0 }
    }

    /// How many of a given chip are staged (drives the chip's count badge).
    func quantity(substance: String, route: RouteOfAdministration, amount: Double, unit: String) -> Int {
        guard let index = stagedIndex(substance: substance, route: route, unit: unit) else { return 0 }
        return staged[index].components.first { Self.sameAmount($0.amount, amount) }?.count ?? 0
    }

    /// Snapshot every staged chip count, bucketed by lowercased substance name,
    /// as ``StagedChipCounts`` value types. Built once per staging change (the
    /// card list reads this in `body`); each card then takes only its own slice,
    /// so a card whose staged state is unchanged is skipped by its `.equatable()`
    /// instead of re-diffing all its chips. Keyed identically to ``quantity`` —
    /// `(substance, route, unit, amount-at-display-resolution)`.
    func stagedCountsBySubstance() -> [String: StagedChipCounts] {
        var byName: [String: [StagedChipKey: Int]] = [:]
        for dose in staged {
            let name = dose.substanceName.lowercased()
            var keyed = byName[name] ?? [:]
            for component in dose.components {
                let key = StagedChipKey(route: dose.route, unit: dose.unit, amountKey: Self.displayKey(component.amount))
                keyed[key, default: 0] += component.count
            }
            byName[name] = keyed
        }
        return byName.mapValues { StagedChipCounts(counts: $0) }
    }

    /// Match two chip amounts at their *display* resolution, replacing a
    /// `doseFormatted` **string** comparison that allocated a formatted string
    /// per component on every staged-chip lookup — this ran inside `body` via
    /// the card's count badge. Mirrors `doseFormatted`'s magnitude-dependent
    /// rounding (0 dp ≥100, 1 dp ≥10, else 2 dp) so the perceived chip identity
    /// is unchanged — the editor's text round-trip of 31.700000000000003 →
    /// "31.7" → 31.7 still matches its chip — just without the allocation.
    private static func sameAmount(_ lhs: Double, _ rhs: Double) -> Bool {
        displayKey(lhs) == displayKey(rhs)
    }

    /// Integer key at `doseFormatted`'s rounding for this magnitude.
    fileprivate static func displayKey(_ value: Double) -> Int {
        let magnitude = Swift.abs(value)
        let scale: Double = magnitude >= 100 ? 1 : magnitude >= 10 ? 10 : 100
        return Int((value * scale).rounded())
    }

    /// Stage a chip. Same substance + route + unit merges into the existing
    /// row: re-staging the same amount increments its count ("took two
    /// pills"), a different amount joins as a new component ("a 150 and a
    /// 182") — always one entry of the summed total at commit, never two.
    func stage(
        substance: String,
        route: RouteOfAdministration,
        amount: Double,
        unit: String,
        colorHex: String?,
        librarySubstance: Substance?,
        isFromDailySet: Bool = false,
        isBackgroundMed: Bool = false,
    ) {
        if let index = stagedIndex(substance: substance, route: route, unit: unit) {
            if let componentIndex = staged[index].components.firstIndex(where: { Self.sameAmount($0.amount, amount) }) {
                staged[index].components[componentIndex].count += 1
            } else {
                staged[index].components.append(.init(amount: amount))
            }
            incrementTick += 1
        } else {
            staged.append(StagedDose(
                substanceName: substance,
                amount: amount,
                unit: unit,
                route: route,
                saltForm: librarySubstance?.saltForms(for: route).first,
                colorHex: colorHex,
                librarySubstance: librarySubstance,
                isFromDailySet: isFromDailySet,
                isBackgroundMed: isBackgroundMed,
            ))
            stageTick += 1
        }
    }

    /// Stage a draft (from search / the ⋯ chip) and open it for editing.
    /// Prefilled with the library's common dose when one is known — the
    /// editor focuses the amount field only when it opens empty. A draft for
    /// an already-staged substance opens that row instead of duplicating it.
    func stageDraft(substance: String, route: RouteOfAdministration, unit: String, colorHex: String?, librarySubstance: Substance?) {
        if let index = stagedIndex(substance: substance, route: route, unit: unit) {
            expandedItemIDs.insert(staged[index].id)
            return
        }
        let saltForm = librarySubstance?.saltForms(for: route).first
        // By-volume substances (alcohol) start empty so the drink presets build the
        // dose up from zero, rather than adding onto a reference-dose default.
        let isByVolume = librarySubstance?.byVolumeDosing.map { unit == $0.canonicalUnit } ?? false
        let seedAmount = isByVolume
            ? 0
            : (StagedDose.lookupReferenceDose(substance: librarySubstance, route: route, unit: unit, saltForm: saltForm) ?? 0)
        let draft = StagedDose(
            substanceName: substance,
            amount: seedAmount,
            unit: unit,
            route: route,
            saltForm: saltForm,
            colorHex: colorHex,
            librarySubstance: librarySubstance,
        )
        staged.append(draft)
        expandedItemIDs.insert(draft.id)
        stageTick += 1
    }

    func remove(_ item: StagedDose) {
        staged.removeAll { $0.id == item.id }
        expandedItemIDs.remove(item.id)
    }

    /// Staged rows merge on substance + route + unit; the distinct amounts
    /// inside match on their *display* form — the user-perceived identity of
    /// a chip. Exact-double matching breaks when the editor round-trips an
    /// amount through its text field (31.700000000000003 → "31.7" → 31.7).
    private func stagedIndex(substance: String, route: RouteOfAdministration, unit: String) -> Int? {
        staged.firstIndex {
            $0.substanceName.lowercased() == substance.lowercased()
                && $0.route == route
                && $0.unit == unit
        }
    }
}

// MARK: - Tray View

/// The commit surface for quick logging: staged doses, shared When/Tags/
/// Location controls, a live interaction check, and the Log button. Items
/// expand inline for per-dose enrichment — never a second sheet.
///
/// Renders content only; the dock in `QuickLogView` owns the glass surface,
/// so nothing here layers material on material.
struct DoseTrayView: View {
    @Bindable var model: DoseTrayModel
    let tagSuggestions: [String]
    /// Distinct places from dose history, most recent first — the inline
    /// location panel offers the first three, the full picker all of them.
    let recentLocations: [PickedLocation]
    let onAddMore: () -> Void
    let onCommit: () -> Void

    @State private var showLocationPicker = false
    /// The location chip expands into an inline panel (like the tag panel) —
    /// current location + recent places; the full search stays a sheet.
    @State private var locationPanelExpanded = false
    /// Ties each collapsed row to its expanded editor so the name, amount,
    /// route, and chevron morph in place instead of cross-fading.
    @Namespace private var morphNamespace

    /// Measured height of the staged-rows stack; past ``rowsMaxHeight`` the
    /// rows scroll internally so the chips and Log button never leave the
    /// screen.
    @State private var rowsHeight: CGFloat = 0
    private static let rowsMaxHeight: CGFloat = 320

    /// Memoized interaction check — the result depends only on the set of
    /// staged substance names, so it's recomputed in `onChange` rather than on
    /// every body evaluation (which fires per keystroke in the amount field).
    @State private var interactions: [InteractionResult] = []

    private var stagedNameSet: Set<String> {
        Set(model.staged.map(\.substanceName))
    }

    var body: some View {
        VStack(spacing: 0) {
            stagedRowsList

            addMoreRow

            if !interactions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(interactions.enumerated(), id: \.offset) { _, warning in
                        InteractionWarningRow(warning: warning)
                    }
                }
                .padding(.top, 10)
            }

            if model.sharedDetailsExpanded {
                TraySharedDetailsPanel(model: model, tagSuggestions: tagSuggestions)
                    .padding(.top, 12)
            }

            if locationPanelExpanded {
                TrayLocationPanel(
                    model: model,
                    recentLocations: recentLocations,
                    panelExpanded: $locationPanelExpanded,
                    onFindPlace: { showLocationPicker = true },
                )
                .padding(.top, 12)
            }

            HStack(spacing: 8) {
                whenChip
                tagsChip
                locationChip
                Spacer(minLength: 0)
            }
            .padding(.top, 12)

            commitButton
                .padding(.top, 14)
        }
        .padding(GlassDockMetrics.contentInsets)
        .onChange(of: stagedNameSet, initial: true) { _, names in
            interactions = names.count >= 2 ? InteractionChecker.checkBatch(Array(names), against: []) : []
        }
        .sensoryFeedback(.selection, trigger: model.time)
        .sheet(isPresented: $showLocationPicker) {
            LocationPickerView(recents: recentLocations) { picked in
                model.location = picked
                locationPanelExpanded = false
            }
        }
    }

    // MARK: Rows

    /// The staged rows, capped at ``rowsMaxHeight``: a tall stack scrolls
    /// internally instead of pushing the chips and Log button off screen.
    /// Height is measured because a bare `maxHeight` would let the greedy
    /// ScrollView claim the cap even for a single row.
    private var stagedRowsList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach($model.staged) { $item in
                    if model.expandedItemIDs.contains(item.id) {
                        StagedDoseEditor(item: $item, namespace: morphNamespace) {
                            withAnimation(.snappy) { _ = model.expandedItemIDs.remove(item.id) }
                        } onRemove: {
                            withAnimation(.snappy) { model.remove(item) }
                        }
                        // Top is 4, not 10: with the tray's 12pt top padding
                        // and the 38pt header row, the trash button's center
                        // lands 35pt from the surface top — the same 35pt
                        // (16pt content inset + half of 38) it sits from the
                        // right edge, so it reads concentric in the corner.
                        .padding(.top, 4)
                        .padding(.bottom, 10)
                    } else {
                        TrayRow(dose: item, model: model, namespace: morphNamespace)
                    }
                    Divider().padding(.leading, 26)
                }
            }
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { newValue in
                guard abs(newValue - rowsHeight) > 0.5 else { return }
                withAnimation(.snappy) { rowsHeight = newValue }
            }
        }
        .frame(height: min(max(rowsHeight, 1), Self.rowsMaxHeight))
        .scrollDisabled(rowsHeight <= Self.rowsMaxHeight)
        .scrollBounceBehavior(.basedOnSize)
    }

    /// Re-opens search inside the dock — staging never requires dismissing
    /// the tray. A magnifier, not a plus: the row brings up search. It shares
    /// the rows' leading chevron column so the edges align; generous
    /// targets — this is the tray's main growth path.
    private var addMoreRow: some View {
        Button(action: onAddMore) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.body.weight(.semibold))
                    .frame(width: 16)
                Text("Add another…")
                    .font(.body.weight(.semibold))
                Spacer()
            }
            .foregroundStyle(Theme.accent)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Shared controls

    private var whenChip: some View {
        Menu {
            Button {
                withAnimation(.snappy) { model.time = .now }
            } label: {
                if model.time.isNow {
                    Label("Now", systemImage: "checkmark")
                } else {
                    Text("Now")
                }
            }
            ForEach(TrayTime.offsetChoices, id: \.self) { minutes in
                Button {
                    withAnimation(.snappy) { model.time = .offset(minutes: minutes) }
                } label: {
                    if model.time == .offset(minutes: minutes) {
                        Label(TrayTime.offsetLabel(minutes: minutes), systemImage: "checkmark")
                    } else {
                        Text(TrayTime.offsetLabel(minutes: minutes))
                    }
                }
            }
            Button {
                withAnimation(.snappy) {
                    model.time = .custom(model.time.resolved)
                    model.sharedDetailsExpanded = true
                }
            } label: {
                Label("Pick date & time…", systemImage: "calendar")
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "clock")
                    .imageScale(.small)
                Text(model.time.chipLabel)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .font(.footnote.weight(.semibold))
            // The chip's capsule animates its width when the time changes; pin
            // the label to its ideal width so the new string isn't clipped to the
            // interpolating frame (which flashed truncated text before snapping).
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                model.time.isNow ? AnyShapeStyle(Color(.secondarySystemFill)) : AnyShapeStyle(Color.orange.opacity(0.18)),
                in: Capsule(),
            )
            .foregroundStyle(model.time.isNow ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.orange))
        }
        .buttonStyle(.plain)
    }

    private var tagsChip: some View {
        Button {
            withAnimation(.snappy) { model.sharedDetailsExpanded.toggle() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "tag")
                    .imageScale(.small)
                if model.tags.isEmpty {
                    Text("Tags")
                } else {
                    Text(verbatim: "\(model.tags.count)")
                }
            }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                model.tags.isEmpty ? AnyShapeStyle(Color(.secondarySystemFill)) : AnyShapeStyle(Theme.accent.opacity(0.15)),
                in: Capsule(),
            )
            .foregroundStyle(model.tags.isEmpty ? AnyShapeStyle(.primary) : AnyShapeStyle(Theme.accent))
        }
        .buttonStyle(.plain)
    }

    private var locationChip: some View {
        Button {
            withAnimation(.snappy) { locationPanelExpanded.toggle() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: model.location == nil ? "mappin.and.ellipse" : "mappin.circle.fill")
                    .imageScale(.small)
                if let location = model.location {
                    Text(location.name)
                        .lineLimit(1)
                } else {
                    Text("Location")
                }
            }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                model.location == nil ? AnyShapeStyle(Color(.secondarySystemFill)) : AnyShapeStyle(Theme.accent.opacity(0.15)),
                in: Capsule(),
            )
            .foregroundStyle(model.location == nil ? AnyShapeStyle(.primary) : AnyShapeStyle(Theme.accent))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 180, alignment: .leading)
    }

    /// Inline location options, Calendar-style: current location, the last
    /// few places, and a row that opens the full search sheet. Selection
    /// collapses the panel.
    // MARK: Commit

    private var commitButton: some View {
        Button(action: onCommit) {
            Text(commitLabel)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                // The dock contract: the Log button and the search field
                // share one frame, so the faces morph into one another.
                .frame(height: GlassDockMetrics.controlHeight)
                .background(Theme.accent, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!model.isCommittable)
        .opacity(model.isCommittable ? 1 : 0.5)
    }

    /// The CTA echoes a backdate ("Log 2 · 1h ago") so a stale time can't be
    /// committed blind.
    private var commitLabel: String {
        let base = model.staged.count == 1
            ? String(localized: "Log Dose")
            : String(localized: "Log \(model.staged.count) Doses")
        return model.time.isNow ? base : "\(base) · \(model.time.chipLabel)"
    }
}

// MARK: - Location Panel

/// The tray's inline location options (Calendar-style): current location, the
/// last few places, "Find a Place…" (which opens the parent's full picker via
/// `onFindPlace`), and a remove row. Owns its own `LocationSearchModel`; writes
/// the picked place onto the model and collapses the panel through the binding.
private struct TrayLocationPanel: View {
    @Bindable var model: DoseTrayModel
    let recentLocations: [PickedLocation]
    @Binding var panelExpanded: Bool
    let onFindPlace: () -> Void

    @State private var locationModel = LocationSearchModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            locationRow(
                icon: "location.fill",
                title: String(localized: "Current Location"),
                tint: Theme.accent,
                showsProgress: locationModel.isLocating,
            ) {
                Task {
                    guard let picked = await locationModel.requestCurrentLocation() else { return }
                    withAnimation(.snappy) {
                        model.location = picked
                        panelExpanded = false
                    }
                }
            }

            ForEach(Array(recentLocations.prefix(3)), id: \.name) { place in
                Divider().padding(.leading, 26)
                locationRow(
                    icon: "mappin.circle.fill",
                    title: place.name,
                    isSelected: model.location == place,
                ) {
                    withAnimation(.snappy) {
                        model.location = model.location == place ? nil : place
                        panelExpanded = false
                    }
                }
            }

            Divider().padding(.leading, 26)
            locationRow(icon: "magnifyingglass", title: String(localized: "Find a Place…")) {
                onFindPlace()
            }

            if model.location != nil {
                Divider().padding(.leading, 26)
                locationRow(icon: "xmark", title: String(localized: "Remove location"), tint: .red) {
                    withAnimation(.snappy) {
                        model.location = nil
                        panelExpanded = false
                    }
                }
            }

            if locationModel.authDenied {
                Text("Location access is off. Turn it on in Settings to use your current location.")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryLabel)
                    .padding(.top, 6)
            }
        }
    }

    private func locationRow(
        icon: String,
        title: String,
        tint: Color? = nil,
        isSelected: Bool = false,
        showsProgress: Bool = false,
        action: @escaping () -> Void,
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .imageScale(.small)
                    .frame(width: 16)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Spacer()
                if showsProgress {
                    ProgressView()
                        .controlSize(.small)
                } else if isSelected {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .foregroundStyle(tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.primary))
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(showsProgress)
    }
}

// MARK: - Shared Details Panel

/// The tray's expanded shared panel: the custom date picker (when a custom time
/// is active) and the tag chips. Reads/writes the model directly; rendered only
/// while `model.sharedDetailsExpanded`.
private struct TraySharedDetailsPanel: View {
    @Bindable var model: DoseTrayModel
    let tagSuggestions: [String]

    private var allTagChoices: [String] {
        tagSuggestions + model.tags.filter { !tagSuggestions.contains($0) }.sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if case let .custom(date) = model.time {
                DatePicker(
                    "When",
                    selection: Binding(
                        get: { date },
                        set: { model.time = .custom($0) },
                    ),
                    in: ...Date.now,
                )
                .font(.footnote.weight(.semibold))
                .datePickerStyle(.compact)
            }

            FlowLayout(spacing: 6) {
                ForEach(allTagChoices, id: \.self) { tag in
                    let on = model.tags.contains(tag)
                    Button {
                        withAnimation(.snappy) {
                            if on { model.tags.remove(tag) } else { model.tags.insert(tag) }
                        }
                    } label: {
                        Text(verbatim: "#\(tag)")
                            .font(.footnote.weight(.medium))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(
                                on ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color(.secondarySystemFill)),
                                in: Capsule(),
                            )
                            .foregroundStyle(on ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Tray Row

/// A staged dose as a compact row: a downward disclosure chevron (it expands
/// in place — never navigates) — tap expands the inline editor, swipe left
/// reveals delete (with full-swipe to remove).
private struct TrayRow: View {
    let dose: StagedDose
    /// Stable reference, not parent closures: the row toggles its own
    /// expansion / removal through the model. With no closures and an
    /// `Equatable` `dose`, SwiftUI can compare `TrayRow` and skip the body of
    /// a collapsed row whose dose didn't change — so editing one staged
    /// amount no longer re-evaluates every other row.
    let model: DoseTrayModel
    let namespace: Namespace.ID

    @State private var offset: CGFloat = 0

    private static let revealWidth: CGFloat = 64
    private static let fullSwipeThreshold: CGFloat = 180

    private func expand() {
        withAnimation(.snappy) { _ = model.expandedItemIDs.insert(dose.id) }
    }

    private func delete() {
        withAnimation(.snappy) { model.remove(dose) }
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            deleteBackdrop
            rowContent
                .offset(x: offset)
        }
        .clipped()
        .gesture(swipeGesture)
    }

    private var rowContent: some View {
        HStack(spacing: 10) {
            // Disclosure chevron leads the row (matching the search results).
            // Apple's convention: points right collapsed, down expanded — the
            // editor renders the same glyph rotated 90°, so the matched-
            // geometry swap reads as the chevron rotating in place.
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 16)
                .matchedGeometryEffect(id: "chevron-\(dose.id)", in: namespace)
            VStack(alignment: .leading, spacing: 2) {
                // Same font and leading column as "Add another…" so the
                // tray reads as one aligned list (the colour dot is gone —
                // the chips already carry the substance colour).
                Text(dose.substanceName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .matchedGeometryEffect(id: "title-\(dose.id)", in: namespace)
                // Day-list phrase: "oral · 100 mg · strong" — route as
                // context, the amount emphasised, the level read via colour.
                HStack(spacing: 5) {
                    Text(String(localized: dose.route.localizedName).lowercased())
                        .foregroundStyle(Theme.secondaryLabel)
                        .matchedGeometryEffect(id: "route-\(dose.id)", in: namespace)
                    Text(verbatim: "·").foregroundStyle(.tertiary)
                    Text(verbatim: "\(dose.totalAmount.doseFormatted) \(dose.unit)")
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        // During the collapse morph the matched siblings carry
                        // inflated mid-flight frames (the route text pairs with
                        // the editor's wide pill), squeezing this text into a
                        // momentary "37.…" ellipsis. Fixed-size keeps it at its
                        // intrinsic width for the whole animation.
                        .fixedSize()
                        .matchedGeometryEffect(id: "amount-\(dose.id)", in: namespace)
                    if let level = dose.doseLevel {
                        Text(verbatim: "·").foregroundStyle(.tertiary)
                        Text(String(localized: level.displayName).lowercased())
                            .foregroundStyle(level.labelColor)
                    }
                    if let breakdown = dose.breakdownLabel {
                        Text(verbatim: "·").foregroundStyle(.tertiary)
                        Text(verbatim: breakdown)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                    if !dose.note.isEmpty {
                        Text(verbatim: "·").foregroundStyle(.tertiary)
                        Text(dose.note)
                            .foregroundStyle(Theme.secondaryLabel)
                            .lineLimit(1)
                    }
                }
                .font(.subheadline)
            }
            Spacer()
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            if offset != 0 {
                withAnimation(.snappy) { offset = 0 }
            } else {
                expand()
            }
        }
    }

    /// A compact red capsule, not a full-height block — centered in the
    /// revealed strip with breathing room on every side.
    private var deleteBackdrop: some View {
        Button(action: delete) {
            Image(systemName: "trash.fill")
                .font(.subheadline)
                .foregroundStyle(.white)
                .frame(width: Self.revealWidth - 8, height: 34)
                .background(.red, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove")
        .opacity(offset < -1 ? 1 : 0)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                offset = min(0, value.translation.width)
            }
            .onEnded { value in
                if offset < -Self.fullSwipeThreshold || value.predictedEndTranslation.width < -Self.fullSwipeThreshold * 1.5 {
                    delete()
                } else if offset < -Self.revealWidth / 2 {
                    withAnimation(.snappy) { offset = -Self.revealWidth }
                } else {
                    withAnimation(.snappy) { offset = 0 }
                }
            }
    }
}

// MARK: - Staged Dose Editor

/// Inline per-dose editor: rows directly on the tray surface — fields use
/// fills, never their own card, so the dock stays a single material. Amount,
/// unit, route, and note; time lives only on the tray's shared When chip.
private struct StagedDoseEditor: View {
    @Binding var item: StagedDose
    let namespace: Namespace.ID
    let onCollapse: () -> Void
    let onRemove: () -> Void

    @State private var amountText = ""
    /// Suppresses the text→amount sync when `amountText` is being set *from*
    /// the model (onAppear / stepper), so opening the editor never rewrites
    /// the staged amount through display rounding.
    @State private var suppressAmountSync = false
    @FocusState private var amountFocused: Bool

    /// The note row stays revealed once opened, even while still empty.
    @State private var noteExpanded = false
    @FocusState private var noteFocused: Bool

    /// Bumped on each stepper tap — drives the value-change pulse + haptic.
    @State private var stepTick = 0

    /// Whether this substance is CYP3A4-heavy — gates the per-dose grapefruit toggle (Stage 4c).
    /// Computed once on appear; the metabolism lookup shouldn't run every render.
    @State private var isGrapefruitSubstrate = false
    @State private var profileStore = UserProfileStore.shared

    // By-volume custom logger (alcohol): a two-tier strength + volume input with an
    // optional drink name. The By Drink / By Weight choice persists across doses.
    @AppStorage("alcoholEditorByDrink") private var byDrinkPreferred = true
    @State private var volumeText = ""
    @State private var abvText = ""
    @State private var drinkName = ""
    @State private var volumeUnit: UnitVolume = ByVolumeDefaults.preferredVolumeUnit

    private var enteredVolumeML: Double? {
        guard let v = Double(volumeText.replacingOccurrences(of: ",", with: ".")), v > 0 else { return nil }
        return Measurement(value: v, unit: volumeUnit).converted(to: .milliliters).value
    }

    private var enteredABV: Double? {
        guard let a = Double(abvText.replacingOccurrences(of: ",", with: ".")), a > 0 else { return nil }
        return a
    }

    private var customDrinkGrams: Double? {
        guard let cap = byVolumeCapability, let ml = enteredVolumeML, let abv = enteredABV else { return nil }
        let g = cap.canonicalAmount(volumeML: ml, strength: abv)
        return g > 0 ? g : nil
    }

    private static let unitChoices = ["µg", "mg", "g", "mL"]
    /// One shared height for the route/note pills — a TextField's intrinsic
    /// height differs from a Menu label's, so padding alone won't match them.
    private static let pillHeight: CGFloat = 33

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if byVolumeCapability != nil {
                byVolumeModeToggle
                if byDrinkPreferred {
                    customDrinkLogger
                } else {
                    stepperBlock
                }
            } else {
                stepperBlock
            }

            HStack(spacing: 8) {
                routeMenu
                SaltPicker(
                    forms: item.librarySubstance?.saltForms(for: item.route) ?? [],
                    selection: $item.saltForm,
                    style: .menuPill(namespace: namespace, id: "salt-\(item.id)", height: Self.pillHeight),
                )
                notePill
                if profileStore.grapefruitLoggingEnabled, isGrapefruitSubstrate {
                    grapefruitPill
                }
            }

            if noteExpanded {
                noteEditor
            }
        }
        .sensoryFeedback(.increase, trigger: stepTick)
        .onAppear {
            if item.amount > 0 {
                suppressAmountSync = true
                amountText = item.amount.doseFormatted
            }
            // Don't pop the keyboard for by-volume substances — the drink presets
            // are the primary action, not manual amount entry.
            if item.amount <= 0, byVolumeCapability == nil { amountFocused = true }
            if profileStore.grapefruitLoggingEnabled {
                isGrapefruitSubstrate = MetabolicModulation
                    .majorEnzymes(metabolism: SubstanceStore.shared.metabolism(forSubstanceName: item.substanceName))
                    .contains(.cyp3a4)
            }
            // Seed the custom-drink fields from a dose already logged by volume, so
            // re-opening it shows its strength/volume/name.
            if byVolumeCapability != nil, let ml = item.volumeML, let abv = item.abv {
                volumeText = ByVolumeDefaults.format(Measurement(value: ml, unit: .milliliters).converted(to: volumeUnit).value)
                abvText = ByVolumeDefaults.format(abv)
                drinkName = item.drinkName ?? ""
            }
        }
        .onChange(of: noteFocused) {
            // Fold an untouched note row back into the pill.
            if !noteFocused, item.note.isEmpty {
                withAnimation(.snappy) { noteExpanded = false }
            }
        }
        // Keep the staged grams + by-volume metadata synced with the custom logger.
        .onChange(of: customDrinkGrams) { syncCustomDrink() }
        .onChange(of: drinkName) { syncCustomDrink() }
        .onChange(of: byDrinkPreferred) {
            if byDrinkPreferred {
                syncCustomDrink()
            } else {
                // Switching to By Weight drops the drink metadata; the grams stay.
                item.volumeML = nil
                item.abv = nil
                item.drinkName = nil
            }
        }
        .onChange(of: volumeUnit) { old, new in
            ByVolumeDefaults.preferredVolumeUnit = new
            guard let v = Double(volumeText.replacingOccurrences(of: ",", with: ".")), v > 0 else { return }
            volumeText = ByVolumeDefaults.format(Measurement(value: v, unit: old).converted(to: new).value)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            // Same glyph as the collapsed row, rotated to point down
            // (expanded, per Apple's disclosure convention) — the matched-
            // geometry swap morphs it in place like a rotation.
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(90))
                .frame(width: 16)
                .matchedGeometryEffect(id: "chevron-\(item.id)", in: namespace)
            Text(item.substanceName)
                .font(.body.weight(.semibold))
                .matchedGeometryEffect(id: "title-\(item.id)", in: namespace)
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "trash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                    .frame(width: 38, height: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove")
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onCollapse)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Collapses the editor")
    }

    /// Behaves like the location chip: neutral "Note" when empty, accent-
    /// tinted with the note's first words once one exists. Toggles the
    /// multi-line editor below.
    private var notePill: some View {
        Button {
            withAnimation(.snappy) { noteExpanded.toggle() }
            if noteExpanded { noteFocused = true }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "note.text")
                    .imageScale(.small)
                Text(item.note.isEmpty ? String(localized: "Note") : item.note)
                    .lineLimit(1)
            }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 11)
            .frame(height: Self.pillHeight)
            .background(
                item.note.isEmpty ? AnyShapeStyle(Color(.secondarySystemFill)) : AnyShapeStyle(Theme.accent.opacity(0.15)),
                in: Capsule(),
            )
            .foregroundStyle(item.note.isEmpty ? AnyShapeStyle(.primary) : AnyShapeStyle(Theme.accent))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 180, alignment: .leading)
    }

    /// By-volume capability for this staged substance (alcohol), gated on the
    /// canonical "g" unit so the drink chips show only when the dose is in grams.
    private var byVolumeCapability: ByVolumeDosing? {
        guard item.unit == "g" else { return nil }
        return item.librarySubstance?.byVolumeDosing
    }

    /// The amount +/− stepper and its breakdown/level readout — the default for
    /// every substance, and the "By Weight" mode for alcohol.
    private var stepperBlock: some View {
        VStack(alignment: .center, spacing: 5) {
            HStack(spacing: 8) {
                stepButton(systemImage: "minus") {
                    setAmount(max(0, item.amount - amountStep))
                }
                amountField
                stepButton(systemImage: "plus") {
                    setAmount(item.amount + amountStep)
                }
            }
            .phaseAnimator([1.0, 1.03], trigger: stepTick) { content, scale in
                content.scaleEffect(scale)
            } animation: { _ in
                .snappy(duration: 0.15)
            }
            if item.breakdownLabel != nil || item.doseLevel != nil {
                HStack(spacing: 5) {
                    if let breakdown = item.breakdownLabel {
                        Text(verbatim: "= \(breakdown) \(item.unit)")
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                    if item.breakdownLabel != nil, item.doseLevel != nil {
                        Text(verbatim: "·").foregroundStyle(.tertiary)
                    }
                    if let level = item.doseLevel {
                        Text(String(localized: level.displayName).lowercased())
                            .foregroundStyle(level.labelColor)
                    }
                }
                .font(.caption.weight(.medium))
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// By Drink (the two-tier strength + volume logger) vs By Weight (the grams
    /// stepper). The choice persists across doses via `byDrinkPreferred`.
    private var byVolumeModeToggle: some View {
        Picker("Input", selection: $byDrinkPreferred) {
            Text("By Drink").tag(true)
            Text("By Weight").tag(false)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    /// The custom drink logger (alcohol): strength + volume + optional name, with
    /// a live grams readout. Syncs the computed grams + metadata onto the staged
    /// dose so a custom drink commits and round-trips like a preset.
    @ViewBuilder
    private var customDrinkLogger: some View {
        if let capability = byVolumeCapability {
            ByVolumeDoseInputView(
                capability: capability,
                volumeText: $volumeText,
                abvText: $abvText,
                volumeUnit: $volumeUnit,
                grams: customDrinkGrams,
                readoutColor: item.doseLevel?.labelColor,
                showsPresets: false,
                name: $drinkName,
            )
        }
    }

    /// Push the custom drink's grams + metadata onto the staged dose. Only writes
    /// once a usable volume + strength is entered, so opening the logger on a dose
    /// already staged from preset chips never wipes its grams.
    private func syncCustomDrink() {
        guard byDrinkPreferred, byVolumeCapability != nil, let grams = customDrinkGrams else { return }
        item.components = [StagedDose.Component(amount: (grams * 10).rounded() / 10)]
        item.unit = byVolumeCapability?.canonicalUnit ?? "g"
        item.volumeML = enteredVolumeML
        item.abv = enteredABV
        item.drinkName = drinkName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : drinkName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Per-dose "had grapefruit" toggle (Stage 4c) — shown only for CYP3A4-heavy substrates when
    /// grapefruit logging is enabled in Settings. Tinted when on; recorded on the committed dose.
    private var grapefruitPill: some View {
        Button {
            withAnimation(.snappy) { item.hadGrapefruit.toggle() }
        } label: {
            Image(systemName: "carrot")
                .imageScale(.small)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 11)
                .frame(height: Self.pillHeight)
                .background(
                    item.hadGrapefruit ? AnyShapeStyle(Theme.accent.opacity(0.15)) : AnyShapeStyle(Color(.secondarySystemFill)),
                    in: Capsule(),
                )
                .foregroundStyle(item.hadGrapefruit ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.primary))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Had grapefruit with this dose"))
        .accessibilityAddTraits(item.hadGrapefruit ? [.isSelected] : [])
    }

    /// Multi-line note editor — a single line that grows with its content,
    /// with an explicit close.
    private var noteEditor: some View {
        HStack(alignment: .top, spacing: 8) {
            TextField("Add note…", text: $item.note, axis: .vertical)
                .font(.footnote.weight(.medium))
                .lineLimit(1 ... 6)
                .focused($noteFocused)
            Button {
                noteFocused = false
                withAnimation(.snappy) { noteExpanded = false }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Theme.secondaryLabel)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.inputBackground, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }

    /// The amount is centered in the pill itself; the unit menu is a trailing
    /// overlay so it never shifts the number off-center.
    private var amountField: some View {
        TextField("0", text: $amountText)
            .keyboardType(.decimalPad)
            .focused($amountFocused)
            .multilineTextAlignment(.center)
            .font(.title3.weight(.semibold))
            .onChange(of: amountText) {
                if suppressAmountSync {
                    suppressAmountSync = false
                    return
                }
                // String binding (not value:format:) is deliberate — the staged
                // amount must update per keystroke for the live dose-level /
                // breakdown reclassification, and the suppress-flag sync above
                // relies on owning the text. Invariant dot-decimal first (the
                // field is populated from `doseFormatted`, which always emits
                // "."), then a locale-aware parse for locale keyboards.
                item.amount = Double(amountText.replacingOccurrences(of: ",", with: "."))
                    ?? (try? Double(amountText, format: .number))
                    ?? 0
            }
            .frame(height: 42)
            .frame(maxWidth: .infinity)
            .background(Theme.inputBackground, in: Capsule())
            .overlay(alignment: .trailing) {
                unitMenu
                    .padding(.trailing, 12)
            }
            .matchedGeometryEffect(id: "amount-\(item.id)", in: namespace)
    }

    private var unitMenu: some View {
        Menu {
            ForEach(unitMenuChoices, id: \.self) { unit in
                Button {
                    item.unit = unit
                } label: {
                    if unit == item.unit {
                        Label(unit, systemImage: "checkmark")
                    } else {
                        Text(unit)
                    }
                }
            }
        } label: {
            HStack(spacing: 2) {
                Text(item.unit)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.secondaryLabel)
        }
        .buttonStyle(.plain)
    }

    private var unitMenuChoices: [String] {
        Self.unitChoices.contains(item.unit) ? Self.unitChoices : [item.unit] + Self.unitChoices
    }

    /// 38pt circles — the trash button's width, so the trailing plus shares
    /// its center line; equal height makes them true circles beside the
    /// 42pt field.
    private func stepButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 38, height: 38)
                .background(Color(.secondarySystemFill), in: Circle())
        }
        .buttonStyle(.plain)
    }

    /// Stepper increment anchored to the substance's reference dose when the
    /// library knows one (LSD → 10 µg, pregabalin → 25 mg), falling back to a
    /// magnitude table for unknowns.
    private var amountStep: Double {
        if let reference = item.referenceDose {
            return Self.niceStep(for: reference)
        }
        return switch item.amount {
        case ..<2: 0.25
        case ..<10: 1
        case ..<100: 5
        case ..<1_000: 25
        default: 100
        }
    }

    /// ≈10% of the reference dose, snapped to a 1 / 2.5 / 5 × 10ᵏ series.
    static func niceStep(for reference: Double) -> Double {
        guard reference > 0 else { return 1 }
        let raw = reference / 10
        let magnitude = pow(10, floor(log10(raw)))
        let normalized = raw / magnitude
        let snapped: Double = normalized < 1.75 ? 1 : normalized < 3.75 ? 2.5 : normalized < 7.5 ? 5 : 10
        return snapped * magnitude
    }

    private func setAmount(_ value: Double) {
        stepTick += 1
        item.amount = value
        let newText = value > 0 ? value.doseFormatted : ""
        // Only arm the suppress flag when onChange will actually fire,
        // otherwise it would stay latched and swallow the next keystroke.
        if newText != amountText {
            suppressAmountSync = true
            amountText = newText
        }
    }

    private var routeMenu: some View {
        Menu {
            ForEach(RouteOfAdministration.allCases) { route in
                Button {
                    item.route = route
                    SaltPicker.revalidate(&item.saltForm, against: item.librarySubstance?.saltForms(for: route) ?? [])
                } label: {
                    if route == item.route {
                        Label(String(localized: route.localizedName), systemImage: "checkmark")
                    } else {
                        Text(route.localizedName)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.down.circle")
                    .imageScale(.small)
                Text(item.route.localizedName)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 11)
            .frame(height: Self.pillHeight)
            .background(Color(.secondarySystemFill), in: Capsule())
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .matchedGeometryEffect(id: "route-\(item.id)", in: namespace)
    }
}
