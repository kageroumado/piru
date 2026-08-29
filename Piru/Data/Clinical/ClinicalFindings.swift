import Foundation

// MARK: - Compressed Interaction

/// A class-deduped interaction: many substance pairs that share the same
/// unordered drug-class pair collapse into one row listing all participants.
nonisolated struct CompressedInteraction: Sendable, Identifiable {
    let id: String
    let severity: InteractionSeverity
    let classA: String
    let classB: String
    let substancesA: [String]
    let substancesB: [String]
    let description: String
}

// MARK: - Clinical Finding

nonisolated struct Finding: Sendable, Identifiable {
    enum Severity: Sendable { case warning, info }
    enum Kind: String, Sendable, Comparable {
        case escalation
        case opioidLoad
        case coExposure
        case cadence
        case duplication

        /// Warning-tier sort order: opioidLoad first, then escalation, coExposure.
        private var sortOrder: Int {
            switch self {
            case .opioidLoad: 0
            case .escalation: 1
            case .coExposure: 2
            case .cadence: 3
            case .duplication: 4
            }
        }

        static func < (lhs: Kind, rhs: Kind) -> Bool {
            lhs.sortOrder < rhs.sortOrder
        }
    }

    let id: String
    let severity: Severity
    let kind: Kind
    let summary: String
}

// MARK: - Finding generation

extension ClinicalStats {
    // MARK: Interaction compression

    static func compressInteractions(
        _ raw: [(severity: InteractionSeverity, substanceA: String, substanceB: String, description: String, drugClassesA: [DrugClass], drugClassesB: [DrugClass])],
    ) -> [CompressedInteraction] {
        struct ClassPairKey: Hashable {
            let classA: String
            let classB: String
        }

        struct Accumulator {
            var severity: InteractionSeverity
            var classA: String
            var classB: String
            var substancesA: Set<String> = []
            var substancesB: Set<String> = []
            var description: String
        }

        var byPair: [ClassPairKey: Accumulator] = [:]

        for row in raw {
            for clsA in row.drugClassesA {
                for clsB in row.drugClassesB {
                    let sorted = [clsA.rawValue, clsB.rawValue].sorted()
                    let key = ClassPairKey(classA: sorted[0], classB: sorted[1])

                    if var existing = byPair[key] {
                        if row.severity > existing.severity {
                            existing.severity = row.severity
                            existing.description = row.description
                        }
                        existing.substancesA.insert(row.substanceA)
                        existing.substancesB.insert(row.substanceB)
                        byPair[key] = existing
                    } else {
                        byPair[key] = Accumulator(
                            severity: row.severity,
                            classA: sorted[0],
                            classB: sorted[1],
                            substancesA: [row.substanceA],
                            substancesB: [row.substanceB],
                            description: row.description,
                        )
                    }
                }
            }
        }

        return byPair.map { key, acc in
            CompressedInteraction(
                id: "\(key.classA)|\(key.classB)",
                severity: acc.severity,
                classA: acc.classA,
                classB: acc.classB,
                substancesA: acc.substancesA.sorted(),
                substancesB: acc.substancesB.sorted(),
                description: acc.description,
            )
        }
        .sorted { $0.severity > $1.severity }
    }

    // MARK: Findings

    static func findings(
        report: ClinicalReport,
        interactions: [CompressedInteraction],
    ) -> [Finding] {
        var results: [Finding] = []
        appendOpioidLoadFindings(from: report, to: &results)
        appendEscalationFindings(from: report, to: &results)
        appendCoExposureFindings(from: report, interactions: interactions, to: &results)
        appendCadenceFindings(from: report, to: &results)
        return results.sorted { lhs, rhs in
            if lhs.severity != rhs.severity {
                return lhs.severity == .warning
            }
            return lhs.kind < rhs.kind
        }
    }

    // MARK: - Threshold rules

