import SwiftUI

// MARK: - Codable Helpers

/// JSON-serializable representation of ClosedRange<Double>.
struct CodableRange: Codable {
    let lower: Double
    let upper: Double

    var closedRange: ClosedRange<Double>? {
        guard lower <= upper else { return nil }
        return lower ... upper
    }

    init(_ range: ClosedRange<Double>) {
        self.lower = range.lowerBound
        self.upper = range.upperBound
    }
}

// MARK: - Dose

struct DoseRange {
    let threshold: Double?
    let light: ClosedRange<Double>?
    let common: ClosedRange<Double>?
    let strong: ClosedRange<Double>?
    let heavy: Double?

    nonisolated init(
        threshold: Double? = nil,
        light: ClosedRange<Double>? = nil,
        common: ClosedRange<Double>? = nil,
        strong: ClosedRange<Double>? = nil,
        heavy: Double? = nil,
    ) {
        self.threshold = threshold
        self.light = light
        self.common = common
        self.strong = strong
        self.heavy = heavy
    }

    /// `true` when at least one dose tier is populated. Routes that ship a
    /// duration but no dose ladder (e.g. Cannabis sublingual from PsychonautWiki)
    /// would otherwise render an empty "Dosage" card.
    var hasAnyValue: Bool {
        threshold != nil || light != nil || common != nil || strong != nil || heavy != nil
    }

    func level(for dose: Double) -> DoseLevel {
        if let heavy, dose >= heavy { return .heavy }
        if let strong, strong.contains(dose) || dose > strong.upperBound { return .strong }
        if let common, common.contains(dose) || dose > common.upperBound { return .common }
        if let light, light.contains(dose) || dose > light.upperBound { return .light }
        if let threshold, dose >= threshold { return .threshold }
        return .sub
    }

    /// How precisely a substance must be measured, derived from its average
    /// reference dose. `critical` substances are active in sub-milligram amounts
    /// where a normal scale can't be trusted; `recommended` substances are
    /// low-milligram enough that a precise scale is worth using but the "active
    /// in micrograms" framing would be false.
    enum DosingPrecision {
        case none
        case recommended
        case critical
    }

    /// Classifies the route by average reference dose (converted to mg):
    /// `< 1 mg` → `.critical` (true µg/sub-mg potency, e.g. fentanyl, nitazenes),
    /// `1–5 mg` → `.recommended` (precise scale advised, e.g. DOx psychedelics),
    /// otherwise `.none`.
    func dosingPrecision(unit: String) -> DosingPrecision {
        var values: [Double] = []
        if let threshold { values.append(threshold) }
        if let light { values.append((light.lowerBound + light.upperBound) / 2) }
        if let common { values.append((common.lowerBound + common.upperBound) / 2) }
        if let strong { values.append((strong.lowerBound + strong.upperBound) / 2) }
        if let heavy { values.append(heavy) }
        guard !values.isEmpty else { return .none }
        let average = values.reduce(0, +) / Double(values.count)
        // Only reason about potency when the unit is a convertible mass unit.
        // Annotated/colloquial units ("g (leaf powder)", "mL", "IU") can't map
        // to mg; treating the raw number as mg would wrongly flag gram-dosed
        // botanicals (kratom leaf, mushrooms) as microgram-potent. Skip then.
        guard let averageInMg = DoseUnit.convert(average, from: unit, to: "mg") else { return .none }
        if averageInMg < 1 { return .critical }
        if averageInMg < 5 { return .recommended }
        return .none
    }
}

extension DoseRange: Hashable {}

extension DoseRange: Codable {
    enum CodingKeys: String, CodingKey {
        case threshold
        case light
        case common
        case strong
        case heavy
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        threshold = try c.decodeIfPresent(Double.self, forKey: .threshold)
        light = try c.decodeIfPresent(CodableRange.self, forKey: .light)?.closedRange
        common = try c.decodeIfPresent(CodableRange.self, forKey: .common)?.closedRange
        strong = try c.decodeIfPresent(CodableRange.self, forKey: .strong)?.closedRange
        heavy = try c.decodeIfPresent(Double.self, forKey: .heavy)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(threshold, forKey: .threshold)
        if let r = light, r.lowerBound <= r.upperBound { try c.encode(CodableRange(r), forKey: .light) }
        if let r = common, r.lowerBound <= r.upperBound { try c.encode(CodableRange(r), forKey: .common) }
        if let r = strong, r.lowerBound <= r.upperBound { try c.encode(CodableRange(r), forKey: .strong) }
        try c.encodeIfPresent(heavy, forKey: .heavy)
    }
}

enum DoseLevel: String, CaseIterable {
    case sub = "Sub-threshold"
    case threshold = "Threshold"
    case light = "Light"
    case common = "Common"
    case strong = "Strong"
    case heavy = "Heavy"

    var color: String {
        switch self {
        case .sub: "gray"
        case .threshold: "blue"
        case .light: "green"
        case .common: "yellow"
        case .strong: "orange"
        case .heavy: "red"
        }
    }

    var displayName: LocalizedStringResource {
        switch self {
        case .sub: "Sub-threshold"
        case .threshold: "Threshold"
        case .light: "Light"
        case .common: "Common"
        case .strong: "Strong"
        case .heavy: "Heavy"
        }
    }
}

// MARK: - Unit Conversion

enum DoseUnit {
    /// Conversion factor from each mass unit to milligrams.
    private static let toMg: [String: Double] = ["µg": 0.001, "mg": 1, "g": 1_000]

    /// Convert a dose amount between compatible mass units (µg, mg, g).
    /// Returns `nil` if either unit is not a convertible mass unit (e.g. mL, IU).
    static func convert(_ amount: Double, from: String, to: String) -> Double? {
        guard from != to else { return amount }
        guard let fromFactor = toMg[from], let toFactor = toMg[to] else { return nil }
        return amount * fromFactor / toFactor
    }
}

// MARK: - Substance-Specific Unit Aliases

/// A colloquial unit that resolves to a fixed amount in a known physical unit.
/// e.g. `("drink", 14, "g")` for alcohol — "2 drinks" is logged as 28 g of ethanol.
struct UnitAlias: Hashable {
    /// User-facing display label (what appears in the unit picker).
    let label: String
    /// How many `unit`s a single instance of `label` represents.
    let amountPerUnit: Double
    /// The physical unit that `amountPerUnit` is denominated in.
    let unit: String
}

extension Substance {
    /// Colloquial unit aliases for this substance. Keys are the canonical
    /// (lowercased) substance name or any alias; the lookup matches whichever
    /// is canonical at runtime.
    ///
    /// References:
    /// - **drink**: US standard drink = 14 g of pure ethanol per
    ///   [NIAAA](https://www.niaaa.nih.gov/alcohols-effects-health/overview-alcohol-consumption/what-standard-drink).
    private static let unitAliasTable: [String: [UnitAlias]] = [
        "alcohol": [
            UnitAlias(label: "drink", amountPerUnit: 14, unit: "g"),
        ],
        "ethanol": [
            UnitAlias(label: "drink", amountPerUnit: 14, unit: "g"),
        ],
    ]

    /// Unit aliases applicable to this substance, looked up by canonical name
    /// or any alias. Empty for substances without colloquial conventions.
    var unitAliases: [UnitAlias] {
        let candidates = [name.lowercased()] + aliases.map { $0.lowercased() }
        return candidates.lazy.compactMap { Self.unitAliasTable[$0] }.first ?? []
    }

    /// Convert an amount-in-some-unit to this substance's native unit for the
    /// given route, against the route's **default-salt** unit.
    ///
    /// Route-only overload (see the overload-family note on
    /// ``unit(for:saltForm:)``): it resolves the reference unit via the default
    /// salt by design. For substances whose salts share a unit this is exact; it
    /// only mis-targets when a *specific* selected salt uses a different unit
    /// than the route default. Reach for
    /// ``convert(amount:from:toRoute:saltForm:)`` on any surface that converts
    /// for a chosen/logged salt.
    func convert(amount: Double, from unit: String, toRoute route: RouteOfAdministration) -> Double? {
        convert(amount: amount, from: unit, toRoute: route, saltForm: nil)
    }

