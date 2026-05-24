import Foundation

// MARK: - Codable Helpers

/// JSON-serializable representation of `ClosedRange<Double>` produced by the
/// iOS app when encoding `DoseRange`. Matches the on-disk shape of
/// `substances_cache.json` exactly.
struct AuditCodableRange: Codable {
    let lower: Double
    let upper: Double
}

// MARK: - Audit Models

/// Minimal decode-only mirror of the iOS app's `Substance` type, scoped to
/// just the fields the audit pipeline needs.
///
/// The full `Substance` type pulls in SwiftUI (`LocalizedStringResource`,
/// `Color`) and cannot be imported into this CLI target. Decoding only the
/// fields we need also keeps the audit resilient to additive schema changes.
struct AuditSubstance: Codable {
    let name: String
    let aliases: [String]
    /// Decoded as the raw category string (e.g. `"Stimulant"`) rather than an
    /// enum so unknown categories don't fail decoding.
    let category: String
    let defaultRoute: String
    let routes: [AuditRoute]
    let halfLifeMinutes: Double?
    let sources: [String]

    enum CodingKeys: String, CodingKey {
        case name, aliases, category, defaultRoute, routes, halfLifeMinutes, sources
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        aliases = (try? c.decode([String].self, forKey: .aliases)) ?? []
        category = try c.decode(String.self, forKey: .category)
        defaultRoute = try c.decode(String.self, forKey: .defaultRoute)
        routes = try c.decode([AuditRoute].self, forKey: .routes)
        halfLifeMinutes = try c.decodeIfPresent(Double.self, forKey: .halfLifeMinutes)
        sources = (try? c.decode([String].self, forKey: .sources)) ?? []
    }

    init(
        name: String,
        aliases: [String] = [],
        category: String,
        defaultRoute: String,
        routes: [AuditRoute],
        halfLifeMinutes: Double? = nil,
        sources: [String] = []
    ) {
        self.name = name
        self.aliases = aliases
        self.category = category
        self.defaultRoute = defaultRoute
        self.routes = routes
        self.halfLifeMinutes = halfLifeMinutes
        self.sources = sources
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(aliases, forKey: .aliases)
        try c.encode(category, forKey: .category)
        try c.encode(defaultRoute, forKey: .defaultRoute)
        try c.encode(routes, forKey: .routes)
        try c.encodeIfPresent(halfLifeMinutes, forKey: .halfLifeMinutes)
        try c.encode(sources, forKey: .sources)
    }
}

struct AuditRoute: Codable {
    let route: String
    let unit: String
    let doses: AuditDoseRange

    init(route: String, unit: String, doses: AuditDoseRange) {
        self.route = route
        self.unit = unit
        self.doses = doses
    }
}

/// Mirror of `DoseRange` from `Piru/Models/Substance.swift`. Threshold and
/// heavy are scalars; light/common/strong are encoded as
/// `{lower, upper}` objects via `CodableRange`.
struct AuditDoseRange: Codable {
    let threshold: Double?
    let light: AuditCodableRange?
    let common: AuditCodableRange?
    let strong: AuditCodableRange?
    let heavy: Double?

    init(
        threshold: Double? = nil,
        light: AuditCodableRange? = nil,
        common: AuditCodableRange? = nil,
        strong: AuditCodableRange? = nil,
        heavy: Double? = nil
    ) {
        self.threshold = threshold
        self.light = light
        self.common = common
        self.strong = strong
        self.heavy = heavy
    }
}
