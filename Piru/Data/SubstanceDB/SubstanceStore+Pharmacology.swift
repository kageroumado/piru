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
    let route: String?
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

/// The pharmacology / pharmacokinetics read layer extracted from `SubstanceStore`: the per-substance
/// binding, PK, molar-mass, metabolism, and resolved `PharmacologyParameters` reads. Split out so the
/// core store stays under the file-length budget; the off-main batch resolve (`pharmacologyParametersBatchOffMain`)
/// lives here alongside the cached interactive accessors it shares assembly logic with.
extension SubstanceStore {
    /// Every binding row associated with a specific substance, resolved by
    /// canonical name. Used by the detail view's "Receptor Literature"
    /// disclosure (pharma-nerd tier) to show the full Ki/EC50 table with
    /// per-row source attribution. Returns rows sorted by tightest Ki first.
    ///
    /// Resolves through ``ActiveIngredient`` first, so a preparation reads its
    /// molecule's rows rather than a copy filed under the plant. This is the
    /// choke point for it: mechanism hero, receptor literature and the monoamine
    /// profile all read through here, so they agree by construction.
    func bindings(forSubstanceName name: String) -> [BindingHit] {
        let resolved = ActiveIngredient.pharmacologyName(for: name)
        guard let substanceID = substanceID(forNameOrAlias: resolved) else { return [] }
        return Self.bindingRows(substanceID: substanceID, db: substancesDB)
    }

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

    /// One route's PK for display: the best-evidenced study row, plus how many
    /// distinct studies the table holds for that route (1 when it's the only
    /// one). Built by ``SubstanceStore/displayRows(_:)``. Declared here rather
    /// than beside its sibling hits in `SubstanceStore.swift`, which is at its
    /// 2500-line lint ceiling.
    struct PKDisplayRow: Identifiable, Hashable {
        let hit: PKRouteHit
        let studyCount: Int

        var id: Int64 {
            hit.id
        }
    }

    /// One PK row per route, for display.
    ///
    /// The raw table carries a row **per study**, so a well-researched route
    /// stacks up several — cocaine had two identical inhalation rows differing
    /// only in an unshown `notes` field, and amphetamine has five oral rows that
    /// restate one review at 90 % vs 75 % bioavailability. The card only renders
    /// the handful of metrics they mostly agree on, so they read as the same row
    /// printed repeatedly. This picks the best-evidenced row per route and
    /// reports how many *distinct* studies stood behind it, so the card can say
    /// so rather than silently dropping the rest.
    ///
    /// "Best" is: human (or unspecified) before animal data, then the row that
    /// fills in the most metrics, then the largest subject count, then the lowest
    /// id so the choice is stable across builds. Deliberately display-only —
    /// ``pharmacokineticsRows(substanceID:db:)`` keeps returning everything,
    /// because the tolerance engine's PK derivation reads across all the rows.
    nonisolated static func displayRows(_ rows: [PKRouteHit]) -> [PKDisplayRow] {
        /// Everything the card can show, so two rows that differ only in prose
        /// don't get counted as two studies.
        func metrics(_ hit: PKRouteHit) -> [Double?] {
            [
                hit.bioavailabilityPct, hit.cmaxNgPerMl, hit.tmaxMin, hit.halfLifeMin,
                hit.vdLPerKg, hit.clearanceMlPerMinPerKg, hit.proteinBindingPct,
            ]
        }
        func signature(_ hit: PKRouteHit) -> String {
            var parts: [String] = metrics(hit).map { value -> String in
                guard let value else { return "-" }
                return String(value)
            }
            parts.append(hit.doseInStudyMg.map { String($0) } ?? "-")
            parts.append(hit.subjectN.map { String($0) } ?? "-")
            parts.append(hit.demographics ?? "-")
            parts.append(hit.species ?? "-")
            return parts.joined(separator: "|")
        }
        func metricCount(_ hit: PKRouteHit) -> Int {
            metrics(hit).count { $0 != nil }
        }
        func isAnimal(_ hit: PKRouteHit) -> Bool {
            guard let species = hit.species else { return false }
            return species != "human"
        }

        var order: [String] = []
        var byRoute: [String: [PKRouteHit]] = [:]
        for hit in rows {
            // A row with no measured value has nothing to render: the card would
            // show a bare route name and a citation link, which reads as a broken
            // section rather than as "we have a study but no numbers". 2-FDCK's
            // insufflation row was exactly this — prose and a DOI, no metrics.
            guard metricCount(hit) > 0 else { continue }
            if byRoute[hit.route] == nil { order.append(hit.route) }
            byRoute[hit.route, default: []].append(hit)
        }

        return order.compactMap { route in
            guard let candidates = byRoute[route], !candidates.isEmpty else { return nil }
            let best = candidates.min { lhs, rhs in
                if isAnimal(lhs) != isAnimal(rhs) { return !isAnimal(lhs) }
                if metricCount(lhs) != metricCount(rhs) { return metricCount(lhs) > metricCount(rhs) }
                if (lhs.subjectN ?? 0) != (rhs.subjectN ?? 0) { return (lhs.subjectN ?? 0) > (rhs.subjectN ?? 0) }
                return lhs.id < rhs.id
            }
            guard let best else { return nil }
            return PKDisplayRow(hit: best, studyCount: Set(candidates.map(signature)).count)
        }
    }