    /// Salt-aware unit conversion: resolves the reference unit via
    /// ``unit(for:saltForm:)`` so a salt whose unit differs from the route
    /// default (elemental mg vs compound mg, or an IU-dosed form) converts
    /// against its *own* unit. Tries direct mass conversion first, then falls
    /// back to substance-specific aliases (e.g. "drink" → grams of ethanol).
    /// Returns `nil` if no conversion path exists. A `nil` (or unknown) salt
    /// label falls back to the route's default-salt unit, so the route-only
    /// ``convert(amount:from:toRoute:)`` delegates here unchanged.
    func convert(
        amount: Double,
        from unit: String,
        toRoute route: RouteOfAdministration,
        saltForm: String?,
    ) -> Double? {
        let targetUnit = self.unit(for: route, saltForm: saltForm)
        if let direct = DoseUnit.convert(amount, from: unit, to: targetUnit) {
            return direct
        }
        if let alias = unitAliases.first(where: { $0.label == unit }) {
            let canonicalAmount = amount * alias.amountPerUnit
            return DoseUnit.convert(canonicalAmount, from: alias.unit, to: targetUnit) ?? canonicalAmount
        }
        return nil
    }
}

// MARK: - Duration

struct DurationRange: Codable, Hashable {
    let min: Double
    let max: Double

    var midpoint: Double {
        (min + max) / 2
    }

    var displayString: String {
        if max >= 120 {
            let minH = Self.roundHours(min / 60)
            let maxH = Self.roundHours(max / 60)
            if minH == maxH {
                return String(localized: "~\(Self.fmtHours(minH)) hours")
            }
            return String(localized: "~\(Self.fmtHours(minH)) – \(Self.fmtHours(maxH)) hours")
        }
        let minR = Int(min.rounded())
        let maxR = Int(max.rounded())
        if minR == maxR {
            return String(localized: "~\(minR) minutes")
        }
        return String(localized: "~\(minR) – \(maxR) minutes")
    }

    /// Rounds hours to the nearest 0.5
    private static func roundHours(_ v: Double) -> Double {
        (v * 2).rounded() / 2
    }

    private static func fmtHours(_ v: Double) -> String {
        v == v.rounded(.toNearestOrEven) ? String(format: "%.0f", v) : String(format: "%.1f", v)
    }
}

struct DurationProfile: Codable, Hashable {
    let onset: DurationRange?
    let comeup: DurationRange?
    let peak: DurationRange?
    let offset: DurationRange?
    let afterglow: DurationRange?
    let total: DurationRange?

    var estimatedTotalMinutes: Double {
        if let total { return total.midpoint }
        let phases = [onset, comeup, peak, offset].compactMap { $0?.midpoint }
        return phases.reduce(0, +)
    }

    var phaseBoundaries: PhaseBoundaries {
        let onsetEnd = onset?.midpoint ?? 0
        let comeupEnd = onsetEnd + (comeup?.midpoint ?? 0)
        let peakEnd = comeupEnd + (peak?.midpoint ?? 0)
        let offsetEnd = peakEnd + (offset?.midpoint ?? 0)
        let afterglowEnd = offsetEnd + (afterglow?.midpoint ?? 0)
        return PhaseBoundaries(
            onsetEnd: onsetEnd,
            comeupEnd: comeupEnd,
            peakEnd: peakEnd,
            offsetEnd: offsetEnd,
            afterglowEnd: afterglowEnd,
        )
    }

    /// Fill in missing come-up/peak/offset phases when the data carries a real
    /// `total` but not the intermediate phases that shape the curve between
    /// onset and total (endpoint-only data from a single source). Without this,
    /// ``phaseBoundaries`` sums only the present phases and collapses the curve
    /// to roughly the onset length — discarding the stated duration (a ~12 h LSD
    /// trip rendered as a ~1 h spike). The real `total` is left intact; only the
    /// *unexplained* span (`total − present phases`) is distributed across the
    /// missing shapers using class-aware proportions
    /// (``SubstanceCategory/synthesizedPhaseShape``), so any genuine phase is
    /// preserved. Returns `self` for complete profiles and those with no `total`
    /// (the latter keep the half-life synthesis fallback). Used only when
    /// building a timeline curve — the detail card still shows the raw phases.
    func fillingMissingPhases(for category: SubstanceCategory) -> DurationProfile {
        guard let total, total.midpoint > 0 else { return self }
        let shape = category.synthesizedPhaseShape
        let totalMin = total.midpoint
        let onsetMin = onset?.midpoint ?? totalMin * shape.onset
        let presentMiddle = (comeup?.midpoint ?? 0) + (peak?.midpoint ?? 0) + (offset?.midpoint ?? 0)
        let budget = totalMin - onsetMin - presentMiddle

        // A complete profile leaves ~no unexplained span; bail so it's untouched.
        // Likewise bail if every shaper is already present.
        let needsComeup = comeup == nil, needsPeak = peak == nil, needsOffset = offset == nil
        guard budget > totalMin * 0.1, needsComeup || needsPeak || needsOffset else { return self }

        let wComeup = needsComeup ? shape.comeup : 0
        let wPeak = needsPeak ? shape.peak : 0
        let wOffset = needsOffset ? shape.offset : 0
        let wSum = wComeup + wPeak + wOffset
        guard wSum > 0 else { return self }

        func filled(_ weight: Double) -> DurationRange? {
            guard weight > 0 else { return nil }
            let v = budget * weight / wSum
            return DurationRange(min: v, max: v)
        }
        return DurationProfile(
            onset: onset ?? DurationRange(min: onsetMin, max: onsetMin),
            comeup: comeup ?? filled(wComeup),
            peak: peak ?? filled(wPeak),
            offset: offset ?? filled(wOffset),
            afterglow: afterglow,
            total: total,
        )
    }
}

extension DurationProfile {
    /// Reconstruct a duration profile from phase boundaries stored in an ActiveSubstanceState.
    init(fromState state: ActiveSubstanceState) {
        let onsetLen = state.onsetEndMinutes
        let comeupLen = state.comeupEndMinutes - state.onsetEndMinutes
        let peakLen = state.peakEndMinutes - state.comeupEndMinutes
        let offsetLen = state.offsetEndMinutes - state.peakEndMinutes
        let afterglowLen: Double? = state.afterglowEndMinutes.map { $0 - state.offsetEndMinutes }

        self.init(
            onset: onsetLen > 0 ? DurationRange(min: onsetLen, max: onsetLen) : nil,
            comeup: comeupLen > 0 ? DurationRange(min: comeupLen, max: comeupLen) : nil,
            peak: peakLen > 0 ? DurationRange(min: peakLen, max: peakLen) : nil,
            offset: offsetLen > 0 ? DurationRange(min: offsetLen, max: offsetLen) : nil,
            afterglow: afterglowLen.flatMap { $0 > 0 ? DurationRange(min: $0, max: $0) : nil },
            total: DurationRange(min: state.totalMinutes, max: state.totalMinutes),
        )
    }
}

struct PhaseBoundaries {
    let onsetEnd: Double
    let comeupEnd: Double
    let peakEnd: Double
    let offsetEnd: Double
    let afterglowEnd: Double
}

// MARK: - Protocol Dosing

/// One rung of a titration ramp, e.g. "2.5 mg" during "weeks 1–4".
struct TitrationStep: Codable, Hashable {
    /// Amount in the route's `unit`.
    let amount: Double
    /// Localized phase label, e.g. "weeks 1–4", "month 2".
    let label: String
}

/// Clinical-protocol dosing for compounds taken on a schedule (peptides, some
/// prescription drugs) rather than along a trip-intensity ladder. When present,
/// the detail UI renders this instead of the `DoseRange` threshold→heavy tiers.
/// Amounts are in the owning `SubstanceRoute.unit` (mcg, mg, or IU).
struct ProtocolDosing: Codable, Hashable {
    /// Typical dose range low/high (either may be nil for a single fixed dose).
    let lowAmount: Double?
    let highAmount: Double?
    /// Localized frequency, e.g. "2×/day", "once weekly", "every 2 months".
    let frequency: String
    /// Optional titration ramp (dose escalates over time).
    let titration: [TitrationStep]?
    /// Course length, e.g. "8–12 weeks", "cycle then break". nil = ongoing/unknown.
    let courseDuration: String?
    /// Administration notes, e.g. "fasted", "before sleep".
    let notes: String?

    init(
        lowAmount: Double? = nil,
        highAmount: Double? = nil,
        frequency: String,
        titration: [TitrationStep]? = nil,
        courseDuration: String? = nil,
        notes: String? = nil,
    ) {
        self.lowAmount = lowAmount
        self.highAmount = highAmount
        self.frequency = frequency
        self.titration = titration
        self.courseDuration = courseDuration
        self.notes = notes
    }
}

// MARK: - Peptide Profile

/// How a peptide/biologic is supplied — determines whether reconstitution UI
/// applies and how the substance is handled.
enum SuppliedForm: String, Codable, Hashable {
    /// Freeze-dried powder in an mg vial — must be reconstituted before use.
    case lyophilizedVial = "lyophilized_vial"
    /// Ready-to-inject solution (prefilled pen/vial).
    case solution
    /// Topical serum/cream (cosmetic peptides) — dosed as a formulation %.
    case topical
    /// Slow-release implant (e.g. Scenesse).
    case implant
    /// Orally administered capsule/tablet.
    case oralCapsule = "oral_capsule"

