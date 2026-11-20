import Foundation

/// JSON-serializable representation of ClosedRange<Double>.
nonisolated struct CodableRange: Codable {
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

nonisolated struct DoseRange {
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

    /// Where `dose` sits on this ladder, or `nil` when there is no ladder.
    ///
    /// A range with every tier empty cannot place a dose, so it answers `nil`.
    /// Never answer `.sub` here: "sub-threshold" is a claim about the dose, and
    /// the reader could not tell it apart from an absence of dose data.
    fileprivate func level(for dose: Double) -> DoseLevel? {
        guard hasAnyValue else { return nil }
        if let heavy, dose >= heavy { return .heavy }
        if let strong, strong.contains(dose) || dose > strong.upperBound { return .strong }
        if let common, common.contains(dose) || dose > common.upperBound { return .common }
        if let light, light.contains(dose) || dose > light.upperBound { return .light }
        if let threshold, dose >= threshold { return .threshold }
        return .sub
    }
}

/// A dose ladder together with the unit its numbers are written in.
///
/// The only way to weigh a dose against a ladder: every placement converts the
/// dose into ``unit`` first and answers `nil` when it can't, so a gram dose is
/// never read off a milligram ladder and an mL dose never off a gram one.
nonisolated struct DoseLadder: Hashable {
    let range: DoseRange
    let unit: String

    /// A number read off this ladder, as a quantity in its unit.
    func quantity(_ value: Double) -> DoseQuantity {
        DoseQuantity(value, unit: unit)
    }

    /// `dose` as a number on this ladder, or `nil` when the ladder's unit can't
    /// express it.
    ///
    /// A ladder in a bare unit converts the dose into it. A ladder whose unit is a
    /// mass with a basis note ("g active GHB", "mg THC") reads a dose written in
    /// that same mass unit as is — the note names what was weighed, and a dose
    /// logged in the same unit is taken to share it. It never converts across mass
    /// units: 1 g of cannabis flower is not 1 000 mg THC.
    func reading(of dose: DoseQuantity) -> Double? {
        if let converted = dose.value(in: unit) { return converted }
        guard case let .mass(mass) = dose, let basis = DoseQuantity.basisMassUnit(unit),
              mass.unit == basis else { return nil }
        return mass.value
    }

    /// Where `dose` sits on this ladder, or `nil` when there is no ladder or the
    /// dose measures something the ladder's unit can't express.
    func level(of dose: DoseQuantity) -> DoseLevel? {
        reading(of: dose).flatMap(range.level(for:))
    }

    /// `dose ÷ reference`, with `reference` read in this ladder's unit; `nil` when
    /// the dose can't be expressed in it.
    func fraction(of dose: DoseQuantity, reference: Double) -> Double? {
        guard reference > 0 else { return nil }
        return reading(of: dose).map { $0 / reference }
    }

    /// A dose as a multiple of the common dose (the common band's midpoint), or
    /// `nil` when it can't be expressed that way: the ladder states no common band
    /// (a threshold-only or heavy-only ladder has no midpoint to divide by), or the
    /// dose measures something the ladder's unit can't — a mL drink against a mg
    /// ladder is not a fraction of anything. Callers leave such a dose out rather
    /// than count it as zero, which would read as "never taken" instead of "not
    /// measurable this way".
    func commonDoses(of dose: DoseQuantity) -> Double? {
        guard let common = range.common else { return nil }
        let midpoint = (common.lowerBound + common.upperBound) / 2
        guard midpoint > 0 else { return nil }
        return reading(of: dose).map { $0 / midpoint }
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
    var dosingPrecision: DosingPrecision {
        var values: [Double] = []
        if let threshold = range.threshold { values.append(threshold) }
        if let light = range.light { values.append((light.lowerBound + light.upperBound) / 2) }
        if let common = range.common { values.append((common.lowerBound + common.upperBound) / 2) }
        if let strong = range.strong { values.append((strong.lowerBound + strong.upperBound) / 2) }
        if let heavy = range.heavy { values.append(heavy) }
        guard !values.isEmpty else { return .none }
        let average = values.reduce(0, +) / Double(values.count)
        // Only reason about potency when the unit is a mass. Annotated or
        // colloquial units ("g (leaf powder)", "mL", "IU") have no mg reading;
        // taking the raw number as mg would flag gram-dosed botanicals (kratom
        // leaf, mushrooms) as microgram-potent.
        guard let averageInMg = quantity(average).milligrams else { return .none }
        if averageInMg < 1 { return .critical }
        if averageInMg < 5 { return .recommended }
        return .none
    }
}

nonisolated extension DoseRange: Hashable {}

nonisolated extension DoseRange {
    /// The ladder as text per dose-dial band, keyed by band index (0 Threshold
    /// … 4 Heavy). Overdose has no range, and a tier the ladder lacks has no
    /// entry.
    func bandDoseText(unit: String) -> [Int: String] {
        var out: [Int: String] = [:]
        func range(_ r: ClosedRange<Double>) -> String {
            "\(r.lowerBound.doseFormatted)–\(r.upperBound.doseFormatted) \(unit)"
        }
        if let t = threshold { out[0] = "\(t.doseFormatted) \(unit)" }
        if let l = light { out[1] = range(l) }
        if let c = common { out[2] = range(c) }
        if let s = strong { out[3] = range(s) }
        if let h = heavy { out[4] = "\(h.doseFormatted)+ \(unit)" }
        return out
    }
}

nonisolated extension DoseRange: Codable {
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
