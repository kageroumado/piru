import Foundation

// MARK: - Validation Result Types

enum DiscrepancyKind: CustomStringConvertible {
    case doseMismatch(route: String, level: String, localValue: String, apiValue: String, percentDiff: Double)
    case missingRoute(route: String, presentIn: String)
    case missingDoseLevel(route: String, level: String, presentIn: String)
    case categoryMismatch(local: String, api: String)
    case unitMismatch(route: String, localUnit: String, apiUnit: String)
    case aliasDifference(localOnly: [String], apiOnly: [String])

    var description: String {
        switch self {
        case .doseMismatch(let route, let level, let local, let api, let pct):
            return "Dose mismatch [\(route)/\(level)]: local=\(local), api=\(api) (diff: \(String(format: "%.1f", pct))%)"
        case .missingRoute(let route, let presentIn):
            return "Route '\(route)' only in \(presentIn)"
        case .missingDoseLevel(let route, let level, let presentIn):
            return "Dose level '\(level)' for \(route) only in \(presentIn)"
        case .categoryMismatch(let local, let api):
            return "Category: local=\(local), api=\(api)"
        case .unitMismatch(let route, let localUnit, let apiUnit):
            return "Unit mismatch [\(route)]: local=\(localUnit), api=\(apiUnit)"
        case .aliasDifference(let localOnly, let apiOnly):
            var parts: [String] = []
            if !localOnly.isEmpty { parts.append("local-only: \(localOnly.joined(separator: ", "))") }
            if !apiOnly.isEmpty { parts.append("api-only: \(apiOnly.joined(separator: ", "))") }
            return "Alias diff: \(parts.joined(separator: "; "))"
        }
    }
}

enum ValidationSeverity: String, Comparable {
    case critical
    case warning
    case info

    static func < (lhs: ValidationSeverity, rhs: ValidationSeverity) -> Bool {
        let order: [ValidationSeverity] = [.critical, .warning, .info]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

struct SubstanceDiscrepancy {
    let substanceName: String
    let kind: DiscrepancyKind
    let severity: ValidationSeverity
    let recommendation: String
}

struct MatchResult {
    let localSubstance: ParsedLocalSubstance
    let apiSubstance: UnifiedSubstance
    let matchType: MatchType
    let discrepancies: [SubstanceDiscrepancy]

    enum MatchType: String {
        case exactName = "Exact name"
        case exactAlias = "Exact alias"
        case fuzzy = "Fuzzy (needs review)"
    }
}

struct ValidationReport {
    let timestamp: Date
    let totalLocalSubstances: Int
    let totalTripSitSubstances: Int
    let totalPWSubstances: Int
    let matchedCount: Int
    let matches: [MatchResult]
    let discrepancies: [SubstanceDiscrepancy]
    let newSubstancesFromAPI: [UnifiedSubstance]
    let localOnlySubstances: [ParsedLocalSubstance]
    let fuzzyMatchesForReview: [MatchResult]

    var criticalCount: Int { discrepancies.filter { $0.severity == .critical }.count }
    var warningCount: Int { discrepancies.filter { $0.severity == .warning }.count }
    var infoCount: Int { discrepancies.filter { $0.severity == .info }.count }
}
