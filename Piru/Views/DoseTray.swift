import SwiftData
import SwiftUI
import UIKit

// MARK: - Metrics

/// Dose-stepper increments shared by the tray editor and the inline search
/// result entry.
enum DoseStepping {
    /// ≈10% of the reference dose, snapped to a 1 / 2.5 / 5 × 10ᵏ series.
    static func niceStep(for reference: Double) -> Double {
        guard reference > 0 else { return 1 }
        let raw = reference / 10
        let magnitude = pow(10, floor(log10(raw)))
        let normalized = raw / magnitude
        let snapped: Double = normalized < 1.75 ? 1 : normalized < 3.75 ? 2.5 : normalized < 7.5 ? 5 : 10
        return snapped * magnitude
    }
}

/// Geometry for the tray's content, shared with the dock sheet that hosts it.
enum DoseTrayMetrics {
    /// Height of the Log button — literally the dock's pinned search field
    /// height, so the two read as one control system at every Dynamic Type
    /// size.
    static var controlHeight: CGFloat {
        QuickLogDockMetrics.fieldHeight
    }
    /// Corner radius of the grouped cards inside the dock, matching the
    /// system inset-grouped list on iOS 26.
    static let cardCornerRadius: CGFloat = 26
}

// MARK: - Motion-aware morphs

/// The tray's expand/collapse matched-geometry pairing, dropped under Reduce
/// Motion: without the pairing the row⇄editor swap plays as SwiftUI's default
/// crossfade (the elements fade in place while the card resizes), instead of
/// text and pills flying between layouts. Removing just the *animation* is not
/// enough — matched geometry with no animation still snaps elements across the
/// card mid-swap.
private struct TrayMorphEffect: ViewModifier {
    let id: String
    let namespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.matchedGeometryEffect(id: id, in: namespace)
        }
    }
}

extension View {
    /// `matchedGeometryEffect` for the tray's row⇄editor morph pairs,
    /// degrading to a plain crossfade under Reduce Motion.
    func trayMorph(id: String, in namespace: Namespace.ID) -> some View {
        modifier(TrayMorphEffect(id: id, namespace: namespace))
    }
}

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
    /// Emoji of the selected drink preset, carried onto the quick-log chip so a
    /// re-logged drink keeps its glyph. Display-only; not persisted on `DoseEntry`.
    var emoji: String?

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

    /// Haptic triggers — bumped on discrete staging events so the view can
    /// attach `.sensoryFeedback` without coupling feedback to every tap.
    private(set) var stageTick = 0
    private(set) var incrementTick = 0

    /// Stored — *not* computed from `staged` — so a view reading it (the
    /// toolbar's close button, the dock's face selection in `QuickLogView.body`)
    /// subscribes to *this* flag rather than the whole `staged` array. Maintained
    /// only at the count-change sites (`stage` append / `stageDraft` / `remove`),
    /// and only when the value actually flips, so stepping a dose's amount or
    /// re-tapping a chip — which mutate `staged` but not its count — no longer
    /// re-runs `QuickLogView.body`. `isCommittable` stays computed: it depends on
    /// per-dose amounts and is read only inside `DoseTrayView`, which must
    /// re-render on those edits anyway.
    private(set) var isEmpty = true

    /// Re-sync the stored ``isEmpty`` after a count change, notifying only on a
    /// real flip (an `@Observable` set always notifies, even for an equal value).
    private func syncEmptiness() {
        let nowEmpty = staged.isEmpty
        if nowEmpty != isEmpty { isEmpty = nowEmpty }
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
        volumeML: Double? = nil,
        abv: Double? = nil,
        drinkName: String? = nil,
        emoji: String? = nil,
    ) {
        if let index = stagedIndex(substance: substance, route: route, unit: unit) {
            if let componentIndex = staged[index].components.firstIndex(where: { Self.sameAmount($0.amount, amount) }) {
                staged[index].components[componentIndex].count += 1
            } else {
                staged[index].components.append(.init(amount: amount))
            }
            incrementTick += 1
        } else {
            var dose = StagedDose(
                substanceName: substance,
                amount: amount,
                unit: unit,
                route: route,
                saltForm: librarySubstance?.saltForms(for: route).first,
                colorHex: colorHex,
                librarySubstance: librarySubstance,
                isFromDailySet: isFromDailySet,
                isBackgroundMed: isBackgroundMed,
            )
            dose.volumeML = volumeML
            dose.abv = abv
            dose.drinkName = drinkName
            dose.emoji = emoji
            staged.append(dose)
            stageTick += 1
            syncEmptiness()
        }
    }

    /// Stage a draft (from search / the ⋯ chip) and open it for editing.
    /// Prefilled with the library's common dose when one is known — the
    /// editor focuses the amount field only when it opens empty. A draft for
    /// an already-staged substance opens that row instead of duplicating it.
    func stageDraft(substance: String, route: RouteOfAdministration, unit: String, colorHex: String?, librarySubstance: Substance?) {
        // A by-volume substance (alcohol) must draft in its canonical unit —
        // the drink editor (By Drink / By Weight) gates on it, so a draft
        // arriving as "units" (a recent's chip unit) would silently lose the
        // whole volumetric logger.
        let unit = librarySubstance?.byVolumeDosing?.canonicalUnit ?? unit
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
        syncEmptiness()
    }

    func remove(_ item: StagedDose) {
        staged.removeAll { $0.id == item.id }
        expandedItemIDs.remove(item.id)
        syncEmptiness()
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

// MARK: - Staged List Card

/// The staged doses as a grouped-style card (matching the system inset-grouped
/// list): one row per dose, expanding inline into its editor — never a second
/// sheet. Every row — collapsed or expanded — swipes left to delete.
struct TrayStagedListCard: View {
    @Bindable var model: DoseTrayModel

    /// Ties each collapsed row to its expanded editor so the name, amount,
    /// route, and chevron morph in place instead of cross-fading.
    @Namespace private var morphNamespace

    var body: some View {
        VStack(spacing: 0) {
            ForEach($model.staged) { $item in
                TraySwipeRow(onDelete: { withAnimation(.snappy) { model.remove(item) } }) {
                    if model.expandedItemIDs.contains(item.id) {
                        StagedDoseEditor(item: $item, namespace: morphNamespace) {
                            withAnimation(.snappy) { _ = model.expandedItemIDs.remove(item.id) }
                        } onRemove: {
                            withAnimation(.snappy) { model.remove(item) }
                        }
                        .padding(8)
                    } else {
                        TrayRow(dose: item, model: model, namespace: morphNamespace)
                            .padding(.horizontal, 8)
                    }
                }
                if item.id != model.staged.last?.id {
                    Divider().padding(.leading, 42)
                }
            }
        }
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: DoseTrayMetrics.cardCornerRadius, style: .continuous),
        )
    }
}

