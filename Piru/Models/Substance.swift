import SwiftUI

// MARK: - Codable Helpers

/// JSON-serializable representation of ClosedRange<Double>.
struct CodableRange: Codable {
    let lower: Double
    let upper: Double

    var closedRange: ClosedRange<Double>? {
        guard lower <= upper else { return nil }
        return lower...upper
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

    /// Returns `true` when the average reference dose (converted to mg) is below 5 mg,
    /// indicating the substance is extremely potent and requires volumetric dosing.
    func requiresVolumetricDosing(unit: String) -> Bool {
        var values: [Double] = []
        if let threshold { values.append(threshold) }
        if let light { values.append((light.lowerBound + light.upperBound) / 2) }
        if let common { values.append((common.lowerBound + common.upperBound) / 2) }
        if let strong { values.append((strong.lowerBound + strong.upperBound) / 2) }
        if let heavy { values.append(heavy) }
        guard !values.isEmpty else { return false }
        let average = values.reduce(0, +) / Double(values.count)
        let averageInMg = DoseUnit.convert(average, from: unit, to: "mg") ?? average
        return averageInMg < 5
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
    private static let toMg: [String: Double] = ["µg": 0.001, "mg": 1, "g": 1000]

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
    /// given route. Tries direct mass conversion first, then falls back to
    /// substance-specific aliases (e.g. "drink" → grams of ethanol). Returns
    /// `nil` if no conversion path exists.
    func convert(amount: Double, from unit: String, toRoute route: RouteOfAdministration) -> Double? {
        let targetUnit = self.unit(for: route)
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

    var midpoint: Double { (min + max) / 2 }

    var displayString: String {
        if max >= 120 {
            let minH = Self.roundHours(min / 60)
            let maxH = Self.roundHours(max / 60)
            if minH == maxH {
                return String(localized: "~\(Self.fmtHours(minH)) hours")
            }
            return String(localized: "~\(Self.fmtHours(minH))-\(Self.fmtHours(maxH)) hours")
        }
        let minR = Int(min.rounded())
        let maxR = Int(max.rounded())
        if minR == maxR {
            return String(localized: "~\(minR) minutes")
        }
        return String(localized: "~\(minR)-\(maxR) minutes")
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
            afterglowEnd: afterglowEnd
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
            total: DurationRange(min: state.totalMinutes, max: state.totalMinutes)
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
        case "anxiolytic", "hypnotic": return .depressant
        case "anticonvulsant", "mood-stabilizer", "mood stabilizer": return .antidepressant
        case "sympathomimetic": return .stimulant
        case "cardiovascular": return .cardiovascular
        case "antimicrobial", "antibiotic", "antifungal", "antiviral": return .antimicrobial
        case "gastrointestinal": return .gastrointestinal
        case "respiratory": return .respiratory
        case "endocrine": return .endocrine
        case "immunological": return .immunological
        default: return .other
        }
    }

    var id: String { rawValue }

    var displayName: LocalizedStringResource {
        switch self {
        case .stimulant: "Stimulant"
        case .psychedelic: "Psychedelic"
        case .dissociative: "Dissociative"
        case .opioid: "Opioid"
        case .benzodiazepine: "Benzodiazepine"
        case .gabapentinoid: "GABAergic"
        case .empathogen: "Empathogen"
        case .cannabinoid: "Cannabinoid"
        case .nootropic: "Nootropic"
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
        case .other: "Other"
        }
    }
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
    var id: String { "\(target)-\(action.rawValue)" }
}

struct MechanismOfAction: Codable {
    let summary: String
    let description: String
    let primaryTargets: [String]
    let bindings: [ReceptorBinding]
    let references: [String]

    private enum CodingKeys: String, CodingKey {
        case summary, description, primaryTargets, bindings, references
    }

    init(summary: String, description: String, primaryTargets: [String] = [], bindings: [ReceptorBinding] = [], references: [String]) {
        self.summary = summary
        self.description = description
        self.primaryTargets = primaryTargets.isEmpty ? bindings.map(\.target) : primaryTargets
        self.bindings = bindings
        self.references = references
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summary = try container.decode(String.self, forKey: .summary)
        description = try container.decode(String.self, forKey: .description)
        primaryTargets = try container.decodeIfPresent([String].self, forKey: .primaryTargets) ?? []
        bindings = try container.decodeIfPresent([ReceptorBinding].self, forKey: .bindings) ?? []
        references = try container.decode([String].self, forKey: .references)
    }
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
    let mechanismOfAction: MechanismOfAction?

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
        sources: [String] = [],
        mechanismOfAction: MechanismOfAction? = nil
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
        self.mechanismOfAction = mechanismOfAction
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
        case name, aliases, category, defaultRoute, routes, effects
        case subjectiveEffects, toleranceInfo, halfLifeMinutes, sources
        case mechanismOfAction
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
        mechanismOfAction = try c.decodeIfPresent(MechanismOfAction.self, forKey: .mechanismOfAction)
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
        try c.encodeIfPresent(mechanismOfAction, forKey: .mechanismOfAction)
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
        case .opioid: "cross.fill"
        case .benzodiazepine: "moon.fill"
        case .gabapentinoid: "waveform"
        case .empathogen: "heart.fill"
        case .cannabinoid: "leaf.fill"
        case .nootropic: "brain.fill"
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
        case .other: "pills.fill"
        }
    }

    var color: Color {
        switch self {
        case .stimulant: .orange
        case .psychedelic: .purple
        case .dissociative: .cyan
        case .opioid: .red
        case .benzodiazepine: .blue
        case .gabapentinoid: .indigo
        case .empathogen: .pink
        case .cannabinoid: .green
        case .nootropic: .teal
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
        case .other: Theme.secondaryLabel
        }
    }
}