    /// Per-route pharmacokinetic rows for a substance, across all sources, with
    /// per-row citation. Drives the detail view's Pharmacokinetics disclosure.
    /// Ordered by route rank (oral first) then tightest study.
    func pharmacokinetics(forSubstanceName name: String) -> [PKRouteHit] {
        guard let substanceID = substanceID(forNameOrAlias: name) else { return [] }
        return Self.pharmacokineticsRows(substanceID: substanceID, db: substancesDB)
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
                .sorted { Self.routeRank(RouteOfAdministration.from(string: $0.route)) < Self.routeRank(RouteOfAdministration.from(string: $1.route)) }
            }
        } catch {
            logger.error("pharmacokineticsRows failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// The substance's molar mass (`molecular_weight`, g/mol), resolved by **one** indexed query
    /// against the same `substances` row the full ``resolveSubstance`` reads — cached per row id.
    ///
    /// The tolerance/PD engine needs only this single column from the heavy record, and resolves it
    /// per unique dosed substance every recompute. Routing that through the full overlay-aware
    /// ``SubstanceLibrary/lookup(_:)`` paid a ~18-subquery + chem/effects/mechanism decode (and a
    /// SHA-256 id) for one `Double`, on the main actor — the post-commit recompute's multi-second
    /// hang on a cold `resolvedCache`. (The custom overlay never carries a molar mass, so reading the
    /// library column directly matches the full path.)
    func molarMass(forSubstanceName name: String) -> Double? {
        guard let id = substanceID(forNameOrAlias: name) else { return nil }
        if let cached = molarMassByID[id] { return cached }
        let value = Self.molarMass(substanceID: id, db: substancesDB)
        molarMassByID[id] = value
        return value
    }

    /// The single-column molar-mass read for one substance id. `nonisolated static` (cacheless) so the
    /// off-main tolerance resolve can run it on the dedicated batch connection.
    nonisolated static func molarMass(substanceID id: Int64, db queue: DatabaseQueue) -> Double? {
        let resolved = try? queue.read { db in
            try Double.fetchOne(db, sql: "SELECT molecular_weight FROM substances WHERE id = ?", arguments: [id])
        }
        return resolved ?? nil
    }

    /// Resolved inputs for the absolute-exposure → occupancy pipeline (the pharmacology axis's
    /// Foundation A): the best graded Vd + bioavailability + half-life from `pk_routes`, the molar
    /// mass, and the engaged targets (Kᵢ/EC₅₀/IC₅₀) from `bindings` — each carrying its confidence.
    ///
    /// This is the single accessor Stage 1's tolerance/PD engine consumes. Stage 0 ships it plus a
    /// peak-occupancy convenience used by the dose-dependence gate. It deliberately *prefers a graded
    /// row* (the flagship seed) over an un-graded one for the Vd, so the engine runs on the verified
    /// number when one exists and degrades to whatever is available otherwise.
    func pharmacologyParameters(forSubstanceName name: String) -> PharmacologyParameters {
        if let cached = pharmacologyParamsByName[name] { return cached }
        let resolved = resolvePharmacologyParameters(forSubstanceName: name)
        pharmacologyParamsByName[name] = resolved
        return resolved
    }

    /// Preparations whose pharmacology lives in an active constituent, mapped to that
    /// compound and a **content fraction** (mg active ÷ mg preparation). See
    /// `Specs/tolerance-plant-active-routing.md`. The logged substance keeps its own name
    /// (the "driven by" chip still says "Kratom"); only the pharmacology rows + dose scale
    /// come from the active compound, badged at the routing's confidence because the content
    /// fraction is an estimate.
    nonisolated static let preparationRouting: [String: (active: String, fraction: Double, confidence: ConfidenceTier)] = [
        // Curated Cannabis doses are already expressed in mg Δ9-THC, so the logged mg *is*
        // active mass (fraction 1.0); .medium because whole-plant entourage/CBD is ignored.
        "cannabis": ("THC", 1.0, .medium),
        // ~0.8% psilocybin by dry weight (P. cubensis, 0.5–1.0% range); potency varies widely.
        "mushrooms": ("Psilocybin", 0.008, .low),
        // ~15 mg/g mitragynine in dried leaf (12–21 mg/g range); extract products run higher.
        "kratom": ("Mitragynine", 0.015, .low),
    ]

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

    /// Route a logged name to the compound its pharmacology should be read from, plus the
    /// dose scale + confidence to carry. A pure compound routes to itself at scale 1.0.
    nonisolated static func routePreparation(_ name: String) -> (name: String, scale: Double, confidence: ConfidenceTier) {
        if let r = preparationRouting[name.lowercased()] {
            return (r.active, r.fraction, r.confidence)
        }
        return (name, 1.0, .high)
    }

    private func resolvePharmacologyParameters(forSubstanceName name: String) -> PharmacologyParameters {
        let routed = Self.routePreparation(name)
        // Lean single-column read of the SAME authoritative `substances.molecular_weight`
        // the full `resolveSubstance` returns — not the timeline batch projection (which
        // omits molecular_weight entirely, so reading it there returned nil and made
        // occupancy uncomputable; that was f2c2c04's regression). Going through the full
        // `lookup` here cost a ~18-query + SHA + localization resolve *per unique dosed
        // substance on the main actor*. The cached instance reads serve interactive callers
        // (detail view, effect attenuation); the tolerance recompute uses the off-main batch
        // path below so it never resolves on the main actor.
        // The escalation reference comes from the **logged** substance's own dose ladder (Kratom's,
        // not mitragynine's), since the logged dose and the ladder are both in preparation mg.
        // The escalation reference *and* the category classes come from the **logged** substance's own
        // row (Kratom's category, not mitragynine's), so a preparation keeps its own tolerance identity.
        let loggedID = substanceID(forNameOrAlias: name)
        let referenceDoseMg = loggedID.flatMap {
            Self.referenceDoseMg(substanceID: $0, db: substancesDB, order: enabledSourceOrder)
        }
        let categoryClasses = loggedID.map {
            Self.toleranceCategoryClasses(substanceID: $0, db: substancesDB)
        } ?? []
        // Reference-substance borrow (the derivation layer): a substance with no citeable PK of its own
        // (2-MMC) inherits a flagged surrogate's kinetics (mephedrone) via its `pk_reference` pointer.
        let pkID = substanceID(forNameOrAlias: routed.name)
        let effectivePK = Self.applyPKReference(
            ownRows: pharmacokinetics(forSubstanceName: routed.name),
            subjectID: pkID, db: substancesDB,
            resolveReferenceID: { self.substanceID(forNameOrAlias: $0) },
        )
        return Self.assemblePharmacologyParameters(
            name: name,
            molarMass: molarMass(forSubstanceName: routed.name),
            pk: effectivePK,
            bindingHits: bindings(forSubstanceName: routed.name),
            doseScale: routed.scale,
            doseScaleConfidence: routed.confidence,
            referenceDoseMg: referenceDoseMg,
            // §5c: keyed on the active compound (Kratom→Mitragynine), defaulting to full-agonist 1.0.
            intrinsicEfficacy: ToleranceStore.intrinsicEfficacyByName[routed.name.lowercased()] ?? 1,
            categoryClasses: categoryClasses,
        )
    }

    /// Resolve pharmacology parameters for several dosed substances **off the main actor**, on the
    /// dedicated batch connection. The background tolerance recompute calls this once per change tick;
    /// routing the per-substance Kᵢ/PK/molar-mass reads through the main-actor
    /// ``pharmacologyParameters(forSubstanceName:)`` resolved them in a tight loop on the main actor
    /// (three GRDB reads each), which competed with interactive rendering. Here the only main-actor work
    /// is snapshotting the immutable post-init ``nameIndex`` subset; the SQL + assembly run on a detached
    /// utility task against the read-only batch connection (the same one the launch prewarm uses).
    func pharmacologyParametersBatchOffMain(forNames names: [String]) async -> [String: PharmacologyParameters] {
        let ids = Dictionary(
            names.compactMap { name -> (String, Int64)? in
                // Preparations resolve their id from the active compound (Kratom→Mitragynine), so
                // the off-main row reads pull the active pharmacology while keyed by the logged name.
                guard let id = substanceID(forNameOrAlias: Self.routePreparation(name).name) else { return nil }
                return (name.lowercased(), id)
            },
            uniquingKeysWith: { first, _ in first },
        )
        // The escalation reference uses the **logged** substance's own dose ladder (preparation mg),
        // so it is keyed by the logged name's own id — not the active-compound id used for binding/PK.
        let referenceDoseIDs = Dictionary(
            names.compactMap { name -> (String, Int64)? in
                guard let id = substanceID(forNameOrAlias: name) else { return nil }
                return (name.lowercased(), id)
            },
            uniquingKeysWith: { first, _ in first },
        )
        let db = substancesBatchDB
        let order = enabledSourceOrder
        return await Task.detached(priority: .utility) {
            Self.resolvePharmacologyParametersBatch(
                names: names, ids: ids, referenceDoseIDs: referenceDoseIDs, order: order, db: db,
            )
        }.value
    }

    /// Resolve params for each unique name once, on the given connection. `nonisolated static` — runs
    /// entirely off the main actor. A name absent from `ids` (not in the bundled DB) still yields a
    /// params record with nil molar mass / no targets, which the engine treats as uncomputable.
    private nonisolated static func resolvePharmacologyParametersBatch(
        names: [String], ids: [String: Int64], referenceDoseIDs: [String: Int64],
        order: [String], db queue: DatabaseQueue,
    ) -> [String: PharmacologyParameters] {
        var out: [String: PharmacologyParameters] = [:]
        for name in names where out[name] == nil {
            let id = ids[name.lowercased()]
            let routed = routePreparation(name)
            let loggedID = referenceDoseIDs[name.lowercased()]
            let referenceDoseMg = loggedID.flatMap {
                Self.referenceDoseMg(substanceID: $0, db: queue, order: order)
            }
            let categoryClasses = loggedID.map { Self.toleranceCategoryClasses(substanceID: $0, db: queue) } ?? []
            // Reference-substance borrow (the derivation layer), off-main: same single-hop borrow as the
            // interactive path, resolving the surrogate's id on the batch connection.
            let effectivePK = applyPKReference(
                ownRows: id.map { pharmacokineticsRows(substanceID: $0, db: queue) } ?? [],
                subjectID: id, db: queue,
                resolveReferenceID: { substanceID(forNameOrAlias: $0, db: queue) },
            )
            out[name] = assemblePharmacologyParameters(
                name: name,
                molarMass: id.flatMap { molarMass(substanceID: $0, db: queue) },
                pk: effectivePK,
                bindingHits: id.map { bindingRows(substanceID: $0, db: queue) } ?? [],
                doseScale: routed.scale,
                doseScaleConfidence: routed.confidence,
                referenceDoseMg: referenceDoseMg,
                intrinsicEfficacy: ToleranceStore.intrinsicEfficacyByName[routed.name.lowercased()] ?? 1,
                categoryClasses: categoryClasses,
            )
        }
        return out
    }

    // MARK: - Derivation layer (interspecies scaling + reference-substance borrow)

    /// Reference body weights (kg) per study species, for interspecies allometric scaling.
    nonisolated static let speciesReferenceWeightKg: [String: Double] = [
        "rat": 0.25, "pig": 40, "human": 70, "mouse": 0.02, "dog": 10, "monkey": 3.5,
    ]

    /// Allometrically project a non-human PK row onto a 70 kg human (Boxenbaum 1982; Mahmood 2010).
    ///
    /// Volume of distribution per kg (L/kg) is species-**invariant** — it reflects tissue partitioning,
    /// not body size — so Vd/kg passes through UNCHANGED; only its *confidence* is floored (a non-human
    /// Vd is a class-default proxy, never a human-anchored value). Clearance and half-life DO scale with
    /// body mass by the classic allometric exponents: `CL ∝ BW^0.75` (→ ×(70/BW)^0.75) and
    /// `t½ ∝ BW^0.25` (→ ×(70/BW)^0.25). These are the *last-resort* fill; a measured-human t½/Tmax and
    /// a human apparent-Vd/F always win over scaled animal kinetics (`assemblePharmacologyParameters`
    /// keeps the human row's t½/Tmax when one exists).
    ///
    /// CAVEAT (load-bearing): single-species allometric scaling systematically **underpredicts cathinone
    /// half-life by ~2–3×** — validated: mephedrone rat-scaled ≈65 min vs measured human 129 min; 3-MMC
    /// pig-scaled ≈55 min vs measured human 180 min. So a scaled t½ is only a floor-confidence stand-in,
    /// never a substitute for the measured human value where one exists.
    ///
    /// A human or unknown-species row is returned unchanged.
    nonisolated static func scaledToHuman(_ row: PKRouteHit) -> PKRouteHit {
        guard let species = row.species?.lowercased(), species != "human",
              let bodyWeightKg = speciesReferenceWeightKg[species], bodyWeightKg > 0 else {
            return row
        }
        let massRatio = 70.0 / bodyWeightKg
        let clearanceScale = pow(massRatio, 0.75)
        let halfLifeScale = pow(massRatio, 0.25)
        return PKRouteHit(
            id: row.id, route: row.route, bioavailabilityPct: row.bioavailabilityPct,
            cmaxNgPerMl: row.cmaxNgPerMl,
            tmaxMin: row.tmaxMin,
            halfLifeMin: row.halfLifeMin.map { $0 * halfLifeScale },
            vdLPerKg: row.vdLPerKg, // species-invariant → unchanged
            clearanceMlPerMinPerKg: row.clearanceMlPerMinPerKg.map { $0 * clearanceScale },
            proteinBindingPct: row.proteinBindingPct, doseInStudyMg: row.doseInStudyMg,
            subjectN: row.subjectN, demographics: row.demographics, species: row.species,
            sourceSlug: row.sourceSlug, doi: row.doi, pmid: row.pmid, notes: row.notes,
            confidence: Swift.min(row.confidence, .low),
        )
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

    /// Rebuild a ``PKRouteHit`` with its confidence floored to `ceiling`.
    private nonisolated static func flooringConfidence(_ row: PKRouteHit, to ceiling: ConfidenceTier) -> PKRouteHit {
        PKRouteHit(
            id: row.id, route: row.route, bioavailabilityPct: row.bioavailabilityPct,
            cmaxNgPerMl: row.cmaxNgPerMl, tmaxMin: row.tmaxMin, halfLifeMin: row.halfLifeMin,
            vdLPerKg: row.vdLPerKg, clearanceMlPerMinPerKg: row.clearanceMlPerMinPerKg,
            proteinBindingPct: row.proteinBindingPct, doseInStudyMg: row.doseInStudyMg,
            subjectN: row.subjectN, demographics: row.demographics, species: row.species,
            sourceSlug: row.sourceSlug, doi: row.doi, pmid: row.pmid, notes: row.notes,
            confidence: Swift.min(row.confidence, ceiling),
        )
    }

    /// Apply the reference-substance PK borrow (the derivation layer). If the subject has a
    /// `pk_reference` and the referenced fields are absent, resolve the surrogate and merge its rows:
    /// **whole-row borrow** when the subject has ZERO pk rows (the 2-MMC case), else a **per-field
    /// top-up** of the individually-null borrowable fields. Every borrowed field's confidence is floored
    /// to `min(referenceRowConfidence, pointerConfidence)`. **Single-hop + visited-set** — a reference
    /// that itself carries a `pk_reference` is refused (no transitive borrow). Returns the subject's own
    /// rows unchanged when no borrow applies.
    nonisolated static func applyPKReference(
        ownRows: [PKRouteHit], subjectID: Int64?, db queue: DatabaseQueue,
        resolveReferenceID: (String) -> Int64?,
    ) -> [PKRouteHit] {
        guard let subjectID, let ref = pkReference(substanceID: subjectID, db: queue),
              let referenceID = resolveReferenceID(ref.name), referenceID != subjectID else {
            return ownRows
        }
        // Single-hop: the surrogate must carry real PK, never another pointer.
        if pkReference(substanceID: referenceID, db: queue) != nil { return ownRows }
        let referenceRows = pharmacokineticsRows(substanceID: referenceID, db: queue)
        guard !referenceRows.isEmpty else { return ownRows }

        if ownRows.isEmpty {
            // Whole-row borrow: take the surrogate's rows, each floored to the pointer ceiling.
            return referenceRows.map { flooringConfidence($0, to: ref.confidence) }
        }

        // Per-field top-up: fill only the listed borrowable fields that are null on the subject's
        // coherent (Vd-first) row from the surrogate's coherent row.
        let referencePrimary = referenceRows.first { $0.vdLPerKg != nil } ?? referenceRows.first
        guard let referencePrimary,
              let subjectPrimary = ownRows.first(where: { $0.vdLPerKg != nil }) ?? ownRows.first
        else { return ownRows }
        let takeVd = ref.fields.contains("vd") && subjectPrimary.vdLPerKg == nil && referencePrimary.vdLPerKg != nil
        let takeF = ref.fields.contains("bioavailability") && subjectPrimary.bioavailabilityPct == nil && referencePrimary.bioavailabilityPct != nil
        let takeTmax = ref.fields.contains("tmax") && subjectPrimary.tmaxMin == nil && referencePrimary.tmaxMin != nil
        let takeHalfLife = ref.fields.contains("half_life") && subjectPrimary.halfLifeMin == nil && referencePrimary.halfLifeMin != nil
        guard takeVd || takeF || takeTmax || takeHalfLife else { return ownRows }
        let ceiling = Swift.min(referencePrimary.confidence, ref.confidence)
        let merged = PKRouteHit(
            id: subjectPrimary.id, route: subjectPrimary.route,
            bioavailabilityPct: takeF ? referencePrimary.bioavailabilityPct : subjectPrimary.bioavailabilityPct,
            cmaxNgPerMl: subjectPrimary.cmaxNgPerMl,
            tmaxMin: takeTmax ? referencePrimary.tmaxMin : subjectPrimary.tmaxMin,
            halfLifeMin: takeHalfLife ? referencePrimary.halfLifeMin : subjectPrimary.halfLifeMin,
            vdLPerKg: takeVd ? referencePrimary.vdLPerKg : subjectPrimary.vdLPerKg,
            clearanceMlPerMinPerKg: subjectPrimary.clearanceMlPerMinPerKg,
            proteinBindingPct: subjectPrimary.proteinBindingPct, doseInStudyMg: subjectPrimary.doseInStudyMg,
            subjectN: subjectPrimary.subjectN, demographics: subjectPrimary.demographics,
            // A borrowed Vd carries the surrogate's species flag so scaledToHuman floors it correctly.
            species: takeVd ? referencePrimary.species : subjectPrimary.species,
            sourceSlug: subjectPrimary.sourceSlug, doi: subjectPrimary.doi, pmid: subjectPrimary.pmid,
            notes: subjectPrimary.notes, confidence: Swift.min(subjectPrimary.confidence, ceiling),
        )
        return ownRows.map { $0.id == subjectPrimary.id ? merged : $0 }
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

    /// Assemble the occupancy-pipeline inputs from already-read rows. `nonisolated static` so the
    /// cached instance path and the off-main batch path share identical resolution logic.
    private nonisolated static func assemblePharmacologyParameters(
        name: String, molarMass: Double?, pk: [PKRouteHit], bindingHits: [BindingHit],
        doseScale: Double = 1, doseScaleConfidence: ConfidenceTier = .high,
        referenceDoseMg: Double? = nil, intrinsicEfficacy: Double = 1,
        categoryClasses: Set<ReceptorClasses.ReceptorClass> = [],
    ) -> PharmacologyParameters {
        // Read Vd, F, and half-life from a SINGLE coherent pk row — never pair a Vd from one study
        // with an F or half-life from another. That cross-pairing silently double-counts F when a
        // stored "Vd" is actually an apparent V/F (e.g. MDMA, where no IV arm exists): C = F·dose/(V/F·wt)
        // would embed F twice. Prefer the highest-confidence row that carries a Vd (pharmacokinetics()
        // is oral-first, so .first is deterministic); fall back to the best row for half-life only when
        // no Vd exists (occupancy needs a Vd regardless, so it stays uncomputable — correct).
        let vdRows = pk.filter { $0.vdLPerKg != nil }
        let primaryRow = vdRows.first { $0.confidence != .unverified }
            ?? vdRows.first
            ?? pk.first { $0.confidence != .unverified }
            ?? pk.first
        // Interspecies allometric projection (the derivation layer). A non-human coherent row keeps its
        // species-invariant Vd/kg but has clearance/half-life scaled to a 70 kg human and its confidence
        // floored (see `scaledToHuman`). Applied right after the coherent-row pick so every downstream
        // read (Vd, F, half-life) sees the human-projected, honestly-badged values.
        let scaledPrimary = primaryRow.map { Self.scaledToHuman($0) }
        let pkSpecies = primaryRow?.species
        let primaryIsNonHuman = (primaryRow?.species.map { $0 != "human" } ?? false)
        let vd = scaledPrimary?.vdLPerKg
        // Bioavailability: use the measured F when the coherent row carries one; otherwise default to
        // 1.0 (full fraction-absorbed), flagged `.unverified`. Absolute oral F is underivable without
        // an IV arm for most recreational drugs, and their stored Vd is an apparent V/F — so F = 1 is
        // the *consistent* reading (the F cancels in C = F·dose/((V/F)·wt)), never an invented number.
        // See `PharmacologyParameters.bioavailabilityFraction`.
        let measuredF = scaledPrimary?.bioavailabilityPct.map { $0 / 100 }
        let f = measuredF ?? 1.0
        let fConfidence: ConfidenceTier = measuredF != nil ? (scaledPrimary?.confidence ?? .unverified) : .unverified
        // Half-life: a *measured human* t½ from any row ALWAYS wins over a scaled animal one — single-
        // species allometric scaling underpredicts cathinone t½ ~2–3× (mephedrone rat-scaled 65 vs human
        // 129 min; 3-MMC pig-scaled 55 vs human 180 min). Only override when the coherent Vd row is
        // itself non-human; otherwise the picked (human/unflagged) row's own t½ stands.
        let humanHalfLife: Double? = primaryIsNonHuman
            ? (
                pk.first { $0.species == "human" && $0.halfLifeMin != nil && $0.confidence != .unverified }?.halfLifeMin
                    ?? pk.first { $0.species == "human" && $0.halfLifeMin != nil }?.halfLifeMin
            )
            : nil
        let halfLife = humanHalfLife ?? scaledPrimary?.halfLifeMin

        // Time-to-peak for a real absorption rate (§3): a measured human Tmax wins over an animal one
        // (same discipline as half-life); otherwise the coherent primary row's own Tmax, else the best-
        // graded PK row that carries one. Tmax is a rate descriptor independent of the F/Vd apparent-V/F
        // coupling, so borrowing it from another row (when the primary lacks one) is safe.
        let tmaxRow = (primaryIsNonHuman ? pk.first { $0.species == "human" && $0.tmaxMin != nil } : nil)
            ?? (
                (primaryRow?.tmaxMin != nil)
                    ? primaryRow
                    : (pk.first { $0.confidence != .unverified && $0.tmaxMin != nil } ?? pk.first { $0.tmaxMin != nil })
            )
        let tmax = tmaxRow?.tmaxMin
        let tmaxConfidence: ConfidenceTier = tmax != nil ? (tmaxRow?.confidence ?? .unverified) : .unverified

        var seenTargets = Set<String>()
        let targets = bindingHits.compactMap { b -> PharmacologyParameters.TargetEngagement? in
            guard let action = BindingAction(rawValue: b.action) else { return nil }
            // Half-saturation constant for the Hill occupancy curve, by mechanism: Kᵢ (binding) is
            // preferred because it *is* fractional receptor occupancy; EC₅₀ (functional release) and
            // IC₅₀ (reuptake inhibition) are used only when no Kᵢ exists. Do not "promote" EC₅₀ over a
            // present Kᵢ — for LSD that would swap 4 nM for 261 nM (~65× different occupancy).
            let halfMax: Double?
            let kind: PharmacologyParameters.HalfMaxKind
            if let ki = b.kiNm { halfMax = ki; kind = .ki } else if let ec = b.ec50Nm { halfMax = ec; kind = .ec50 } else if let ic = b.ic50Nm { halfMax = ic; kind = .ic50 } else { halfMax = nil; kind = .ki }
            guard let halfMax, halfMax > 0 else { return nil }
            let citationKey = b.doi.map { "doi:\($0)" } ?? b.pmid.map { "pmid:\($0)" }
            return .init(
                target: b.target, action: action, halfMaxNanomolar: halfMax,
                kind: kind, confidence: b.confidence,
                sourceSlug: b.sourceSlug, citationKey: citationKey, species: b.species,
            )
        }
        // Tightest (most potent) first, then collapse duplicate target+action+kind rows (which a
        // future substance-merge could introduce, since bindings has no DB-level dedup) so each
        // engaged target appears once and `TargetEngagement.id` stays unique for any ForEach.
        .sorted { $0.halfMaxNanomolar < $1.halfMaxNanomolar }
        .filter { seenTargets.insert($0.id).inserted }

        // Vd resolution with a class-default fallback (meta-plan Foundation A — "tier-mapped fallback
        // elsewhere"). A graded Vd is always preferred; when none exists but the substance engages a
        // classifiable target, fall back to that receptor class's CNS-distribution default (e.g. LSD,
        // which the evidence run left without a Vd) so the tolerance engine can still resolve occupancy
        // library-wide — flagged `.unverified` so the UI badges exactly how much to trust it. Without a
        // graded Vd *and* without a classifiable target there is nothing to stand in for, so it stays
        // nil (occupancy uncomputable — correct).
        let resolvedVd: Double?
        let resolvedVdConfidence: ConfidenceTier
        if let vd {
            resolvedVd = vd
            // The scaled row's confidence — floored to `.low` for a non-human Vd, so an allometric
            // class-default Vd never masquerades as a measured human one.
            resolvedVdConfidence = scaledPrimary?.confidence ?? .unverified
        } else if let primaryTarget = targets.first {
            // Target-only classification: the Vd fallback is about CNS distribution, not tolerance
            // mechanism, so it must not be gated by the binding *direction* (an antagonist primary
            // still distributes like its receptor class).
            resolvedVd = ReceptorClasses.parameters(forTarget: primaryTarget.target).classDefaultVdLPerKg
            resolvedVdConfidence = .unverified
        } else {
            resolvedVd = nil
            resolvedVdConfidence = .unverified
        }

        return PharmacologyParameters(
            substanceName: name,
            molarMassGramsPerMole: molarMass,
            vdLPerKg: resolvedVd,
            bioavailabilityFraction: f,
            bioavailabilityConfidence: fConfidence,
            doseScale: doseScale,
            doseScaleConfidence: doseScaleConfidence,
            halfLifeMinutes: halfLife,
            vdConfidence: resolvedVdConfidence,
            referenceDoseMg: referenceDoseMg,
            // Per-substance serotonin-synthesis suppression (§3.4): set by membership in the curated
            // entactogen set, so MDMA-type releasers route onto the weeks-scale synthesis pool while
            // the cathinones (spared synthesis) reset in days. Both resolver paths funnel through here.
            suppressesSerotoninSynthesis: ToleranceStore.serotoninSynthesisSuppressors.contains(name.lowercased()),
            targets: targets,
            tmaxMinutes: tmax,
            tmaxConfidence: tmaxConfidence,
            intrinsicEfficacy: intrinsicEfficacy,
            categoryClasses: categoryClasses,
            pkSpecies: pkSpecies,
        )
    }

    /// Metabolism rows (enzymes/pathways + metabolites) for a substance, with
    /// per-row citation. Ordered by fraction-of-clearance (largest first), then
    /// enzyme name. Drives the Pharmacokinetics disclosure's metabolism block.
    func metabolism(forSubstanceName name: String) -> [MetabolismHit] {
        guard let substanceID = substanceID(forNameOrAlias: name) else { return [] }
        do {
            return try substancesDB.read { db in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT m.id, m.enzyme, m.fraction_of_clearance_pct, m.metabolite_name,
                           ms.canonical_name AS metabolite_substance_name,
                           m.metabolite_active, m.metabolite_potency_vs_parent_pct,
                           m.metabolite_potency_basis, m.metabolite_potency_target,
                           m.metabolite_mechanism_vs_parent, m.metabolite_half_life_min,
                           m.formation_fraction_pct, m.route, m.notes,
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
                    MetabolismHit(
                        id: row["id"],
                        enzyme: row["enzyme"],
                        fractionOfClearancePct: row["fraction_of_clearance_pct"],
                        metaboliteName: row["metabolite_name"],
                        metaboliteSubstanceName: row["metabolite_substance_name"],
                        metaboliteActive: (row["metabolite_active"] as Int64?).map { $0 != 0 },
                        metabolitePotencyVsParentPct: row["metabolite_potency_vs_parent_pct"],
                        metabolitePotencyBasis: (row["metabolite_potency_basis"] as String?)
                            .flatMap(MetabolitePotencyBasis.init(rawValue:)),
                        metabolitePotencyTarget: row["metabolite_potency_target"],
                        // Unrecognized or absent both mean "not established to be
                        // a scaled copy", which must fail `canScaleParentEffect`.
                        metaboliteMechanismVsParent: (row["metabolite_mechanism_vs_parent"] as String?)
                            .flatMap(MetaboliteMechanism.init(rawValue:)) ?? .unknown,
                        // Own record first, scalar column only when we don't carry the
                        // metabolite as a substance (norfluoxetine, cotinine, dextrorphan).
                        metaboliteHalfLifeMinutes: (row["metabolite_own_half_life_min"] as Double?)
                            ?? (row["metabolite_half_life_min"] as Double?),
                        formationFractionPct: row["formation_fraction_pct"],
                        route: row["route"],
                        sourceSlug: row["source_slug"],
                        doi: row["doi"],
                        pmid: (row["pmid"] as Int64?).map(Int.init),
                        notes: row["notes"],
                    )
                }
            }
        } catch {
            logger.error("metabolism(forSubstanceName:) failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Distinct binding targets sorted by how many substances hit them.
    /// Powers an autocomplete / chip picker in the advanced-search UI.
    func availableBindingTargets() -> [(target: String, substanceCount: Int)] {
        do {
            return try substancesDB.read { db in
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

    /// Resolve one representative pharmacokinetic row per substance for the Pharma table tool, **off the
    /// main actor**. Snapshots the resolved library (canonical name + source-priority category + top-level
    /// half-life) on the main actor, then runs a single windowed SQL pass over `pk_routes` on the batch
    /// connection to pick the preferred route per substance (oral first, else the row carrying the most PK
    /// fields, best confidence). Substances with no `pk_routes` row keep their top-level half-life; rows
    /// with no PK signal at all are dropped. The result is cache-worthy — recomputing per keystroke is not.
    func pharmaTableRowsOffMain() async -> [PharmaTableRow] {
        let substances: [PharmaSubstanceSeed] = SubstanceLibrary.all.compactMap { substance in
            guard let id = substanceID(forNameOrAlias: substance.name) else { return nil }
            // Cheap main-actor mechanism/class label (pure ``MechanismOfActionDatabase`` dictionary
            // lookups — no heavy per-substance DB resolve): the per-substance class template if one is
            // mapped, else the category fallback. Feeds the table's default Mechanism column and widens
            // the inclusion gate so categorised-but-PK-less substances still appear.
            let mechanism = MechanismOfActionDatabase.mechanism(for: substance.name)
                ?? MechanismOfActionDatabase.categoryFallback(for: substance.category)
            let mechanismLabel: String? = (mechanism?.summary).flatMap { $0.isEmpty ? nil : $0 }
            return PharmaSubstanceSeed(
                id: id, name: substance.name, category: substance.category,
                mechanismLabel: mechanismLabel, halfLifeMin: substance.halfLifeMinutes,
            )
        }
        let db = substancesBatchDB
        return await Task.detached(priority: .utility) {
            Self.buildPharmaTableRows(substances: substances, db: db)
        }.value
    }

    /// Immutable main-actor snapshot handed to the off-main resolve: the resolved identity + half-life
    /// fallback for one substance, keyed by its bundled-DB id (used to join the `pk_routes` pass).
    private struct PharmaSubstanceSeed {
        let id: Int64
        let name: String
        let category: SubstanceCategory
        let mechanismLabel: String?
        let halfLifeMin: Double?
    }

    /// The single windowed `pk_routes` pass + merge. `nonisolated static` so it runs entirely off the main
    /// actor on the batch connection. `ROW_NUMBER()` partitioned by substance picks the preferred route in
    /// one query (SQLite window functions), so there is no per-substance read loop.
    private nonisolated static func buildPharmaTableRows(
        substances: [PharmaSubstanceSeed], db queue: DatabaseQueue,
    ) -> [PharmaTableRow] {
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
            logger.error("buildPharmaTableRows failed: \(error.localizedDescription, privacy: .public)")
        }

        var out: [PharmaTableRow] = []
        out.reserveCapacity(substances.count)
        for substance in substances {
            let pk = pkByID[substance.id]
            let halfLife: Double? = pk.flatMap { $0["half_life_min"] } ?? substance.halfLifeMin
            let row = PharmaTableRow(
                name: substance.name,
                category: substance.category,
                route: pk.flatMap { $0["route"] },
                mechanismLabel: substance.mechanismLabel,
                halfLifeMin: halfLife,
                tmaxMin: pk.flatMap { $0["tmax_min"] },
                bioavailabilityPct: pk.flatMap { $0["bioavailability_pct"] },
                cmaxNgPerMl: pk.flatMap { $0["cmax_ng_per_ml"] },
                proteinBindingPct: pk.flatMap { $0["protein_binding_pct"] },
                vdLPerKg: pk.flatMap { $0["vd_l_per_kg"] },
                clearanceMlPerMinPerKg: pk.flatMap { $0["clearance_ml_per_min_per_kg"] },
            )
            if row.hasAnyData { out.append(row) }
        }
        return out
    }
}
