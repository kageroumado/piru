import Foundation
import GRDB
import os

private nonisolated let logger = Logger(subsystem: "dev.yumeji.piru", category: "SubstanceStore")

/// One representative-per-substance pharmacokinetic projection, built for the Pharma table tool
/// (`PharmaTableView`). Each substance contributes exactly one row — the preferred route (oral first,
/// otherwise the row carrying the most PK fields / best confidence) — so the tool renders a flat,
/// sortable spreadsheet across the whole library. `Sendable` so the resolve runs off the main actor.
///
/// Only substances that carry *some* PK signal (a half-life or any `pk_routes` field) are emitted;
/// half-life falls back to the substance's own top-level ``Substance/halfLifeMinutes`` when no
/// `pk_routes` row exists, so half-life-only substances still appear.
nonisolated struct PharmaTableRow: Identifiable {
    let name: String
    let category: SubstanceCategory?
    /// The substance's mechanism/class one-liner (e.g. "Selective Serotonin Reuptake Inhibitor (SSRI)"),
    /// resolved cheaply from ``MechanismOfActionDatabase`` (per-substance class template, else category
    /// fallback) on the main actor while seeding — the Pharma table's default **Mechanism** column. The
    /// richer receptor targets are layered on separately via ``PharmacologyParameters``.
    let mechanismLabel: String?
    let halfLifeMin: Double?
    let tmaxMin: Double?
    let bioavailabilityPct: Double?
    let cmaxNgPerMl: Double?
    let proteinBindingPct: Double?
    let vdLPerKg: Double?
    let clearanceMlPerMinPerKg: Double?

    var id: String {
        name
    }

    /// True when at least one PK figure is present.
    var hasAnyPK: Bool {
        halfLifeMin != nil || tmaxMin != nil || bioavailabilityPct != nil || cmaxNgPerMl != nil
            || proteinBindingPct != nil || vdLPerKg != nil || clearanceMlPerMinPerKg != nil
    }

    /// The inclusion gate: a substance earns a row when it carries *some* PK signal **or** a resolvable
    /// mechanism/class label — the table now leads with receptor/mechanism data, so a categorised drug
    /// with no PK study still belongs (its Mechanism/Targets columns carry the story).
    var hasAnyData: Bool {
        hasAnyPK || mechanismLabel != nil
    }
}

/// One per-route pharmacokinetic row joined to its source + citation.
/// Surfaced in the detail view's Pharmacokinetics disclosure (pharma-nerd
/// tier). Every numeric is from primary literature with explicit attribution;
/// fields are optional because most rows populate only a subset.
nonisolated struct PKRouteHit: Identifiable, Hashable {
    let id: Int64
    let route: String
    let bioavailabilityPct: Double?
    let cmaxNgPerMl: Double?
    let tmaxMin: Double?
    let halfLifeMin: Double?
    let vdLPerKg: Double?
    let clearanceMlPerMinPerKg: Double?
    let proteinBindingPct: Double?
    let doseInStudyMg: Double?
    let subjectN: Int?
    let demographics: String?
    /// Study species (`human`, `rat`, `pig`, …), lowercased, or `nil` when unstated. Drives the
    /// resolver's interspecies allometric scaling (``SubstanceStore/scaledToHuman(_:)``): a
    /// non-human row keeps its species-invariant Vd/kg but has its confidence floored and its
    /// clearance/half-life allometrically scaled to a 70 kg human when no human value exists.
    let species: String?
    let sourceSlug: String
    let doi: String?
    let pmid: Int?
    let notes: String?
    /// Citation-verification grade for this route's values (`.unverified` when un-graded).
    var confidence: ConfidenceTier = .unverified
}

/// One row from the bindings table joined to its substance + source +
/// citation. Used by advanced-search results.
nonisolated struct BindingHit: Identifiable, Hashable {
    let id: Int64
    let substanceName: String
    let target: String
    let action: String
    let kiNm: Double?
    let ec50Nm: Double?
    let ic50Nm: Double?
    let species: String?
    let sourceSlug: String
    let doi: String?
    let pmid: Int?
    /// Citation-verification grade for this binding (`.unverified` when un-graded).
    var confidence: ConfidenceTier = .unverified
}

