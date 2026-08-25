import Foundation
import GRDB
import os

private nonisolated let logger = Logger(subsystem: "dev.yumeji.piru", category: "SubstanceStore")

/// One thing a drug acts on that is **not** the reason anyone takes it —
/// citalopram's hERG block, ketamine's bladder, zopiclone's metallic taste.
///
/// The value column is `ki_or_ic50_nm`: the table records whichever the paper
/// reported and does **not** say which. So it is never rendered with a Kᵢ or
/// IC₅₀ symbol — a Kᵢ and an IC₅₀ are not the same quantity, and labeling an
/// unknown one as either invents a fact the row does not carry.
nonisolated struct OffTargetHit: Identifiable, Hashable {
    let id: Int64
    /// Free-text target, as authored: a receptor ("hERG"), a channel
    /// ("HCN1"), or a tissue ("Bladder urothelium").
    let target: String
    let valueNm: Double?
    let concern: OffTargetConcern
    /// What it means in practice — the row's whole point, and the reason a
    /// row with a `low` concern is worth showing rather than filtering out:
    /// "binds, and it doesn't matter" is the answer to a question readers
    /// otherwise answer for themselves, wrongly.
    let clinicalConsequence: String?
    let sourceSlug: String
    let doi: String?
    let pmid: Int?
}

/// How much the off-target action actually matters clinically. Authored per
/// row; the ordering is the card's sort key.
nonisolated enum OffTargetConcern: String, Hashable, Sendable, Comparable {
    /// Documented harm in humans — a black-box QT restriction, a withdrawn drug, ketamine cystitis.
    case high
    /// Real but bounded — a label warning, case reports, effects at supratherapeutic exposures.
    case moderate
    /// Measured and not clinically dominant. The "no, actually" rows.
    case low

    /// Descending clinical weight, so `sorted(by: >)` puts `high` first.
    private var rank: Int {
        switch self {
        case .high: 2
        case .moderate: 1
        case .low: 0
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rank < rhs.rank
    }
}

extension SubstanceReadModel {
    /// Off-target actions for a substance, most-concerning first and **one row
    /// per target**. Deliberately unfiltered by source — the table is
    /// single-source curated and a concern row must not vanish with a source
    /// toggle.
    ///
    /// The collapse is not cosmetic. Citalopram carries two hERG rows — an FDA
    /// black-box `high` and a mechanistic `moderate` about supratherapeutic
    /// block — and printing both invites the reader to average them, which is
    /// the wrong answer to "does this drug prolong my QT?". Keeping the
    /// highest-concern row per target means the strongest documented statement
    /// wins; the tie-break to the lower concentration then picks the more potent
    /// measurement (ketamine's two HCN1 rows, both `moderate`, say the same
    /// thing at 7 µM and 16 µM).
    func offTargets(substanceID: Int64) -> [OffTargetHit] {
        do {
            return try db.read { db in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT o.id, o.target, o.ki_or_ic50_nm, o.concern_level, o.clinical_consequence,
                           src.slug AS source_slug, c.doi, c.pmid
                      FROM off_targets o
                      JOIN sources src ON src.id = o.source_id
                      LEFT JOIN citations c ON c.id = o.citation_id
                     WHERE o.substance_id = ?
                     ORDER BY CASE lower(o.concern_level)
                                WHEN 'high' THEN 0 WHEN 'moderate' THEN 1 ELSE 2 END ASC,
                              o.ki_or_ic50_nm ASC NULLS LAST,
                              o.target ASC
                """, arguments: [substanceID])
                var seenTargets = Set<String>()
                return rows.compactMap { row -> OffTargetHit? in
                    let target: String = row["target"]
                    // The query's ORDER BY already put the row to keep first.
                    guard seenTargets.insert(target.lowercased()).inserted else { return nil }
                    return OffTargetHit(
                        id: row["id"],
                        target: target,
                        valueNm: row["ki_or_ic50_nm"],
                        // An unrecognized or absent level must not read as "low" — that is a
                        // claim of safety nobody made. `moderate` is the neutral middle.
                        concern: (row["concern_level"] as String?)
                            .flatMap { OffTargetConcern(rawValue: $0.lowercased()) } ?? .moderate,
                        clinicalConsequence: row["clinical_consequence"],
                        sourceSlug: row["source_slug"],
                        doi: row["doi"],
                        pmid: (row["pmid"] as Int64?).map(Int.init),
                    )
                }
            }
        } catch {
            logger.error("offTargets(substanceID:) failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}

extension SubstanceStore {
    typealias OffTargetHit = Piru.OffTargetHit
    typealias OffTargetConcern = Piru.OffTargetConcern

    /// Name-keyed entry to ``SubstanceReadModel/offTargets(substanceID:)`` —
    /// the store contributes only the alias resolution.
    func offTargets(forSubstanceName name: String) -> [OffTargetHit] {
        guard let substanceID = substanceID(forNameOrAlias: name) else { return [] }
        return reader.offTargets(substanceID: substanceID)
    }
}