// MARK: - Commit Bar

/// The tray's shared bottom bar — the When/Tags/Location chips and the Log
/// button. Hosted in the dock's bottom `safeAreaBar`, so scroll content can
/// pass beneath it with the soft edge effect.
///
/// At accessibility text sizes the chips leave the bar: stacked, the pinned
/// bar alone outgrew the compact detent's cap and clipped the Log button —
/// the flow's primary action. The dock renders ``TrayMetaChips`` inside the
/// scroll content instead, and only the button stays pinned.
struct TrayCommitBar: View {
    @Bindable var model: DoseTrayModel
    let tagSuggestions: [String]
    /// Distinct places from dose history, most recent first — the inline
    /// location panel offers the first three, the full picker all of them.
    let recentLocations: [PickedLocation]
    let onCommit: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 0) {
            if !dynamicTypeSize.isAccessibilitySize {
                TrayMetaChips(model: model, tagSuggestions: tagSuggestions, recentLocations: recentLocations)

                commitButton
                    .padding(.top, 14)
            } else {
                commitButton
            }
        }
    }

    // MARK: Commit

    private var commitButton: some View {
        Button(action: onCommit) {
            Text(commitLabel)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                // The dock contract: the Log button and the search field
                // share one frame, so the faces morph into one another.
                .frame(height: DoseTrayMetrics.controlHeight)
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

// MARK: - Meta Chips

/// The tray-wide When/Tags/Location chips with their anchored presentations.
/// Rendered inside ``TrayCommitBar`` normally; at accessibility sizes the
/// dock hosts them in the scroll content (see ``TrayCommitBar``).
struct TrayMetaChips: View {
    @Bindable var model: DoseTrayModel
    let tagSuggestions: [String]
    let recentLocations: [PickedLocation]

    @State private var showLocationPicker = false
    /// Anchored presentations off the chips — Apple's idiom for quick options
    /// (menus/popovers) instead of the old inline floating panels.
    @State private var showTagsPopover = false
    @State private var showDatePopover = false
    @State private var showLocationDeniedAlert = false
    /// Owns current-location requests for the location menu; the chip shows a
    /// spinner while a request is in flight.
    @State private var locationModel = LocationSearchModel()
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Chips side by side normally; stacked at accessibility sizes, where
    /// three capsules can't share the row — squeezed, their labels wrapped
    /// character-per-line into vertical columns.
    private var chipLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
    }

    var body: some View {
        chipLayout {
            whenChip
            tagsChip
            locationChip
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sensoryFeedback(.selection, trigger: model.time)
        .sheet(isPresented: $showLocationPicker) {
            LocationPickerView(recents: recentLocations) { picked in
                model.location = picked
            }
        }
        .alert("Location access is off", isPresented: $showLocationDeniedAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Turn on location access in Settings to use your current location.")
        }
    }

    // MARK: Shared controls

    /// The visible chip is plain SwiftUI with the Menu overlaid as an invisible
    /// tap target. As a `Menu` *label* the chip's width was sized by the
    /// UIKit-backed menu button, which applies the new size outside the SwiftUI
    /// transaction — the colour crossfaded at the old width, then the frame
    /// snapped. Decoupled, the whole chip animates in one `.snappy` pass.
    private var whenChip: some View {
        HStack(spacing: 5) {
            Image(systemName: "clock")
                .imageScale(.small)
            Text(model.time.chipLabel)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
        }
        .font(.subheadline.weight(.semibold))
        // Pin the label to its ideal width so the new string isn't clipped to
        // the interpolating frame (which flashed truncated text mid-animation).
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            model.time.isNow ? AnyShapeStyle(Color(.secondarySystemFill)) : AnyShapeStyle(Color.orange.opacity(0.18)),
            in: Capsule(),
        )
        .foregroundStyle(model.time.isNow ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.orange))
        .animation(.snappy, value: model.time)
        // The overlay Menu is the accessible element — expose only it, or
        // VoiceOver stops on the decorative chip content too.
        .accessibilityHidden(true)
        .overlay {
            Menu {
                whenMenuItems
            } label: {
                Color.clear.contentShape(Capsule())
            }
            .accessibilityLabel(Text("Dose time: \(model.time.chipLabel)"))
        }
        .popover(isPresented: $showDatePopover, arrowEdge: .bottom) {
            DatePicker(
                "When",
                selection: Binding(
                    get: {
                        if case let .custom(date) = model.time { date } else { model.time.resolved }
                    },
                    set: { model.time = .custom($0) },
                ),
                in: ...Date.now,
            )
            .datePickerStyle(.graphical)
            .frame(width: 320)
            .padding(12)
            .presentationCompactAdaptation(.popover)
        }
    }

    @ViewBuilder
    private var whenMenuItems: some View {
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
            withAnimation(.snappy) { model.time = .custom(model.time.resolved) }
            // Presenting while the menu is still tearing down races UIKit's
            // presentation slot — defer one runloop turn.
            Task { @MainActor in showDatePopover = true }
        } label: {
            Label("Pick date & time…", systemImage: "calendar")
        }
    }

    /// Tag toggles live in an anchored popover (Apple's quick-options idiom),
    /// not an inline panel that reflows the whole bar.
    private var tagsChip: some View {
        Button {
            showTagsPopover = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "tag")
                    .imageScale(.small)
                if model.tags.isEmpty {
                    Text("Tags")
                        .lineLimit(1)
                } else {
                    Text(verbatim: "\(model.tags.count)")
                }
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                model.tags.isEmpty ? AnyShapeStyle(Color(.secondarySystemFill)) : AnyShapeStyle(Theme.accent.opacity(0.15)),
                in: Capsule(),
            )
            .foregroundStyle(model.tags.isEmpty ? AnyShapeStyle(.primary) : AnyShapeStyle(Theme.accent))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showTagsPopover, arrowEdge: .bottom) {
            TrayTagsPopover(model: model, tagSuggestions: tagSuggestions)
                .presentationCompactAdaptation(.popover)
        }
    }

    /// A native Menu — current location, recent places, the full search, and
    /// remove — with the same decoupled chip visual as the when chip (the
    /// label resizes when a place is picked).
    private var locationChip: some View {
        HStack(spacing: 5) {
            if locationModel.isLocating {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Image(systemName: model.location == nil ? "mappin.and.ellipse" : "mappin.circle.fill")
                    .imageScale(.small)
            }
            if let location = model.location {
                Text(location.name)
                    .lineLimit(1)
            } else {
                Text("Location")
                    .lineLimit(1)
            }
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            model.location == nil ? AnyShapeStyle(Color(.secondarySystemFill)) : AnyShapeStyle(Theme.accent.opacity(0.15)),
            in: Capsule(),
        )
        .foregroundStyle(model.location == nil ? AnyShapeStyle(.primary) : AnyShapeStyle(Theme.accent))
        .frame(maxWidth: 180, alignment: .leading)
        .animation(.snappy, value: model.location)
        // The overlay Menu is the accessible element — expose only it, or
        // VoiceOver stops on the decorative chip content too.
        .accessibilityHidden(true)
        .overlay(alignment: .leading) {
            Menu {
                locationMenuItems
            } label: {
                Color.clear.contentShape(Capsule())
            }
            .accessibilityLabel(model.location.map { Text("Location: \($0.name)") } ?? Text("Location"))
        }
    }

    @ViewBuilder
    private var locationMenuItems: some View {
        Button {
            Task {
                guard let picked = await locationModel.requestCurrentLocation() else {
                    if locationModel.authDenied { showLocationDeniedAlert = true }
                    return
                }
                withAnimation(.snappy) { model.location = picked }
            }
        } label: {
            Label("Current Location", systemImage: "location.fill")
        }
        ForEach(Array(recentLocations.prefix(3)), id: \.name) { place in
            Button {
                withAnimation(.snappy) { model.location = place }
            } label: {
                if model.location == place {
                    Label(place.name, systemImage: "checkmark")
                } else {
                    Label(place.name, systemImage: "mappin.circle.fill")
                }
            }
        }
        Button {
            showLocationPicker = true
        } label: {
            Label("Find a Place…", systemImage: "magnifyingglass")
        }
        if model.location != nil {
            Divider()
            Button(role: .destructive) {
                withAnimation(.snappy) { model.location = nil }
            } label: {
                Label("Remove location", systemImage: "xmark")
            }
        }
    }
}

