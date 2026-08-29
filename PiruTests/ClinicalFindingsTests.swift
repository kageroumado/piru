import Foundation
import Testing
@testable import Piru

@Suite("ClinicalFindings")
struct ClinicalFindingsTests {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private let base = Date(timeIntervalSince1970: 1_699_920_000) // 2023-11-14 00:00:00 UTC

    private func day(_ n: Int) -> Date {
        base.addingTimeInterval(Double(n) * 86_400)
    }

    private func substance(_ name: String, _ currency: ExposureCurrency) -> ClinicalSubstance {
        ClinicalSubstance(name: name, displayName: name, colorHex: "#FF0000", unit: "mg", currency: currency)
    }

    private func report(
        substances: [ClinicalSubstance] = [],
        totalDays: Int = 0,
        daysUsed: Int = 0,
        longestBreakDays: Int = 0,
        currentBreakDays: Int = 0,
        exposure: [ExposureStat] = [],
        escalation: [EscalationStat] = [],
        overlaps: [OverlapStat] = [],
    ) -> ClinicalReport {
        ClinicalReport(
            start: base,
            end: base.addingTimeInterval(Double(max(totalDays, 1)) * 86_400),
            substances: substances,
            holidays: HolidayStats(totalDays: totalDays, daysUsed: daysUsed, longestBreakDays: longestBreakDays, currentBreakDays: currentBreakDays),
            exposure: exposure,
            escalation: escalation,
            overlaps: overlaps,
        )
    }

    // MARK: - Empty report

    @Test
    func `Empty report yields no findings`() {
        let r = report()
        let findings = ClinicalStats.findings(report: r, interactions: [])
        #expect(findings.isEmpty)
    }

    // MARK: - Escalation

    @Test
    func `Rising substance produces escalation finding`() throws {
        let subs = [substance("Oxycodone", .mme)]
        let r = report(
            substances: subs,
            totalDays: 90,
            daysUsed: 45,
            escalation: [
                EscalationStat(substanceIndex: 0, direction: .rising, change: 0.4, earlyMedian: 10, lateMedian: 14, doseCount: 12),
            ],
        )
        let findings = ClinicalStats.findings(report: r, interactions: [])
        let escalation = try #require(findings.first { $0.kind == .escalation })
        #expect(escalation.severity == .warning)
        #expect(escalation.summary.contains("Oxycodone"))
        #expect(escalation.summary.contains("+40%"))
        #expect(escalation.summary.contains("10"))
        #expect(escalation.summary.contains("14"))
    }

    // MARK: - Opioid load

    @Test
    func `Peak MME at or above 50 produces opioid load finding`() throws {
        let subs = [substance("Oxycodone", .mme)]
        let r = report(
            substances: subs,
            totalDays: 30,
            daysUsed: 15,
            exposure: [
                ExposureStat(substanceIndex: 0, currency: .mme, total: 1_500, peakDay: 75, dailyMean: 50, cumulative: []),
            ],
        )
        let findings = ClinicalStats.findings(report: r, interactions: [])
        let opioid = try #require(findings.first { $0.kind == .opioidLoad })
        #expect(opioid.severity == .warning)
        #expect(opioid.summary.contains("75 MME/day"))
        #expect(opioid.summary.contains("50 MME"))
    }

    @Test
    func `Peak MME at or above 90 references CDC 90 band`() throws {
        let subs = [substance("Oxycodone", .mme)]
        let r = report(
            substances: subs,
            totalDays: 30,
            daysUsed: 15,
            exposure: [
                ExposureStat(substanceIndex: 0, currency: .mme, total: 3_000, peakDay: 100, dailyMean: 100, cumulative: []),
            ],
        )
        let findings = ClinicalStats.findings(report: r, interactions: [])
        let opioid = try #require(findings.first { $0.kind == .opioidLoad })
        #expect(opioid.summary.contains("90 MME"))
    }

    @Test
    func `Peak MME below 50 produces no opioid finding`() {
        let subs = [substance("Codeine", .mme)]
        let r = report(
            substances: subs,
            totalDays: 30,
            daysUsed: 10,
            exposure: [
                ExposureStat(substanceIndex: 0, currency: .mme, total: 300, peakDay: 30, dailyMean: 10, cumulative: []),
            ],
        )
        let findings = ClinicalStats.findings(report: r, interactions: [])
        #expect(findings.allSatisfy { $0.kind != .opioidLoad })
    }

    // MARK: - Co-exposure

