import Foundation

/// Renders an `audit-report.md` from a list of `AuditFinding`s, grouped by
/// severity → check → substance.
enum AuditReportGenerator {
    /// Generate the full markdown report.
    ///
    /// - Parameters:
    ///   - findings: every finding produced by the audit checks.
    ///   - substances: the full library, used for header stats.
    ///   - cachePath: surfaced in the header so the report is self-describing.
    static func generate(
        findings: [AuditFinding],
        substances: [AuditSubstance],
        cachePath: String,
        timestamp: Date = Date()
    ) -> String {
        var out = ""

        // MARK: Header
        out += "# Piru Substance Library Audit\n\n"
        out += "**Cache:** `\(cachePath)`  \n"
        out += "**Generated:** \(ISO8601DateFormatter().string(from: timestamp))  \n"
        out += "**Total substances:** \(substances.count)  \n"

        // Source breakdown
        var sourceCounts: [String: Int] = [:]
        for substance in substances {
            for source in substance.sources {
                sourceCounts[source, default: 0] += 1
            }
        }
        if !sourceCounts.isEmpty {
            out += "**Per source:** "
            out += sourceCounts.sorted { $0.key < $1.key }
                .map { "\($0.key): \($0.value)" }
                .joined(separator: ", ")
            out += "\n"
        }

        // Severity counts
        let errors = findings.filter { $0.severity == .error }
        let warnings = findings.filter { $0.severity == .warning }
        let infos = findings.filter { $0.severity == .info }
        out += "**Findings:** \(errors.count) error(s), \(warnings.count) warning(s), \(infos.count) info\n\n"

        // MARK: Findings by severity → check
        for severity in [AuditSeverity.error, .warning, .info] {
            let bucket = findings.filter { $0.severity == severity }
            guard !bucket.isEmpty else { continue }
            out += "## \(severity.displayName) (\(bucket.count))\n\n"

            for check in [AuditCheck.monotonicity, .plausibility, .groundTruth] {
                let checkFindings = bucket.filter { $0.check == check }
                guard !checkFindings.isEmpty else { continue }
                out += "### \(check.rawValue) (\(checkFindings.count))\n\n"
                out += renderTable(checkFindings)
                out += "\n"
            }
        }

        // MARK: Summary by category
        out += "## Summary by category\n\n"
        var byCategory: [String: Int] = [:]
        for finding in findings {
            byCategory[finding.category, default: 0] += 1
        }
        if byCategory.isEmpty {
            out += "_No findings._\n"
        } else {
            out += "| Category | Findings |\n"
            out += "|----------|---------:|\n"
            for (category, count) in byCategory.sorted(by: { $0.value > $1.value }) {
                out += "| \(escape(category)) | \(count) |\n"
            }
        }
        out += "\n"

        // Cross-source disagreement TODO
        out += "## Cross-source disagreement\n\n"
        // TODO: per-route source attribution does not currently exist on
        // `Substance`. To implement this check, `SubstanceRoute` would need to
        // track each contributing source (TripSit / DailyMed / PsychonautWiki
        // / drug.community) so the audit can flag conflicting `heavy` /
        // `threshold` values across providers for the same route.
        out += "_Deferred — requires per-route source attribution on `Substance.routes` (currently only the substance-level `sources` array exists)._\n"

        return out
    }

    // MARK: - Helpers

    private static func renderTable(_ findings: [AuditFinding]) -> String {
        var out = "| Substance | Category | Route | Actual | Expected | Detail |\n"
        out += "|-----------|----------|-------|--------|----------|--------|\n"
        for f in findings.sorted(by: { $0.substance.lowercased() < $1.substance.lowercased() }) {
            out += "| \(escape(f.substance))"
            out += " | \(escape(f.category))"
            out += " | \(escape(f.route ?? "-"))"
            out += " | \(escape(f.actual ?? "-"))"
            out += " | \(escape(f.expected ?? "-"))"
            out += " | \(escape(f.detail)) |\n"
        }
        return out
    }

    /// Escape pipes and newlines so they don't break the markdown table layout.
    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
    }
}
