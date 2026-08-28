import Foundation
import GRDB
import os

private nonisolated let logger = Logger(subsystem: "dev.yumeji.piru", category: "SubstanceStore")

/// One `zero_order_kinetics` row: the parameters that put a substance on the dose-scaled
/// linear-decline curve instead of the fixed phase bell. Weight scaling happens at the point of use
/// (``PKModel/zeroOrderKinetics(vmaxMgPerMin:referenceWeightKg:kaPerMin:bioavailability:weightKg:)``),
/// so this stays the substance's stored answer rather than one person's.
nonisolated struct ZeroOrderRow: Equatable, Sendable {
    /// Maximal elimination rate, mg/min, at ``referenceWeightKg``.
    let vmaxMgPerMin: Double
    /// Body weight (kg) ``vmaxMgPerMin`` is anchored to.
    let referenceWeightKg: Double
    /// First-order absorption rate constant, per minute.
    let kaPerMin: Double
}

/// One zero-order substance as read from the database: its row, plus every name a logged dose could
/// carry it under (canonical name and aliases, lowercased).
nonisolated struct ZeroOrderEntry: Equatable, Sendable {
    let canonicalName: String
    let lookupKeys: [String]
    let row: ZeroOrderRow
}

/// A ``ZeroOrderRow`` paired with the substance's resolved oral bioavailability, which lives in
/// `pk_routes` rather than in the zero-order table — see ``SubstanceStore/zeroOrderProfiles()``.
nonisolated struct ZeroOrderProfile: Equatable, Sendable {
    let row: ZeroOrderRow
    /// Fraction in `(0, 1]`, from ``PharmacologyParameters/bioavailabilityFraction``.
    let bioavailability: Double
}

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
    /// The curated ordinal tier (1 weak … 3 primary) for a row that carries no
    /// measured value. NULL on measured rows, which rank by their own
    /// concentration through ``ReceptorStrength/tier(kiNm:ec50Nm:ic50Nm:)``.
    /// Read it only as a fallback for that call, never instead of it.
    var affinityTier: Int?
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
                           b.affinity_tier,
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
                        affinityTier: row["affinity_tier"],
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
                           b.affinity_tier,
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
                        affinityTier: row["affinity_tier"],
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

    /// Whether a substance carries one `substance_flags` flag. `nonisolated static` so the off-main
    /// batch resolve can run it on the dedicated batch connection. Flags are model gates, not display
    /// vocabulary — the app never renders one, so there is no source-priority resolution here: a flag
    /// is present or it is not.
    nonisolated static func hasFlag(_ flag: String, substanceID id: Int64, db queue: DatabaseQueue) -> Bool {
        let hit = try? queue.read { db in
            try Int64.fetchOne(
                db, sql: "SELECT 1 FROM substance_flags WHERE substance_id = ? AND flag = ? LIMIT 1",
                arguments: [id, flag],
            )
        }
        return (hit ?? nil) != nil
    }

    /// Diazepam-mg per 1 mg of this substance, from the highest-priority enabled `diazepam_equivalents`
    /// row **that carries a citation**. `nil` when the substance has no row, when its row carries only
    /// the "no validated equivalence" prose with no numbers (the designer benzos), or when its number
    /// has no source — in every case the caller falls through to the dose-fraction proxy rather than
    /// invent a factor.
    ///
    /// The citation gate is the point, not a nicety. The caller uses this ratio to model a PK-less
    /// benzodiazepine AS diazepam and *raises the result's confidence floor from `.unverified` to
    /// `.low`* on the strength of it — an upgrade only a validated clinical equivalence earns. The
    /// upstream `diazvalue` field carries no per-value source, so before this gate the upgrade applied
    /// to numbers of unknown origin. Five rows sit uncited today (brotizolam, etizolam, flutoprazepam,
    /// midazolam, phenazepam): absent from Ashton Table 1, and none the worse for saying so.
    nonisolated static func diazepamPerMg(substanceID id: Int64, db queue: DatabaseQueue, order: [String]) -> Double? {
        let enabled = enabledSourceListSQL(order)
        let priority = priorityCaseSQL(order)
        return (try? queue.read { db -> Double? in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT dose_mg, equivalent_diazepam_mg
                  FROM diazepam_equivalents d
                  JOIN sources src ON src.id = d.source_id
                 WHERE d.substance_id = ?
                   AND src.slug IN (\(enabled))
                   AND d.citation_id IS NOT NULL
                 ORDER BY \(priority) ASC
                 LIMIT 1
            """, arguments: [id]) else { return nil }
            guard let doseMg: Double = row["dose_mg"], doseMg > 0,
                  let equivalent: Double = row["equivalent_diazepam_mg"] else { return nil }
            return equivalent / doseMg
        }) ?? nil
    }

    /// Morphine-mg per 1 mg of this opioid, from the highest-priority enabled `opioid_mme` row.
    /// `nil` when the substance has no row **or** its row is not `linear` — methadone, transdermal
    /// fentanyl and buprenorphine must fall through to the generic dose-fraction proxy rather than
    /// borrow a factor that does not exist for them.
    nonisolated static func opioidMMEPerMg(substanceID id: Int64, db queue: DatabaseQueue, order: [String]) -> Double? {
        let enabled = enabledSourceListSQL(order)
        let priority = priorityCaseSQL(order)
        return (try? queue.read { db -> Double? in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT mme_per_mg, convertibility
                  FROM opioid_mme o
                  JOIN sources src ON src.id = o.source_id
                 WHERE o.substance_id = ?
                   AND src.slug IN (\(enabled))
                 ORDER BY \(priority) ASC
                 LIMIT 1
            """, arguments: [id]) else { return nil }
            guard row["convertibility"] == OpioidEquivalence.Convertibility.linear.rawValue else { return nil }
            return row["mme_per_mg"]
        }) ?? nil
    }

    /// Intrinsic efficacy at MOR relative to a full agonist, for the tolerance engine's
    /// occupancy-weighted drive. `nil` when the substance has no row — which is the common case and
    /// means the full-agonist default, not "unknown".
    ///
    /// The table is deliberately tiny: every row comes from one low-amplification assay, because
    /// measured efficacy tracks receptor reserve and readout amplification hard enough that mixing
    /// assays encodes an ordering that is an artifact of method. See the `intrinsic_efficacy` DDL.
    nonisolated static func intrinsicEfficacy(substanceID id: Int64, db queue: DatabaseQueue, order: [String]) -> Double? {
        let enabled = enabledSourceListSQL(order)
        let priority = priorityCaseSQL(order)
        return (try? queue.read { db -> Double? in
            try Row.fetchOne(db, sql: """
                SELECT efficacy
                  FROM intrinsic_efficacy e
                  JOIN sources src ON src.id = e.source_id
                 WHERE e.substance_id = ?
                   AND src.slug IN (\(enabled))
                 ORDER BY \(priority) ASC
                 LIMIT 1
            """, arguments: [id])?["efficacy"]
        }) ?? nil
    }

    /// The whole `tolerance_modulation` table — which receptor class, while onboard, scales another
    /// class's tolerance development and by how much. Read once at index build; see
    /// ``ToleranceModulation`` for why it is held rather than queried per call.
    nonisolated static func toleranceModulationEdges(
        db queue: DatabaseQueue,
    ) -> [ReceptorClasses.ReceptorClass: [ToleranceModulation.Edge]] {
        let rows = (try? queue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT modulator_class, affected_class, mu_factor
                  FROM tolerance_modulation
                 ORDER BY modulator_class, affected_class
            """)
        }) ?? []
        var out: [ReceptorClasses.ReceptorClass: [ToleranceModulation.Edge]] = [:]
        for row in rows {
            guard let modulatorRaw: String = row["modulator_class"],
                  let affectedRaw: String = row["affected_class"],
                  let modulator = ReceptorClasses.ReceptorClass(rawValue: modulatorRaw),
                  let affected = ReceptorClasses.ReceptorClass(rawValue: affectedRaw),
                  let muFactor: Double = row["mu_factor"] else { continue }
            out[modulator, default: []].append(
                ToleranceModulation.Edge(affectedClass: affected, muFactor: muFactor),
            )
        }
        return out
    }

    /// The tolerance mechanism classes each representative substance stands in for, keyed by substance
    /// id — the whole `class_representatives` table in one read. `nonisolated static` so the off-main
    /// batch resolve can run it once per recompute on the batch connection.
    nonisolated static func classRepresentatives(db queue: DatabaseQueue) -> [Int64: Set<ReceptorClasses.ReceptorClass>] {
        let rows = (try? queue.read { db in
            try Row.fetchAll(db, sql: "SELECT receptor_class, substance_id FROM class_representatives")
        }) ?? []
        var out: [Int64: Set<ReceptorClasses.ReceptorClass>] = [:]
        for row in rows {
            guard let raw: String = row["receptor_class"],
                  let cls = ReceptorClasses.ReceptorClass(rawValue: raw),
                  let id: Int64 = row["substance_id"] else { continue }
            out[id, default: []].insert(cls)
        }
        return out
    }

    /// `substances.drug_class` for every substance that carries one, keyed by lowercased canonical
    /// name — the normalized antidepressant-subclass axis, a few dozen rows.
    nonisolated static func drugClasses(db queue: DatabaseQueue) -> [String: CuratedDrugClass] {
        let rows = (try? queue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT canonical_name, drug_class, drug_class_ambiguous
                  FROM substances WHERE drug_class IS NOT NULL
            """)
        }) ?? []
        return rows.reduce(into: [:]) { out, row in
            guard let name: String = row["canonical_name"], let value: String = row["drug_class"]
            else { return }
            out[name.lowercased()] = CuratedDrugClass(
                value: value,
                isContested: (row["drug_class_ambiguous"] as Int?) == 1,
            )
        }
    }

    /// The recognisable names one comparison family is drawn against, most prominent first.
    nonisolated static func referenceCompounds(db queue: DatabaseQueue, family: String) -> [String] {
        (try? queue.read { db in
            try String.fetchAll(db, sql: """
                SELECT s.canonical_name
                  FROM class_reference_compounds r
                  JOIN substances s ON s.id = r.substance_id
                 WHERE r.family = ?
                 ORDER BY r.rank
            """, arguments: [family])
        }) ?? []
    }

    /// The whole `saturable_kinetics` table in curated display order — every substance whose
    /// dose→exposure relationship is not proportional, with the Michaelis-Menten constants for the
    /// ones that have clean human values and nothing but a mechanism for the ones that do not.
    nonisolated static func saturableKinetics(db queue: DatabaseQueue) -> [SaturableKineticsRow] {
        let rows = (try? queue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT s.canonical_name AS name, k.mechanism, k.confidence, k.km_mg_per_l,
                       k.vmax, k.vmax_basis, k.vd_l_per_kg, k.ka_per_min,
                       k.half_life_min, k.citation_text
                  FROM saturable_kinetics k
                  JOIN substances s ON s.id = k.substance_id
                 ORDER BY k.rank ASC
            """)
        }) ?? []
        return rows.compactMap { row in
            guard let name: String = row["name"], let mechanism: String = row["mechanism"],
                  let confidence: String = row["confidence"], let citation: String = row["citation_text"]
            else { return nil }
            return SaturableKineticsRow(
                substanceName: name,
                mechanism: mechanism,
                confidence: confidence,
                kmMgPerL: row["km_mg_per_l"],
                vmax: row["vmax"],
                vmaxBasis: row["vmax_basis"],
                vdLPerKg: row["vd_l_per_kg"],
                kaPerMin: row["ka_per_min"],
                halfLifeMinutes: row["half_life_min"],
                citation: citation,
            )
        }
    }

    /// Every `bioavailability_by_dose` series, keyed by lowercased canonical name, each ascending by
    /// dose — the ingester refuses a series that is not, so a consumer may interpolate between
    /// neighbouring points without re-sorting.
    nonisolated static func bioavailabilityByDose(db queue: DatabaseQueue) -> [String: [BioavailabilityPoint]] {
        let rows = (try? queue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT s.canonical_name AS name, b.dose_mg, b.dose_basis, b.bioavailability_pct,
                       b.citation_text
                  FROM bioavailability_by_dose b
                  JOIN substances s ON s.id = b.substance_id
                 ORDER BY s.canonical_name COLLATE NOCASE, b.dose_mg ASC
            """)
        }) ?? []
        var out: [String: [BioavailabilityPoint]] = [:]
        for row in rows {
            guard let name: String = row["name"], let dose: Double = row["dose_mg"],
                  let basis: String = row["dose_basis"], let pct: Double = row["bioavailability_pct"],
                  let citation: String = row["citation_text"] else { continue }
            out[name.lowercased(), default: []].append(
                BioavailabilityPoint(
                    doseMg: dose, basis: basis, bioavailabilityPct: pct, citation: citation,
                ),
            )
        }
        return out
    }

    /// The whole `attenuation_bands` table, keyed by transporter — how far a releaser's effect is
    /// blunted by a blocker competing for the same transporter. Read once at index build; see
    /// ``CompetingTransporter`` for why it is held rather than queried per call.
    nonisolated static func attenuationBands(db queue: DatabaseQueue) -> [String: CompetingTransporter.Band] {
        let rows = (try? queue.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT transporter, reduction_low, reduction_high FROM attenuation_bands",
            )
        }) ?? []
        var out: [String: CompetingTransporter.Band] = [:]
        for row in rows {
            guard let key: String = row["transporter"], let low: Double = row["reduction_low"],
                  let high: Double = row["reduction_high"] else { continue }
            out[key] = CompetingTransporter.Band(low: low, high: high)
        }
        return out
    }

    /// Preparation → the molecule its pharmacology is measured on, both lowercased canonical names.
    /// Read once at index build; see ``ActiveIngredient`` for why it is held rather than queried.
    nonisolated static func activeIngredients(db queue: DatabaseQueue) -> [String: String] {
        let rows = (try? queue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT s.canonical_name AS preparation, i.canonical_name AS ingredient
                  FROM substances s
                  JOIN substances i ON i.id = s.active_ingredient_substance_id
            """)
        }) ?? []
        var out: [String: String] = [:]
        for row in rows {
            guard let preparation: String = row["preparation"],
                  let ingredient: String = row["ingredient"] else { continue }
            out[preparation.lowercased()] = ingredient
        }
        return out
    }

    /// The lowercased canonical names carrying one `substance_flags` flag — the whole-table read a
    /// gate needs when it asks "is this substance in the set", rather than "does this id have the
    /// flag". `nonisolated static` so it can run at index build off the main actor.
    nonisolated static func flaggedNames(_ flag: String, db queue: DatabaseQueue) -> Set<String> {
        let names = (try? queue.read { db in
            try String.fetchAll(db, sql: """
                SELECT s.canonical_name
                  FROM substance_flags f
                  JOIN substances s ON s.id = f.substance_id
                 WHERE f.flag = ?
            """, arguments: [flag])
        }) ?? []
        return Set(names.map { $0.lowercased() })
    }

    /// The whole `regional_names` table, keyed by lowercased canonical name — which spelling of a
    /// substance to display in which regions. Read once at index build; see ``RegionalSubstanceName``
    /// for why it is held rather than queried per call.
    nonisolated static func regionalNames(db queue: DatabaseQueue) -> [String: RegionalSubstanceName.Variant] {
        let rows = (try? queue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT s.canonical_name AS name, r.base_name, r.alternate_name, r.alternate_regions
                  FROM regional_names r
                  JOIN substances s ON s.id = r.substance_id
            """)
        }) ?? []
        var out: [String: RegionalSubstanceName.Variant] = [:]
        for row in rows {
            guard let name: String = row["name"],
                  let base: String = row["base_name"],
                  let alternate: String = row["alternate_name"],
                  let regions: String = row["alternate_regions"] else { continue }
            out[name.lowercased()] = RegionalSubstanceName.Variant(
                base: base,
                alternate: alternate,
                alternateRegions: Set(regions.split(separator: ",").map(String.init)),
            )
        }
        return out
    }

    /// The whole `by_volume_dosing` + `drink_presets` pair as capabilities keyed by lowercased
    /// canonical name **and** by every alias, so a substance logged as "Ethanol" finds the row
    /// written against "Alcohol". Read once at index build; see ``ByVolumeCatalog`` for why it is
    /// held rather than queried per call.
    ///
    /// Resolved by the sources' own `default_priority` rather than the user's enabled order: this is
    /// the dose *input* the app offers, not a pharmacological claim a reader would want to attribute,
    /// and it is read during index build before the user's source preferences are loaded.
    nonisolated static func byVolumeCapabilities(db queue: DatabaseQueue) -> [String: ByVolumeDosing] {
        let (rows, presetRows): ([Row], [Row]) = (try? queue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT b.substance_id AS sid, s.canonical_name AS name, b.concentration_kind,
                       b.canonical_unit, b.density_g_per_ml, b.standard_unit_mass, b.standard_unit_label
                  FROM (
                    SELECT bv.*, ROW_NUMBER() OVER (
                        PARTITION BY bv.substance_id
                        ORDER BY src.default_priority ASC) AS rn
                      FROM by_volume_dosing bv
                      JOIN sources src ON src.id = bv.source_id
                  ) b
                  JOIN substances s ON s.id = b.substance_id
                 WHERE b.rn = 1
            """)
            let presetRows = try Row.fetchAll(db, sql: """
                SELECT p.substance_id AS sid, p.kind, p.volume_ml, p.default_strength
                  FROM drink_presets p
                  JOIN sources src ON src.id = p.source_id
                 ORDER BY src.default_priority ASC, p.rank ASC
            """)
            return (rows, presetRows)
        }) ?? ([], [])

        var presets: [Int64: [DrinkPreset]] = [:]
        for row in presetRows {
            guard let sid: Int64 = row["sid"],
                  let raw: String = row["kind"],
                  // A kind this build has no label or symbol for is dropped: the presets are
                  // emoji-and-label chips, and a raw "kind" string is not one.
                  let kind = DrinkPreset.Kind(rawValue: raw),
                  let volume: Double = row["volume_ml"],
                  let strength: Double = row["default_strength"] else { continue }
            presets[sid, default: []].append(DrinkPreset(
                kind: kind,
                volume: Measurement(value: volume, unit: .milliliters),
                defaultABV: strength,
            ))
        }

        var byID: [Int64: ByVolumeDosing] = [:]
        var out: [String: ByVolumeDosing] = [:]
        for row in rows {
            guard let sid: Int64 = row["sid"], let name: String = row["name"],
                  row["concentration_kind"] == "percent_by_volume",
                  let density: Double = row["density_g_per_ml"], density > 0,
                  let unit: String = row["canonical_unit"] else { continue }
            let capability = ByVolumeDosing(
                concentration: .percentByVolume(densityGramsPerML: density),
                canonicalUnit: unit,
                standardUnitMass: row["standard_unit_mass"] ?? 0,
                standardUnitLabel: row["standard_unit_label"] ?? "",
                drinkPresets: presets[sid] ?? [],
            )
            byID[sid] = capability
            out[name.lowercased()] = capability
        }
        guard !byID.isEmpty else { return out }
        let aliasRows = (try? queue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT substance_id AS sid, alias FROM aliases
                 WHERE substance_id IN (\(byID.keys.map(String.init).joined(separator: ",")))
            """)
        }) ?? []
        for row in aliasRows {
            guard let sid: Int64 = row["sid"], let alias: String = row["alias"],
                  let capability = byID[sid] else { continue }
            out[alias.lowercased()] = capability
        }
        return out
    }

    /// The whole `zero_order_kinetics` table, as canonical name → the substance's saturable
    /// elimination parameters. Carries no bioavailability: F is the same quantity `pk_routes`
    /// already holds, and the caller pairs each row with the one
    /// ``PharmacologyParameters/bioavailabilityFraction`` resolved, so the timeline and the
    /// occupancy math can never read two different answers to it.
    nonisolated static func zeroOrderKinetics(db queue: DatabaseQueue, order: [String]) -> [ZeroOrderEntry] {
        let enabled = enabledSourceListSQL(order)
        let priority = priorityCaseSQL(order)
        let (rows, aliasRows): ([Row], [Row]) = (try? queue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT z.substance_id AS sid, s.canonical_name AS name, z.vmax_mg_per_min,
                       z.vmax_reference_weight_kg, z.ka_per_min
                  FROM (
                    SELECT zo.*, ROW_NUMBER() OVER (
                        PARTITION BY zo.substance_id
                        ORDER BY \(priority) ASC) AS rn
                      FROM zero_order_kinetics zo
                      JOIN sources src ON src.id = zo.source_id
                     WHERE src.slug IN (\(enabled))
                  ) z
                  JOIN substances s ON s.id = z.substance_id
                 WHERE z.rn = 1
            """)
            let aliasRows = try Row.fetchAll(db, sql: """
                SELECT a.substance_id AS sid, a.alias
                  FROM aliases a
                 WHERE a.substance_id IN (SELECT substance_id FROM zero_order_kinetics)
            """)
            return (rows, aliasRows)
        }) ?? ([], [])

        var aliases: [Int64: [String]] = [:]
        for row in aliasRows {
            guard let sid: Int64 = row["sid"], let alias: String = row["alias"] else { continue }
            aliases[sid, default: []].append(alias)
        }
        return rows.compactMap { row in
            guard let sid: Int64 = row["sid"], let name: String = row["name"],
                  let vmax: Double = row["vmax_mg_per_min"], vmax > 0,
                  let referenceWeight: Double = row["vmax_reference_weight_kg"], referenceWeight > 0,
                  let ka: Double = row["ka_per_min"], ka > 0 else { return nil }
            return ZeroOrderEntry(
                canonicalName: name,
                lookupKeys: ([name] + (aliases[sid] ?? [])).map { $0.lowercased() },
                row: ZeroOrderRow(vmaxMgPerMin: vmax, referenceWeightKg: referenceWeight, kaPerMin: ka),
            )
        }
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
                           m.formation_fraction_pct, m.route, m.conditional_combination_id,
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
                        conditionalCombinationID: (row["conditional_combination_id"] as String?)
                            .flatMap(CombinationMetabolite.CombinationID.init(rawValue:)),
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

    /// The Mechanism-column label for every substance at once: the highest-priority enabled
    /// source's `mechanisms_summary` headline, resolved locale-first.
    ///
    /// One windowed query rather than a per-substance resolve, and `nonisolated static` so the
    /// Pharma table's off-main pass can run it on the batch connection. It reads the same table
    /// under the same priority and language rules as the detail card's mechanism, which is the
    /// point: the two used to disagree, because the table asked the Swift class templates and the
    /// card asked the database.
    nonisolated static func mechanismLabelBySubstanceID(
        db queue: DatabaseQueue, order: [String], language: ContentLanguage,
    ) -> [Int64: String] {
        let lang = language.clauses(column: "m.language")
        var labels: [Int64: String] = [:]
        do {
            let rows = try queue.read { db in
                try Row.fetchAll(db, sql: """
                    SELECT substance_id, summary FROM (
                        SELECT m.substance_id, m.summary,
                               ROW_NUMBER() OVER (
                                 PARTITION BY m.substance_id
                                 ORDER BY \(lang.orderPrefix)\(priorityCaseSQL(order)) ASC
                               ) AS rn
                          FROM mechanisms_summary m
                          JOIN sources src ON src.id = m.source_id
                         WHERE src.slug IN (\(enabledSourceListSQL(order)))
                           \(lang.whereAnd)
                    )
                     WHERE rn = 1
                """)
            }
            for row in rows {
                let id: Int64 = row["substance_id"]
                let summary: String = row["summary"]
                if !summary.isEmpty { labels[id] = summary }
            }
        } catch {
            logger.error("mechanismLabelBySubstanceID failed: \(error.localizedDescription, privacy: .public)")
        }
        return labels
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