    var displayName: LocalizedStringResource {
        switch self {
        case .lyophilizedVial: "Lyophilized powder (vial)"
        case .solution: "Ready-to-inject solution"
        case .topical: "Topical formulation"
        case .implant: "Slow-release implant"
        case .oralCapsule: "Oral capsule"
        }
    }

    /// Whether the reconstitution calculator is meaningful for this form.
    var isReconstituted: Bool {
        self == .lyophilizedVial
    }
}

/// Cold-chain / handling requirement for a peptide or biologic.
struct StorageRequirement: Codable, Hashable {
    enum Temperature: String, Codable, Hashable {
        case roomTemp = "room_temp"
        case refrigerate
        case freeze

        var displayName: LocalizedStringResource {
            switch self {
            case .roomTemp: "Room temperature"
            case .refrigerate: "Refrigerate (2–8 °C)"
            case .freeze: "Freeze"
            }
        }

        /// SF Symbol summarising the requirement.
        var icon: String {
            switch self {
            case .roomTemp: "thermometer.medium"
            case .refrigerate: "refrigerator"
            case .freeze: "snowflake"
            }
        }
    }

    let temperature: Temperature
    let lightSensitive: Bool
    /// Days the product stays stable once reconstituted (refrigerated). nil = unknown.
    let reconstitutedStabilityDays: Double?

    init(temperature: Temperature, lightSensitive: Bool = false, reconstitutedStabilityDays: Double? = nil) {
        self.temperature = temperature
        self.lightSensitive = lightSensitive
        self.reconstitutedStabilityDays = reconstitutedStabilityDays
    }
}

/// Peptide/biologic-specific reference data. Presence switches the detail UI to
/// a peptide presentation (amino-acid sequence, handling, reconstitution) instead
/// of the psychoactive trip-arc model.
struct PeptideProfile: Codable, Hashable {
    /// Amino-acid sequence, one-letter with modification notes
    /// (e.g. "Ac-Nle-cyclo[Asp-His-D-Phe-Arg-Trp-Lys]-NH2"). nil = not published.
    let sequence: String?
    let suppliedForm: SuppliedForm?
    /// Typical vial size in mg, seeds the reconstitution calculator.
    let typicalVialMg: Double?
    /// Recommended reconstitution solvent (e.g. "Bacteriostatic water").
    let reconstitutionSolvent: String?
    let storage: StorageRequirement?
    /// IU↔mg bridge for hormones dosed in international units (GH, HCG, …).
    let iuPerMg: Double?

    init(
        sequence: String? = nil,
        suppliedForm: SuppliedForm? = nil,
        typicalVialMg: Double? = nil,
        reconstitutionSolvent: String? = nil,
        storage: StorageRequirement? = nil,
        iuPerMg: Double? = nil,
    ) {
        self.sequence = sequence
        self.suppliedForm = suppliedForm
        self.typicalVialMg = typicalVialMg
        self.reconstitutionSolvent = reconstitutionSolvent
        self.storage = storage
        self.iuPerMg = iuPerMg
    }

    /// True when at least one field carries usable information.
    var hasAnyValue: Bool {
        sequence != nil || suppliedForm != nil || typicalVialMg != nil
            || reconstitutionSolvent != nil || storage != nil || iuPerMg != nil
    }
}

// MARK: - Route

/// Release / duration-of-action window for a long-acting formulation — depot
/// injections, esters, weekly peptides. Distinct from ``DurationProfile``, which
/// is the *acute* dose-effect curve (hours): a single dose of these acts or
/// releases over days to weeks, which is useful to show in the drug card but is
/// NOT plotted as an acute timeline curve. Stored normalized to minutes.
struct DurationOfAction: Codable, Hashable {
    let minMinutes: Double
    let maxMinutes: Double

    init(minMinutes: Double, maxMinutes: Double) {
        self.minMinutes = minMinutes
        self.maxMinutes = maxMinutes
    }

    /// Authored as `{ min, max, unit }` (unit: hours/days/weeks/months) in the
    /// curated overlay; normalized to minutes on decode.
    private enum CodingKeys: String, CodingKey { case min, max, unit }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let factor = Self.minutesPerUnit((try? c.decode(String.self, forKey: .unit)) ?? "days")
        minMinutes = try c.decode(Double.self, forKey: .min) * factor
        maxMinutes = try c.decode(Double.self, forKey: .max) * factor
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(minMinutes / 1_440, forKey: .min)
        try c.encode(maxMinutes / 1_440, forKey: .max)
        try c.encode("days", forKey: .unit)
    }

    static func minutesPerUnit(_ unit: String) -> Double {
        switch unit.lowercased() {
        case "hour", "hours", "h": 60
        case "week", "weeks", "w": 1_440 * 7
        case "month", "months", "mo": 1_440 * 30
        default: 1_440 // days
        }
    }

    /// Human-friendly release window for the drug card — picks the most readable
    /// unit (e.g. "7–10 days", "8–12 weeks", "4–6 months"). Localized.
    var formattedWindow: String {
        let maxDays = maxMinutes / 1_440
        func n(_ minutes: Double, per: Double) -> String {
            let v = minutes / per
            return v.rounded() == v ? String(Int(v)) : v.formatted(.number.precision(.fractionLength(1)))
        }
        if maxDays >= 90 {
            return String(localized: "\(n(minMinutes, per: 1_440 * 30))–\(n(maxMinutes, per: 1_440 * 30)) months", comment: "Long-acting release window")
        } else if maxDays >= 21 {
            return String(localized: "\(n(minMinutes, per: 1_440 * 7))–\(n(maxMinutes, per: 1_440 * 7)) weeks", comment: "Long-acting release window")
        } else {
            return String(localized: "\(n(minMinutes, per: 1_440))–\(n(maxMinutes, per: 1_440)) days", comment: "Long-acting release window")
        }
    }
}

/// One salt/ester form of a substance for a given route — e.g. Magnesium
/// *Citrate* vs *Glycinate* vs *L-Threonate*. The salt genuinely changes dosing
/// (elemental fraction, absorption), so each form carries its own dose ladder
/// and (optionally) duration. Nested under ``SubstanceRoute``: a route's
/// ``SubstanceRoute/saltForms`` lists all forms, ordered with the default first;
/// the route's top-level `doses`/`unit`/`duration` mirror that default form so
/// salt-unaware code keeps working transparently.
struct SaltVariant: Codable, Hashable {
    /// Free-form label (Citrate, Glycinate, L-Threonate, Carbonate, Orotate…).
    let saltForm: String
    let unit: String
    let doses: DoseRange
    let duration: DurationProfile?
    /// Mass fraction of the elemental active (e.g. elemental magnesium) in this
    /// salt — Magnesium citrate ≈ 0.16, glycinate ≈ 0.14, L-threonate ≈ 0.08.
    /// `nil` when unknown / not applicable. Lets the UI show "= ⟨elemental⟩ mg".
    let elementalFraction: Double?

    nonisolated init(
        saltForm: String,
        unit: String,
        doses: DoseRange,
        duration: DurationProfile? = nil,
        elementalFraction: Double? = nil,
    ) {
        self.saltForm = saltForm
        self.unit = unit
        self.doses = doses
        self.duration = duration
        self.elementalFraction = elementalFraction
    }
}

struct SubstanceRoute: Codable {
    let route: RouteOfAdministration
    let unit: String
    let doses: DoseRange
    let duration: DurationProfile?
    /// Clinical-protocol dosing (peptides/Rx). When present the UI shows this
    /// instead of the `doses` trip-intensity ladder.
    let protocolDosing: ProtocolDosing?
    /// Release / duration-of-action window for long-acting formulations (depot
    /// injections, weekly peptides). Shown in the drug card; never drawn as an
    /// acute timeline curve.
    let durationOfAction: DurationOfAction?
    /// Salt/ester forms available for this route, ordered with the default
    /// (highest-priority) form first. `nil`/empty for the overwhelming majority
    /// of substances, which have a single unspecified form. When present, the
    /// top-level `unit`/`doses`/`duration` mirror `saltForms.first` (the
    /// default), so code that ignores salt form transparently gets the default.
    /// The salt picker is shown only when this holds more than one form.
    let saltForms: [SaltVariant]?

