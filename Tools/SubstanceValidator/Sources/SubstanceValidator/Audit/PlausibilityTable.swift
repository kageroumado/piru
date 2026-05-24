import Foundation

/// A plausibility bound for a `(category, route)` pair. The bounds describe
/// the range that a typical substance in this class should fall within for a
/// recreational/clinical heavy dose. Specialty outliers (e.g. ultra-potent
/// fentanyl analogs) are expected to trip the check — that's the point.
struct PlausibilityBound {
    let category: String
    let route: String
    /// Unit the bounds are denominated in (always a mass unit here).
    let unit: String
    /// Minimum acceptable threshold dose, in `unit`.
    let minThreshold: Double
    /// Maximum acceptable heavy dose, in `unit`.
    let maxHeavy: Double
    /// One-line justification, surfaced in the report.
    let rationale: String
}

/// Hard-coded `(category, route)` → expected dose range table used by the
/// plausibility check. Bounds are deliberately generous so that *typical*
/// substances pass and only true outliers (off-by-1000 unit slips, broken
/// parses) get flagged.
enum PlausibilityTable {
    static let bounds: [PlausibilityBound] = [
        // Cocaine, amphetamine, methylphenidate sit comfortably under 500 mg PO.
        PlausibilityBound(category: "Stimulant", route: "oral", unit: "mg",
                          minThreshold: 0.1, maxHeavy: 500,
                          rationale: "Typical recreational/clinical stimulants top out near 500 mg PO."),

        // Insufflated stimulants are usually dosed lower than oral due to higher bioavailability.
        PlausibilityBound(category: "Stimulant", route: "insufflation", unit: "mg",
                          minThreshold: 0.1, maxHeavy: 200,
                          rationale: "Insufflated stimulants peak around 150-200 mg per dose."),

        // Most clinically used opioids (oxycodone, morphine, codeine) heavy dose is well under 200 mg PO.
        PlausibilityBound(category: "Opioid", route: "oral", unit: "mg",
                          minThreshold: 0.05, maxHeavy: 200,
                          rationale: "Most opioids — morphine, oxycodone, codeine — cap heavy oral near 200 mg."),

        // Insufflated opioids are dose-reduced; 100 mg is a generous upper bound.
        PlausibilityBound(category: "Opioid", route: "insufflation", unit: "mg",
                          minThreshold: 0.05, maxHeavy: 100,
                          rationale: "Insufflated opioids rarely exceed 100 mg recreationally."),

        // Psychedelics range from LSD (µg) to mescaline (~1 g). Bound is wide on purpose.
        PlausibilityBound(category: "Psychedelic", route: "oral", unit: "mg",
                          minThreshold: 0.001, maxHeavy: 1000,
                          rationale: "Psychedelic mass range spans LSD (µg) to mescaline (~1 g)."),

        // Benzodiazepines: alprazolam ~4 mg, diazepam ~30 mg, never near 100 mg clinically.
        PlausibilityBound(category: "Benzodiazepine", route: "oral", unit: "mg",
                          minThreshold: 0.05, maxHeavy: 100,
                          rationale: "Benzodiazepines top out near 100 mg PO (diazepam high end)."),

        // Ketamine PO can reach 400-500 mg; PCP/MXE/DXM all fit well under 2 g.
        PlausibilityBound(category: "Dissociative", route: "oral", unit: "mg",
                          minThreshold: 1, maxHeavy: 2000,
                          rationale: "Oral dissociatives — ketamine, DXM, MXE — fit under 2 g heavy."),

        // Insufflated ketamine heavy is ~250 mg; 500 mg is a generous outer bound.
        PlausibilityBound(category: "Dissociative", route: "insufflation", unit: "mg",
                          minThreshold: 1, maxHeavy: 500,
                          rationale: "Insufflated dissociatives (mostly ketamine) cap near 500 mg."),

        // Inhaled THC: a heavy joint delivers ~10-30 mg absorbed THC. 100 mg is a generous cap.
        PlausibilityBound(category: "Cannabinoid", route: "inhalation", unit: "mg",
                          minThreshold: 0.1, maxHeavy: 100,
                          rationale: "Inhaled THC delivery rarely exceeds 100 mg per session."),

        // MDMA heavy is ~200 mg; some empathogens (MDA, methylone) go higher but stay <500 mg.
        PlausibilityBound(category: "Empathogen", route: "oral", unit: "mg",
                          minThreshold: 10, maxHeavy: 500,
                          rationale: "Empathogens — MDMA, MDA, methylone — fit under 500 mg PO."),

        // Alcohol is the one well-known substance dosed in grams of pure ethanol.
        PlausibilityBound(category: "Depressant", route: "oral", unit: "g",
                          minThreshold: 5, maxHeavy: 200,
                          rationale: "Ethanol dosing — 5 g threshold (~0.5 drink) to 200 g heavy."),
    ]

    /// Look up the bound for a given `(category, route)`. The lookup is
    /// case-insensitive. Returns `nil` if no row applies — the plausibility
    /// check silently skips substances/routes that have no policy.
    static func bound(category: String, route: String) -> PlausibilityBound? {
        bounds.first { $0.category.caseInsensitiveCompare(category) == .orderedSame
            && $0.route.caseInsensitiveCompare(route) == .orderedSame }
    }
}
