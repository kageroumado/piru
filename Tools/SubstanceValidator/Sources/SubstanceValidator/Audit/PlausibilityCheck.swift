import Foundation

/// Verifies that each route's `threshold` and `heavy` values fall within the
/// category-specific bounds from `PlausibilityTable`. Out-of-band values are
/// usually unit-mismatch slips (mg labeled as g, etc.) or upstream data
/// corruption.
enum PlausibilityCheck {
    /// Severity escalation threshold: above this multiple of the bound we
    /// treat the slip as `.error` rather than `.warning`. 10× catches the
    /// classic mg/g (1000×) and mg/µg (1000×) unit-mismatch bugs.
    private static let errorMultiple: Double = 10

    /// Run plausibility against every route of every substance.
    static func run(_ substances: [AuditSubstance]) -> [AuditFinding] {
        var findings: [AuditFinding] = []
        for substance in substances {
            for route in substance.routes {
                findings.append(contentsOf: check(substance: substance, route: route))
            }
        }
        return findings
    }

    /// Returns any plausibility violations for the given route. Two kinds of
    /// findings are produced:
    ///
    /// 1. **Unit mismatch.** A category has a known mass unit (e.g. mg for
    ///    stimulants) but the route uses a different convertible unit (µg or g).
    ///    Surfaced as a SUSPICIOUS warning.
    /// 2. **Out-of-bounds.** After unit conversion, `threshold` is below
    ///    `minThreshold` or `heavy` is above `maxHeavy`. Mildly outside →
    ///    warning; more than 10× outside → error.
    static func check(substance: AuditSubstance, route: AuditRoute) -> [AuditFinding] {
        guard let bound = PlausibilityTable.bound(category: substance.category, route: route.route) else {
            return []
        }
        var findings: [AuditFinding] = []

        // 1. Unit-mismatch heuristic. Only meaningful when both units are
        // convertible mass units (µg/mg/g) but differ from the canonical one.
        let isMassUnit: (String) -> Bool = { ["µg", "ug", "mg", "g"].contains($0.lowercased()) }
        if route.unit != bound.unit, isMassUnit(route.unit), isMassUnit(bound.unit) {
            findings.append(AuditFinding(
                substance: substance.name,
                category: substance.category,
                route: route.route,
                unit: route.unit,
                check: .plausibility,
                severity: .warning,
                detail: "category \(substance.category) typically uses \(bound.unit) on \(route.route); route uses \(route.unit) — verify not a unit-conversion slip.",
                expected: bound.unit,
                actual: route.unit
            ))
        }

        // 2. Compare threshold and heavy *in the bound's unit* so we don't
        // false-positive when the route uses µg but the values are correct.
        if let threshold = substance.routes
            .first(where: { $0.route == route.route })?.doses.threshold,
           let thresholdInBoundUnit = convert(threshold, from: route.unit, to: bound.unit),
           thresholdInBoundUnit < bound.minThreshold {
            let severity: AuditSeverity = (thresholdInBoundUnit * errorMultiple < bound.minThreshold) ? .error : .warning
            findings.append(AuditFinding(
                substance: substance.name,
                category: substance.category,
                route: route.route,
                unit: route.unit,
                check: .plausibility,
                severity: severity,
                detail: "threshold \(format(threshold)) \(route.unit) (= \(format(thresholdInBoundUnit)) \(bound.unit)) below expected minimum \(format(bound.minThreshold)) \(bound.unit). \(bound.rationale)",
                expected: ">= \(format(bound.minThreshold)) \(bound.unit)",
                actual: "\(format(threshold)) \(route.unit)"
            ))
        }

        if let heavy = route.doses.heavy,
           let heavyInBoundUnit = convert(heavy, from: route.unit, to: bound.unit),
           heavyInBoundUnit > bound.maxHeavy {
            let severity: AuditSeverity = (heavyInBoundUnit > bound.maxHeavy * errorMultiple) ? .error : .warning
            findings.append(AuditFinding(
                substance: substance.name,
                category: substance.category,
                route: route.route,
                unit: route.unit,
                check: .plausibility,
                severity: severity,
                detail: "heavy \(format(heavy)) \(route.unit) (= \(format(heavyInBoundUnit)) \(bound.unit)) above expected maximum \(format(bound.maxHeavy)) \(bound.unit). \(bound.rationale)",
                expected: "<= \(format(bound.maxHeavy)) \(bound.unit)",
                actual: "\(format(heavy)) \(route.unit)"
            ))
        }

        return findings
    }

    // MARK: - Helpers

    /// Convert a mass amount between µg/mg/g. Returns `nil` for non-mass units
    /// (mL, IU, etc.), which skips out-of-bounds comparison for those routes.
    private static func convert(_ amount: Double, from src: String, to dst: String) -> Double? {
        let toMg: [String: Double] = ["µg": 0.001, "ug": 0.001, "mg": 1, "g": 1000]
        let srcKey = src.lowercased(), dstKey = dst.lowercased()
        guard let s = toMg[srcKey], let d = toMg[dstKey] else { return nil }
        if srcKey == dstKey { return amount }
        return amount * s / d
    }

    private static func format(_ v: Double) -> String {
        v == v.rounded() ? String(format: "%g", v) : String(format: "%.4g", v)
    }
}