    nonisolated init(
        route: RouteOfAdministration,
        unit: String,
        doses: DoseRange,
        duration: DurationProfile? = nil,
        protocolDosing: ProtocolDosing? = nil,
        durationOfAction: DurationOfAction? = nil,
        saltForms: [SaltVariant]? = nil,
    ) {
        self.route = route
        self.unit = unit
        self.doses = doses
        self.duration = duration
        self.protocolDosing = protocolDosing
        self.durationOfAction = durationOfAction
        self.saltForms = saltForms
    }
}

enum SubstanceCategory: String, Codable, CaseIterable, Identifiable {
    case stimulant = "Stimulant"
    case psychedelic = "Psychedelic"
    case dissociative = "Dissociative"
    case dysdelic = "Dysdelic"
    case deliriant = "Deliriant"
    case opioid = "Opioid"
    case benzodiazepine = "Benzodiazepine"
    case gabapentinoid = "GABAergic"
    case empathogen = "Empathogen"
    case cannabinoid = "Cannabinoid"
    case nootropic = "Nootropic"
    case ampakine = "AMPAkine"
    case eugeroic = "Eugeroic"
    case depressant = "Depressant"
    case antidepressant = "Antidepressant"
    case antipsychotic = "Antipsychotic"
    case analgesic = "Analgesic"
    case antihistamine = "Antihistamine"
    case cardiovascular = "Cardiovascular"
    case antimicrobial = "Antimicrobial"
    case gastrointestinal = "Gastrointestinal"
    case respiratory = "Respiratory"
    case endocrine = "Endocrine"
    case immunological = "Immunological"
    case supplement = "Supplement"
    case peptide = "Peptide"
    case anticonvulsant = "Anticonvulsant"
    case other = "Other"

    /// Modifier categories that are flags, not substantive classifications
    static let modifierCategories: Set<String> = [
        "common", "habit-forming", "research-chemical", "tentative", "inactive",
    ]

    /// Map TripSit lowercase categories to our enum
    nonisolated static func from(tripSitCategory: String) -> SubstanceCategory {
        switch tripSitCategory.lowercased() {
        case "stimulant": .stimulant
        case "psychedelic", "hallucinogen": .psychedelic
        case "dissociative": .dissociative
        case "dysdelic", "kappa-agonist", "kappa-opioid-agonist", "salvinorin": .dysdelic
        case "deliriant", "anticholinergic", "muscarinic-antagonist": .deliriant
        case "opioid", "opiate": .opioid
        case "benzodiazepine": .benzodiazepine
        case "depressant", "barbiturate", "sedative": .depressant
        case "empathogen", "entactogen": .empathogen
        case "cannabinoid": .cannabinoid
        case "nootropic": .nootropic
        case "ampakine", "ampa-pam", "ampa-positive-modulator": .ampakine
        case "eugeroic", "afinil", "wake-promoting": .eugeroic
        case "ssri", "snri", "maoi", "antidepressant": .antidepressant
        case "antipsychotic": .antipsychotic
        case "antihistamine": .antihistamine
        case "analgesic": .analgesic
        case "supplement", "vitamin", "steroid": .supplement
        case "peptide", "peptide-mimetic": .peptide
        case "gabapentinoid", "gabaergic": .gabapentinoid
        case "anxiolytic", "hypnotic": .depressant
        case "anticonvulsant", "mood-stabilizer", "mood stabilizer", "antiepileptic": .anticonvulsant
        case "sympathomimetic": .stimulant
        case "cardiovascular": .cardiovascular
        case "antimicrobial", "antibiotic", "antifungal", "antiviral": .antimicrobial
        case "gastrointestinal": .gastrointestinal
        case "respiratory": .respiratory
        case "endocrine": .endocrine
        case "immunological": .immunological
        default: .other
        }
    }

    var id: String {
        rawValue
    }

    /// Acute-tolerance (tachyphylaxis) strength, `0...1`. Drives the timeline's
    /// descending-limb gate: how much faster subjective effect fades than the
    /// drug's plasma curve once past peak. Catecholamine/serotonin releasers
    /// crash hard while blood levels are still high (the classic stimulant
    /// comedown), so they score high; most depressants/psychedelics track
    /// concentration far more closely and score 0 (no reshaping — the pure
    /// Bateman offset is kept). See `TimelineGraphView.intensity(at:…)`.
    var acuteToleranceFactor: Double {
        switch self {
        case .stimulant: 0.75
        case .empathogen: 0.70
        case .eugeroic: 0.20
        case .dissociative: 0.25
        default: 0
        }
    }

    /// Proportions for synthesizing a renderable effect curve from
    /// endpoint-only duration data (a `total` but no come-up/peak/offset — the
    /// LSD-oral class, where one source supplied only onset+total). `onset` is a
    /// fraction of `total`, used only when no onset phase exists; `comeup` /
    /// `peak` / `offset` are *relative weights* that split the remaining active
    /// span into the rising / plateau / falling shoulders of the bell. Shaped by
    /// class pharmacology: psychedelics build slowly into a broad peak, stimulants
    /// spike then taper (the descending limb is further crashed by
    /// ``acuteToleranceFactor``), opioids peak fast. See
    /// ``DurationProfile/fillingMissingPhases(for:)``.
    var synthesizedPhaseShape: (onset: Double, comeup: Double, peak: Double, offset: Double) {
        switch self {
        case .psychedelic, .dysdelic, .deliriant:
            (0.08, 0.20, 0.30, 0.50)
        case .stimulant:
            (0.06, 0.15, 0.20, 0.65)
        case .empathogen:
            (0.07, 0.18, 0.27, 0.55)
        case .eugeroic:
            (0.08, 0.15, 0.35, 0.50)
        case .opioid, .analgesic:
            (0.06, 0.16, 0.24, 0.60)
        case .dissociative:
            (0.06, 0.17, 0.27, 0.56)
        case .benzodiazepine, .depressant, .gabapentinoid:
            (0.07, 0.18, 0.30, 0.52)
        case .cannabinoid:
            (0.06, 0.18, 0.26, 0.56)
        default:
            (0.08, 0.20, 0.25, 0.55)
        }
    }

    var displayName: LocalizedStringResource {
        switch self {
        case .stimulant: "Stimulant"
        case .psychedelic: "Psychedelic"
        case .dissociative: "Dissociative"
        case .dysdelic: "Dysdelic"
        case .deliriant: "Deliriant"
        case .opioid: "Opioid"
        case .benzodiazepine: "Benzodiazepine"
        case .gabapentinoid: "GABAergic"
        case .empathogen: "Empathogen"
        case .cannabinoid: "Cannabinoid"
        case .nootropic: "Nootropic"
        case .ampakine: "AMPAkine"
        case .eugeroic: "Eugeroic"
        case .depressant: "Depressant"
        case .antidepressant: "Antidepressant"
        case .antipsychotic: "Antipsychotic"
        case .analgesic: "Analgesic"
        case .antihistamine: "Antihistamine"
        case .cardiovascular: "Cardiovascular"
        case .antimicrobial: "Antimicrobial"
        case .gastrointestinal: "Gastrointestinal"
        case .respiratory: "Respiratory"
        case .endocrine: "Endocrine"
        case .immunological: "Immunological"
        case .supplement: "Supplement"
        case .peptide: "Peptide"
        case .anticonvulsant: "Anticonvulsant"
        case .other: "Other"
        }
    }
}

struct SubjectiveEffect: Codable {
    let name: String
    let description: String
}

struct ToleranceInfo: Codable {
    let halfLife: Double // days for tolerance to halve
    let fullResetDays: Double // days for full tolerance reset
    let buildRate: String // "rapid" | "moderate" | "slow"
}

enum BindingAction: String, Codable {
    case agonist
    case partialAgonist
    case antagonist
    case inverseAgonist
    case positiveAllostericModulator
    case negativeAllostericModulator
    case reuptakeInhibitor
    case releasingAgent
    case enzymeInhibitor
    case channelBlocker
    case modulator

    var displayName: LocalizedStringResource {
        switch self {
        case .agonist: "Agonist"
        case .partialAgonist: "Partial Agonist"
        case .antagonist: "Antagonist"
        case .inverseAgonist: "Inverse Agonist"
        case .positiveAllostericModulator: "PAM"
        case .negativeAllostericModulator: "NAM"
        case .reuptakeInhibitor: "Reuptake Inhibitor"
        case .releasingAgent: "Releasing Agent"
        case .enzymeInhibitor: "Enzyme Inhibitor"
        case .channelBlocker: "Channel Blocker"
        case .modulator: "Modulator"
        }
    }
}

enum BindingAffinity: Int, Codable, Comparable {
    case weak = 1
    case significant = 2
    case primary = 3

