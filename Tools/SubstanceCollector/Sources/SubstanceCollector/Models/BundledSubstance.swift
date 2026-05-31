import Foundation

// MARK: - Output Schema
//
// Mirrors `Piru/Models/Substance.swift` so the encoded JSON matches the
// `Substance` Codable conformance the app expects. Field names, optionality,
// and array-omission rules track the iOS model. When that model changes,
// update this file.

/// Codable JSON representation of `ClosedRange<Double>` matching `CodableRange`
/// in the iOS app.
struct JSONRange: Codable, Hashable {
    let lower: Double
    let upper: Double

    init(_ lo: Double, _ hi: Double) {
        // Repair inverted ranges defensively; the iOS decoder drops them.
        self.lower = min(lo, hi)
        self.upper = max(lo, hi)
    }

    init?(_ range: ClosedRange<Double>?) {
        guard let range else { return nil }
        self.init(range.lowerBound, range.upperBound)
    }
}

struct JSONDoseRange: Codable, Hashable {
    var threshold: Double?
    var light: JSONRange?
    var common: JSONRange?
    var strong: JSONRange?
    var heavy: Double?

    var isEmpty: Bool {
        threshold == nil && light == nil && common == nil && strong == nil && heavy == nil
    }
}

struct JSONDurationRange: Codable, Hashable {
    let min: Double
    let max: Double
}

struct JSONDurationProfile: Codable, Hashable {
    var onset: JSONDurationRange?
    var comeup: JSONDurationRange?
    var peak: JSONDurationRange?
    var offset: JSONDurationRange?
    var afterglow: JSONDurationRange?
    var total: JSONDurationRange?

    var isEmpty: Bool {
        onset == nil && comeup == nil && peak == nil && offset == nil
            && afterglow == nil && total == nil
    }
}

struct JSONTitrationStep: Codable, Hashable {
    let amount: Double
    let label: String
}

struct JSONProtocolDosing: Codable, Hashable {
    var lowAmount: Double?
    var highAmount: Double?
    var frequency: String
    var titration: [JSONTitrationStep]?
    var courseDuration: String?
    var notes: String?
}

struct JSONRoute: Codable, Hashable {
    let route: String   // RouteOfAdministration raw value, e.g. "oral"
    let unit: String
    let doses: JSONDoseRange
    let duration: JSONDurationProfile?
    /// Clinical-protocol dosing (peptides/Rx); mirrors `SubstanceRoute.protocolDosing`.
    var protocolDosing: JSONProtocolDosing?
}

struct JSONStorageRequirement: Codable, Hashable {
    let temperature: String   // "room_temp" | "refrigerate" | "freeze"
    var lightSensitive: Bool
    var reconstitutedStabilityDays: Double?
}

/// Mirrors `PeptideProfile` in the iOS app.
struct JSONPeptideProfile: Codable, Hashable {
    var sequence: String?
    var suppliedForm: String?   // SuppliedForm raw value, e.g. "lyophilized_vial"
    var typicalVialMg: Double?
    var reconstitutionSolvent: String?
    var storage: JSONStorageRequirement?
    var iuPerMg: Double?
}

struct JSONSubjectiveEffect: Codable, Hashable {
    let name: String
    let description: String
}

struct JSONToleranceInfo: Codable, Hashable {
    let halfLife: Double
    let fullResetDays: Double
    let buildRate: String
}

struct JSONReceptorBinding: Codable, Hashable {
    let target: String
    let action: String
    let affinity: Int
}

struct JSONMechanismOfAction: Codable, Hashable {
    let summary: String
    let description: String
    let primaryTargets: [String]
    let bindings: [JSONReceptorBinding]
    let references: [String]
}

/// The fully-merged substance record we emit to `substances-bundled.json`.
struct BundledSubstance: Codable, Hashable {
    var name: String
    var aliases: [String]
    var category: String           // SubstanceCategory raw value (e.g. "Stimulant")
    var defaultRoute: String       // RouteOfAdministration raw value
    var routes: [JSONRoute]
    var effects: [String]
    var subjectiveEffects: [JSONSubjectiveEffect]
    var toleranceInfo: JSONToleranceInfo?
    var halfLifeMinutes: Double?
    var sources: [String]
    var mechanismOfAction: JSONMechanismOfAction?
    var tags: [String]
    // Chemical identifiers. On the curated overlay these live on the substance
    // object (matching the iOS `Substance` Codable); the SQLite builder lifts
    // them onto the substance row. nil for records whose identifiers ride the
    // SourcedSubstance wrapper instead.
    var cas: String?
    var inchikey: String?
    var formula: String?
    var pubchemCID: Int?
    /// Molar mass in g/mol → `substances.molecular_weight`.
    var molarMass: Double?
    /// Peptide/biologic-specific reference data; mirrors `Substance.peptideProfile`.
    var peptideProfile: JSONPeptideProfile?

    /// Empty array if no usable dose data on any route — the iOS app handles
    /// this via `Substance.hasNoDoseData` and switches to a "see references"
    /// detail view.
    var hasNoDoseData: Bool {
        routes.isEmpty || routes.allSatisfy { $0.doses.isEmpty }
    }

