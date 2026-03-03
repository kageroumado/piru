import Foundation

// MARK: - Codable Helpers

/// JSON-serializable representation of ClosedRange<Double>.
struct CodableRange: Codable {
    let lower: Double
    let upper: Double

    var closedRange: ClosedRange<Double> { lower...upper }

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

    init(
        threshold: Double? = nil,
        light: ClosedRange<Double>? = nil,
        common: ClosedRange<Double>? = nil,
        strong: ClosedRange<Double>? = nil,
        heavy: Double? = nil
    ) {
        self.threshold = threshold
        self.light = light
        self.common = common
        self.strong = strong
        self.heavy = heavy
    }

    func level(for dose: Double) -> DoseLevel {
        if let heavy, dose >= heavy { return .heavy }
        if let strong, strong.contains(dose) || dose > strong.upperBound { return .strong }
        if let common, common.contains(dose) || dose > common.upperBound { return .common }
        if let light, light.contains(dose) || dose > light.upperBound { return .light }
        if let threshold, dose >= threshold { return .threshold }
        return .sub
    }
}

extension DoseRange: Codable {
    enum CodingKeys: String, CodingKey {
        case threshold, light, common, strong, heavy
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
}

// MARK: - Unit Conversion

enum DoseUnit {
    /// Conversion factor from each mass unit to milligrams.
    private static let toMg: [String: Double] = ["µg": 0.001, "mg": 1, "g": 1000]

    /// Convert a dose amount between compatible mass units (µg, mg, g).
    /// Returns `nil` if either unit is not a convertible mass unit (e.g. mL, IU).
    static func convert(_ amount: Double, from: String, to: String) -> Double? {
        guard from != to else { return amount }
        guard let fromFactor = toMg[from], let toFactor = toMg[to] else { return nil }
        return amount * fromFactor / toFactor
    }
}

extension Double {
    /// Format a dose value: show integer for whole numbers under 10000, otherwise default formatting
    var doseFormatted: String {
        if self == rounded() && self < 10000 {
            return String(format: "%.0f", self)
        }
        return formatted()
    }
}

// MARK: - Duration

struct TimeRange: Codable {
    let min: Double
    let max: Double

    var midpoint: Double { (min + max) / 2 }

    var displayString: String {
        if max >= 120 {
            let minH = min / 60
            let maxH = max / 60
            return "~\(Self.fmt(minH))-\(Self.fmt(maxH)) hours"
        }
        return "~\(Self.fmt(min))-\(Self.fmt(max)) minutes"
    }

    private static func fmt(_ v: Double) -> String {
        v == v.rounded(.toNearestOrEven) ? String(format: "%.0f", v) : String(format: "%.1f", v)
    }
}

struct DurationProfile: Codable {
    let onset: TimeRange?
    let comeup: TimeRange?
    let peak: TimeRange?
    let offset: TimeRange?
    let afterglow: TimeRange?
    let total: TimeRange?

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
            afterglowEnd: afterglowEnd
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

// MARK: - Route

struct SubstanceRoute: Codable {
    let route: RouteOfAdministration
    let unit: String
    let doses: DoseRange
    let duration: DurationProfile?

    init(
        route: RouteOfAdministration,
        unit: String,
        doses: DoseRange,
        duration: DurationProfile? = nil
    ) {
        self.route = route
        self.unit = unit
        self.doses = doses
        self.duration = duration
    }
}

enum SubstanceCategory: String, Codable, CaseIterable, Identifiable {
    case stimulant = "Stimulant"
    case psychedelic = "Psychedelic"
    case dissociative = "Dissociative"
    case opioid = "Opioid"
    case benzodiazepine = "Benzodiazepine"
    case gabapentinoid = "GABAergic"
    case empathogen = "Empathogen"
    case cannabinoid = "Cannabinoid"
    case nootropic = "Nootropic"
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
    case other = "Other"