    static func < (lhs: BindingAffinity, rhs: BindingAffinity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ReceptorBinding: Codable, Identifiable {
    let target: String
    let action: BindingAction
    let affinity: BindingAffinity
    var id: String {
        "\(target)-\(action.rawValue)"
    }
}

/// Long-form substance overview prose, resolved locale-first. `machineTranslated`
/// flags FreeOD Wiki text auto-translated into the app's language so the UI can
/// label it.
struct SubstanceOverview: Codable, Hashable {
    let text: String
    let machineTranslated: Bool
    /// DB slug of the source that actually supplied the resolved text (e.g.
    /// `psychonautwiki` for an authentic English lead, `freeodwiki` for native
    /// Chinese or a machine translation). Drives the attribution row + deep link.
    var sourceSlug: String = "freeodwiki"
}

struct MechanismOfAction: Codable {
    let summary: String
    let description: String
    let primaryTargets: [String]
    let bindings: [ReceptorBinding]

    private enum CodingKeys: String, CodingKey {
        case summary
        case description
        case primaryTargets
        case bindings
    }

    init(summary: String, description: String, primaryTargets: [String] = [], bindings: [ReceptorBinding] = []) {
        self.summary = summary
        self.description = description
        self.primaryTargets = primaryTargets.isEmpty ? bindings.map(\.target) : primaryTargets
        self.bindings = bindings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summary = try container.decode(String.self, forKey: .summary)
        description = try container.decode(String.self, forKey: .description)
        primaryTargets = try container.decodeIfPresent([String].self, forKey: .primaryTargets) ?? []
        bindings = try container.decodeIfPresent([ReceptorBinding].self, forKey: .bindings) ?? []
    }
}

/// How a compound is surfaced under the display policy. Baked at build time
/// into `substances.display_class`. Gates dose/duration visibility and whether
/// the compound appears in recreational category browsing. See
/// `docs/` and `pipeline/build/sqlite.py:classify_compounds`.
enum CompoundDisplayClass: String, Codable {
    /// Recreational use is the primary frame — full dose ladder + duration.
    case recreational
    /// A medical drug that PsychonautWiki/TripSit also document recreationally
    /// (mirtazapine, DXM, gabapentin, …). Shown like recreational.
    case dualUse = "dual_use"
    /// Over-the-counter — dose is on the package, so dose may be shown without
    /// a recreational signal. Duration suppressed when implausible (>24h).
    case otc
    /// Prescription medication, no recreational value — show mechanism /
    /// indications / warnings, but NEVER dose or duration (a doctor's domain).
    case medicalRx = "medical_rx"
    /// No recreational value at all (antibiotics, …). Trackable + recognisable
    /// but hidden from recreational browsing; no dose/duration.
    case nonRecreational = "non_recreational"

    /// Dose ladder visible. Suppressed for medical/non-recreational compounds.
    var showsDoseLadder: Bool {
        switch self {
        case .recreational, .dualUse, .otc: true
        case .medicalRx, .nonRecreational: false
        }
    }

    /// Duration profile visible. (OTC additionally requires a plausible
    /// duration — gate on `Substance.durationImplausible` at the call site.)
    var showsDuration: Bool {
        switch self {
        case .recreational, .dualUse, .otc: true
        case .medicalRx, .nonRecreational: false
        }
    }

    /// Whether this compound appears in recreational category browsing. Non-
    /// recreational compounds stay searchable (for medication tracking) but are
    /// not surfaced in the browse grid.
    var surfacesInBrowse: Bool {
        self != .nonRecreational
    }
}

/// A single contraindication or boxed warning sourced from a clinical label.
struct Contraindication: Codable, Hashable {
    let text: String
    let isBoxedWarning: Bool
}

/// Cross-benzodiazepine dose equivalency (relative to 10 mg diazepam). Sourced
/// from the TripSit benzo dataset; the only such data in Piru.
struct DiazepamEquivalent: Codable, Hashable {
    let doseMg: Double?
    let equivalentDiazepamMg: Double?
    let displayText: String?
}

/// A primary reference for a compound — a DOI, PubMed ID, URL, or free-text
/// label ("Egrifta SmPC"). Surfaced in the detail "References" section so every
/// curated claim is traceable to its source.
struct Citation: Codable, Hashable {
    let doi: String?
    let pmid: Int?
    let url: String?
    let title: String?

    init(doi: String? = nil, pmid: Int? = nil, url: String? = nil, title: String? = nil) {
        self.doi = doi
        self.pmid = pmid
        self.url = url
        self.title = title
    }

    /// A tappable link, when the reference resolves to one. Free-text labels
    /// (stored in `url` without an http scheme) return nil → rendered as text.
    var resolvedURL: URL? {
        if let doi, !doi.isEmpty { return URL(string: "https://doi.org/\(doi)") }
        if let pmid { return URL(string: "https://pubmed.ncbi.nlm.nih.gov/\(pmid)/") }
        if let url, url.hasPrefix("http") { return URL(string: url) }
        return nil
    }

    /// Human-facing label.
    var label: String {
        if let title, !title.isEmpty { return title }
        if let doi, !doi.isEmpty { return "DOI \(doi)" }
        if let pmid { return "PMID \(pmid)" }
        if let url, !url.isEmpty { return url }
        return String(localized: "Reference")
    }
}

struct Substance: Identifiable {
    let id: UUID
    let name: String
    /// Optional human-facing title override (e.g. "2,3-MDMA" for the compound
    /// whose canonical `name` is "2,3-Methylenedioxymethamphetamine"). When set,
    /// the UI shows this as the primary title and demotes `name` to the subtitle.
    /// `name` stays canonical for search/dedup/logging. See `displayTitle`/`displaySubtitle`.
    let displayName: String?
    let aliases: [String]
    let category: SubstanceCategory
    /// Additional browse homes beyond `category` (the resolved primary). Lets an
    /// intentionally cross-class compound surface under more than one family
    /// (e.g. Tianeptine under both Antidepressant and Opioid). Curated-only,
    /// loaded in the batch path; empty for everything else. The primary
    /// `category` still drives card colour/icon and the default home.
    let extraBrowseCategories: [SubstanceCategory]
    let defaultRoute: RouteOfAdministration
    let routes: [SubstanceRoute]
    let effects: [String]
    let subjectiveEffects: [SubjectiveEffect]
    let toleranceInfo: ToleranceInfo?
    let halfLifeMinutes: Double?
    let sources: [String]
    let mechanismOfAction: MechanismOfAction?
    /// Display-policy classification governing dose/duration/browse visibility.
    let displayClass: CompoundDisplayClass
    /// Parsed OTC/Rx/controlled status, when known (`rx`, `otc`,
    /// `rx_otc_dependent`, `controlled_schedule_N`).
    let regulatoryStatus: String?
    /// True when the total duration exceeds 24h (the vitamin problem); OTC
    /// duration is suppressed when set. Recreational/dual-use are exempt.
    let durationImplausible: Bool
    /// Clinical indications (what it's prescribed for), for medical/OTC display.
    let indications: [String]
    /// Contraindications + boxed warnings, for medical/OTC display.
    let contraindications: [Contraindication]
    /// Cross-benzo diazepam equivalency (benzodiazepines only).
    let diazepamEquivalent: DiazepamEquivalent?
    /// Chemical identifiers (detail-only; nil in the batch/browse path).
    let cas: String?
    let inchikey: String?
    let formula: String?
    /// PubChem Compound ID, for linking out to the curated chemistry record.
    /// Detail-only (nil in the batch/browse path), like the other identifiers.
    let pubchemCID: Int?
    /// Hand-curated popularity score in [0,1] (0 = not curated). Drives the
    /// "Popularity" sort in category browse; loaded in the batch path.
    let popularity: Double
    /// True for a genuinely thin catalog entry — zero dose AND duration AND
    /// protocol data from any source (the pipeline's `flag_dose_less_stubs`).
    /// Drives the "Limited data" list badge. NOT the same as "no dose ladder":
    /// a brew like Ayahuasca has no mg ladder but plenty of duration/effect data,
    /// so it isn't a stub. Loaded in the batch path.
    let isStub: Bool
    /// Orthogonal class metadata: mechanism (`DRI`, `NMDA-antagonist`), chemical
    /// family (`cathinone`, `arylcyclohexylamine`), provenance (`PIHKAL`,
    /// `research-chemical`), legal/safety status (`US-Schedule-I`, `no-human-data`).
    /// Compounds often belong to multiple families; tags compose where `category` cannot.
    let tags: [String]
    /// Molar mass in g/mol, when known. Populated for peptides (where it drives
    /// IU↔mg reasoning and is shown in the handling card) and any compound with a
    /// curated molecular weight. Maps to the `substances.molecular_weight` column.
    let molarMass: Double?
    /// Peptide/biologic-specific reference data. Non-nil switches the detail view
    /// to a peptide presentation (sequence, handling, reconstitution) in place of
    /// the psychoactive trip model. nil for ordinary small molecules.
    let peptideProfile: PeptideProfile?
    /// Primary references (DOIs / PMIDs / URLs / labels) for this compound's
    /// curated claims. Detail-only (empty in the batch/browse path).
    let references: [Citation]
    /// Canonical drug.community page slug, for deep-linking `/drug/<slug>`.
    /// drug.community's page resolves only this canonical form (no alias
    /// fallback), so it can't be derived from the app's own name. Detail-only
    /// (nil in the batch/browse path); nil when there's no drug.community entry.
    let drugCommunitySlug: String?
    /// FreeOD Wiki page slug, for deep-linking `freeodwiki.org/药物/<slug>` (the
    /// page titles are Chinese, so the slug can't be derived from `name`).
    /// Detail-only; nil when there's no FreeOD entry.
    let freeodwikiSlug: String?
    /// Long-form overview prose ("what it is / history / risk profile"),
    /// resolved locale-first (native Chinese when the app runs in Chinese,
    /// machine-translated English as a fallback). Detail-only; nil when no
    /// source supplies an overview. Distinct from `mechanismOfAction`.
    let overview: SubstanceOverview?

    nonisolated init(
        name: String,
        displayName: String? = nil,
        aliases: [String],
        category: SubstanceCategory,
        extraBrowseCategories: [SubstanceCategory] = [],
        defaultRoute: RouteOfAdministration,
        routes: [SubstanceRoute],
        effects: [String],
        subjectiveEffects: [SubjectiveEffect] = [],
        toleranceInfo: ToleranceInfo? = nil,
        halfLifeMinutes: Double? = nil,
        sources: [String] = [],
        mechanismOfAction: MechanismOfAction? = nil,
        tags: [String] = [],
        displayClass: CompoundDisplayClass = .recreational,
        regulatoryStatus: String? = nil,
        durationImplausible: Bool = false,
        indications: [String] = [],
        contraindications: [Contraindication] = [],
        diazepamEquivalent: DiazepamEquivalent? = nil,
        cas: String? = nil,
        inchikey: String? = nil,
        formula: String? = nil,
        pubchemCID: Int? = nil,
        popularity: Double = 0,
        isStub: Bool = false,
        molarMass: Double? = nil,
        peptideProfile: PeptideProfile? = nil,
        references: [Citation] = [],
        drugCommunitySlug: String? = nil,
        freeodwikiSlug: String? = nil,
        overview: SubstanceOverview? = nil,
    ) {
        self.id = UUID()
        self.name = name
        self.displayName = displayName
        self.aliases = aliases
        self.category = category
        self.extraBrowseCategories = extraBrowseCategories
        self.defaultRoute = defaultRoute
        self.routes = routes
        self.effects = effects
        self.subjectiveEffects = subjectiveEffects
        self.toleranceInfo = toleranceInfo
        self.halfLifeMinutes = halfLifeMinutes
        self.sources = sources
        self.mechanismOfAction = mechanismOfAction
        self.tags = tags
        self.displayClass = displayClass
        self.regulatoryStatus = regulatoryStatus
        self.durationImplausible = durationImplausible
        self.indications = indications
        self.contraindications = contraindications
        self.diazepamEquivalent = diazepamEquivalent
        self.cas = cas
        self.inchikey = inchikey
        self.formula = formula
        self.pubchemCID = pubchemCID
        self.popularity = popularity
        self.isStub = isStub
        self.molarMass = molarMass
        self.peptideProfile = peptideProfile
        self.references = references
        self.drugCommunitySlug = drugCommunitySlug
        self.freeodwikiSlug = freeodwikiSlug
        self.overview = overview
    }

    /// Title shown in lists and the detail header — the curated override when
    /// present, otherwise the canonical `name`. A leading pictograph is stripped
    /// (see ``titlePictograph``).
    var displayTitle: String {
        Substance.strippingLeadingPictograph(displayName ?? name).text
    }

    /// A leading pictograph in the curated display name — e.g. PsychonautWiki's
    /// "🍰 Cake" April-Fools entry — telegraphs the in-joke wherever the title
    /// shows (search, browse lists). It's stripped from ``displayTitle`` and
    /// surfaced here so the *detail* screen can play along instead of spoiling it.
    var titlePictograph: String? {
        Substance.strippingLeadingPictograph(displayName ?? name).pictograph
    }

    /// Splits a leading emoji (a default-emoji-presentation scalar) off a title:
    /// "🍰 Cake" → ("Cake", "🍰"). Ordinary names pass through unchanged.
    static func strippingLeadingPictograph(_ s: String) -> (text: String, pictograph: String?) {
        guard let first = s.first,
              let scalar = first.unicodeScalars.first,
              scalar.properties.isEmojiPresentation
        else {
            return (s, nil)
        }
        let rest = String(s.dropFirst()).drop(while: \.isWhitespace)
        return (String(rest), String(first))
    }

    /// Aliases cleaned for display (search uses the separate normalized index,
    /// so this never affects findability). Collapses hyphen / spacing / casing
    /// variants ("2C-B" / "2cb" / "2c-b") to one — keeping the best-cased form —
    /// and drops aliases that merely restate the name. Useful clutter for search,
    /// noise for a human reading "Also known as".
    var displayAliases: [String] {
        let drop: Set<String> = [Substance.aliasKey(name), Substance.aliasKey(displayTitle)]
        var best: [String: String] = [:]
        var order: [String] = []
        for alias in aliases {
            let key = Substance.aliasKey(alias)
            if key.isEmpty || drop.contains(key) { continue }
            if let existing = best[key] {
                if Substance.aliasCasingScore(alias) > Substance.aliasCasingScore(existing) {
                    best[key] = alias
                }
            } else {
                best[key] = alias
                order.append(key)
            }
        }
        let resolved = order.compactMap { best[$0] }
        // In a non-Chinese UI, push CJK aliases (FreeOD's Chinese street names) to
        // the end so an English title isn't immediately followed by Han — Latin
        // names a reader recognises lead. A stable partition keeps source order
        // within each group. In a Chinese UI the source order already reads well.
        guard !SubstanceStore.contentLanguage.isChinese else { return resolved }
        return resolved.filter { !$0.containsHan } + resolved.filter(\.containsHan)
    }

    /// Casing/spacing-insensitive identity key for an alias.
    static func aliasKey(_ s: String) -> String {
        s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }

    /// Prefer the better-cased variant: more capitals (proper "2C-B" over "2cb"),
    /// then a hyphenated form over a run-together one.
    static func aliasCasingScore(_ s: String) -> Int {
        s.filter(\.isUppercase).count * 10 + (s.contains("-") ? 1 : 0)
    }

    /// Secondary line for rows: the canonical (expanded) name when it differs
    /// from the shown title, otherwise the cleaned aliases (up to 3).
    var displaySubtitle: String? {
        if displayName != nil, name != displayTitle { return name }
        let cleaned = displayAliases
        guard !cleaned.isEmpty else { return nil }
        return cleaned.prefix(3).joined(separator: ", ")
    }

    /// External chemistry reference, preferring an exact PubChem CID, then an
    /// InChIKey search, then a name search — so every substance resolves.
    var pubChemURL: URL? {
        if let cid = pubchemCID {
            return URL(string: "https://pubchem.ncbi.nlm.nih.gov/compound/\(cid)")
        }
        let query = inchikey ?? name
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: "https://pubchem.ncbi.nlm.nih.gov/#query=\(encoded)")
    }

    /// True when no route on this substance has any usable dose data. Used by
    /// the detail view to switch to a "see references" presentation for
    /// research chemicals whose only available information is the literature.
    var hasNoDoseData: Bool {
        guard !routes.isEmpty else { return true }
        return routes.allSatisfy { !$0.doses.hasAnyValue }
    }

    /// True when this compound should use the peptide-specific detail
    /// presentation (sequence / handling / reconstitution / protocol dosing)
    /// rather than the psychoactive trip model. Driven by category or the
    /// presence of curated peptide data.
    var usesPeptidePresentation: Bool {
        category == .peptide || (peptideProfile?.hasAnyValue ?? false)
    }

    /// The protocol-dosing schedule to surface, preferring the default route,
    /// then any route that carries one. nil when no protocol dosing is curated.
    var primaryProtocolDosing: ProtocolDosing? {
        routes.first { $0.route == defaultRoute }?.protocolDosing
            ?? routes.compactMap(\.protocolDosing).first
    }

    var defaultUnit: String {
        routes.first { $0.route == defaultRoute }?.unit
            ?? routes.first?.unit
            ?? "mg"
    }

    func doseRange(for route: RouteOfAdministration) -> DoseRange? {
        routes.first { $0.route == route }?.doses
    }

    func unit(for route: RouteOfAdministration) -> String {
        routes.first { $0.route == route }?.unit ?? defaultUnit
    }

    func duration(for route: RouteOfAdministration) -> DurationProfile? {
        routes.first { $0.route == route }?.duration
    }

    // MARK: - Salt forms

    // Overload-family convention — `…(for:)` vs `…(for:saltForm:)`:
    //
    // The route-only accessors — `doseRange(for:)`, `unit(for:)`,
    // `duration(for:)`, and `convert(amount:from:toRoute:)` — intentionally
    // return the route's **default-salt** data (the top-level fields, which
    // mirror `saltForms.first`). They exist so salt-unaware code stays correct
    // without threading a salt through every call site.
    //
    // The `…(for:saltForm:)` variants narrow to a *specific* form, falling back
    // to the default when the salt is `nil` or unknown. Any surface that
    // displays or computes for a SPECIFIC logged/selected salt (the dose-level
    // ladder, the unit shown next to an amount, a salt-aware conversion) MUST
    // use the salt overload — otherwise it silently shows the default form's
    // numbers/unit for a different salt. New call sites: default to the salt
    // overload whenever a salt is in scope; reach for the route-only one only
    // when no salt selection exists.

    /// Distinct salt/ester forms across all routes, ordered (default first,
    /// then by first appearance). Empty for the vast majority of substances.
    /// Drives the "does this substance have a salt dimension at all" check.
    var availableSaltForms: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for route in routes {
            for variant in route.saltForms ?? [] where seen.insert(variant.saltForm).inserted {
                ordered.append(variant.saltForm)
            }
        }
        return ordered
    }

