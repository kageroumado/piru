import Foundation
import GRDB
import os

private nonisolated let logger = Logger(subsystem: "dev.yumeji.piru", category: "SubstanceStore")

/// The deep-pharmacology read models and their queries: the genes that change
/// what a substance does, the cascade it sets off after binding, and the
/// evidence about its targets that is not an affinity number.
///
/// These four tables shipped in the bundled database for months with no query
/// reading them — 1,076 curated, cited rows that no screen could show. They are
/// grouped here rather than spread across the existing extensions because they
/// share a shape: one authored sentence plus the study behind it.
extension SubstanceStore {
    /// One gene whose variants change what a substance does to the person
    /// carrying them.
    ///
    /// Distinct from the `metabolism` table, which says *which* enzyme clears a
    /// drug: this says what happens when that enzyme is the slow or the fast
    /// variant, and it covers genes that are not enzymes at all — `OPRM1`
    /// (the µ-opioid receptor), `COMT`, `5-HTTLPR`, `HTR2A`.
    struct PharmacogeneticHit: Identifiable, Hashable {
        let id: Int64
        /// The gene as authored, allele included where the row is about one:
        /// `CYP2D6`, `OPRM1 (A118G / rs1799971)`, `CYP1A2*1F (rs762551)`.
        let gene: String
        let phenotypeEffects: String
        let sourceSlug: String
        let doi: String?
        let pmid: Int?
    }

