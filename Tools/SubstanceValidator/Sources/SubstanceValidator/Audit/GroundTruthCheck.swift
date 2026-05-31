import Foundation

/// Compares the library's `heavy` values against the hand-curated reference
/// doses in `GroundTruth`. Substances matched by lowercased name *or* alias.
enum GroundTruthCheck {
    /// Run ground-truth comparisons against the full library.
    static func run(_ substances: [AuditSubstance]) -> [AuditFinding] {
        var findings: [AuditFinding] = []
        for entry in GroundTruth.entries {
            findings.append(contentsOf: check(entry: entry, in: substances))
        }
        return findings
    }

    /// For a single ground-truth entry, locate the matching substance/route
    /// and either flag a deviation or note that the data is missing.
    static func check(entry: GroundTruthEntry, in substances: [AuditSubstance]) -> [AuditFinding] {
        // Match by canonical name or any alias, case-insensitively.
        let matched = substances.first { substance in
            let key = entry.name.lowercased()
            if substance.name.lowercased() == key { return true }
            return substance.aliases.contains { $0.lowercased() == key }
        }
        guard let substance = matched else {
            return [] // Substance not in library — silent, not an audit concern.
        }

        guard let route = substance.routes.first(where: { $0.route.lowercased() == entry.route.lowercased() }) else {
            return [AuditFinding(
                substance: substance.name,
                category: substance.category,
                route: entry.route,
                unit: entry.unit,
                check: .groundTruth,
                severity: .warning,
                detail: "ground-truth has \(entry.route) data (heavy \(format(entry.expectedHeavy)) \(entry.unit), source: \(entry.source)) but library has no \(entry.route) route.",
                expected: "route \(entry.route) present",
                actual: "missing",
            )]
        }

        guard let heavy = route.doses.heavy else {
            return [AuditFinding(
                substance: substance.name,
                category: substance.category,
                route: route.route,
                unit: route.unit,
                check: .groundTruth,
                severity: .warning,
                detail: "ground-truth has heavy = \(format(entry.expectedHeavy)) \(entry.unit) (\(entry.source)) but library is missing heavy.",
                expected: "heavy ~\(format(entry.expectedHeavy)) \(entry.unit)",
                actual: "nil",
            )]
        }

        // Compare values in the entry's declared unit. Skip cleanly if the
        // library route uses an incompatible unit (e.g. IU vs mg).
        guard let heavyInEntryUnit = convert(heavy, from: route.unit, to: entry.unit) else {
            return [] // Unit incompatible — can't compare meaningfully, leave it.
        }

        let lower = entry.expectedHeavy * (1 - entry.tolerancePercent)
        let upper = entry.expectedHeavy * (1 + entry.tolerancePercent)
        if heavyInEntryUnit < lower || heavyInEntryUnit > upper {
            return [AuditFinding(
                substance: substance.name,
                category: substance.category,
                route: route.route,
                unit: route.unit,
                check: .groundTruth,
                severity: .error,
                detail: "library heavy \(format(heavy)) \(route.unit) (= \(format(heavyInEntryUnit)) \(entry.unit)) outside expected \(format(entry.expectedHeavy)) ±\(Int(entry.tolerancePercent * 100))% [\(format(lower))-\(format(upper)) \(entry.unit)]. Source: \(entry.source).",
                expected: "\(format(entry.expectedHeavy)) ±\(Int(entry.tolerancePercent * 100))% \(entry.unit)",
                actual: "\(format(heavy)) \(route.unit)",
            )]
        }
        return []
    }

    // MARK: - Helpers

    /// Convert mass amounts between µg/mg/g. Returns `nil` for non-mass units
    /// (mL, IU) or when src/dst aren't both mass.
    private static func convert(_ amount: Double, from src: String, to dst: String) -> Double? {
        let toMg: [String: Double] = ["µg": 0.001, "ug": 0.001, "mg": 1, "g": 1_000]
        let srcKey = src.lowercased(), dstKey = dst.lowercased()
        if srcKey == dstKey { return amount }
        guard let s = toMg[srcKey], let d = toMg[dstKey] else { return nil }
        return amount * s / d
    }

    private static func format(_ v: Double) -> String {
        v == v.rounded() ? String(format: "%g", v) : String(format: "%.4g", v)
    }
}
