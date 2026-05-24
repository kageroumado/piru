import Foundation

/// Severity of an audit finding.
///
/// Ordered so that `error < warning < info`, matching the convention used by
/// `ValidationReport` for sorting.
enum AuditSeverity: String, Comparable {
    case error
    case warning
    case info

    private var rank: Int {
        switch self {
        case .error: 0
        case .warning: 1
        case .info: 2
        }
    }

    static func < (lhs: AuditSeverity, rhs: AuditSeverity) -> Bool {
        lhs.rank < rhs.rank
    }

    var displayName: String {
        switch self {
        case .error: "ERROR"
        case .warning: "WARNING"
        case .info: "INFO"
        }
    }
}

/// Which audit check produced a finding.
enum AuditCheck: String {
    case monotonicity = "Monotonicity"
    case plausibility = "Plausibility"
    case groundTruth = "GroundTruth"
}

/// A single audit finding referencing a substance and (usually) a route.
struct AuditFinding {
    let substance: String
    let category: String
    let route: String?
    let unit: String?
    let check: AuditCheck
    let severity: AuditSeverity
    /// Free-form description of *what* was wrong (e.g. "light upper (40 mg) > common lower (20 mg)").
    let detail: String
    /// Human-readable description of *what was expected* (e.g. "heavy in 10-500 mg").
    let expected: String?
    /// The actual offending value, formatted for display.
    let actual: String?
}