/// The pharmacology / pharmacokinetics query layer: the per-substance binding,
/// PK, molar-mass, and metabolism reads. Every function here is a plain read —
/// the derivation/assembly layer (interspecies scaling, the reference-substance
/// borrow, `PharmacologyParameters` assembly, caches, and the off-main batch
/// orchestration) lives on ``SubstanceStore``, in `SubstanceStore+Pharmacology`.
extension SubstanceReadModel {
    /// The raw `bindings` read for one substance id. `nonisolated static` so the off-main tolerance
    /// resolve can run it on the dedicated batch connection without hopping to the main actor.
    nonisolated static func bindingRows(substanceID: Int64, db queue: DatabaseQueue) -> [BindingHit] {
        do {
            return try queue.read { db in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT b.id, b.target, b.action, b.ki_nm, b.ec50_nm, b.ic50_nm, b.species, b.confidence,
                           s.canonical_name AS substance_name,
                           src.slug AS source_slug,
                           c.doi, c.pmid
                      FROM bindings b
                      JOIN substances s ON s.id = b.substance_id
                      JOIN sources    src ON src.id = b.source_id
                      LEFT JOIN citations c ON c.id = b.citation_id
                     WHERE b.substance_id = ?
                     ORDER BY b.ki_nm ASC NULLS LAST, b.ec50_nm ASC NULLS LAST
                """, arguments: [substanceID])
                return rows.map { row in
                    BindingHit(
                        id: row["id"],
                        substanceName: row["substance_name"],
                        target: row["target"],
                        action: row["action"],
                        kiNm: row["ki_nm"],
                        ec50Nm: row["ec50_nm"],
                        ic50Nm: row["ic50_nm"],
                        species: row["species"],
                        sourceSlug: row["source_slug"],
                        doi: row["doi"],
                        pmid: row["pmid"],
                        confidence: ConfidenceTier(grade: row["confidence"]),
                    )
                }
            }
        } catch {
            logger.error("bindingRows failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Returns every binding row matching the predicate, *across all sources*
    /// (including disabled) so pharma-nerd users can see the literature even
    /// for sources they've deprioritised. UI labels which source supplied each
    /// row so users can apply their own trust filter.
    func bindings(
        target: String? = nil,
        kiNmAtMost: Double? = nil,
        substanceContains: String? = nil,
        limit: Int = 200,
    ) -> [BindingHit] {
        do {
            return try db.read { db in
                var sql = """
                    SELECT b.id, b.target, b.action, b.ki_nm, b.ec50_nm, b.ic50_nm, b.species, b.confidence,
                           s.canonical_name AS substance_name,
                           src.slug AS source_slug,
                           c.doi, c.pmid
                      FROM bindings b
                      JOIN substances s ON s.id = b.substance_id
                      JOIN sources    src ON src.id = b.source_id
                      LEFT JOIN citations c ON c.id = b.citation_id
                     WHERE 1=1
                """
                var args: [DatabaseValueConvertible?] = []
                if let target {
                    sql += " AND b.target = ?"
                    args.append(target)
                }
                if let kiNmAtMost {
                    sql += " AND b.ki_nm IS NOT NULL AND b.ki_nm <= ?"
                    args.append(kiNmAtMost)
                }
                if let substanceContains, !substanceContains.isEmpty {
                    sql += " AND s.canonical_name LIKE ?"
                    args.append("%\(substanceContains)%")
                }
                sql += " ORDER BY b.ki_nm ASC NULLS LAST LIMIT ?"
                args.append(limit)

                let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
                return rows.map { row in
                    BindingHit(
                        id: row["id"],
                        substanceName: row["substance_name"],
                        target: row["target"],
                        action: row["action"],
                        kiNm: row["ki_nm"],
                        ec50Nm: row["ec50_nm"],
                        ic50Nm: row["ic50_nm"],
                        species: row["species"],
                        sourceSlug: row["source_slug"],
                        doi: row["doi"],
                        pmid: row["pmid"],
                        confidence: ConfidenceTier(grade: row["confidence"]),
                    )
                }
            }
        } catch {
            logger.error("bindings query failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Distinct binding targets sorted by how many substances hit them.
    /// Powers an autocomplete / chip picker in the advanced-search UI.
    func availableBindingTargets() -> [(target: String, substanceCount: Int)] {
        do {
            return try db.read { db in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT target, COUNT(DISTINCT substance_id) AS n
                      FROM bindings
                     WHERE target IS NOT NULL AND target <> ''
                     GROUP BY target
                     ORDER BY n DESC, target ASC
                """)
                return rows.map { ($0["target"], $0["n"]) }
            }
        } catch { return [] }
    }

    /// The raw `pk_routes` read for one substance id, route-ranked (oral first). `nonisolated static`
    /// so the off-main tolerance resolve can run it on the dedicated batch connection.
    nonisolated static func pharmacokineticsRows(substanceID: Int64, db queue: DatabaseQueue) -> [PKRouteHit] {
        do {
            return try queue.read { db in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT p.id, p.route, p.bioavailability_pct, p.cmax_ng_per_ml, p.tmax_min,
                           p.half_life_min, p.vd_l_per_kg, p.clearance_ml_per_min_per_kg,
                           p.protein_binding_pct, p.dose_in_study_mg, p.subject_n, p.demographics,
                           p.species, p.notes, p.confidence, src.slug AS source_slug, c.doi, c.pmid
                      FROM pk_routes p
                      JOIN sources src ON src.id = p.source_id
                      LEFT JOIN citations c ON c.id = p.citation_id
                     WHERE p.substance_id = ?
                """, arguments: [substanceID])
                return rows.map { row in
                    PKRouteHit(
                        id: row["id"],
                        route: row["route"],
                        bioavailabilityPct: row["bioavailability_pct"],
                        cmaxNgPerMl: row["cmax_ng_per_ml"],
                        tmaxMin: row["tmax_min"],
                        halfLifeMin: row["half_life_min"],
                        vdLPerKg: row["vd_l_per_kg"],
                        clearanceMlPerMinPerKg: row["clearance_ml_per_min_per_kg"],
                        proteinBindingPct: row["protein_binding_pct"],
                        doseInStudyMg: row["dose_in_study_mg"],
                        subjectN: (row["subject_n"] as Int64?).map(Int.init),
                        demographics: row["demographics"],
                        species: (row["species"] as String?)?.lowercased(),
                        sourceSlug: row["source_slug"],
                        doi: row["doi"],
                        pmid: (row["pmid"] as Int64?).map(Int.init),
                        notes: row["notes"],
                        confidence: ConfidenceTier(grade: row["confidence"]),
                    )
                }
                .sorted { SubstanceReadModel.routeRank(RouteOfAdministration.from(string: $0.route)) < SubstanceReadModel.routeRank(RouteOfAdministration.from(string: $1.route)) }
            }
        } catch {
            logger.error("pharmacokineticsRows failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// The single-column molar-mass read for one substance id. `nonisolated static` (cacheless) so the
    /// off-main tolerance resolve can run it on the dedicated batch connection.
    nonisolated static func molarMass(substanceID id: Int64, db queue: DatabaseQueue) -> Double? {
        let resolved = try? queue.read { db in
            try Double.fetchOne(db, sql: "SELECT molecular_weight FROM substances WHERE id = ?", arguments: [id])
        }
        return resolved ?? nil
    }

    /// The tolerance classes a substance's **pharmacological categories** imply (benzodiazepine → GABA,
    /// opioid → μ, …), read from the `categories` table for one substance id. `nonisolated static` so the
    /// off-main batch resolve can run it on the dedicated batch connection. Drives the category fallback
    /// that rescues categorised-but-untargeted RC substances (§7 follow-up).
    nonisolated static func toleranceCategoryClasses(substanceID id: Int64, db queue: DatabaseQueue) -> Set<ReceptorClasses.ReceptorClass> {
        let raws: [String] = (try? queue.read { db in
            try String.fetchAll(db, sql: "SELECT category FROM categories WHERE substance_id = ?", arguments: [id])
        }) ?? []
        var classes: Set<ReceptorClasses.ReceptorClass> = []
        for raw in raws {
            let category = SubstanceCategory(rawValue: raw) ?? SubstanceCategory.from(tripSitCategory: raw)
            if let cls = ReceptorClasses.toleranceClass(forCategory: category) { classes.insert(cls) }
        }
        return classes
    }

    /// The single-column name→id lookup on a given connection. `nonisolated static` so the off-main
    /// batch borrow can resolve a reference-substance name without hopping to the main actor's
    /// in-memory `nameIndex`. Canonical name first (case-insensitive), then alias.
    nonisolated static func substanceID(forNameOrAlias name: String, db queue: DatabaseQueue) -> Int64? {
        let key = name.lowercased()
        return (try? queue.read { db -> Int64? in
            if let id = try Int64.fetchOne(
                db, sql: "SELECT id FROM substances WHERE lower(canonical_name) = ? LIMIT 1", arguments: [key],
            ) {
                return id
            }
            return try Int64.fetchOne(
                db, sql: "SELECT substance_id FROM aliases WHERE lower(alias) = ? LIMIT 1", arguments: [key],
            )
        }) ?? nil
    }

    /// The pharmacokinetics **reference-substance** pointer for a substance (the derivation layer): the
    /// surrogate name, the set of borrowable field keys (`vd`/`bioavailability`/`tmax`/`half_life`), and
    /// the confidence ceiling every borrowed value is floored to. `nil` when the substance carries no
    /// `pk_reference`. Single-hop is enforced at build (`reject_transitive_pk_references`); the resolver
    /// additionally refuses a reference that itself carries a pointer.
    nonisolated static func pkReference(
        substanceID id: Int64, db queue: DatabaseQueue,
    ) -> (name: String, fields: Set<String>, confidence: ConfidenceTier)? {
        let maybeRow: Row? = (try? queue.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT pk_reference_name, pk_reference_fields, pk_reference_confidence FROM substances WHERE id = ?",
                arguments: [id],
            )
        }) ?? nil
        guard let row = maybeRow,
              let name = row["pk_reference_name"] as String?, !name.isEmpty else { return nil }
        let fieldsCSV = (row["pk_reference_fields"] as String?) ?? ""
        let fields = Set(
            fieldsCSV.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                .filter { !$0.isEmpty },
        )
        return (name, fields, ConfidenceTier(grade: row["pk_reference_confidence"] as String?))
    }

    /// Metabolism rows for one substance id on the given connection — `nonisolated static` so the
    /// off-main tolerance resolve reads them on the batch connection (mirrors ``bindingRows`` /
    /// ``pharmacokineticsRows``). The metabolite's own half-life is resolved by source priority from
    /// the linked substance's ``half_lives`` (falling back to the scalar column) exactly as the
    /// interactive read does.
    nonisolated static func metabolismRows(
        substanceID: Int64, db queue: DatabaseQueue, order: [String],
    ) -> [SubstanceStore.MetabolismHit] {
        let enabledSourceListSQL = SubstanceReadModel.enabledSourceListSQL(order)
        let priorityCaseSQL = SubstanceReadModel.priorityCaseSQL(order)
        do {
            return try queue.read { db in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT m.id, m.enzyme, m.fraction_of_clearance_pct, m.metabolite_name,
                           ms.canonical_name AS metabolite_substance_name,
                           m.metabolite_active, m.metabolite_potency_vs_parent_pct,
                           m.metabolite_potency_basis, m.metabolite_potency_target,
                           m.metabolite_mechanism_vs_parent, m.metabolite_half_life_min,
                           m.formation_fraction_pct, m.route,
                           src.slug AS source_slug, c.doi, c.pmid,
                           -- The metabolite's OWN sourced half-life, when we carry it as a
                           -- substance. Linking beats copying (see the `metabolite_substance_id`
                           -- comment in the schema). Do not drop this in favour of the scalar
                           -- `metabolite_half_life_min` beside it: that column holds whatever a
                           -- single paper reported, on whatever basis it used, and is not
                           -- comparable with the parent's own half-life. Methamphetamine →
                           -- amphetamine stores 1242 min there, which the row's own note
                           -- identifies as a *urinary* elimination half-life; set against
                           -- methamphetamine's *plasma* 606 min it reads as a 2× difference
                           -- where there is none — both are ~10 h plasma. Same mixed-basis trap
                           -- the ternary's gate exists to catch, in a different table.
                           -- The inner `src` alias deliberately shadows the outer one so the
                           -- shared source-priority CASE applies to the metabolite's own rows.
                           (SELECT h.half_life_minutes
                              FROM half_lives h
                              JOIN sources src ON src.id = h.source_id
                             WHERE h.substance_id = m.metabolite_substance_id
                               AND src.slug IN (\(enabledSourceListSQL))
                             ORDER BY \(priorityCaseSQL) ASC
                             LIMIT 1) AS metabolite_own_half_life_min
                      FROM metabolism m
                      JOIN sources src ON src.id = m.source_id
                      LEFT JOIN substances ms ON ms.id = m.metabolite_substance_id
                      LEFT JOIN citations c ON c.id = m.citation_id
                     WHERE m.substance_id = ?
                     ORDER BY m.fraction_of_clearance_pct DESC NULLS LAST, m.enzyme ASC
                """, arguments: [substanceID])
                return rows.map { row in
                    SubstanceStore.MetabolismHit(
                        id: row["id"],
                        enzyme: row["enzyme"],
                        fractionOfClearancePct: row["fraction_of_clearance_pct"],
                        metaboliteName: row["metabolite_name"],
                        metaboliteSubstanceName: row["metabolite_substance_name"],
                        metaboliteActive: (row["metabolite_active"] as Int64?).map { $0 != 0 },
                        metabolitePotencyVsParentPct: row["metabolite_potency_vs_parent_pct"],
                        metabolitePotencyBasis: (row["metabolite_potency_basis"] as String?)
                            .flatMap(SubstanceStore.MetabolitePotencyBasis.init(rawValue:)),
                        metabolitePotencyTarget: row["metabolite_potency_target"],
                        // Unrecognized or absent both mean "not established to be
                        // a scaled copy", which must never scale the parent's effect.
                        metaboliteMechanismVsParent: (row["metabolite_mechanism_vs_parent"] as String?)
                            .flatMap(SubstanceStore.MetaboliteMechanism.init(rawValue:)) ?? .unknown,
                        // Own record first, scalar column only when we don't carry the
                        // metabolite as a substance (norfluoxetine, cotinine, dextrorphan).
                        metaboliteHalfLifeMinutes: (row["metabolite_own_half_life_min"] as Double?)
                            ?? (row["metabolite_half_life_min"] as Double?),
                        formationFractionPct: row["formation_fraction_pct"],
                        route: row["route"],
                        sourceSlug: row["source_slug"],
                        doi: row["doi"],
                        pmid: (row["pmid"] as Int64?).map(Int.init),
                    )
                }
            }
        } catch {
            logger.error("metabolismRows failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// The single windowed `pk_routes` pass behind the Pharma table: one preferred row per substance
    /// (oral first, else the row carrying the most PK fields, best confidence), keyed by substance id.
    /// `nonisolated static` so it runs entirely off the main actor on the batch connection —
    /// `ROW_NUMBER()` partitioned by substance picks the route in one query, so there is no
    /// per-substance read loop. The seed-merge that turns these into ``PharmaTableRow``s stays on
    /// ``SubstanceStore``.
    nonisolated static func preferredPKRowBySubstanceID(db queue: DatabaseQueue) -> [Int64: Row] {
        var pkByID: [Int64: Row] = [:]
        do {
            let rows = try queue.read { db in
                try Row.fetchAll(db, sql: """
                    SELECT substance_id, route, bioavailability_pct, cmax_ng_per_ml, tmax_min,
                           half_life_min, vd_l_per_kg, clearance_ml_per_min_per_kg, protein_binding_pct
                      FROM (
                        SELECT p.*,
                               ROW_NUMBER() OVER (
                                 PARTITION BY p.substance_id
                                 ORDER BY (lower(p.route) = 'oral') DESC,
                                          (lower(p.route) LIKE 'oral%') DESC,
                                          ((p.bioavailability_pct IS NOT NULL) + (p.cmax_ng_per_ml IS NOT NULL)
                                           + (p.tmax_min IS NOT NULL) + (p.half_life_min IS NOT NULL)
                                           + (p.vd_l_per_kg IS NOT NULL) + (p.clearance_ml_per_min_per_kg IS NOT NULL)
                                           + (p.protein_binding_pct IS NOT NULL)) DESC,
                                          CASE upper(COALESCE(p.confidence, ''))
                                              WHEN 'HIGH' THEN 0 WHEN 'MEDIUM' THEN 1 WHEN 'LOW' THEN 2 ELSE 3 END,
                                          p.id
                               ) AS rn
                          FROM pk_routes p
                      )
                     WHERE rn = 1
                """)
            }
            for row in rows {
                let substanceID: Int64 = row["substance_id"]
                pkByID[substanceID] = row
            }
        } catch {
            logger.error("preferredPKRowBySubstanceID failed: \(error.localizedDescription, privacy: .public)")
        }
        return pkByID
    }
}
