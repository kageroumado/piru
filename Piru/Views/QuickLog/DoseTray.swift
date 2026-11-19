import SwiftData
import SwiftUI

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

    /// The stepper increment: `niceStep` off the library reference dose when one is
    /// known, else a magnitude table on the amount itself. Shared by the tray editor
    /// and the watch quick-log so both nudge in the same increments.
    static func step(referenceDose: Double?, amount: Double) -> Double {
        if let referenceDose {
            return niceStep(for: referenceDose)
        }
        return switch amount {
        case ..<2: 0.25
        case ..<10: 1
        case ..<100: 5
        case ..<1_000: 25
        default: 100
        }
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
    /// system inset-grouped list.
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
    /// Exactly one side of each pair must be the source: two views claiming one
    /// id in one namespace is undefined behavior, and it reads as a
    /// snap-then-settle on expansion. The collapsed row is the source because it
    /// is the state the tray sits in.
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

        /// Every staged amount enters through here, so a typed, derived or
        /// automated value is held to ``StagedDose/sanitizedAmount(_:)``.
        init(amount: Double, count: Int = 1) {
            self.amount = StagedDose.sanitizedAmount(amount)
            self.count = max(1, count)
        }
    }

    /// The largest amount one staged component may carry, in any unit: a
    /// billion µg is a kilogram, past anything a person logs, and well inside
    /// the range the tray's integer chip keys and the PK engines handle.
    static let maximumAmount: Double = 1_000_000_000

    /// `value` as a stageable amount: zero when it is not finite or negative
    /// (a URL, a Shortcut or the amount field can hand over `inf` or `nan`),
    /// otherwise at most ``maximumAmount``.
    static func sanitizedAmount(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else { return 0 }
        return min(value, maximumAmount)
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
    /// The release form this dose records — "Concerta" is Methylphenidate, but the
    /// XR product, so it records `"XR"`. `nil` = standard/unspecified.
    ///
    /// Seeded at staging from the name (see the `init`), so a searched brand keeps
    /// its form with no picker interaction; settable by the "Form" pill for the
    /// bare-molecule path. It must be resolved by log time: a committed dose gets
    /// its uid at commit, so the (`substanceUID == nil`)-gated backfill never
    /// revisits it, and by then the typed string is gone — a Concerta dose that
    /// commits without its form is byte-identical to a Ritalin one, forever.
    var releaseForm: String?
    /// The name the user named this dose by — the alias their search matched
    /// ("Concerta"), or the literal string a daily item was saved under. `nil`
    /// when they named the canonical substance.
    ///
    /// This is the *only* record that the dose was Concerta and not Ritalin:
    /// `substanceName` is canonicalized at staging, so once this is dropped the
    /// distinction is gone for good.
    var productName: String?
    var note: String = ""
    var tint: P3Color?
    var librarySubstance: Substance?
    /// Staged from the Daily routine card. Daily items keep their own surface,
    /// so they don't mint quick-log chips on commit.
    var isFromDailySet = false
    /// Carried from `DailyDoseItem.isBackgroundMed` onto the committed entry.
    var isBackgroundMed = false
    /// Per-dose "had grapefruit" flag (Stage 4c). Only ever toggled for CYP3A4-heavy
    /// substrates when grapefruit logging is enabled; carried onto the committed entry.
    var hadGrapefruit = false
    /// The user took this without knowing how much. The staged components are
    /// kept (toggling back restores them) but the row reads `?`, no level or
    /// breakdown is shown, and the dose commits as ``DoseEntry/isUnknownDose``
    /// with `amount = 0`.
    var isUnknownAmount = false
    /// By-volume metadata recorded when a custom drink is logged (alcohol),
    /// carried onto the committed entry's structured fields so it round-trips on
    /// edit. `nil` for preset/grams doses.
    var volumeML: Double?
    var abv: Double?
    var drinkName: String?
    /// Emoji of the selected drink preset, carried onto the quick-log chip so a
    /// re-logged drink keeps its glyph. Display-only; not persisted on `DoseEntry`.
    var emoji: String?
    /// The combination product this row was staged from ("Co-codamol" on its
    /// paracetamol row), carried onto the committed entry. `nil` for a dose
    /// staged on its own. For a liquid product, ``volumeML`` is the volume
    /// taken and ``abv`` this component's amount per mL in ``unit``.
    var combinationName: String?
    /// Where an intramuscular or subcutaneous dose goes, carried onto the
    /// committed entry. The editor seeds it from the rotation
    /// (``InjectionSiteHistory``) until the user picks or clears one, which
    /// ``injectionSiteTouched`` records so a re-opened row keeps the choice.
    var injectionSite: InjectionSite?
    var injectionSiteTouched = false

    /// A component of a liquid combination, staged by volume: the editor shows
    /// the product's volume in place of a mass field, and the amount is always
    /// volume × amount per mL.
    var isLiquidCombinationRow: Bool {
        combinationName != nil && volumeML != nil && abv != nil
    }

    /// The user opened this row to type into it (the sliders pill, a row tap),
    /// so the editor focuses the amount field on appear — even over a seeded
    /// reference dose. The editor clears it once consumed. Stays false for
    /// rows the dock re-opens on its own (growing out of compact), which must
    /// never raise the keyboard unasked.
    var wantsAmountFocus = false

    init(
        substanceName: String,
        amount: Double,
        unit: String,
        route: RouteOfAdministration,
        saltForm: String? = nil,
        isomer: String? = nil,
        productName: String? = nil,
        tint: P3Color? = nil,
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
        // Seed the release form from the name the dose was staged by ("Concerta" →
        // "XR"), matching what the alias table records; the "Form" pill overrides it
        // on the bare-molecule path. `productName` leads: `substanceName` is
        // canonicalized at staging, so it names no form and would always answer nil.
        self.releaseForm = SubstanceLibrary.releaseForm(for: productName ?? substanceName)
        self.productName = productName
        self.tint = tint
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
        guard !isUnknownAmount, components.count > 1 || (components.first?.count ?? 1) > 1 else { return nil }
        return components
            .map { $0.count > 1 ? "\($0.count) × \($0.amount.doseFormatted)" : $0.amount.doseFormatted }
            .joined(separator: " + ")
    }

    /// Where the merged total lands on the substance's dose ladder — `nil`
    /// when no ladder describes this dose: no dose data for the route, or a
    /// release form the ladder wasn't written for (a Concerta tablet). See
    /// ``Substance/tierLadder(for:saltForm:isomer:releaseForm:)``.
    var doseLevel: DoseLevel? {
        guard !isUnknownAmount, let librarySubstance, librarySubstance.displayClass.showsDoseLadder else { return nil }
        return librarySubstance.doseLevel(
            of: librarySubstance.quantity(totalAmount, unit: unit),
            route: route, saltForm: saltForm, isomer: isomer, releaseForm: releaseForm,
        )
    }

    /// The library's reference dose for this item's route, in this item's
    /// unit — anchors stepper increments and draft prefills to what a person
    /// actually takes (LSD steps in 10 µg, not 0.25 µg).
    var referenceDose: Double? {
        librarySubstance?.referenceDose(route: route, unit: unit, saltForm: saltForm, isomer: isomer)
    }

    /// The PSID FAMILY for the staged substance, snapshotted onto the committed
    /// dose so it carries a stable identity from log time (not only via backfill).
    var substanceUID: String? {
        librarySubstance?.substanceUID
    }

    /// Hormone esters offered for `route` (Estradiol → Cypionate / Valerate /
    /// Enanthate), from the `ester_pk` table. Offered on oral as well as the two
    /// injection routes — estradiol valerate is also an oral tablet (Progynova), and
    /// the ester is meaningful on either. Empty on other routes (patches are plain
    /// estradiol) and for substances with no ester data. The depot curve still only
    /// consumes IM/SC doses; a route/parameter mismatch is the tool's note to make,
    /// not a reason to hide the ester the person actually took.
    @MainActor
    func esterForms(for route: RouteOfAdministration) -> [String] {
        guard route == .oral || route == .intramuscular || route == .subcutaneous,
              let uid = substanceUID else { return [] }
        return SubstanceStore.shared.esters(forParentUID: uid).map(\.label)
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
        let base: String = if let productName, !productName.isEmpty {
            productName
        } else if let isomer, let librarySubstance,
                  let named = librarySubstance.isomerOptions(for: route).first(where: { $0.code == isomer })?.displayName {
            named
        } else {
            CustomSubstanceStore.shared.displayName(for: substanceName)
        }
        // Fold an injectable ester into the name — "Estradiol Valerate" — matching
        // ``DoseTitle/resolve(for:)`` so the tray and the journal row agree.
        if SubstanceStore.shared.isEster(saltForm, forParentUID: substanceUID),
           let ester = saltForm, !base.localizedCaseInsensitiveContains(ester) {
            return "\(base) \(ester)"
        }
        return base
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
        // Whole hours read as "2h ago"; anything with leftover minutes stays in
        // minutes ("90 min ago") rather than rounding down to a wrong "1h ago".
        minutes >= 60 && minutes % 60 == 0
            ? String(localized: "\(minutes / 60)h ago")
            : String(localized: "\(minutes) min ago")
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

// MARK: - Dose Time Presets

/// The user-configurable relative-time presets shown in the "When" menu, stored
/// as a comma-joined list of minutes in the shared app-group suite. Parse falls
/// back to the defaults for empty/garbled input, so a bad write can never leave
/// the menu with no quick times.
enum DoseTimeDefaults {
    static let suite = AppIdentity.appGroup
    static let choicesKey = "doseTimeOffsetChoices"

    static let defaultChoices = [15, 30, 60, 120]
    static let defaultRaw = "15,30,60,120"

    /// A single preset spans one minute to a full day.
    static let range = 1 ... (24 * 60)
    /// The menu stays legible with a bounded number of presets.
    static let maxCount = 6

    static func parse(_ raw: String) -> [Int] {
        let minutes = raw
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            .filter { range.contains($0) }
        return minutes.isEmpty ? defaultChoices : minutes
    }

    static func format(_ choices: [Int]) -> String {
        choices.map(String.init).joined(separator: ",")
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

/// One chip across the whole tray: the staged row's substance identity plus
/// the chip within it. What a My Meds pill records per dose it staged.
struct StagedChipUnit: Hashable {
    let identity: String
    let chip: StagedChipKey
    /// The combination product the chip's row was staged from, `nil` for a
    /// dose staged on its own: a product's component is a row of its own.
    var combinationName: String?
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
    /// What was eaten before this dose. Tray-wide like the location, but committed
    /// only onto oral doses: it is the stomach an oral dose waits in.
    var meal: MealState?
    /// The profile this log is for when it is someone other than the active
    /// one (the For chip); `nil` logs into the active profile's journal. Lasts
    /// one log: ``takeRecipient()`` clears it at commit.
    var recipientID: UUID?
    /// Every staged dose the user has opened inline — multiple can stay
    /// expanded at once, so a complex stack can be composed in one pass.
    var expandedItemIDs: Set<UUID> = []

    /// Haptic triggers — bumped on discrete staging events so the view can
    /// attach `.sensoryFeedback` without coupling feedback to every tap.
    private(set) var stageTick = 0
    private(set) var incrementTick = 0
    /// Bumped when a My Meds pill takes its doses back out of the tray.
    private(set) var unstageTick = 0

    /// What each My Meds pill's taps put in the tray, keyed by the pill's
    /// ``DailyCategoryGroup/id``: units per chip. A second tap subtracts
    /// exactly this, so a dose added by any other path — another substance,
    /// one more unit of a med the pill also staged — stays put.
    private var pillContributions: [String: [StagedChipUnit: Int]] = [:]

    /// Stored — *not* computed from `staged` — so a view reading it (the
    /// toolbar's close button, the dock's face selection in `QuickLogView.body`)
    /// subscribes to *this* flag rather than the whole `staged` array. Maintained
    /// only at the count-change sites (`stage` append / `stageDraft` / `remove`),
    /// and only when the value actually flips, so stepping a dose's amount or
    /// re-tapping a chip, which mutate `staged` but not its count, doesn't
    /// re-run `QuickLogView.body`. `isCommittable` stays computed: it depends on
    /// per-dose amounts and is read only inside `DoseTrayView`, which must
    /// re-render on those edits anyway.
    private(set) var isEmpty = true

    /// Re-sync the stored ``isEmpty`` after a count change, notifying only on a
    /// real flip (an `@Observable` set always notifies, even for an equal value).
    /// The profile to log for, handed to the commit and reset to the active
    /// profile, so a choice of someone else never outlives the log it was for.
    func takeRecipient() -> UUID? {
        defer { recipientID = nil }
        return recipientID
    }

    private func syncEmptiness() {
        let nowEmpty = staged.isEmpty
        if nowEmpty != isEmpty { isEmpty = nowEmpty }
    }

    /// Every staged dose carries a number, or has declared it has none.
    var isCommittable: Bool {
        !staged.isEmpty && staged.allSatisfy { $0.isUnknownAmount || $0.totalAmount > 0 }
    }

    /// How many of a given chip are staged (drives the chip's count badge).
    func quantity(substance: String, productName: String? = nil, route: RouteOfAdministration, amount: Double, unit: String) -> Int {
        // Resolve the library record the same way the daily-item staging does, so a
        // faceted med (Concerta) counts on its own row. A dose staged *without* a
        // library record — a custom substance the catalog can't resolve — keys by
        // bare name instead, so match that identity too. The two are disjoint (a
        // uid-bearing key is never a lowercased name), so this can't false-match.
        let resolved = Self.stagedIdentity(substance: substance, productName: productName, librarySubstance: SubstanceLibrary.lookup(substance.lowercased()), route: route)
        let nameOnly = Self.stagedIdentity(substance: substance, productName: productName, librarySubstance: nil, route: route)
        guard let index = staged.firstIndex(where: {
            ($0.identityKey == resolved || $0.identityKey == nameOnly) && $0.route == route && $0.unit == unit
                && $0.combinationName == nil
        }) else { return 0 }
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
        // A product's component counts on the product's card, never on its
        // substance's: that substance's chip stages a row of its own.
        var byIdentity: [String: [StagedChipKey: Int]] = [:]
        for dose in staged where dose.combinationName == nil {
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

    /// The amount in hundredths, rounded at `doseFormatted`'s resolution for
    /// its magnitude. The rounded value is put back into hundredths at every
    /// magnitude, so the key is the amount itself: keyed as a bare
    /// `value × scale`, 4, 40 and 400 would all be 400 and a 400 mg chip
    /// would count as one more 40.
    ///
    /// Total over every `Double`: a non-finite value keys as 0, and the scaled
    /// value is clamped into a range `Int` holds before converting, because
    /// `Int(_:)` traps past `Int.max`. Amounts that large are all one chip.
    fileprivate static func displayKey(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        let magnitude = Swift.abs(value)
        let scale: Double = magnitude >= 100 ? 1 : magnitude >= 10 ? 10 : 100
        let limit = 1e15
        let rounded = min(max((value * scale).rounded(), -limit), limit)
        return Int(rounded * (100 / scale))
    }

    /// Stage a daily-set med as a chip, carrying its product so a Concerta med
    /// logs as Concerta — the tray derives the release form/isomer from it,
    /// same as search.
    func stage(dailyItem item: DailyDoseItem, colorLookup: [String: P3Color]) {
        stage(dailyMed: DailyMedSnapshot(item), colorLookup: colorLookup)
    }

    /// Stage a daily-set med from the My Meds pills' value snapshot. A med
    /// saved as a combination product stages the product: its amount is a
    /// count of units, or a volume in mL for a liquid.
    func stage(dailyMed item: DailyMedSnapshot, colorLookup: [String: P3Color]) {
        if let product = CustomSubstanceStore.shared.combination(named: item.substance) {
            stage(product: product, amount: item.amount, colorLookup: colorLookup)
            for index in staged.indices where staged[index].combinationName == product.name {
                staged[index].isFromDailySet = true
                staged[index].isBackgroundMed = item.isBackgroundMed
            }
            return
        }
        stage(
            substance: item.substance,
            route: item.route,
            amount: item.amount,
            unit: item.unit,
            tint: SubstancePalette.tint(for: item.substance, tintMap: colorLookup),
            librarySubstance: SubstanceLibrary.lookup(item.substance.lowercased()),
            productName: item.productName,
            isFromDailySet: true,
            isBackgroundMed: item.isBackgroundMed,
        )
    }

    // MARK: My Meds pills

    /// Whether a My Meds pill reads as staged: it staged something, and all of
    /// it is still in the tray. A pill whose doses were partly removed by hand
    /// reads as unstaged, and its next tap stages what is missing.
    func isPillStaged(_ pillID: String) -> Bool {
        guard let contribution = pillContributions[pillID], !contribution.isEmpty else { return false }
        return contribution.allSatisfy { unit, count in stagedCount(of: unit) >= count }
    }

    /// One tap on a My Meds pill. A staged pill (``isPillStaged(_:)``) takes
    /// back exactly what it staged; otherwise it stages each of `meds` not
    /// already in the tray from any source — so two pills sharing a med never
    /// stage it twice — and records those units as its own.
    func togglePill(_ pillID: String, meds: [DailyMedSnapshot], colorLookup: [String: P3Color]) {
        if isPillStaged(pillID) {
            unstagePill(pillID)
        } else {
            stagePill(pillID, meds: meds, colorLookup: colorLookup)
        }
    }

    /// Stage the members of a pill that are missing from the tray, adding them
    /// to whatever of the pill's earlier contribution is still there.
    func stagePill(_ pillID: String, meds: [DailyMedSnapshot], colorLookup: [String: P3Color]) {
        var contribution = presentContribution(of: pillID)
        for med in meds {
            let units = Self.chipUnits(for: med)
            guard !units.keys.allSatisfy({ stagedCount(of: $0) > 0 }) else { continue }
            stage(dailyMed: med, colorLookup: colorLookup)
            for (unit, count) in units {
                contribution[unit, default: 0] += count
            }
        }
        pillContributions[pillID] = contribution.isEmpty ? nil : contribution
    }

    /// Take a pill's contribution back out: subtract each recorded unit from
    /// its chip, never past what the chip still holds, and drop rows left
    /// with nothing in them. Units staged by any other path are untouched.
    func unstagePill(_ pillID: String) {
        guard let contribution = pillContributions.removeValue(forKey: pillID) else { return }
        var removedAny = false
        for (unit, count) in contribution {
            guard let rowIndex = staged.firstIndex(where: { Self.matches($0, unit) }),
                  let componentIndex = staged[rowIndex].components.firstIndex(where: { Self.displayKey($0.amount) == unit.chip.amountKey })
            else { continue }
            let available = staged[rowIndex].components[componentIndex].count
            let removing = min(count, available)
            guard removing > 0 else { continue }
            removedAny = true
            if removing == available {
                staged[rowIndex].components.remove(at: componentIndex)
            } else {
                staged[rowIndex].components[componentIndex].count -= removing
            }
            if staged[rowIndex].components.isEmpty {
                expandedItemIDs.remove(staged[rowIndex].id)
                staged.remove(at: rowIndex)
            }
        }
        guard removedAny else { return }
        unstageTick += 1
        syncEmptiness()
    }

    /// The pill's recorded units, each capped at what the tray still holds.
    private func presentContribution(of pillID: String) -> [StagedChipUnit: Int] {
        (pillContributions[pillID] ?? [:]).reduce(into: [:]) { result, entry in
            let present = min(entry.value, stagedCount(of: entry.key))
            if present > 0 { result[entry.key] = present }
        }
    }

    /// Units staged on one chip, across every row carrying its identity.
    private func stagedCount(of unit: StagedChipUnit) -> Int {
        staged
            .filter { Self.matches($0, unit) }
            .flatMap(\.components)
            .filter { Self.displayKey($0.amount) == unit.chip.amountKey }
            .reduce(0) { $0 + $1.count }
    }

    private static func matches(_ dose: StagedDose, _ unit: StagedChipUnit) -> Bool {
        dose.identityKey == unit.identity && dose.route == unit.chip.route && dose.unit == unit.chip.unit
            && dose.combinationName == unit.combinationName
    }

    /// The chips ``stage(dailyMed:colorLookup:)`` files a med under, with how
    /// many units of each: one chip for a med of one substance (its resolved
    /// identity, route, unit and amount), one per component for a combination
    /// product — a count of its amount per unit for a solid, one chip of
    /// volume × amount per mL for a liquid.
    static func chipUnits(for med: DailyMedSnapshot) -> [StagedChipUnit: Int] {
        guard let product = CustomSubstanceStore.shared.combination(named: med.substance) else {
            let identity = stagedIdentity(
                substance: med.substance,
                productName: med.productName,
                librarySubstance: SubstanceLibrary.lookup(med.substance.lowercased()),
                route: med.route,
            )
            let chip = StagedChipKey(route: med.route, unit: med.unit, amountKey: displayKey(med.amount))
            return [StagedChipUnit(identity: identity, chip: chip): 1]
        }
        let isLiquid = product.isLiquidCombination
        let volume = CombinationComponent.volumeML(for: med.amount)
        let count = isLiquid ? 1 : CombinationComponent.units(for: med.amount)
        var units: [StagedChipUnit: Int] = [:]
        for component in product.components ?? [] {
            let library = SubstanceLibrary.lookup(component.substance)
            let identity = stagedIdentity(
                substance: library?.name ?? component.substance, productName: nil,
                librarySubstance: library, route: component.route,
            )
            let amount = isLiquid ? component.amount(inVolumeML: volume) : component.amountPerUnit
            let chip = StagedChipKey(route: component.route, unit: component.unit, amountKey: displayKey(amount))
            units[StagedChipUnit(identity: identity, chip: chip, combinationName: product.name), default: 0] += count
        }
        return units
    }

    /// Stage a chip. Same substance + route + unit + product merges into the
    /// existing row: re-staging the same amount increments its count ("took
    /// two pills"), a different amount joins as a new component ("a 150 and a
    /// 182") — always one entry of the summed total at commit, never two.
    /// `count` stages that many of the chip at once (two tablets of a
    /// combination). `combinationName` labels the row with the product it
    /// came from and is part of the merge key: a component never merges into
    /// another product's row or into a dose staged on its own, so each product
    /// keeps its own rows, quantity and logged entries.
    func stage(
        substance: String,
        route: RouteOfAdministration,
        amount: Double,
        unit: String,
        tint: P3Color?,
        librarySubstance: Substance?,
        productName: String? = nil,
        saltForm: String? = nil,
        isFromDailySet: Bool = false,
        isBackgroundMed: Bool = false,
        volumeML: Double? = nil,
        abv: Double? = nil,
        drinkName: String? = nil,
        emoji: String? = nil,
        count: Int = 1,
        combinationName: String? = nil,
    ) {
        let identity = Self.stagedIdentity(substance: substance, productName: productName, librarySubstance: librarySubstance, route: route, saltForm: saltForm)
        if let index = stagedIndex(identity: identity, route: route, unit: unit, combinationName: combinationName) {
            if let componentIndex = staged[index].components.firstIndex(where: { Self.sameAmount($0.amount, amount) }) {
                staged[index].components[componentIndex].count += count
            } else {
                staged[index].components.append(.init(amount: amount, count: count))
            }
            incrementTick += 1
        } else {
            var dose = StagedDose(
                substanceName: substance,
                amount: amount,
                unit: unit,
                route: route,
                saltForm: saltForm ?? librarySubstance?.saltForms(for: route).first,
                isomer: Self.seedIsomer(productName: productName, librarySubstance: librarySubstance, route: route),
                productName: productName,
                tint: tint,
                librarySubstance: librarySubstance,
                isFromDailySet: isFromDailySet,
                isBackgroundMed: isBackgroundMed,
            )
            dose.components = [.init(amount: amount, count: count)]
            dose.volumeML = volumeML
            dose.abv = abv
            dose.drinkName = drinkName
            dose.emoji = emoji
            dose.combinationName = combinationName
            staged.append(dose)
            stageTick += 1
            syncEmptiness()
        }
    }

    /// Stage a combination product: one chip per component, `quantity` units
    /// of each ("two co-codamol" is 2 × 500 mg paracetamol and 2 × 30 mg
    /// codeine), every row labeled with the product's name. Rows merge like any
    /// other chip, so picking the product again adds another unit to each. A
    /// component whose substance the library no longer knows stages under its
    /// raw name, as a custom substance does.
    ///
    /// A liquid product (``CustomSubstanceEntry/isLiquidCombination``) stages
    /// by volume instead: `quantity` is ignored and it takes
    /// ``CombinationComponent/defaultVolumeML``; see
    /// ``stage(combination:volumeML:colorLookup:)``.
    func stage(combination: CustomSubstanceEntry, quantity: Int = 1, colorLookup: [String: P3Color] = [:]) {
        if combination.isLiquidCombination {
            stage(combination: combination, volumeML: CombinationComponent.defaultVolumeML, colorLookup: colorLookup)
            return
        }
        guard quantity > 0 else { return }
        for component in combination.components ?? [] {
            let library = SubstanceLibrary.lookup(component.substance)
            let name = library?.name ?? component.substance
            stage(
                substance: name,
                route: component.route,
                amount: component.amountPerUnit,
                unit: component.unit,
                tint: SubstancePalette.tint(for: name, tintMap: colorLookup),
                librarySubstance: library,
                count: quantity,
                combinationName: combination.name,
            )
        }
    }

    /// Stage `volumeML` of a liquid combination product: one row per
    /// component, each at volume × its amount per mL in its own unit (0.25 mL
    /// of 2 g/mL morphine is 0.5 g). Each row records the volume and the
    /// per-mL amount (``StagedDose/volumeML`` / ``StagedDose/abv``), which the
    /// committed entries keep and the editor's volume field rescales from.
    /// Picking the product again adds its volume to each row. Rows merge only
    /// with this product's own rows, so a component that another product or a
    /// lone dose shares stays a row of its own.
    func stage(combination: CustomSubstanceEntry, volumeML: Double, colorLookup: [String: P3Color] = [:]) {
        guard volumeML.isFinite, volumeML > 0 else { return }
        let volume = min(volumeML, CombinationComponent.maximumVolumeML)
        for component in combination.components ?? [] {
            let library = SubstanceLibrary.lookup(component.substance)
            let name = library?.name ?? component.substance
            let amount = component.amount(inVolumeML: volume)
            let identity = Self.stagedIdentity(substance: name, productName: nil, librarySubstance: library, route: component.route)
            let existing = stagedIndex(identity: identity, route: component.route, unit: component.unit, combinationName: combination.name)
            let previous = existing.map { (volumeML: staged[$0].volumeML, perML: staged[$0].abv) }
            stage(
                substance: name,
                route: component.route,
                amount: amount,
                unit: component.unit,
                tint: SubstancePalette.tint(for: name, tintMap: colorLookup),
                librarySubstance: library,
                combinationName: combination.name,
            )
            guard let index = existing ?? staged.indices.last else { continue }
            let recordsVolume = Self.recordsCombinationVolume(component: component, library: library)
            if let previous {
                // Merged into this product's row: the volumes add only while
                // that row still records one at the same strength.
                if recordsVolume, let previousML = previous.volumeML, let perML = previous.perML,
                   Self.sameAmount(perML, component.amountPerUnit) {
                    staged[index].volumeML = previousML + volume
                } else {
                    staged[index].volumeML = nil
                    staged[index].abv = nil
                }
            } else if recordsVolume {
                staged[index].volumeML = volume
                staged[index].abv = component.amountPerUnit
            }
        }
    }

    /// Set the volume of a liquid combination already in the tray: every row
    /// staged from `combinationName` that records a volume is re-derived as
    /// `volumeML` × its amount per mL. The editor's volume field calls this,
    /// so one volume moves every component of the product together.
    func setVolume(_ volumeML: Double, ofCombination combinationName: String) {
        guard volumeML.isFinite, volumeML > 0 else { return }
        let volume = min(volumeML, CombinationComponent.maximumVolumeML)
        for index in staged.indices where staged[index].combinationName == combinationName {
            guard staged[index].isLiquidCombinationRow, let perML = staged[index].abv else { continue }
            staged[index].components = [.init(amount: ByVolumeDosing.mass(volumeML: volume, concentrationPerML: perML))]
            staged[index].volumeML = volume
            staged[index].isUnknownAmount = false
        }
    }

    /// Open a liquid combination's product row for editing, so its volume
    /// field is on screen the moment the product is picked: a liquid is staged
    /// at a placeholder 1 mL that the user is about to change. The tray draws
    /// the whole product on its lead row (``leadRowID(ofCombination:)``).
    func openVolume(ofCombination combinationName: String) {
        guard let lead = leadRowID(ofCombination: combinationName) else { return }
        openForEditing(lead)
    }

    // MARK: Combination products

    /// Stage `amount` of a combination product: a count of units for a solid
    /// product, a volume in mL for a liquid one.
    func stage(product: CustomSubstanceEntry, amount: Double, colorLookup: [String: P3Color] = [:]) {
        if product.isLiquidCombination {
            stage(combination: product, volumeML: CombinationComponent.volumeML(for: amount), colorLookup: colorLookup)
        } else {
            stage(combination: product, quantity: CombinationComponent.units(for: amount), colorLookup: colorLookup)
        }
    }

    /// The first row staged from `combinationName`. The tray draws the whole
    /// product, every component beneath one quantity control, on this row and
    /// skips the product's other rows.
    func leadRowID(ofCombination combinationName: String) -> UUID? {
        staged.first { $0.combinationName == combinationName }?.id
    }

    /// How much of a product is staged: units for a solid, read off the lead
    /// component's count at its amount per unit; mL for a liquid. `nil` when
    /// nothing of it is staged or its rows no longer say.
    func stagedQuantity(of product: CustomSubstanceEntry) -> Double? {
        guard let lead = staged.first(where: { $0.combinationName == product.name }) else { return nil }
        if product.isLiquidCombination { return lead.volumeML }
        guard let component = product.components?.first(where: {
            Self.stagedName(of: $0) == lead.substanceName && $0.unit == lead.unit
        }),
            let units = lead.components.first(where: { Self.sameAmount($0.amount, component.amountPerUnit) })?.count
        else { return nil }
        return Double(units)
    }

    /// Set how many units of a solid product are staged: each component's
    /// share of its row becomes `count` × its amount per unit, so one control
    /// moves every component together. Only this product's rows change.
    func setUnits(_ count: Int, of product: CustomSubstanceEntry) {
        let units = min(max(count, 1), CombinationComponent.maximumUnits)
        for component in product.components ?? [] {
            let name = Self.stagedName(of: component)
            for index in staged.indices where staged[index].combinationName == product.name
                && staged[index].substanceName == name && staged[index].unit == component.unit {
                if let share = staged[index].components.firstIndex(where: { Self.sameAmount($0.amount, component.amountPerUnit) }) {
                    staged[index].components[share].count = units
                } else {
                    staged[index].components.append(.init(amount: component.amountPerUnit, count: units))
                }
                staged[index].isUnknownAmount = false
            }
        }
        incrementTick += 1
    }

    /// Take a whole product out of the tray: every row staged from it.
    func removeCombination(_ combinationName: String) {
        let ids = Set(staged.filter { $0.combinationName == combinationName }.map(\.id))
        guard !ids.isEmpty else { return }
        staged.removeAll { ids.contains($0.id) }
        expandedItemIDs.subtract(ids)
        syncEmptiness()
    }

    /// The name a component stages under: the library's canonical name, or the
    /// raw name of a substance the library doesn't carry.
    static func stagedName(of component: CombinationComponent) -> String {
        SubstanceLibrary.lookup(component.substance)?.name ?? component.substance
    }

    /// Whether a liquid component's row may carry the volume on the by-volume
    /// fields. Those fields already mean something for a substance with its
    /// own by-volume input: alcohol reads `abv` as percent, so it never takes
    /// one, and an injectable ester reads it as concentration in its own unit,
    /// so it takes one only when the component is measured in that unit.
    static func recordsCombinationVolume(component: CombinationComponent, library: Substance?) -> Bool {
        guard let capability = library?.byVolumeDosing else { return true }
        return capability.isMassPerVolume && component.unit == capability.canonicalUnit
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

    /// The substance-identity a freshly-staged dose will carry, from the same
    /// facet sources ``StagedDose/identityKey`` derives — so merge dedup keys on
    /// *form* identity, not the canonical name alone. Without this a Concerta
    /// (canonical Methylphenidate + `XR`) staged onto a plain Methylphenidate row
    /// matched by name and summed into it, doubling the dose (they are different
    /// forms and must stay separate rows).
    static func stagedIdentity(
        substance: String,
        productName: String?,
        librarySubstance: Substance?,
        route: RouteOfAdministration,
        saltForm: String? = nil,
    ) -> String {
        QuickLogDose.identityKey(
            substanceUID: librarySubstance?.substanceUID,
            substance: substance,
            isomer: seedIsomer(productName: productName, librarySubstance: librarySubstance, route: route),
            releaseForm: SubstanceLibrary.releaseForm(for: productName ?? substance),
            saltForm: saltForm ?? librarySubstance?.saltForms(for: route).first,
        )
    }

    /// Open a staged row for editing on the user's behalf: expands it and, with
    /// `focusesAmount`, asks the editor to focus the amount field (see
    /// ``StagedDose/wantsAmountFocus``).
    func openForEditing(_ id: UUID, focusesAmount: Bool = true) {
        if focusesAmount, let index = staged.firstIndex(where: { $0.id == id }) {
            staged[index].wantsAmountFocus = true
        }
        expandedItemIDs.insert(id)
    }

    /// Stage a draft (from search / the sliders pill) and open it for editing.
    /// Prefilled with the library's common dose when one is known. A draft for
    /// an already-staged substance opens that row instead of duplicating it.
    ///
    /// `focusesAmount` raises the keyboard on the amount field. Search keeps
    /// it on, since the dock is already full height there. The cards behind the
    /// dock pass `false`: the draft opens at the dock's half-height detent,
    /// and a keyboard there makes UIKit expand the sheet to full height, only
    /// to drop back to half the moment a −/+ tap puts the keyboard down. A
    /// draft with no seeded amount still focuses (the editor's own rule).
    func stageDraft(
        substance: String,
        route: RouteOfAdministration,
        unit: String,
        tint: P3Color?,
        librarySubstance: Substance?,
        productName: String? = nil,
        saltForm: String? = nil,
        focusesAmount: Bool = true,
    ) {
        // A by-volume substance (alcohol) must draft in its canonical unit —
        // the drink editor (By Volume / By Mass) gates on it, so a draft
        // arriving as "units" (a recent's chip unit) would silently lose the
        // whole volumetric logger.
        let unit = librarySubstance?.byVolumeDosing?.canonicalUnit ?? unit
        let identity = Self.stagedIdentity(substance: substance, productName: productName, librarySubstance: librarySubstance, route: route, saltForm: saltForm)
        if let index = stagedIndex(identity: identity, route: route, unit: unit, combinationName: nil) {
            openForEditing(staged[index].id, focusesAmount: focusesAmount)
            return
        }
        let saltForm = saltForm ?? librarySubstance?.saltForms(for: route).first
        // By-volume substances (alcohol, an injectable ester) start at zero: the
        // editor seeds the drink or vial from the substance's last by-volume
        // log, which is a better default than a reference dose in grams.
        let isByVolume = librarySubstance?.byVolumeDosing.map { unit == $0.canonicalUnit } ?? false
        let seedAmount = isByVolume
            ? 0
            : (librarySubstance?.referenceDose(route: route, unit: unit, saltForm: saltForm) ?? 0)
        var draft = StagedDose(
            substanceName: substance,
            amount: seedAmount,
            unit: unit,
            route: route,
            saltForm: saltForm,
            isomer: Self.seedIsomer(productName: productName, librarySubstance: librarySubstance, route: route),
            productName: productName,
            tint: tint,
            librarySubstance: librarySubstance,
        )
        draft.wantsAmountFocus = focusesAmount
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

    /// Staged rows merge on form *identity* + route + unit + product; the distinct amounts
    /// inside match on their *display* form — the user-perceived identity of
    /// a chip. Exact-double matching breaks when the editor round-trips an
    /// amount through its text field (31.700000000000003 → "31.7" → 31.7).
    ///
    /// Keying on ``StagedDose/identityKey`` — not the bare name — is what keeps a
    /// Concerta (Methylphenidate·XR) and a plain Methylphenidate row from merging
    /// and summing into one doubled dose.
    private func stagedIndex(identity: String, route: RouteOfAdministration, unit: String, combinationName: String?) -> Int? {
        staged.firstIndex {
            $0.identityKey == identity
                && $0.route == route
                && $0.unit == unit
                && $0.combinationName == combinationName
        }
    }
}

// MARK: - Staged List Card