    /// Salt forms available for a specific route, in stored order (default
    /// first). The salt picker is shown only when this has more than one entry.
    func saltForms(for route: RouteOfAdministration) -> [String] {
        routes.first { $0.route == route }?.saltForms?.map(\.saltForm) ?? []
    }

    /// The salt form selected by default — the default route's first form,
    /// falling back to any route's first form. `nil` when the substance has no
    /// salt dimension.
    var defaultSaltForm: String? {
        (routes.first { $0.route == defaultRoute } ?? routes.first)?
            .saltForms?.first?.saltForm
    }

    /// Dose ladder for a route, narrowed to a salt form when one is given and
    /// present. Falls back to the route's default (top-level) ladder when the
    /// salt is `nil` or not found — so salt-unaware callers stay correct.
    func doseRange(for route: RouteOfAdministration, saltForm: String?) -> DoseRange? {
        guard let r = routes.first(where: { $0.route == route }) else { return nil }
        if let saltForm, let variant = r.saltForms?.first(where: { $0.saltForm == saltForm }) {
            return variant.doses
        }
        return r.doses
    }

    /// Unit for a route, narrowed to a salt form when present (salts may differ:
    /// elemental mg vs compound mg). Falls back to the route/default unit.
    func unit(for route: RouteOfAdministration, saltForm: String?) -> String {
        guard let r = routes.first(where: { $0.route == route }) else { return defaultUnit }
        if let saltForm, let variant = r.saltForms?.first(where: { $0.saltForm == saltForm }) {
            return variant.unit
        }
        return r.unit
    }

