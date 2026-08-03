import GRDB
import os

private nonisolated let logger = Logger(subsystem: "dev.yumeji.piru", category: "SubstanceStore")

/// Library-wide reads for the class signatures. A signature is a *comparison*, so unlike every other
/// pharmacology query on this store it cannot be scoped to one substance: the ladder, the arc and the
/// triangle all need the peers that were measured beside it.
///
/// The tables involved are small (≈360 transporter rows, ≈160 serotonin rows, ≈180 opioid/cannabinoid
/// rows), so each family is a single unfiltered read rather than a per-substance query — and the
/// comparability gate ``SignatureComparability`` then runs in memory where it is testable.
///
/// Lives beside ``SubstanceStore`` rather than inside it: `SubstanceStore.swift` sits at its
/// 2,500-line lint ceiling.
extension SubstanceStore {
    /// Every leg of one signature family, across the whole library, normalized for the gate.
    func signatureLegs(family: SignatureFamily) -> [SignatureLeg] {
        var legs = bindingLegs(family: family)
        // Releaser potencies for several stimulants live in `functional_assays` rather than
        // `bindings` (Fenfluramine, Aminorex, 4,4'-DMAR, Phentermine, …), so the triangle has to
        // read both. The table carries no `comparable_set`, so those rows gate on citation alone.
        if family == .transporters {
            legs += functionalAssayLegs()
        }
        return legs
    }

    private func bindingLegs(family: SignatureFamily) -> [SignatureLeg] {
        do {
            return try substancesDB.read { db in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT b.id, b.target, b.action, b.ki_nm, b.ec50_nm, b.ic50_nm,
                           b.relative_tau, b.intrinsic_activity_pct, b.emax_pct,
                           b.comparable_set, b.citation_id, b.species, b.reference_agonist,
                           s.canonical_name AS substance_name, s.popularity,
                           c.doi, c.pmid, c.year
                      FROM bindings b
                      JOIN substances s ON s.id = b.substance_id
                      LEFT JOIN citations c ON c.id = b.citation_id
                     WHERE \(Self.targetPredicate(family))
                """)
                return rows.compactMap { row -> SignatureLeg? in
                    guard let target = SignatureTarget.normalized(row["target"]) else { return nil }
                    let id: Int64 = row["id"]
                    return SignatureLeg(
                        id: "b:\(id)",
                        substanceName: row["substance_name"],
                        target: target,
                        action: row["action"],
                        kiNm: row["ki_nm"],
                        ec50Nm: row["ec50_nm"],
                        ic50Nm: row["ic50_nm"],
                        relativeTau: row["relative_tau"],
                        intrinsicActivityPct: row["intrinsic_activity_pct"],
                        emaxPct: row["emax_pct"],
                        comparableSet: row["comparable_set"],
                        citationID: row["citation_id"],
                        species: row["species"],
                        referenceAgonist: row["reference_agonist"],
                        doi: row["doi"],
                        pmid: row["pmid"],
                        year: row["year"],
                        popularity: row["popularity"] ?? 0,
                    )
                }
            }
        } catch {
            logger.error("signatureLegs failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func functionalAssayLegs() -> [SignatureLeg] {
        do {
            return try substancesDB.read { db in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT f.id, f.target, f.ec50_nm, f.ic50_nm, f.emax_pct, f.reference_agonist,
                           f.species, f.citation_id,
                           s.canonical_name AS substance_name, s.popularity,
                           c.doi, c.pmid, c.year
                      FROM functional_assays f
                      JOIN substances s ON s.id = f.substance_id
                      LEFT JOIN citations c ON c.id = f.citation_id
                     WHERE f.target IN ('SERT', 'DAT', 'NET')
                """)
                return rows.compactMap { row -> SignatureLeg? in
                    guard let target = SignatureTarget.normalized(row["target"]) else { return nil }
                    let id: Int64 = row["id"]
                    return SignatureLeg(
                        id: "f:\(id)",
                        substanceName: row["substance_name"],
                        target: target,
                        action: nil,
                        ec50Nm: row["ec50_nm"],
                        ic50Nm: row["ic50_nm"],
                        emaxPct: row["emax_pct"],
                        citationID: row["citation_id"],
                        species: row["species"],
                        referenceAgonist: row["reference_agonist"],
                        doi: row["doi"],
                        pmid: row["pmid"],
                        year: row["year"],
                        popularity: row["popularity"] ?? 0,
                    )
                }
            }
        } catch {
            logger.error("functionalAssayLegs failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// A coarse SQL prefilter; ``SignatureTarget/normalized(_:)`` does the real matching in Swift so
    /// a multi-target row like `"MOR / DOR / KOR / NOP"` can never masquerade as a single leg.
    private nonisolated static func targetPredicate(_ family: SignatureFamily) -> String {
        switch family {
        case .transporters: "b.target IN ('SERT', 'DAT', 'NET', '5-HTT')"
        case .serotonin: "(b.target LIKE '5-HT2A%' OR b.target LIKE '5-HT1A%')"
        case .muOpioid: "(b.target LIKE 'MOR%' OR b.target LIKE 'μ-opioid%' OR b.target LIKE 'mu-opioid%')"
        case .cannabinoid1: "b.target LIKE 'CB1%'"
        case .nmda: "b.target LIKE 'NMDA%'"
        }
    }
}
