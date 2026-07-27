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
    /// Whether this side of the pair defines the geometry the other adopts.
    let isSource: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.matchedGeometryEffect(id: id, in: namespace, isSource: isSource)
        }
    }
}

extension View {
    /// `matchedGeometryEffect` for the tray's row⇄editor morph pairs,
    /// degrading to a plain crossfade under Reduce Motion.
    ///
    /// Exactly one side of each pair must be the source. Both sides used to take
    /// the default `isSource: true`, which is undefined behavior — two views
    /// claiming one id in one namespace — and it read as the snap-then-settle
    /// the expansion animation was reported for. The collapsed row is the source
    /// because it is the state the tray sits in.
    func trayMorph(id: String, in namespace: Namespace.ID, isSource: Bool = true) -> some View {
        modifier(TrayMorphEffect(id: id, namespace: namespace, isSource: isSource))
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
    /// Selected stereoisomer form (D/S/L/R). `nil` = racemic/unspecified — the
    /// common case; set for the handful of isomer families (Focalin, Esketamine…).
    var isomer: String?
    /// The name the user named this dose by — the alias their search matched
    /// ("Concerta"), or the literal string a daily item was saved under. `nil`
    /// when they named the canonical substance.
    ///
    /// This is the *only* record that the dose was Concerta and not Ritalin:
    /// `substanceName` is canonicalized at staging, so once this is dropped the
    /// distinction is gone for good.
    var productName: String?
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
        isomer: String? = nil,
        productName: String? = nil,
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
        self.isomer = isomer
        self.productName = productName
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
              let range = librarySubstance.doseRange(for: route, saltForm: saltForm, isomer: isomer) else { return nil }
        let referenceUnit = librarySubstance.unit(for: route, saltForm: saltForm, isomer: isomer)
        let normalized = unit.caseInsensitiveCompare(referenceUnit) == .orderedSame
            ? totalAmount
            : (librarySubstance.convert(amount: totalAmount, from: unit, toRoute: route, saltForm: saltForm) ?? totalAmount)
        return range.level(for: normalized)
    }

    /// The library's reference dose for this item's route, in this item's
    /// unit — anchors stepper increments and draft prefills to what a person
    /// actually takes (LSD steps in 10 µg, not 0.25 µg).
    var referenceDose: Double? {
        Self.lookupReferenceDose(substance: librarySubstance, route: route, unit: unit, saltForm: saltForm, isomer: isomer)
    }

    /// The PSID FAMILY for the staged substance, snapshotted onto the committed
    /// dose so it carries a stable identity from log time (not only via backfill).
    var substanceUID: String? {
        librarySubstance?.substanceUID
    }

    /// The release form the staged dose names — "Concerta" is Methylphenidate, but
    /// it is the XR product, so the committed dose records `"XR"`. Derived, not
    /// stored: with no release picker there is nothing for a user to choose, so the
    /// name is the only source.
    ///
    /// Resolves `productName` **first**. `substanceName` is canonicalized the moment
    /// a search hit is staged (`QuickLogSearchResults.payload(for:)`), so asking it
    /// about a release form asks the wrong string: "Concerta" has already become
    /// "Methylphenidate", which names no form, and the answer is always `nil`. Only
    /// the daily-item path — which stages the user's literal string — ever worked.
    ///
    /// This has to happen at log time. A committed dose gets its uid here, so the
    /// (`substanceUID == nil`)-gated backfill will never revisit it, and by then the
    /// typed string is gone: a Concerta dose that commits without its form is
    /// byte-identical to a Ritalin one, forever.
    var releaseForm: String? {
        SubstanceLibrary.releaseForm(for: productName ?? substanceName)
    }

    /// The locale-stable identity anchor to snapshot onto the committed dose —
    /// the full composed form title across both facets ("Dexmethylphenidate XR"),
    /// not just the isomer's name. See ``DoseTitle/snapshot(canonicalName:isomer:releaseForm:)``.
    var displayNameSnapshot: String? {
        DoseTitle.snapshot(canonicalName: substanceName, isomer: isomer, releaseForm: releaseForm)
    }