    /// Duration profile for a route, narrowed to a salt form when present.
    /// Falls back to the route's default duration.
    func duration(for route: RouteOfAdministration, saltForm: String?) -> DurationProfile? {
        guard let r = routes.first(where: { $0.route == route }) else { return nil }
        if let saltForm, let variant = r.saltForms?.first(where: { $0.saltForm == saltForm }) {
            return variant.duration
        }
        return r.duration
    }

    /// Mass fraction of the elemental active for a salt form on a route (e.g.
    /// 0.14 for Magnesium glycinate). `nil` when unknown / not applicable.
    func elementalFraction(for route: RouteOfAdministration, saltForm: String?) -> Double? {
        guard let saltForm else { return nil }
        return routes.first { $0.route == route }?
            .saltForms?.first { $0.saltForm == saltForm }?.elementalFraction
    }

    /// The amount of *elemental* active (e.g. elemental magnesium) in `amount`
    /// of the given salt form on a route — `amount × elementalFraction`. `nil`
    /// when the salt has no known elemental fraction (the common case), so the
    /// UI shows the breakdown only where it's meaningful (Magnesium, Lithium…).
    func elementalAmount(of amount: Double, for route: RouteOfAdministration, saltForm: String?) -> Double? {
        elementalFraction(for: route, saltForm: saltForm).map { amount * $0 }
    }

    /// Best available duration: exact route → similar route → generic fallback.
    /// Only falls back when a single route has duration data (implying it's generic).
    /// When multiple routes have distinct durations, returns nil rather than guessing.
    func resolveDuration(for route: RouteOfAdministration) -> DurationProfile? {
        if let exact = duration(for: route) { return exact }
        let routesWithDuration = routes.filter { $0.duration != nil }
        // Single route with data is likely generic — safe to use for any route
        if routesWithDuration.count == 1 { return routesWithDuration.first?.duration }
        return nil
    }

    /// Longest total effect a dose can have and still be drawn as a timeline
    /// curve. Beyond this an "acute" onset→peak→offset shape is the wrong model:
    /// the effect outlasts any sane graph window, so the dose is a point-in-time
    /// marker instead. Matches the data pipeline's `duration_implausible`
    /// threshold (`pipeline/build/sqlite.py`).
    static let maxAcuteTimelineMinutes: Double = 24 * 60

    /// Duration to use when *drawing a dose on a timeline* (curve thumbnails, the
    /// day-detail graph, the active-session accessory) — `nil` means "don't draw
    /// a curve; render a marker instead."
    ///
    /// Returns `nil` for long-acting / maintenance compounds whose modelled
    /// effect exceeds ``maxAcuteTimelineMinutes`` (memantine, bupropion, SSRIs,
    /// GLP-1 agonists, depot injectables, vitamins, …). Their acute curve would
    /// be a flat line stretching the shared x-axis and crushing every real curve
    /// beside it. The decision is taken from the *actual* profile that would be
    /// drawn — so it's correct for custom substances and route-specific profiles
    /// that the precomputed `durationImplausible` flag can miss. Distinct from
    /// ``resolveDuration(for:)``, which returns the raw profile regardless.
    func timelineDuration(for route: RouteOfAdministration) -> DurationProfile? {
        if let profile = resolveDuration(for: route),
           profile.estimatedTotalMinutes > 0,
           profile.estimatedTotalMinutes <= Self.maxAcuteTimelineMinutes {
            return profile
        }
        // The requested route has no usable acute profile, but the substance may
        // have one on another route. Borrowing it is far closer to reality than
        // falling through to a blood-half-life synthesis, whose elimination t½
        // can vastly outlast subjective effects — e.g. logging amphetamine
        // *rectal* (no profile) would otherwise synthesize a ~45 h curve from
        // its ~10 h t½, when the felt effect is the ~6–8 h oral curve. Synthesis
        // stays reserved for substances with no acute curve on any route.
        return representativeAcuteDuration()
    }

    /// A stand-in acute profile for routes that lack their own: the default
    /// route's profile when it's a sane acute curve, otherwise the shortest
    /// acute profile across all routes (the most conservative — least likely to
    /// overstate how long effects last). `nil` when no route has an acute curve.
    private func representativeAcuteDuration() -> DurationProfile? {
        func acute(_ profile: DurationProfile?) -> DurationProfile? {
            guard let profile, profile.estimatedTotalMinutes > 0,
                  profile.estimatedTotalMinutes <= Self.maxAcuteTimelineMinutes else { return nil }
            return profile
        }
        if let def = acute(duration(for: defaultRoute)) { return def }
        return routes.compactMap { acute($0.duration) }
            .min { $0.estimatedTotalMinutes < $1.estimatedTotalMinutes }
    }

    func matches(_ query: String) -> Bool {
        let q = query.lowercased()
        return name.lowercased().contains(q)
            || aliases.contains { $0.lowercased().contains(q) }
    }

    /// All routes ordered: substance-specific first, then remaining system routes.
    var orderedRoutes: [RouteOfAdministration] {
        let subRoutes = routes.map(\.route)
        let otherRoutes = RouteOfAdministration.allCases.filter { !subRoutes.contains($0) }
        return subRoutes + otherRoutes
    }
}

// MARK: - Substance Codable

