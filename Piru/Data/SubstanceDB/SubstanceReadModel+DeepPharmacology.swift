import Foundation
import GRDB
import os

private nonisolated let logger = Logger(subsystem: "dev.yumeji.piru", category: "SubstanceStore")

/// One gene whose variants change what a substance does to the person
/// carrying them.
///
/// Distinct from the `metabolism` table, which says *which* enzyme clears a
/// drug: this says what happens when that enzyme is the slow or the fast
/// variant, and it covers genes that are not enzymes at all — `OPRM1`
/// (the µ-opioid receptor), `COMT`, `5-HTTLPR`, `HTR2A`.
nonisolated struct PharmacogeneticHit: Identifiable, Hashable {
    let id: Int64
    /// The gene as authored, allele included where the row is about one:
    /// `CYP2D6`, `OPRM1 (A118G / rs1799971)`, `CYP1A2*1F (rs762551)`.
    let gene: String
    let phenotypeEffects: String
    let sourceSlug: String
    let doi: String?
    let pmid: Int?
}

/// What happens after the receptor binds, as the chain it is.
///
/// A target list says a drug blocks NMDA; this says the block disinhibits
/// pyramidal cells, which surges glutamate, which recruits AMPA, BDNF/TrkB
/// and mTORC1. That chain is the half of a mechanism a list of receptors
/// cannot state, and it is the half that explains why the effect outlasts
/// the drug.
nonisolated struct SignallingCascade: Hashable {
    let summary: String
    let sourceSlug: String
    let doi: String?
    let pmid: Int?
}

/// One `interaction_rules` row: a class pair, how bad, and why.
nonisolated struct ClassInteractionRule: Hashable {
    let classA: String
    let classB: String
    let severity: String
    let note: String
}