    /// Modifier categories that are flags, not substantive classifications
    static let modifierCategories: Set<String> = [
        "common", "habit-forming", "research-chemical", "tentative", "inactive",
    ]

    /// Map TripSit lowercase categories to our enum
    static func from(tripSitCategory: String) -> SubstanceCategory {
        switch tripSitCategory.lowercased() {
        case "stimulant": return .stimulant
        case "psychedelic", "hallucinogen": return .psychedelic
        case "dissociative": return .dissociative
        case "opioid", "opiate": return .opioid
        case "benzodiazepine": return .benzodiazepine
        case "depressant", "barbiturate", "sedative": return .depressant
        case "empathogen", "entactogen": return .empathogen
        case "cannabinoid": return .cannabinoid
        case "nootropic": return .nootropic
        case "ssri", "snri", "maoi", "antidepressant": return .antidepressant
        case "antipsychotic": return .antipsychotic
        case "antihistamine", "deliriant": return .antihistamine
        case "analgesic": return .analgesic
        case "supplement", "vitamin", "steroid": return .supplement
        case "gabapentinoid", "gabaergic": return .gabapentinoid
        default: return .other
        }
    }

    var id: String { rawValue }
}

struct SubjectiveEffect: Codable {
    let name: String
    let description: String
}

struct ToleranceInfo: Codable {
    let halfLife: Double       // days for tolerance to halve
    let fullResetDays: Double  // days for full tolerance reset
    let buildRate: String      // "rapid" | "moderate" | "slow"
}

struct Substance: Identifiable {
    let id: UUID
    let name: String
    let aliases: [String]
    let category: SubstanceCategory
    let defaultRoute: RouteOfAdministration
    let routes: [SubstanceRoute]
    let effects: [String]
    let subjectiveEffects: [SubjectiveEffect]
    let toleranceInfo: ToleranceInfo?
    let halfLifeMinutes: Double?
    let sources: [String]

    init(
        name: String,
        aliases: [String],
        category: SubstanceCategory,
        defaultRoute: RouteOfAdministration,
        routes: [SubstanceRoute],
        effects: [String],
        subjectiveEffects: [SubjectiveEffect] = [],
        toleranceInfo: ToleranceInfo? = nil,
        halfLifeMinutes: Double? = nil,
        sources: [String] = []
    ) {
        self.id = UUID()
        self.name = name
        self.aliases = aliases
        self.category = category
        self.defaultRoute = defaultRoute
        self.routes = routes
        self.effects = effects
        self.subjectiveEffects = subjectiveEffects
        self.toleranceInfo = toleranceInfo
        self.halfLifeMinutes = halfLifeMinutes
        self.sources = sources
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

    func matches(_ query: String) -> Bool {
        let q = query.lowercased()
        return name.lowercased().contains(q)
            || aliases.contains { $0.lowercased().contains(q) }
    }
}

// MARK: - Substance Codable

extension Substance: Codable {
    enum CodingKeys: String, CodingKey {
        case name, aliases, category, defaultRoute, routes, effects
        case subjectiveEffects, toleranceInfo, halfLifeMinutes, sources
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID()
        name = try c.decode(String.self, forKey: .name)
        aliases = try c.decode([String].self, forKey: .aliases)
        category = try c.decode(SubstanceCategory.self, forKey: .category)
        defaultRoute = try c.decode(RouteOfAdministration.self, forKey: .defaultRoute)
        routes = try c.decode([SubstanceRoute].self, forKey: .routes)
        effects = try c.decode([String].self, forKey: .effects)
        subjectiveEffects = try c.decodeIfPresent([SubjectiveEffect].self, forKey: .subjectiveEffects) ?? []
        toleranceInfo = try c.decodeIfPresent(ToleranceInfo.self, forKey: .toleranceInfo)
        halfLifeMinutes = try c.decodeIfPresent(Double.self, forKey: .halfLifeMinutes)
        sources = try c.decodeIfPresent([String].self, forKey: .sources) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
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
