import SwiftUI

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

    /// Where `dose` sits on this ladder, or `nil` when there is no ladder.
    ///
    /// A range with every tier empty cannot place a dose. It used to answer
    /// `.sub` — so a custom substance logged with no dose data was labeled
    /// "sub-threshold", which is a claim about the dose rather than an absence
    /// of one, and the reader has no way to tell the two apart.
    func level(for dose: Double) -> DoseLevel? {
        guard hasAnyValue else { return nil }
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
