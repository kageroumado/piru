import Foundation

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
    /// Per-dose "had grapefruit" flag. Only ever toggled for CYP3A4-heavy
    /// substrates when grapefruit logging is enabled; carried onto the committed entry.
    var hadGrapefruit = false
    /// The user took this without knowing how much. The staged components are
    /// kept (toggling back restores them) but the row reads `?`, no level or
    /// breakdown is shown, and the dose commits as ``DoseEntry/isUnknownDose``
    /// with `amount = 0`.
    var isUnknownAmount = false
    /// The amount is the user's estimate, set by the editor's Approximate pill
    /// and carried onto the committed entry (``DoseEntry/isApproximate``).
    var isApproximate = false
    /// How far off that estimate may be, in ``unit``, carried onto the committed
    /// entry (``DoseEntry/amountDeviation``). `nil` for a plain `~` estimate.
    var amountDeviation: Double?
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

    /// The amount as the tray row prints it: "? mg" for an unknown amount,
    /// "10 ± 1 mg" or "~10 mg" for an estimate, else the bare figure.
    var amountLabel: String {
        if isUnknownAmount { return "? \(unit)" }
        return DoseReadout.text(
            amount: totalAmount, unit: unit.unitDisplay(for: totalAmount),
            isApproximate: isApproximate, deviation: isApproximate ? amountDeviation : nil,
        )
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
    /// `substanceName` is canonical, so titling from it would make the tray
    /// contradict the row that fed it: a tap on "Concerta" would stage a card
    /// named "Methylphenidate". Mirrors ``DoseTitle``'s precedence, minus the
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