// MARK: - Tags Popover

/// The tags chip's anchored popover: the suggestion + selected tag chips as
/// toggles. Reads/writes the model directly; dismisses on outside taps like
/// any popover.
private struct TrayTagsPopover: View {
    @Bindable var model: DoseTrayModel
    let tagSuggestions: [String]

    private var allTagChoices: [String] {
        tagSuggestions + model.tags.filter { !tagSuggestions.contains($0) }.sorted()
    }

    var body: some View {
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
        .frame(width: 280)
        .padding(14)
    }
}

// MARK: - Swipe Row

/// Swipe-to-delete container for one staged row — collapsed or expanded, the
/// same leftward swipe reveals the delete capsule (full swipe removes). The
/// content stays fully interactive at rest; while the delete strip is
/// revealed, the first tap anywhere on the row closes it again.
private struct TraySwipeRow<Content: View>: View {
    let onDelete: () -> Void
    @ViewBuilder var content: Content

    @State private var offset: CGFloat = 0

    private static var revealWidth: CGFloat {
        64
    }
    private static var fullSwipeThreshold: CGFloat {
        180
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            deleteBackdrop
            content
                // The row's own surface slides with it, and it turns visible
                // (a grey rounded surface, like the row capsule Reminders
                // shows mid-swipe) so the *background* reads as moving — on
                // the white card a white surface sliding is invisible.
                .background {
                    RoundedRectangle(cornerRadius: DoseTrayMetrics.cardCornerRadius, style: .continuous)
                        .fill(Color(.secondarySystemFill))
                        .opacity(offset < -1 ? 1 : 0)
                }
                .offset(x: offset)
                .overlay {
                    if offset != 0 {
                        // Tap-catcher while revealed — swallows the tap that
                        // would otherwise expand/edit and closes the strip.
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.snappy) { offset = 0 }
                            }
                    }
                }
                // The swipe gesture is invisible to assistive tech — expose
                // deletion as a rotor action on the row itself.
                .accessibilityAction(named: Text("Remove")) {
                    onDelete()
                }
        }
        .clipped()
        .gesture(swipeGesture)
    }

    /// The revealed action: a compact red capsule pill, vertically centered —
    /// the iOS 26 swipe-action button (see Reminders), not a full-height fill.
    private var deleteBackdrop: some View {
        Button {
            onDelete()
        } label: {
            Capsule()
                .fill(.red)
                .overlay {
                    Image(systemName: "trash.fill")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                }
                .frame(width: Self.revealWidth - 8, height: 44)
        }
        .buttonStyle(.plain)
        .frame(maxHeight: .infinity, alignment: .center)
        .padding(.trailing, 8)
        .accessibilityLabel("Remove")
        .opacity(offset < -1 ? 1 : 0)
        // Hidden until the swipe reveals it — otherwise VoiceOver stops on an
        // invisible button behind every row.
        .accessibilityHidden(offset >= -1)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                offset = min(0, value.translation.width)
            }
            .onEnded { value in
                if offset < -Self.fullSwipeThreshold || value.predictedEndTranslation.width < -Self.fullSwipeThreshold * 1.5 {
                    onDelete()
                } else if offset < -Self.revealWidth / 2 {
                    withAnimation(.snappy) { offset = -Self.revealWidth }
                } else {
                    withAnimation(.snappy) { offset = 0 }
                }
            }
    }
}