    /// Custom encoder mirrors the iOS app's `Substance.encode(to:)` which
    /// omits `subjectiveEffects`/`sources`/`tags` when empty.
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
        if !tags.isEmpty {
            try c.encode(tags, forKey: .tags)
        }
        try c.encodeIfPresent(cas, forKey: .cas)
        try c.encodeIfPresent(inchikey, forKey: .inchikey)
        try c.encodeIfPresent(formula, forKey: .formula)
        try c.encodeIfPresent(pubchemCID, forKey: .pubchemCID)
        try c.encodeIfPresent(molarMass, forKey: .molarMass)
        try c.encodeIfPresent(peptideProfile, forKey: .peptideProfile)
    }

    init(
        name: String,
        aliases: [String] = [],
        category: String,
        defaultRoute: String,
        routes: [JSONRoute] = [],
        effects: [String] = [],
        subjectiveEffects: [JSONSubjectiveEffect] = [],
        toleranceInfo: JSONToleranceInfo? = nil,
        halfLifeMinutes: Double? = nil,
        sources: [String] = [],
        mechanismOfAction: JSONMechanismOfAction? = nil,
        tags: [String] = [],
        cas: String? = nil,
        inchikey: String? = nil,
        formula: String? = nil,
        pubchemCID: Int? = nil,
        molarMass: Double? = nil,
        peptideProfile: JSONPeptideProfile? = nil
    ) {
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
        self.tags = tags
        self.cas = cas
        self.inchikey = inchikey
        self.formula = formula
        self.pubchemCID = pubchemCID
        self.molarMass = molarMass
        self.peptideProfile = peptideProfile
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        aliases = (try? c.decode([String].self, forKey: .aliases)) ?? []
        category = try c.decode(String.self, forKey: .category)
        defaultRoute = try c.decode(String.self, forKey: .defaultRoute)
        routes = (try? c.decode([JSONRoute].self, forKey: .routes)) ?? []
        effects = (try? c.decode([String].self, forKey: .effects)) ?? []
        subjectiveEffects = (try? c.decode([JSONSubjectiveEffect].self, forKey: .subjectiveEffects)) ?? []
        toleranceInfo = try? c.decodeIfPresent(JSONToleranceInfo.self, forKey: .toleranceInfo)
        halfLifeMinutes = try? c.decodeIfPresent(Double.self, forKey: .halfLifeMinutes)
        sources = (try? c.decode([String].self, forKey: .sources)) ?? []
        mechanismOfAction = try? c.decodeIfPresent(JSONMechanismOfAction.self, forKey: .mechanismOfAction)
        tags = (try? c.decode([String].self, forKey: .tags)) ?? []
        cas = try? c.decodeIfPresent(String.self, forKey: .cas)
        inchikey = try? c.decodeIfPresent(String.self, forKey: .inchikey)
        formula = try? c.decodeIfPresent(String.self, forKey: .formula)
        pubchemCID = try? c.decodeIfPresent(Int.self, forKey: .pubchemCID)
        molarMass = try? c.decodeIfPresent(Double.self, forKey: .molarMass)
        peptideProfile = try? c.decodeIfPresent(JSONPeptideProfile.self, forKey: .peptideProfile)
    }

    enum CodingKeys: String, CodingKey {
        case name, aliases, category, defaultRoute, routes, effects
        case subjectiveEffects, toleranceInfo, halfLifeMinutes, sources
        case mechanismOfAction, tags
        case cas, inchikey, formula, pubchemCID, molarMass, peptideProfile
    }
}

// MARK: - Provenance

/// Where a `BundledSubstance` originated. Used during merging for conflict
/// resolution and during SQLite emission as the `source_id` for every
/// fact-bearing row attributable to this record. Raw values map 1:1 to the
/// SQLite `sources.slug` column so the build pipeline can join cleanly.
enum Provenance: String, Codable, Comparable {
    case wikidataPubchem  = "wikidata"
    case pubchem          = "pubchem"
    case tripSit          = "tripsit"
    case erowidPIHKAL     = "erowid-pihkal"
    case erowidTIHKAL     = "erowid-tihkal"
    case deaOrangeBook    = "dea-orange-book"
    case curated          = "piru-curated"

    /// Merge precedence: higher wins on conflict.
    var precedence: Int {
        switch self {
        case .wikidataPubchem: 1
        case .pubchem:         1
        case .deaOrangeBook:   1
        case .tripSit:         2
        case .erowidTIHKAL:    3
        case .erowidPIHKAL:    3
        case .curated:         4
        }
    }

    static func < (a: Provenance, b: Provenance) -> Bool { a.precedence < b.precedence }

    /// Short display label used in CLI stats output.
    var label: String { rawValue }
}

/// A substance record with provenance and dedup identifiers attached so the
/// merge pipeline can reason about precedence and join across sources, and so
/// the SQLite builder can attribute every fact to the right source.
struct SourcedSubstance: Codable {
    var substance: BundledSubstance
    var provenance: Provenance
    /// InChIKey if known. Highest-confidence dedup key.
    var inchiKey: String?
    /// PubChem CID. Secondary dedup key.
    var pubchemCID: Int?
    /// CAS number for cross-referencing.
    var cas: String?
}