extension Substance: Codable {
    enum CodingKeys: String, CodingKey {
        case name
        case displayName
        case aliases
        case category
        case defaultRoute
        case routes
        case effects
        case subjectiveEffects
        case toleranceInfo
        case halfLifeMinutes
        case sources
        case mechanismOfAction
        case tags
        case displayClass
        case regulatoryStatus
        case durationImplausible
        case indications
        case contraindications
        case diazepamEquivalent
        case cas
        case inchikey
        case formula
        case pubchemCID
        case popularity
        case isStub
        case molarMass
        case peptideProfile
        case references
        case drugCommunitySlug
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID()
        name = try c.decode(String.self, forKey: .name)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        aliases = try c.decode([String].self, forKey: .aliases)
        category = try c.decode(SubstanceCategory.self, forKey: .category)
        // Browse-only metadata loaded from the DB, never part of the serialized
        // Substance (export/import) — default to none on decode.
        extraBrowseCategories = []
        defaultRoute = try c.decode(RouteOfAdministration.self, forKey: .defaultRoute)
        routes = try c.decode([SubstanceRoute].self, forKey: .routes)
        effects = try c.decode([String].self, forKey: .effects)
        subjectiveEffects = try c.decodeIfPresent([SubjectiveEffect].self, forKey: .subjectiveEffects) ?? []
        toleranceInfo = try c.decodeIfPresent(ToleranceInfo.self, forKey: .toleranceInfo)
        halfLifeMinutes = try c.decodeIfPresent(Double.self, forKey: .halfLifeMinutes)
        sources = try c.decodeIfPresent([String].self, forKey: .sources) ?? []
        mechanismOfAction = try c.decodeIfPresent(MechanismOfAction.self, forKey: .mechanismOfAction)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        displayClass = try c.decodeIfPresent(CompoundDisplayClass.self, forKey: .displayClass) ?? .recreational
        regulatoryStatus = try c.decodeIfPresent(String.self, forKey: .regulatoryStatus)
        durationImplausible = try c.decodeIfPresent(Bool.self, forKey: .durationImplausible) ?? false
        indications = try c.decodeIfPresent([String].self, forKey: .indications) ?? []
        contraindications = try c.decodeIfPresent([Contraindication].self, forKey: .contraindications) ?? []
        diazepamEquivalent = try c.decodeIfPresent(DiazepamEquivalent.self, forKey: .diazepamEquivalent)
        cas = try c.decodeIfPresent(String.self, forKey: .cas)
        inchikey = try c.decodeIfPresent(String.self, forKey: .inchikey)
        formula = try c.decodeIfPresent(String.self, forKey: .formula)
        pubchemCID = try c.decodeIfPresent(Int.self, forKey: .pubchemCID)
        popularity = try c.decodeIfPresent(Double.self, forKey: .popularity) ?? 0
        isStub = try c.decodeIfPresent(Bool.self, forKey: .isStub) ?? false
        molarMass = try c.decodeIfPresent(Double.self, forKey: .molarMass)
        peptideProfile = try c.decodeIfPresent(PeptideProfile.self, forKey: .peptideProfile)
        references = try c.decodeIfPresent([Citation].self, forKey: .references) ?? []
        drugCommunitySlug = try c.decodeIfPresent(String.self, forKey: .drugCommunitySlug)
        // Detail/browse-only metadata, never part of the serialized Substance.
        freeodwikiSlug = nil
        overview = nil
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(displayName, forKey: .displayName)
        try c.encode(aliases, forKey: .aliases)
        try c.encode(category, forKey: .category)
        try c.encode(defaultRoute, forKey: .defaultRoute)
        try c.encode(routes, forKey: .routes)
        try c.encode(effects, forKey: .effects)
        if !subjectiveEffects.isEmpty {
            try c.encode(subjectiveEffects, forKey: .subjectiveEffects)
        }
        try c.encodeIfPresent(toleranceInfo, forKey: .toleranceInfo)
        try c.encodeIfPresent(halfLifeMinutes, forKey: .halfLifeMinutes)
        if !sources.isEmpty {
            try c.encode(sources, forKey: .sources)
        }
        try c.encodeIfPresent(mechanismOfAction, forKey: .mechanismOfAction)
        if !tags.isEmpty {
            try c.encode(tags, forKey: .tags)
        }
        if displayClass != .recreational {
            try c.encode(displayClass, forKey: .displayClass)
        }
        try c.encodeIfPresent(regulatoryStatus, forKey: .regulatoryStatus)
        if durationImplausible {
            try c.encode(durationImplausible, forKey: .durationImplausible)
        }
        if !indications.isEmpty {
            try c.encode(indications, forKey: .indications)
        }
        if !contraindications.isEmpty {
            try c.encode(contraindications, forKey: .contraindications)
        }
        try c.encodeIfPresent(diazepamEquivalent, forKey: .diazepamEquivalent)
        try c.encodeIfPresent(cas, forKey: .cas)
        try c.encodeIfPresent(inchikey, forKey: .inchikey)
        try c.encodeIfPresent(formula, forKey: .formula)
        try c.encodeIfPresent(pubchemCID, forKey: .pubchemCID)
        if popularity != 0 { try c.encode(popularity, forKey: .popularity) }
        if isStub { try c.encode(isStub, forKey: .isStub) }
        try c.encodeIfPresent(molarMass, forKey: .molarMass)
        if let peptideProfile, peptideProfile.hasAnyValue {
            try c.encode(peptideProfile, forKey: .peptideProfile)
        }
        if !references.isEmpty { try c.encode(references, forKey: .references) }
        try c.encodeIfPresent(drugCommunitySlug, forKey: .drugCommunitySlug)
    }
}

// MARK: - Hashable

extension Substance: Hashable {
    static func == (lhs: Substance, rhs: Substance) -> Bool {
        lhs.id == rhs.id
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Category Display Metadata

extension SubstanceCategory {
    var icon: String {
        switch self {
        case .stimulant: "bolt.fill"
        case .psychedelic: "eye.fill"
        case .dissociative: "waveform.path"
        case .dysdelic: "tornado"
        case .deliriant: "cloud.fog.fill"
        case .opioid: "cross.fill"
        case .benzodiazepine: "moon.fill"
        case .gabapentinoid: "waveform"
        case .empathogen: "heart.fill"
        case .cannabinoid: "leaf.fill"
        case .nootropic: "brain.fill"
        case .ampakine: "sparkles"
        case .eugeroic: "sunrise.fill"
        case .depressant: "arrow.down.circle.fill"
        case .antidepressant: "sun.max.fill"
        case .antipsychotic: "shield.fill"
        case .analgesic: "bandage.fill"
        case .antihistamine: "allergens.fill"
        case .cardiovascular: "heart.text.square.fill"
        case .antimicrobial: "microbe.fill"
        case .gastrointestinal: "fork.knife"
        case .respiratory: "lungs.fill"
        case .endocrine: "atom"
        case .immunological: "shield.lefthalf.filled"
        case .supplement: "pill.fill"
        case .peptide: "link.circle.fill"
        case .anticonvulsant: "waveform.path.ecg"
        case .other: "pills.fill"
        }
    }

    var color: Color {
        switch self {
        case .stimulant: .orange
        case .psychedelic: .purple
        case .dissociative: .cyan
        case .dysdelic: Color(red: 0.55, green: 0.25, blue: 0.55)
        case .deliriant: Color(red: 0.52, green: 0.48, blue: 0.32)
        case .opioid: .red
        case .benzodiazepine: .blue
        case .gabapentinoid: .indigo
        case .empathogen: .pink
        case .cannabinoid: .green
        case .nootropic: .teal
        case .ampakine: Color(red: 0.55, green: 0.85, blue: 0.45)
        case .eugeroic: Color(red: 0.95, green: 0.70, blue: 0.30)
        case .depressant: Color(red: 0.45, green: 0.55, blue: 0.72)
        case .antidepressant: .yellow
        case .antipsychotic: .mint
        case .analgesic: .brown
        case .antihistamine: Color(red: 0.72, green: 0.45, blue: 0.55)
        case .cardiovascular: .red.opacity(0.7)
        case .antimicrobial: .teal.opacity(0.7)
        case .gastrointestinal: .orange.opacity(0.7)
        case .respiratory: .cyan.opacity(0.7)
        case .endocrine: .purple.opacity(0.7)
        case .immunological: .blue.opacity(0.7)
        case .supplement: .green.opacity(0.7)
        case .peptide: Color(red: 0.40, green: 0.65, blue: 0.85)
        case .anticonvulsant: Color(red: 0.65, green: 0.55, blue: 0.85)
        case .other: Theme.secondaryLabel
        }
    }
}

extension String {
    /// Whether the string contains any CJK Han character — used to push Chinese
    /// aliases to the end of "Also known as" in a non-Chinese UI.
    var containsHan: Bool {
        unicodeScalars.contains { (0x4E00 ... 0x9FFF).contains($0.value) }
    }
}