/// The pharmacological class a substance belongs to, and what its members
/// share: mechanism, kinetics, safety profile, and the SAR that tells them
/// apart.
///
/// Answers a question a single substance's page cannot — *is this one like
/// the others?* — for the long tail especially, where a research chemical
/// has almost no data of its own and everything worth knowing is a property
/// of the family.
nonisolated struct ClassContext: Hashable {
    let slug: String
    let title: String
    let category: SubstanceCategory?
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

nonisolated struct ClassContextSummary: Identifiable, Hashable {
    var id: String {
        slug
    }
    let slug: String
    let title: String
    let subtitle: String?
    /// The Library family this class sits under, derived at build from what
    /// its members are. `nil` when no member carries a category.
    let category: SubstanceCategory?
    let memberCount: Int
}

/// The plasma concentration at which a named effect appears, and the one at
/// which it is full.
///
/// This is what turns the PK curve from a shape into a reading: the same
/// axis that says "ketamine, 200 ng/mL" can say that 70 is where analgesia
/// starts and 640 is where consciousness goes.
nonisolated struct ConcentrationThreshold: Identifiable, Hashable {
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
    /// The dose that reaches `threshold`, when the conversion applies.
    /// See ``DoseEquivalent`` for when it does not.
    let doseEquivalent: DoseAnchor?

    struct DoseAnchor: Hashable {
        let milligrams: Double
        let route: RouteOfAdministration
        let weightKg: Double

        /// The amount in the unit a reader would use for it. LSD's anchor is
        /// 0.023 mg, which nobody says — 23 µg is the same number in the
        /// units the substance is dosed in.
        var displayAmount: (value: Double, unit: String) {
            milligrams < 1 ? (milligrams * 1_000, "µg") : (milligrams, "mg")
        }
    }
}

/// One piece of evidence about how a substance engages a target that is not
/// an affinity number: which signalling pathway it favours, what complex the
/// receptor is in, or what a scan of a living brain showed.
///
/// Three tables, one row type, because they answer one question — *and what
/// does that binding actually do?* — and because three separate sections for
/// 83 rows would cost more screen than the rows are worth.
nonisolated struct TargetEvidence: Identifiable, Hashable {
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

/// The deep-pharmacology read models and their queries: the genes that change
/// what a substance does, the cascade it sets off after binding, and the
/// evidence about its targets that is not an affinity number.
///
/// These four tables shipped in the bundled database for months with no query
/// reading them — 1,076 curated, cited rows that no screen could show. They are
/// grouped here because they share a shape: one authored sentence plus the
/// study behind it.
extension SubstanceReadModel {
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
    func pharmacogenetics(substanceID: Int64) -> [PharmacogeneticHit] {
        do {
            return try db.read { db in
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
                    guard seenGenes.insert(Self.geneKey(gene)).inserted else { continue }
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
            logger.error("pharmacogenetics(substanceID:) failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// The gene name without the allele the row happens to name, so
    /// `CYP1A2*1F (rs762551)` and `CYP1A2` collapse to one row.
    private nonisolated static func geneKey(_ gene: String) -> String {
        gene.lowercased()
            .split(whereSeparator: { $0 == "*" || $0 == "(" || $0 == " " })
            .first
            .map(String.init) ?? gene.lowercased()
    }

    // MARK: - Signalling cascade

    func signallingCascade(substanceID: Int64) -> SignallingCascade? {
        do {
            return try db.read { db in
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
            logger.error("signallingCascade(substanceID:) failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Interaction classes

    /// Every substance-name interaction-class override, keyed by lowercased name.
    ///
    /// A row linked to a catalog substance is expanded across that substance's
    /// canonical name and every alias, so a dose logged as "Nembutal" or "Xanax"
    /// carries the same class as the spelling the override was written under. A
    /// row the catalog has no substance for still answers under its own spelling:
    /// a person can log a name the library does not have, and the overrides that
    /// matter most (xylazine, the rarer barbiturates) are exactly those.
    ///
    /// An explicit row always beats an alias expansion — an alias shared between
    /// two overridden substances would otherwise decide by row order.
    func substanceInteractionClasses() -> [String: [DrugClass]] {
        do {
            return try db.read { db in
                var explicit: [String: [DrugClass]] = [:]
                var expanded: [String: [DrugClass]] = [:]

                let rows = try Row.fetchAll(db, sql: """
                    SELECT name, drug_class, substance_id
                      FROM substance_interaction_classes
                     ORDER BY name, rank
                """)
                var classesBySubstance: [Int64: [DrugClass]] = [:]
                for row in rows {
                    guard let name: String = row["name"],
                          let raw: String = row["drug_class"],
                          let drugClass = DrugClass(rawValue: raw) else { continue }
                    explicit[name, default: []].append(drugClass)
                    if let id: Int64 = row["substance_id"] {
                        classesBySubstance[id, default: []].append(drugClass)
                    }
                }
                guard !classesBySubstance.isEmpty else { return explicit }

                let ids = classesBySubstance.keys.map(String.init).joined(separator: ",")
                let names = try Row.fetchAll(db, sql: """
                    SELECT id AS substance_id, canonical_name AS name
                      FROM substances WHERE id IN (\(ids))
                    UNION ALL
                    SELECT substance_id, alias AS name
                      FROM aliases WHERE substance_id IN (\(ids))
                    UNION ALL
                    SELECT substance_id, alias_normalized AS name
                      FROM aliases WHERE substance_id IN (\(ids))
                """)
                for row in names {
                    guard let id: Int64 = row["substance_id"],
                          let name: String = row["name"],
                          let classes = classesBySubstance[id] else { continue }
                    expanded[name.lowercased()] = classes
                }
                return expanded.merging(explicit) { _, explicitClasses in explicitClasses }
            }
        } catch {
            logger.error("substanceInteractionClasses() failed: \(error.localizedDescription, privacy: .public)")
            return [:]
        }
    }

    /// The interaction class each substance category falls back to, keyed by the
    /// category's raw value. A category with no row participates in no rule; that
    /// default lives in ``InteractionChecker``, because it is what an unmapped
    /// category means rather than a value someone chose.
    func categoryInteractionClasses() -> [String: DrugClass] {
        do {
            return try db.read { db in
                try Row.fetchAll(db, sql: "SELECT category, drug_class FROM category_interaction_classes")
                    .reduce(into: [String: DrugClass]()) { out, row in
                        guard let category: String = row["category"],
                              let raw: String = row["drug_class"],
                              let drugClass = DrugClass(rawValue: raw) else { return }
                        out[category] = drugClass
                    }
            }
        } catch {
            logger.error("categoryInteractionClasses() failed: \(error.localizedDescription, privacy: .public)")
            return [:]
        }
    }

    // MARK: - Class-pair interaction rules

    /// Every class-pair rule in the bundled database — the curated verdicts and,
    /// for the pairs curation does not reach, TripSit's matrix.
    func classInteractionRules() -> [ClassInteractionRule] {
        do {
            return try db.read { db in
                try Row.fetchAll(db, sql: """
                    SELECT class_a, class_b, severity, note
                      FROM interaction_rules
                """).map {
                    ClassInteractionRule(
                        classA: $0["class_a"],
                        classB: $0["class_b"],
                        severity: $0["severity"],
                        note: $0["note"],
                    )
                }
            }
        } catch {
            logger.error("classInteractionRules() failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    // MARK: - Class context

    /// Every class that has something to read, for the browse list.
    /// Order is member count, which stands in for both specificity and how
    /// likely a reader is to have heard of it — Cathinones and Amphetamines
    /// lead the stimulants, Benztropine analogues sit at the bottom.
    func classContexts() -> [ClassContextSummary] {
        do {
            return try db.read { db in
                try Row.fetchAll(db, sql: """
                    SELECT c.slug, c.display_name, c.subtitle, c.category,
                           (SELECT COUNT(*) FROM substance_classes sc
                             WHERE sc.class_context_id = c.id) AS member_count
                      FROM class_contexts c
                     WHERE COALESCE(c.shared_mechanism, c.shared_pk,
                                    c.shared_safety, c.sar_summary) IS NOT NULL
                     ORDER BY member_count DESC, c.display_name
                """).map {
                    ClassContextSummary(
                        slug: $0["slug"],
                        title: $0["display_name"],
                        subtitle: $0["subtitle"],
                        category: ($0["category"] as String?)
                            .flatMap { SubstanceCategory(rawValue: $0) },
                        memberCount: Int($0["member_count"] as Int64),
                    )
                }
            }
        } catch {
            logger.error("classContexts() failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func classContext(slug: String) -> ClassContext? {
        loadClassContext(matching: "c.slug = ?", argument: slug)
    }

    func classContext(substanceID: Int64) -> ClassContext? {
        loadClassContext(
            matching: "c.id = (SELECT sc.class_context_id FROM substance_classes sc "
                + "WHERE sc.substance_id = ? LIMIT 1)",
            argument: substanceID,
            excluding: substanceID,
        )
    }

    private func loadClassContext(
        matching predicate: String,
        argument: DatabaseValueConvertible,
        excluding substanceID: Int64? = nil,
    ) -> ClassContext? {
        do {
            return try db.read { db in
                guard let row = try Row.fetchOne(db, sql: """
                    SELECT c.id, c.slug, c.display_name, c.subtitle, c.category,
                           c.shared_mechanism, c.shared_pk, c.shared_safety, c.sar_summary
                      FROM class_contexts c
                     WHERE \(predicate)
                     LIMIT 1
                """, arguments: [argument]) else { return nil }
                let classID: Int64 = row["id"]

                // Popularity first, so the recognizable members lead. Not
                // capped: the screen is a list, and a cap here would silently
                // shorten a class — benzodiazepines has 70 members and a
                // `LIMIT 60` made the count on the substance row wrong as well
                // as hiding ten of them.
                let siblings = try String.fetchAll(db, sql: """
                    SELECT s.canonical_name
                      FROM substance_classes sc
                      JOIN substances s ON s.id = sc.substance_id
                     WHERE sc.class_context_id = :class AND s.id IS NOT :exclude
                     ORDER BY s.popularity DESC, s.canonical_name
                """, arguments: ["class": classID, "exclude": substanceID])

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
                    category: (row["category"] as String?)
                        .flatMap { SubstanceCategory(rawValue: $0) },
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
            logger.error("loadClassContext failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Concentration thresholds

    /// Concentration-effect rows plus, where the model earns it, the dose that
    /// reaches each threshold. `weightKg` is a parameter so this stays a pure
    /// function of its snapshot — the store wrapper supplies the profile's
    /// effective weight from the main actor.
    func concentrationThresholds(substanceID: Int64, weightKg: Double) -> [ConcentrationThreshold] {
        do {
            return try db.read { db in
                // Vd is a property of the drug, not of how it got in, so it is
                // taken from whichever route recorded one — commonly the
                // intravenous row, which is also the one route the conversion
                // must not use for bioavailability.
                let vd = try Double.fetchOne(db, sql: """
                    SELECT vd_l_per_kg FROM pk_routes
                     WHERE substance_id = ? AND vd_l_per_kg IS NOT NULL
                     ORDER BY (species IS NULL OR species = 'human') DESC
                     LIMIT 1
                """, arguments: [substanceID])

                // The most bioavailable ABSORPTION-LIMITED route.
                //
                // Intravenous and intramuscular are excluded because their peak
                // precedes distribution, which is the one thing the relation
                // assumes is finished — it understates an IV induction dose
                // three- to fivefold. Transdermal is excluded because a patch
                // delivers a *rate*: "0.5 mg transdermal" is not a dose anyone
                // takes.
                let absorbed = try Row.fetchOne(db, sql: """
                    SELECT route, bioavailability_pct FROM pk_routes
                     WHERE substance_id = ? AND bioavailability_pct IS NOT NULL
                       AND LOWER(route) NOT IN ('intravenous', 'iv',
                                                'intramuscular', 'transdermal')
                     ORDER BY bioavailability_pct DESC
                     LIMIT 1
                """, arguments: [substanceID])
                let route = (absorbed?["route"] as String?)
                    .flatMap { RouteOfAdministration(rawValue: $0) }
                let bioavailability: Double? = absorbed?["bioavailability_pct"]

                // The substance's own dose ladder on that route, as the check.
                //
                // Two things at once. An anchor that lands nowhere near the
                // ladder means the model disagrees with the curated data, and
                // the model is the thing that is wrong — fentanyl's Vd puts
                // respiratory depression at six times the dose that causes it.
                // And where a substance has NO visible ladder, it is a
                // prescription drug whose therapeutic doses are deliberately
                // stripped (see the dose-context rule); printing a derived one
                // would put them straight back.
                var ladder: (low: Double, high: Double)?
                if let routeName = absorbed?["route"] as String?,
                   let row = try Row.fetchOne(db, sql: """
                       SELECT MIN(COALESCE(threshold, light_lower, common_lower)) AS low,
                              MAX(COALESCE(heavy, strong_upper, common_upper)) AS high,
                              MIN(unit) AS unit
                         FROM dose_ranges
                        WHERE substance_id = ? AND route = ?
                          AND (unit LIKE 'mg%' OR unit LIKE '\u{00b5}g%' OR unit LIKE 'ug%'
                               OR unit LIKE 'mcg%')
                   """, arguments: [substanceID, routeName]),
                   let low: Double = row["low"], let high: Double = row["high"],
                   // LSD's ladder is in micrograms; comparing 0.023 mg against a
                   // bound of 15 suppressed the one substance where the estimate
                   // is most obviously right.
                   let scale = DoseEquivalent.milligramScale(ofDoseUnit: row["unit"] ?? "mg"),
                   low > 0, high > 0 {
                    ladder = (low * scale, high * scale)
                }

                let rows = try Row.fetchAll(db, sql: """
                    SELECT e.id, e.effect, e.concentration_unit, e.threshold, e.peak_effect,
                           src.slug AS source_slug, c.doi, c.pmid
                      FROM concentration_effects e
                      JOIN sources src ON src.id = e.source_id
                      LEFT JOIN citations c ON c.id = e.citation_id
                     WHERE e.substance_id = ?
                     ORDER BY e.threshold ASC NULLS LAST
                """, arguments: [substanceID])

                // Every anchor the relation can produce, and whether any of them
                // disagreed with the ladder.
                var candidates: [Int64: Double] = [:]
                var modelDisagreed = false
                for row in rows {
                    let effect: String = row["effect"]
                    guard let threshold: Double = row["threshold"], let vd, let bioavailability,
                          route != nil, let ladder,
                          DoseEquivalent.isConvertible(effect: effect),
                          let mgPerL = DoseEquivalent.milligramsPerLitre(threshold, unit: row["concentration_unit"]),
                          let mg = DoseEquivalent.milligrams(
                              concentrationMgPerL: mgPerL,
                              vdLitresPerKg: vd,
                              bioavailabilityPct: bioavailability,
                              weightKg: weightKg,
                          )
                    else { continue }
                    if DoseEquivalent.agreesWithLadder(mg, low: ladder.low, high: ladder.high) {
                        candidates[row["id"]] = mg
                    } else {
                        modelDisagreed = true
                    }
                }
                // All or nothing. Fentanyl's respiratory-depression threshold
                // lands at six times the dose that causes it and is dropped,
                // which would leave its analgesia anchor standing alone — a
                // benefit dose shown while the harm dose beside it is hidden
                // reads as the safer claim, and it is the more dangerous one.
                // One threshold the model gets wrong disqualifies the drug.
                if modelDisagreed { candidates.removeAll() }

                return rows.map { row in
                    let id: Int64 = row["id"]
                    return ConcentrationThreshold(
                        id: id,
                        effect: row["effect"],
                        unit: row["concentration_unit"],
                        threshold: row["threshold"],
                        peak: row["peak_effect"],
                        sourceSlug: row["source_slug"],
                        doi: row["doi"],
                        pmid: (row["pmid"] as Int64?).map(Int.init),
                        doseEquivalent: candidates[id].flatMap { mg in
                            route.map {
                                .init(
                                    milligrams: DoseEquivalent.rounded(mg),
                                    route: $0,
                                    weightKg: weightKg,
                                )
                            }
                        },
                    )
                }
            }
        } catch {
            logger.error("concentrationThresholds(substanceID:weightKg:) failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    // MARK: - Target evidence

    func targetEvidence(substanceID: Int64) -> [TargetEvidence] {
        do {
            return try db.read { db in
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
            logger.error("targetEvidence(substanceID:) failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}

extension SubstanceStore {
    typealias PharmacogeneticHit = Piru.PharmacogeneticHit
    typealias SignallingCascade = Piru.SignallingCascade
    typealias ClassInteractionRule = Piru.ClassInteractionRule
    typealias ClassContext = Piru.ClassContext
    typealias ClassContextSummary = Piru.ClassContextSummary
    typealias ConcentrationThreshold = Piru.ConcentrationThreshold
    typealias TargetEvidence = Piru.TargetEvidence

    /// Name-keyed entries to the deep-pharmacology resolvers — the store
    /// contributes alias resolution (and, for the concentration thresholds,
    /// the profile's effective weight).
    func pharmacogenetics(forSubstanceName name: String) -> [PharmacogeneticHit] {
        guard let substanceID = substanceID(forNameOrAlias: name) else { return [] }
        return reader.pharmacogenetics(substanceID: substanceID)
    }

    func signallingCascade(forSubstanceName name: String) -> SignallingCascade? {
        guard let substanceID = substanceID(forNameOrAlias: name) else { return nil }
        return reader.signallingCascade(substanceID: substanceID)
    }

    func classInteractionRules() -> [ClassInteractionRule] {
        reader.classInteractionRules()
    }

    /// The classes under one Library family, most-populated first.
    func classContexts(in category: SubstanceCategory) -> [ClassContextSummary] {
        classContexts().filter { $0.category == category }
    }

    func classContexts() -> [ClassContextSummary] {
        reader.classContexts()
    }

    func classContext(slug: String) -> ClassContext? {
        reader.classContext(slug: slug)
    }

    func classContext(forSubstanceName name: String) -> ClassContext? {
        guard let substanceID = substanceID(forNameOrAlias: name) else { return nil }
        return reader.classContext(substanceID: substanceID)
    }

    func concentrationThresholds(forSubstanceName name: String) -> [ConcentrationThreshold] {
        guard let substanceID = substanceID(forNameOrAlias: name) else { return [] }
        return reader.concentrationThresholds(
            substanceID: substanceID,
            weightKg: UserProfileStore.shared.effectiveWeightKg,
        )
    }

    func targetEvidence(forSubstanceName name: String) -> [TargetEvidence] {
        guard let substanceID = substanceID(forNameOrAlias: name) else { return [] }
        return reader.targetEvidence(substanceID: substanceID)
    }
}
