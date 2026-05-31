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
        case let .doseMismatch(route, level, local, api, pct):
            return "Dose mismatch [\(route)/\(level)]: local=\(local), api=\(api) (diff: \(String(format: "%.1f", pct))%)"
        case let .missingRoute(route, presentIn):
            return "Route '\(route)' only in \(presentIn)"
        case let .missingDoseLevel(route, level, presentIn):
            return "Dose level '\(level)' for \(route) only in \(presentIn)"
        case let .categoryMismatch(local, api):
            return "Category: local=\(local), api=\(api)"
        case let .unitMismatch(route, localUnit, apiUnit):
            return "Unit mismatch [\(route)]: local=\(localUnit), api=\(apiUnit)"
        case let .aliasDifference(localOnly, apiOnly):
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

    var criticalCount: Int {
        discrepancies.count(where: { $0.severity == .critical })
    }
    var warningCount: Int {
        discrepancies.count(where: { $0.severity == .warning })
    }
    var infoCount: Int {
        discrepancies.count(where: { $0.severity == .info })
    }
}
