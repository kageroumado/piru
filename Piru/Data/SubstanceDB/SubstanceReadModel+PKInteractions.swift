import Foundation
import GRDB
import os

private nonisolated let logger = Logger(subsystem: "dev.yumeji.piru", category: "SubstanceStore")

/// One `drug_interactions_pk` row — a named counterpart, the enzyme mechanism,
/// and the measured effect on exposure.
///
/// These are **not** severity-bearing warnings and must never be rendered as
/// one. The table has no severity column because its sources do not assign
/// one: a row says "clarithromycin raises oral ketamine AUC ~2.6×", which is a
/// measurement, and turning a measurement into `caution`/`unsafe`/`dangerous`
/// would be inventing the part a reader most relies on. Severity comes from
/// ``InteractionChecker``'s class rules or from the curated layer, never here.
nonisolated struct PKInteractionHit: Identifiable, Hashable {
    let id: Int64
    /// The counterpart, **verbatim from the source**. Often a single drug
    /// ("clarithromycin"), often a slash-separated set
    /// ("ketoconazole / itraconazole"), and often a class
    /// ("CYP3A4 inhibitors (azoles, macrolides)"). See ``counterpartNames``.
    let withSubstance: String
    /// The enzyme mechanism — "CYP3A4 inhibition", "CYP2C19 induction".
    let mechanism: String?
    /// Inhibition constant in µM, when the source measured one.
    let kiMicromolar: Double?
    /// What it does to exposure, in the source's own terms.
    let clinicalEffect: String?
    let sourceSlug: String
    let doi: String?
    let pmid: Int?

    /// ``withSubstance`` split into its individual names.
    ///
    /// Two thirds of the table names a *class* rather than a drug, so this is
    /// a best-effort split for matching, not a promise that each piece is a
    /// substance. Anything that fails to resolve is simply not matched — the
    /// row still displays in full on the substance's own page, which is where
    /// a class-named row earns its keep.
    var counterpartNames: [String] {
        withSubstance
            .split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

/// Pharmacokinetic drug-interaction rows: what co-administering another drug does
/// to *this* one's exposure, and by what enzyme mechanism.
extension SubstanceReadModel {
    /// `nonisolated static` to match ``metabolismRows(substanceID:db:order:)`` — the
    /// same rows are read off the batch connection by the interaction checker,
    /// which is not main-actor-isolated.
    nonisolated static func pkInteractionRows(
        substanceID: Int64, db queue: DatabaseQueue, order: [String],
    ) -> [PKInteractionHit] {
        do {
            return try queue.read { db in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT d.id, d.with_substance, d.mechanism, d.ki_um, d.clinical_effect,
                           src.slug AS source_slug, c.doi, c.pmid
                      FROM drug_interactions_pk d
                      JOIN sources src ON src.id = d.source_id
                      LEFT JOIN citations c ON c.id = d.citation_id
                     WHERE d.substance_id = ?
                       AND src.slug IN (\(enabledSourceListSQL(order)))
                     ORDER BY \(priorityCaseSQL(order)) ASC, d.with_substance ASC
                """, arguments: [substanceID])
                return rows.map { row in
                    PKInteractionHit(
                        id: row["id"],
                        withSubstance: row["with_substance"],
                        mechanism: row["mechanism"],
                        kiMicromolar: row["ki_um"],
                        clinicalEffect: row["clinical_effect"],
                        sourceSlug: row["source_slug"],
                        doi: row["doi"],
                        pmid: (row["pmid"] as Int64?).map(Int.init),
                    )
                }
            }
        } catch {
            logger.error("pkInteractionRows(substanceID:) failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}

extension SubstanceStore {
    typealias PKInteractionHit = Piru.PKInteractionHit

    /// PK interaction rows for one substance, highest-evidence source first.
    func pkInteractions(forSubstanceName name: String) -> [PKInteractionHit] {
        guard let substanceID = substanceID(forNameOrAlias: name) else { return [] }
        return SubstanceReadModel.pkInteractionRows(substanceID: substanceID, db: substancesDB, order: enabledSourceOrder)
    }
}
