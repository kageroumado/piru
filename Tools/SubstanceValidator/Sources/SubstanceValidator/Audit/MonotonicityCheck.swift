import Foundation

/// Verifies that dose levels within a single route are monotonically
/// non-decreasing: `threshold ≤ light.lower ≤ light.upper ≤ common.lower ≤
/// common.upper ≤ strong.lower ≤ strong.upper ≤ heavy`.
///
/// Any missing level is skipped — only the present pairs are compared.
enum MonotonicityCheck {
    /// Run the check against every route of every substance.
    static func run(_ substances: [AuditSubstance]) -> [AuditFinding] {
        var findings: [AuditFinding] = []
        for substance in substances {
            for route in substance.routes {
                findings.append(contentsOf: check(substance: substance, route: route))
            }
        }
        return findings
    }

    /// Returns the inversions found in a single route's dose ladder.
    static func check(substance: AuditSubstance, route: AuditRoute) -> [AuditFinding] {
        let d = route.doses
        var findings: [AuditFinding] = []

        // Collect the ordered (label, value) pairs that are present.
        var rungs: [(label: String, value: Double)] = []
        if let v = d.threshold { rungs.append(("threshold", v)) }
        if let r = d.light {
            rungs.append(("light.lower", r.lower))
            rungs.append(("light.upper", r.upper))
        }
        if let r = d.common {
            rungs.append(("common.lower", r.lower))
            rungs.append(("common.upper", r.upper))
        }
        if let r = d.strong {
            rungs.append(("strong.lower", r.lower))
            rungs.append(("strong.upper", r.upper))
        }
        if let v = d.heavy { rungs.append(("heavy", v)) }

        guard rungs.count >= 2 else { return findings }
        for i in 1 ..< rungs.count {
            let prev = rungs[i - 1]
            let curr = rungs[i]
            if curr.value < prev.value {
                findings.append(AuditFinding(
                    substance: substance.name,
                    category: substance.category,
                    route: route.route,
                    unit: route.unit,
                    check: .monotonicity,
                    severity: .error,
                    detail: "\(curr.label) (\(format(curr.value)) \(route.unit)) < \(prev.label) (\(format(prev.value)) \(route.unit))",
                    expected: "\(curr.label) >= \(prev.label)",
                    actual: "\(format(curr.value)) < \(format(prev.value))",
                ))
            }
        }
        return findings
    }

    private static func format(_ v: Double) -> String {
        v == v.rounded() ? String(format: "%g", v) : String(format: "%.4g", v)
    }
}
