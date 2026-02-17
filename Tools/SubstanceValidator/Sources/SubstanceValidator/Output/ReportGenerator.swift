import Foundation

/// Generates validation reports in text and JSON formats.
enum ReportGenerator {
    // MARK: - Text Report

    static func generateTextReport(_ report: ValidationReport) -> String {
        var out = ""
        let divider = String(repeating: "=", count: 70)
        let subDivider = String(repeating: "-", count: 70)

        out += "\n\(divider)\n"
        out += "  PIRU SUBSTANCE VALIDATION REPORT\n"
        out += "  Generated: \(ISO8601DateFormatter().string(from: report.timestamp))\n"
        out += "\(divider)\n\n"

        // Summary
        out += "SUMMARY\n\(subDivider)\n"
        out += "  Local substances:          \(report.totalLocalSubstances)\n"
        out += "  TripSit substances:        \(report.totalTripSitSubstances)\n"
        out += "  PsychonautWiki substances: \(report.totalPWSubstances)\n"
        out += "  Matched pairs:             \(report.matchedCount)\n"
        out += "  New from APIs:             \(report.newSubstancesFromAPI.count)\n"
        out += "  Local-only (no API match): \(report.localOnlySubstances.count)\n"
        out += "  Discrepancies found:       \(report.discrepancies.count)\n"
        out += "    Critical:                \(report.criticalCount)\n"
        out += "    Warning:                 \(report.warningCount)\n"
        out += "    Info:                    \(report.infoCount)\n"
        out += "\n"

        // Critical discrepancies
        let criticals = report.discrepancies.filter { $0.severity == .critical }
        if !criticals.isEmpty {
            out += "\(divider)\n"
            out += "CRITICAL DISCREPANCIES (\(criticals.count))\n"
            out += "\(divider)\n\n"
            for (i, d) in criticals.enumerated() {
                out += "[C-\(String(format: "%03d", i + 1))] \(d.substanceName)\n"
                out += "  \(d.kind)\n"
                out += "  -> \(d.recommendation)\n\n"
            }
        }

        // Warnings
        let warnings = report.discrepancies.filter { $0.severity == .warning }
        if !warnings.isEmpty {
            out += "\(divider)\n"
            out += "WARNING DISCREPANCIES (\(warnings.count))\n"
            out += "\(divider)\n\n"
            for (i, d) in warnings.enumerated() {
                out += "[W-\(String(format: "%03d", i + 1))] \(d.substanceName)\n"
                out += "  \(d.kind)\n"
                out += "  -> \(d.recommendation)\n\n"
            }
        }

        // Info
        let infos = report.discrepancies.filter { $0.severity == .info }
        if !infos.isEmpty {
            out += "\(divider)\n"
            out += "INFO DISCREPANCIES (\(infos.count))\n"
            out += "\(divider)\n\n"
            for (i, d) in infos.enumerated() {
                out += "[I-\(String(format: "%03d", i + 1))] \(d.substanceName)\n"
                out += "  \(d.kind)\n"
                out += "  -> \(d.recommendation)\n\n"
            }
        }

        // New substances
        if !report.newSubstancesFromAPI.isEmpty {
            out += "\(divider)\n"
            out += "NEW SUBSTANCES FROM APIs (\(report.newSubstancesFromAPI.count))\n"
            out += "\(divider)\n\n"

            let sorted = report.newSubstancesFromAPI.sorted { $0.name < $1.name }
            for (i, sub) in sorted.enumerated() {
                let cats = sub.categories.joined(separator: ", ")
                out += "  \(i + 1). \(sub.name) (\(sub.source.rawValue)) - \(cats)\n"
            }
            out += "\n"
        }

        // Local-only
        if !report.localOnlySubstances.isEmpty {
            out += "\(divider)\n"
            out += "LOCAL-ONLY SUBSTANCES (\(report.localOnlySubstances.count))\n"
            out += "\(divider)\n\n"
            out += "  These exist in Piru but were not found in either API.\n\n"

            let sorted = report.localOnlySubstances.sorted { $0.name < $1.name }
            for (i, sub) in sorted.enumerated() {
                out += "  \(i + 1). \(sub.name) (\(sub.category)) [\(sub.sourceFile)]\n"
            }
            out += "\n"
        }

        // Fuzzy matches for review
        if !report.fuzzyMatchesForReview.isEmpty {
            out += "\(divider)\n"
            out += "FUZZY MATCHES REQUIRING REVIEW (\(report.fuzzyMatchesForReview.count))\n"
            out += "\(divider)\n\n"
            for m in report.fuzzyMatchesForReview {
                out += "  Local \"\(m.localSubstance.name)\" <-> API \"\(m.apiSubstance.name)\" (\(m.apiSubstance.source.rawValue))\n"
            }
            out += "\n"
        }

        out += "\(divider)\n"
        out += "END OF REPORT\n"
        out += "\(divider)\n"

        return out
    }

    // MARK: - JSON Report

    static func generateJSONReport(_ report: ValidationReport) -> String {
        var dict: [String: Any] = [:]

        dict["timestamp"] = ISO8601DateFormatter().string(from: report.timestamp)
        dict["summary"] = [
            "totalLocal": report.totalLocalSubstances,
            "totalTripSit": report.totalTripSitSubstances,
            "totalPsychonautWiki": report.totalPWSubstances,
            "matched": report.matchedCount,
            "newFromAPIs": report.newSubstancesFromAPI.count,
            "localOnly": report.localOnlySubstances.count,
            "discrepancies": report.discrepancies.count,
            "critical": report.criticalCount,
            "warning": report.warningCount,
            "info": report.infoCount,
        ] as [String: Int]

        dict["discrepancies"] = report.discrepancies.map { d -> [String: Any] in
            [
                "substance": d.substanceName,
                "severity": d.severity.rawValue,
                "description": d.kind.description,
                "recommendation": d.recommendation,
            ]
        }

        dict["newSubstances"] = report.newSubstancesFromAPI.map { s -> [String: Any] in
            [
                "name": s.name,
                "source": s.source.rawValue,
                "categories": s.categories,
                "aliases": s.aliases,
                "routeCount": s.routes.count,
            ]
        }

        dict["localOnly"] = report.localOnlySubstances.map { s -> [String: String] in
            ["name": s.name, "category": s.category, "file": s.sourceFile]
        }

        dict["fuzzyMatches"] = report.fuzzyMatchesForReview.map { m -> [String: String] in
            ["localName": m.localSubstance.name, "apiName": m.apiSubstance.name, "source": m.apiSubstance.source.rawValue]
        }

        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return "{\"error\": \"Failed to serialize report\"}"
        }

        return json
    }
}