    private static func appendEscalationFindings(
        from report: ClinicalReport,
        to results: inout [Finding],
    ) {
        for stat in report.escalation where stat.direction == .rising && abs(stat.change) > 0.15 {
            guard stat.substanceIndex < report.substances.count else { continue }
            let substance = report.substances[stat.substanceIndex]
            let pct = Int((stat.change * 100).rounded())
            let early = formatDose(stat.earlyMedian)
            let late = formatDose(stat.lateMedian)
            results.append(Finding(
                id: "escalation-\(stat.substanceIndex)",
                severity: .warning,
                kind: .escalation,
                summary: String(
                    localized: "\(substance.displayName) dose rising, +\(pct)% over the reporting period (\(early) → \(late) \(substance.unit)).",
                ),
            ))
        }
    }

    private static func appendOpioidLoadFindings(
        from report: ClinicalReport,
        to results: inout [Finding],
    ) {
        guard let peakMME = report.opioidPeakDayMME, peakMME >= 50 else { return }
        let n = Int(peakMME.rounded())
        let summary = if peakMME >= 90 {
            String(
                localized: "Peak opioid load \(n) MME/day — above the CDC 90 MME reference.",
            )
        } else {
            String(
                localized: "Peak opioid load \(n) MME/day — at or above the CDC 50 MME reference.",
            )
        }
        results.append(Finding(
            id: "opioidLoad",
            severity: .warning,
            kind: .opioidLoad,
            summary: summary,
        ))
    }

    private static func appendCoExposureFindings(
        from report: ClinicalReport,
        interactions: [CompressedInteraction],
        to results: inout [Finding],
    ) {
        let dangerousInteractions = interactions.filter {
            $0.severity == .dangerous || $0.severity == .unsafe
        }
        guard !dangerousInteractions.isEmpty else { return }

        struct OverlapEntry {
            let displayA: String
            let displayB: String
            let hours: Double
        }
        var overlapByPair: [String: OverlapEntry] = [:]
        for overlap in report.overlaps {
            guard overlap.a < report.substances.count,
                  overlap.b < report.substances.count else { continue }
            let subA = report.substances[overlap.a]
            let subB = report.substances[overlap.b]
            let key = [subA.name.lowercased(), subB.name.lowercased()].sorted().joined(separator: "|")
            overlapByPair[key] = OverlapEntry(displayA: subA.displayName, displayB: subB.displayName, hours: overlap.hours)
        }

        for interaction in dangerousInteractions {
            var best: OverlapEntry?
            for subA in interaction.substancesA {
                for subB in interaction.substancesB {
                    let key = [subA.lowercased(), subB.lowercased()].sorted().joined(separator: "|")
                    if let entry = overlapByPair[key], entry.hours > (best?.hours ?? 0) {
                        best = entry
                    }
                }
            }
            guard let match = best else { continue }
            let hours = match.hours
            let nameA = match.displayA
            let nameB = match.displayB
            let h = Int(hours.rounded())
            results.append(Finding(
                id: "coExposure-\(interaction.id)",
                severity: .warning,
                kind: .coExposure,
                summary: String(
                    localized: "\(nameA) + \(nameB) active together ~\(h)h (\(interaction.classA) + \(interaction.classB)).",
                ),
            ))
        }
    }

    private static func appendCadenceFindings(
        from report: ClinicalReport,
        to results: inout [Finding],
    ) {
        let h = report.holidays
        guard h.totalDays >= 14 else { return }

        if h.fractionUsed > 0.85 {
            let pct = Int((h.fractionUsed * 100).rounded())
            results.append(Finding(
                id: "cadence-high",
                severity: .info,
                kind: .cadence,
                summary: String(
                    localized: "Used \(h.daysUsed) of \(h.totalDays) days (\(pct)%).",
                ),
            ))
        } else if h.fractionUsed < 0.15 {
            results.append(Finding(
                id: "cadence-low",
                severity: .info,
                kind: .cadence,
                summary: String(
                    localized: "Used \(h.daysUsed) of \(h.totalDays) days; longest break \(h.longestBreakDays) days.",
                ),
            ))
        }
    }

    // MARK: Helpers

    private static func formatDose(_ value: Double) -> String {
        if value == value.rounded(), value < 10_000 {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }
}