    /// This staged dose's substance-identity key — matched against a recents
    /// card's ``SubstanceCard/id`` so its staged-count badge lands on the right
    /// card (Concerta's staged count on the Concerta card, not Ritalin's). See
    /// ``QuickLogDose/identityKey``.
    var identityKey: String {
        QuickLogDose.identityKey(
            substanceUID: substanceUID, substance: substanceName,
            isomer: isomer, releaseForm: releaseForm, saltForm: saltForm,
        )
    }

    /// What to call this dose while it's staged — the same answer the search row
    /// above it gave, and the journal row below it will give.
    ///
    /// `substanceName` is canonical, so titling from it made the tray contradict
    /// the row that fed it: you tapped "Concerta" and a card named
    /// "Methylphenidate" appeared. Mirrors ``DoseTitle``'s precedence, minus the
    /// facets a staged dose can't have yet resolved.
    var displayTitle: String {
        if let relabel = CustomSubstanceStore.shared.relabel(forCanonicalName: substanceName) { return relabel }
        if let productName, !productName.isEmpty { return productName }
        if let isomer, let librarySubstance,
           let named = librarySubstance.isomerOptions(for: route).first(where: { $0.code == isomer })?.displayName {
            return named
        }
        return CustomSubstanceStore.shared.displayName(for: substanceName)
    }

    static func lookupReferenceDose(substance: Substance?, route: RouteOfAdministration, unit: String, saltForm: String? = nil, isomer: String? = nil) -> Double? {
        guard let substance,
              let doses = substance.doseRange(for: route, saltForm: saltForm, isomer: isomer),
              substance.unit(for: route, saltForm: saltForm, isomer: isomer) == unit
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
        // Bucketed by substance *identity* (== a card's `id`), so a Concerta chip's
        // staged count shows on the Concerta card, not a plain Methylphenidate one.
        var byIdentity: [String: [StagedChipKey: Int]] = [:]
        for dose in staged {
            let identity = dose.identityKey
            var keyed = byIdentity[identity] ?? [:]
            for component in dose.components {
                let key = StagedChipKey(route: dose.route, unit: dose.unit, amountKey: Self.displayKey(component.amount))
                keyed[key, default: 0] += component.count
            }
            byIdentity[identity] = keyed
        }
        return byIdentity.mapValues { StagedChipCounts(counts: $0) }
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
        productName: String? = nil,
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
                isomer: Self.seedIsomer(productName: productName, librarySubstance: librarySubstance, route: route),
                productName: productName,
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

    /// The isomer a staged dose should open on: the one its product names, else
    /// the route's default.
    ///
    /// A user who searched "Focalin" has already told us the enantiomer — opening
    /// the picker on racemic Methylphenidate would make them re-answer a question
    /// they answered by typing, and silently mis-classify the dose against the
    /// racemic ladder if they don't notice. Guarded on the option actually
    /// existing for this route, since the alias names a substance-wide fact while
    /// the ladder is per-route (methylphenidate has a D ladder on oral but not
    /// insufflation).
    static func seedIsomer(productName: String?, librarySubstance: Substance?, route: RouteOfAdministration) -> String? {
        guard let productName,
              let named = SubstanceLibrary.isomer(for: productName),
              let substance = librarySubstance,
              substance.isomerOptions(for: route).contains(where: { $0.code == named })
        else { return librarySubstance?.defaultIsomer(for: route) }
        return named
    }

    /// Stage a draft (from search / the ⋯ chip) and open it for editing.
    /// Prefilled with the library's common dose when one is known — the
    /// editor focuses the amount field only when it opens empty. A draft for
    /// an already-staged substance opens that row instead of duplicating it.
    func stageDraft(
        substance: String,
        route: RouteOfAdministration,
        unit: String,
        colorHex: String?,
        librarySubstance: Substance?,
        productName: String? = nil,
    ) {
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
            isomer: Self.seedIsomer(productName: productName, librarySubstance: librarySubstance, route: route),
            productName: productName,
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