    @Test
    func `Co-exposure with dangerous interaction produces finding`() throws {
        let subs = [substance("Oxycodone", .mme), substance("Alprazolam", .diazepam)]
        let r = report(
            substances: subs,
            totalDays: 30,
            daysUsed: 10,
            overlaps: [
                OverlapStat(a: 0, b: 1, hours: 6.5),
            ],
        )
        let interactions = [
            CompressedInteraction(
                id: "benzodiazepine|opioid",
                severity: .dangerous,
                classA: "benzodiazepine",
                classB: "opioid",
                substancesA: ["Alprazolam"],
                substancesB: ["Oxycodone"],
                description: "Combined respiratory depression",
            ),
        ]
        let findings = ClinicalStats.findings(report: r, interactions: interactions)
        let coExposure = try #require(findings.first { $0.kind == .coExposure })
        #expect(coExposure.severity == .warning)
        #expect(coExposure.summary.contains("Oxycodone") || coExposure.summary.contains("Alprazolam"))
        #expect(coExposure.summary.contains("~7h") || coExposure.summary.contains("~6h"))
    }

    // MARK: - Cadence

    @Test
    func `High usage fraction produces cadence finding`() throws {
        let r = report(
            substances: [substance("X", .milligrams)],
            totalDays: 30,
            daysUsed: 28,
            longestBreakDays: 1,
        )
        let findings = ClinicalStats.findings(report: r, interactions: [])
        let cadence = try #require(findings.first { $0.kind == .cadence })
        #expect(cadence.severity == .info)
        #expect(cadence.summary.contains("28 of 30"))
        #expect(cadence.summary.contains("93%"))
    }

    @Test
    func `Short window below 14 days produces no cadence finding`() {
        let r = report(
            substances: [substance("X", .milligrams)],
            totalDays: 10,
            daysUsed: 10,
        )
        let findings = ClinicalStats.findings(report: r, interactions: [])
        #expect(findings.allSatisfy { $0.kind != .cadence })
    }

    // MARK: - Sorting

    @Test
    func `Findings sort warnings first, then by kind order`() {
        let subs = [substance("Oxycodone", .mme)]
        let r = report(
            substances: subs,
            totalDays: 30,
            daysUsed: 29,
            longestBreakDays: 1,
            exposure: [
                ExposureStat(substanceIndex: 0, currency: .mme, total: 3_000, peakDay: 100, dailyMean: 100, cumulative: []),
            ],
            escalation: [
                EscalationStat(substanceIndex: 0, direction: .rising, change: 0.5, earlyMedian: 10, lateMedian: 15, doseCount: 12),
            ],
        )
        let findings = ClinicalStats.findings(report: r, interactions: [])
        #expect(findings.count >= 3)
        let warnings = findings.filter { $0.severity == .warning }
        let infos = findings.filter { $0.severity == .info }
        #expect(!warnings.isEmpty)
        #expect(!infos.isEmpty)
        if let lastWarningIndex = findings.lastIndex(where: { $0.severity == .warning }),
           let firstInfoIndex = findings.firstIndex(where: { $0.severity == .info }) {
            #expect(lastWarningIndex < firstInfoIndex)
        }
        if let opioidIdx = findings.firstIndex(where: { $0.kind == .opioidLoad }),
           let escIdx = findings.firstIndex(where: { $0.kind == .escalation }) {
            #expect(opioidIdx < escIdx)
        }
    }

    // MARK: - Interaction compression

    @Test
    func `Compression deduplicates by class pair, keeps highest severity`() {
        let raw: [(severity: InteractionSeverity, substanceA: String, substanceB: String, description: String, drugClassesA: [DrugClass], drugClassesB: [DrugClass])] = [
            (.dangerous, "Oxycodone", "Alprazolam", "Respiratory depression", [.opioid], [.benzodiazepine]),
            (.dangerous, "Morphine", "Diazepam", "Respiratory depression", [.opioid], [.benzodiazepine]),
            (.dangerous, "Oxycodone", "Diazepam", "Respiratory depression", [.opioid], [.benzodiazepine]),
            (.caution, "Amphetamine", "MDMA", "Cardiovascular strain", [.stimulant], [.empathogen]),
            (.caution, "Methylphenidate", "MDMA", "Cardiovascular strain", [.stimulant], [.empathogen]),
            (.unsafe, "Cocaine", "MDA", "Cardiovascular strain and serotonergic", [.stimulant], [.empathogen]),
        ]

        let compressed = ClinicalStats.compressInteractions(raw)
        #expect(compressed.count == 2)

        let opioidBenzo = compressed.first { $0.id == "benzodiazepine|opioid" }
        let stimEmpathogen = compressed.first { $0.id == "empathogen|stimulant" }

        #expect(opioidBenzo != nil)
        #expect(opioidBenzo?.severity == .dangerous)

        #expect(stimEmpathogen != nil)
        #expect(stimEmpathogen?.severity == .unsafe)
    }
}
