import Foundation

/// A plausibility bound for a `(category, route)` pair. The bounds describe
/// the range that a typical substance in this class should fall within for a
/// recreational/clinical heavy dose. Specialty outliers (e.g. ultra-potent
/// fentanyl analogs) are expected to trip the check — that's the point.
///
/// `acceptableUnits` lists every unit the category × route legitimately uses
/// when bounds are *interpreted in `unit`*. A µg dose still satisfies an mg
/// bound if µg is in the acceptable list; the audit converts before comparing.
/// Routes that mix incompatible units (e.g. mg vs g) only get flagged when the
/// observed unit isn't in `acceptableUnits` — covering the alcohol-in-mg /
/// fentanyl-in-mg / LSD-in-mg slip cases without false-flagging the routine
/// µg-dosed psychedelics and opioids.
struct PlausibilityBound {
    let category: String
    let route: String
    /// Unit the bounds are denominated in (always a mass unit here).
    let unit: String
    /// Minimum acceptable threshold dose, in `unit`.
    let minThreshold: Double
    /// Maximum acceptable heavy dose, in `unit`.
    let maxHeavy: Double
    /// Units the category × route can legitimately use. The first entry is
    /// always `unit`. Doses in any of these convert into `unit` before
    /// comparing to the bound.
    let acceptableUnits: [String]
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
                          acceptableUnits: ["mg", "µg"],
                          rationale: "Typical recreational/clinical stimulants top out near 500 mg PO."),

        // Insufflated stimulants are usually dosed lower than oral due to higher bioavailability.
        PlausibilityBound(category: "Stimulant", route: "insufflation", unit: "mg",
                          minThreshold: 0.1, maxHeavy: 200,
                          acceptableUnits: ["mg", "µg"],
                          rationale: "Insufflated stimulants peak around 150-200 mg per dose."),

        // Most clinically used opioids cap heavy at ~200 mg PO. Fentanyl-class
        // analogs legitimately dose in µg, so µg is acceptable.
        PlausibilityBound(category: "Opioid", route: "oral", unit: "mg",
                          minThreshold: 0.05, maxHeavy: 200,
                          acceptableUnits: ["mg", "µg"],
                          rationale: "Most opioids — morphine, oxycodone, codeine — cap heavy oral near 200 mg; fentanyl-class µg-dosed."),

        // Insufflated opioids are dose-reduced; 100 mg is a generous upper bound.
        PlausibilityBound(category: "Opioid", route: "insufflation", unit: "mg",
                          minThreshold: 0.05, maxHeavy: 100,
                          acceptableUnits: ["mg", "µg"],
                          rationale: "Insufflated opioids rarely exceed 100 mg recreationally; fentanyl-class µg-dosed."),

        // Psychedelics span LSD-class (µg) through phenethylamines/mescaline (mg–g).
        // µg is *normal* for the LSD/NBOMe family — don't false-flag it.
        PlausibilityBound(category: "Psychedelic", route: "oral", unit: "mg",
                          minThreshold: 0.001, maxHeavy: 1000,
                          acceptableUnits: ["mg", "µg"],
                          rationale: "Psychedelic mass range spans LSD (µg) to mescaline (~1 g)."),

        // Sublingual is the canonical route for tabbed LSDs.
        PlausibilityBound(category: "Psychedelic", route: "sublingual", unit: "µg",
                          minThreshold: 1, maxHeavy: 5000,
                          acceptableUnits: ["µg", "mg"],
                          rationale: "Sublingual LSD-class dose 50-500 µg, mescaline-class mg-dosed."),

        // Benzodiazepines: alprazolam ~4 mg, diazepam ~30 mg, never near 100 mg clinically.
        PlausibilityBound(category: "Benzodiazepine", route: "oral", unit: "mg",
                          minThreshold: 0.05, maxHeavy: 100,
                          acceptableUnits: ["mg", "µg"],
                          rationale: "Benzodiazepines top out near 100 mg PO (diazepam high end)."),

        // Ketamine PO can reach 400-500 mg; PCP/MXE/DXM all fit well under 2 g.
        PlausibilityBound(category: "Dissociative", route: "oral", unit: "mg",
                          minThreshold: 1, maxHeavy: 2000,
                          acceptableUnits: ["mg", "g"],
                          rationale: "Oral dissociatives — ketamine, DXM, MXE — fit under 2 g heavy."),

        // Insufflated ketamine heavy is ~250 mg; 500 mg is a generous outer bound.
        PlausibilityBound(category: "Dissociative", route: "insufflation", unit: "mg",
                          minThreshold: 1, maxHeavy: 500,
                          acceptableUnits: ["mg"],
                          rationale: "Insufflated dissociatives (mostly ketamine) cap near 500 mg."),

        // Inhaled THC: a heavy joint delivers ~10-30 mg absorbed THC.
        // Synthetic cannabinoids (5F-AKB48, AM-2201, etc.) are µg-active per dose.
        PlausibilityBound(category: "Cannabinoid", route: "inhalation", unit: "mg",
                          minThreshold: 0.1, maxHeavy: 100,
                          acceptableUnits: ["mg", "µg"],
                          rationale: "Inhaled THC delivery rarely exceeds 100 mg per session; synthetic SC µg-active."),

        // MDMA heavy is ~200 mg; some empathogens (MDA, methylone) go higher but stay <500 mg.
        PlausibilityBound(category: "Empathogen", route: "oral", unit: "mg",
                          minThreshold: 10, maxHeavy: 500,
                          acceptableUnits: ["mg"],
                          rationale: "Empathogens — MDMA, MDA, methylone — fit under 500 mg PO."),

        // Depressants split into two unit camps:
        //   - mg: benzos, barbiturates, gabapentinoids, GHB analogs in mass
        //   - g: ethanol, raw GHB (typical recreational doses in grams)
        // The combined plausibility window stretches from 0.05 mg (potent
        // benzos) through 200 g (alcohol). Both mg and g are acceptable.
        PlausibilityBound(category: "Depressant", route: "oral", unit: "mg",
                          minThreshold: 0.05, maxHeavy: 200_000,
                          acceptableUnits: ["mg", "g", "µg"],
                          rationale: "Depressants span benzos (mg) through ethanol (g) — wide window."),
    ]

    /// Look up the bound for a given `(category, route)`. The lookup is
    /// case-insensitive. Returns `nil` if no row applies — the plausibility
    /// check silently skips substances/routes that have no policy.
    static func bound(category: String, route: String) -> PlausibilityBound? {
        bounds.first { $0.category.caseInsensitiveCompare(category) == .orderedSame
            && $0.route.caseInsensitiveCompare(route) == .orderedSame }
    }
}