// MARK: - Tray Row

/// A staged dose as a compact row: a downward disclosure chevron (it expands
/// in place — never navigates) — tap expands the inline editor; the enclosing
/// ``TraySwipeRow`` owns swipe-to-delete.
private struct TrayRow: View {
    let dose: StagedDose
    /// Stable reference, not parent closures: the row toggles its own
    /// expansion / removal through the model. With no closures and an
    /// `Equatable` `dose`, SwiftUI can compare `TrayRow` and skip the body of
    /// a collapsed row whose dose didn't change — so editing one staged
    /// amount no longer re-evaluates every other row.
    let model: DoseTrayModel
    let namespace: Namespace.ID

    private func expand() {
        withAnimation(.snappy) { _ = model.expandedItemIDs.insert(dose.id) }
    }

    var body: some View {
        // 8pt chevron→text gap: with the row's 8pt edge padding and the 16pt
        // chevron frame, the chevron sits exactly midway between card edge
        // and text.
        HStack(spacing: 8) {
            // Disclosure chevron leads the row (matching the search results).
            // Apple's convention: points right collapsed, down expanded — the
            // editor renders the same glyph rotated 90°, so the matched-
            // geometry swap reads as the chevron rotating in place.
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 16)
                .trayMorph(id: "chevron-\(dose.id)", in: namespace)
            VStack(alignment: .leading, spacing: 2) {
                // Same font and leading column as "Add another…" so the
                // tray reads as one aligned list (the colour dot is gone —
                // the chips already carry the substance colour).
                Text(CustomSubstanceStore.shared.displayName(for: dose.substanceName))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .trayMorph(id: "title-\(dose.id)", in: namespace)
                // Day-list phrase: "oral · 100 mg · strong" — route as
                // context, the amount emphasised, the level read via colour.
                HStack(spacing: 5) {
                    Text(dose.route.localizedName)
                        .textCase(.lowercase)
                        .foregroundStyle(Theme.secondaryLabel)
                        .trayMorph(id: "route-\(dose.id)", in: namespace)
                    Text(verbatim: "·").foregroundStyle(.tertiary)
                    Text(verbatim: "\(dose.totalAmount.doseFormatted) \(dose.unit.unitDisplay(for: dose.totalAmount))")
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        // During the collapse morph the matched siblings carry
                        // inflated mid-flight frames (the route text pairs with
                        // the editor's wide pill), squeezing this text into a
                        // momentary "37.…" ellipsis. Fixed-size keeps it at its
                        // intrinsic width for the whole animation.
                        .fixedSize()
                        .trayMorph(id: "amount-\(dose.id)", in: namespace)
                    // No level for a zero amount — "0 g · sub-threshold" reads
                    // like a valid dose; the trailing warning marks it instead.
                    if dose.totalAmount > 0, let level = dose.doseLevel {
                        Text(verbatim: "·").foregroundStyle(.tertiary)
                        Text(level.displayName)
                            .textCase(.lowercase)
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
            // A zero-amount dose blocks the Log button — flag it on the row,
            // otherwise the disabled button gives no clue which dose is why.
            if dose.totalAmount <= 0 {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Needs an amount")
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture(perform: expand)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Expands the editor")
    }
}