    /// Pharmacogenetic rows for a substance, one per distinct finding.
    ///
    /// Two collapses, and both were visible on ketamine's screen:
    ///
    /// - **Same gene, several papers.** Ketamine carries four CYP2B6 rows.
    ///   Printing all four asks the reader to reconcile four statements about
    ///   one gene; the longest is kept, since the short ones are almost always a
    ///   restatement of the same finding.
    /// - **Same finding, several genes.** One study that reports a CYP2B6
    ///   effect *and* a null result for CYP3A4 and CYP3A5 is filed as three rows
    ///   carrying one identical sentence, which rendered as the same paragraph
    ///   three times under three headings. Those become one row naming all three
    ///   genes — which is what the sentence itself says.
    func pharmacogenetics(forSubstanceName name: String) -> [PharmacogeneticHit] {
        guard let substanceID = substanceID(forNameOrAlias: name) else { return [] }
        do {
            return try substancesDB.read { db in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT p.id, p.gene, p.phenotype_effects,
                           src.slug AS source_slug, c.doi, c.pmid
                      FROM pharmacogenetics p
                      JOIN sources src ON src.id = p.source_id
                      LEFT JOIN citations c ON c.id = p.citation_id
                     WHERE p.substance_id = ?
                     ORDER BY LENGTH(p.phenotype_effects) DESC
                """, arguments: [substanceID])
                var seenGenes = Set<String>()
                var byFinding: [String: PharmacogeneticHit] = [:]
                var order: [String] = []
                for row in rows {
                    let gene: String = row["gene"]
                    // The ORDER BY already put the row to keep first.
                    guard seenGenes.insert(geneKey(gene)).inserted else { continue }
                    let finding: String = row["phenotype_effects"]
                    let key = finding.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let existing = byFinding[key] {
                        byFinding[key] = PharmacogeneticHit(
                            id: existing.id,
                            gene: "\(existing.gene) · \(gene)",
                            phenotypeEffects: existing.phenotypeEffects,
                            sourceSlug: existing.sourceSlug,
                            doi: existing.doi,
                            pmid: existing.pmid,
                        )
                        continue
                    }
                    order.append(key)
                    byFinding[key] = PharmacogeneticHit(
                        id: row["id"],
                        gene: gene,
                        phenotypeEffects: finding,
                        sourceSlug: row["source_slug"],
                        doi: row["doi"],
                        pmid: (row["pmid"] as Int64?).map(Int.init),
                    )
                }
                return order.compactMap { byFinding[$0] }.sorted { $0.gene < $1.gene }
            }
        } catch {
            logger.error("pharmacogenetics(forSubstanceName:) failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// The gene name without the allele the row happens to name, so
    /// `CYP1A2*1F (rs762551)` and `CYP1A2` collapse to one row.
    private nonisolated func geneKey(_ gene: String) -> String {
        gene.lowercased()
            .split(whereSeparator: { $0 == "*" || $0 == "(" || $0 == " " })
            .first
            .map(String.init) ?? gene.lowercased()
    }

    // MARK: - Signalling cascade

    /// What happens after the receptor binds, as the chain it is.
    ///
    /// A target list says a drug blocks NMDA; this says the block disinhibits
    /// pyramidal cells, which surges glutamate, which recruits AMPA, BDNF/TrkB
    /// and mTORC1. That chain is the half of a mechanism a list of receptors
    /// cannot state, and it is the half that explains why the effect outlasts
    /// the drug.
    struct SignallingCascade: Hashable {
        let summary: String
        let sourceSlug: String
        let doi: String?
        let pmid: Int?
    }

    func signallingCascade(forSubstanceName name: String) -> SignallingCascade? {
        guard let substanceID = substanceID(forNameOrAlias: name) else { return nil }
        do {
            return try substancesDB.read { db in
                guard let row = try Row.fetchOne(db, sql: """
                    SELECT d.summary, src.slug AS source_slug, c.doi, c.pmid
                      FROM downstream_signalling d
                      JOIN sources src ON src.id = d.source_id
                      LEFT JOIN citations c ON c.id = d.citation_id
                     WHERE d.substance_id = ?
                     ORDER BY LENGTH(d.summary) DESC
                     LIMIT 1
                """, arguments: [substanceID]) else { return nil }
                return SignallingCascade(
                    summary: row["summary"],
                    sourceSlug: row["source_slug"],
                    doi: row["doi"],
                    pmid: (row["pmid"] as Int64?).map(Int.init),
                )
            }
        } catch {
            logger.error("signallingCascade(forSubstanceName:) failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Class context

    /// The pharmacological class a substance belongs to, and what its members
    /// share: mechanism, kinetics, safety profile, and the SAR that tells them
    /// apart.
    ///
    /// Answers a question a single substance's page cannot — *is this one like
    /// the others?* — for the long tail especially, where a research chemical
    /// has almost no data of its own and everything worth knowing is a property
    /// of the family.
    struct ClassContext: Hashable {
        let slug: String
        let title: String
        /// The membership the authored name carried in parentheses, when it had
        /// one: "2C-x, DOx, mescaline analogues, NBOMe / NBOH / NBF / NBMD".
        let subtitle: String?
        let sharedMechanism: String?
        let sharedPharmacokinetics: String?
        let sharedSafety: String?
        let sarSummary: String?
        /// Other substances in the class, by canonical name, most recognizable
        /// first. Excludes the substance being viewed.
        let siblings: [String]
        let references: [Reference]

        struct Reference: Identifiable, Hashable {
            let id: Int64
            let title: String?
            let doi: String?
            let pmid: Int?
        }
    }

    func classContext(forSubstanceName name: String) -> ClassContext? {
        guard let substanceID = substanceID(forNameOrAlias: name) else { return nil }
        do {
            return try substancesDB.read { db in
                guard let row = try Row.fetchOne(db, sql: """
                    SELECT c.id, c.slug, c.display_name, c.subtitle, c.shared_mechanism,
                           c.shared_pk, c.shared_safety, c.sar_summary
                      FROM class_contexts c
                      JOIN substance_classes sc ON sc.class_context_id = c.id
                     WHERE sc.substance_id = ?
                     LIMIT 1
                """, arguments: [substanceID]) else { return nil }
                let classID: Int64 = row["id"]

                // Popularity first: a class card is only useful if the peers it
                // names are ones the reader recognizes.
                let siblings = try String.fetchAll(db, sql: """
                    SELECT s.canonical_name
                      FROM substance_classes sc
                      JOIN substances s ON s.id = sc.substance_id
                     WHERE sc.class_context_id = ? AND sc.substance_id != ?
                     ORDER BY s.popularity DESC, s.canonical_name
                     LIMIT 12
                """, arguments: [classID, substanceID])

                let references = try Row.fetchAll(db, sql: """
                    SELECT ci.id, ci.title, ci.doi, ci.pmid
                      FROM class_citations cc
                      JOIN citations ci ON ci.id = cc.citation_id
                     WHERE cc.class_context_id = ?
                     ORDER BY ci.year DESC NULLS LAST
                """, arguments: [classID]).map {
                    ClassContext.Reference(
                        id: $0["id"],
                        title: $0["title"],
                        doi: $0["doi"],
                        pmid: ($0["pmid"] as Int64?).map(Int.init),
                    )
                }

                return ClassContext(
                    slug: row["slug"],
                    title: row["display_name"],
                    subtitle: row["subtitle"],
                    sharedMechanism: row["shared_mechanism"],
                    sharedPharmacokinetics: row["shared_pk"],
                    sharedSafety: row["shared_safety"],
                    sarSummary: row["sar_summary"],
                    siblings: siblings,
                    references: references,
                )
            }
        } catch {
            logger.error("classContext(forSubstanceName:) failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Concentration thresholds

    /// The plasma concentration at which a named effect appears, and the one at
    /// which it is full.
    ///
    /// This is what turns the PK curve from a shape into a reading: the same
    /// axis that says "ketamine, 200 ng/mL" can say that 70 is where analgesia
    /// starts and 640 is where consciousness goes.
    struct ConcentrationThreshold: Identifiable, Hashable {
        let id: Int64
        /// The effect, as authored — "general anesthesia (loss of
        /// consciousness)", "respiratory depression (clinically significant)".
        let effect: String
        let unit: String
        /// Where the effect starts. Nil when the row only recorded a peak.
        let threshold: Double?
        /// Where it is full. **Not always a concentration** — Citalomram's QTc
        /// row records 18.5 ms of prolongation here, so this is rendered with
        /// the unit only when it is plausibly one, never assumed to be.
        let peak: Double?
        let sourceSlug: String
        let doi: String?
        let pmid: Int?
    }

    func concentrationThresholds(forSubstanceName name: String) -> [ConcentrationThreshold] {
        guard let substanceID = substanceID(forNameOrAlias: name) else { return [] }
        do {
            return try substancesDB.read { db in
                try Row.fetchAll(db, sql: """
                    SELECT e.id, e.effect, e.concentration_unit, e.threshold, e.peak_effect,
                           src.slug AS source_slug, c.doi, c.pmid
                      FROM concentration_effects e
                      JOIN sources src ON src.id = e.source_id
                      LEFT JOIN citations c ON c.id = e.citation_id
                     WHERE e.substance_id = ?
                     ORDER BY e.threshold ASC NULLS LAST
                """, arguments: [substanceID]).map { row in
                    ConcentrationThreshold(
                        id: row["id"],
                        effect: row["effect"],
                        unit: row["concentration_unit"],
                        threshold: row["threshold"],
                        peak: row["peak_effect"],
                        sourceSlug: row["source_slug"],
                        doi: row["doi"],
                        pmid: (row["pmid"] as Int64?).map(Int.init),
                    )
                }
            }
        } catch {
            logger.error("concentrationThresholds(forSubstanceName:) failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    // MARK: - Target evidence

    /// One piece of evidence about how a substance engages a target that is not
    /// an affinity number: which signalling pathway it favours, what complex the
    /// receptor is in, or what a scan of a living brain showed.
    ///
    /// Three tables, one row type, because they answer one question — *and what
    /// does that binding actually do?* — and because three separate sections for
    /// 83 rows would cost more screen than the rows are worth.
    struct TargetEvidence: Identifiable, Hashable {
        enum Kind: String, Hashable, Sendable {
            /// Which pathway the agonist favours at one receptor.
            case bias
            /// The receptor complex the action happens in.
            case complex
            /// Measured in a living brain or animal, not a dish.
            case imaging

            var label: LocalizedStringResource {
                switch self {
                case .bias: "Pathway bias"
                case .complex: "Receptor complex"
                case .imaging: "In vivo"
                }
            }
        }

        let id: String
        let kind: Kind
        /// What the row is about: a target, a complex, or a scan modality.
        let subject: String
        let finding: String
        let sourceSlug: String
        let doi: String?
        let pmid: Int?
    }

    func targetEvidence(forSubstanceName name: String) -> [TargetEvidence] {
        guard let substanceID = substanceID(forNameOrAlias: name) else { return [] }
        do {
            return try substancesDB.read { db in
                // One UNION rather than three round trips; `kind` keeps the rows
                // distinguishable and `sort_rank` orders them so the human
                // evidence leads. The rank is a column and not an ORDER BY
                // expression because SQLite allows only result columns to order
                // a compound SELECT — an expression there is a prepare error,
                // and this query returned nothing at all until it was one.
                let rows = try Row.fetchAll(db, sql: """
                    SELECT 0 AS sort_rank, 'imaging' AS kind, n.id AS row_id, n.modality AS subject,
                           n.finding AS finding, src.slug AS source_slug, c.doi, c.pmid
                      FROM neuroimaging n
                      JOIN sources src ON src.id = n.source_id
                      LEFT JOIN citations c ON c.id = n.citation_id
                     WHERE n.substance_id = :id
                    UNION ALL
                    SELECT 1, 'bias', b.id, b.target,
                           COALESCE(b.interpretation, b.pathways_compared),
                           src.slug, c.doi, c.pmid
                      FROM biased_agonism b
                      JOIN sources src ON src.id = b.source_id
                      LEFT JOIN citations c ON c.id = b.citation_id
                     WHERE b.substance_id = :id
                    UNION ALL
                    SELECT 2, 'complex', o.id, o.complex_description,
                           COALESCE(o.functional_consequence, o.evidence_type),
                           src.slug, c.doi, c.pmid
                      FROM receptor_oligomers o
                      JOIN sources src ON src.id = o.source_id
                      LEFT JOIN citations c ON c.id = o.citation_id
                     WHERE o.substance_id = :id
                    ORDER BY sort_rank, subject
                """, arguments: ["id": substanceID])
                return rows.compactMap { row -> TargetEvidence? in
                    guard let kind = TargetEvidence.Kind(rawValue: row["kind"]),
                          let finding: String = row["finding"], !finding.isEmpty
                    else { return nil }
                    let rowID: Int64 = row["row_id"]
                    return TargetEvidence(
                        id: "\(kind.rawValue)-\(rowID)",
                        kind: kind,
                        subject: row["subject"],
                        finding: finding,
                        sourceSlug: row["source_slug"],
                        doi: row["doi"],
                        pmid: (row["pmid"] as Int64?).map(Int.init),
                    )
                }
            }
        } catch {
            logger.error("targetEvidence(forSubstanceName:) failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}
