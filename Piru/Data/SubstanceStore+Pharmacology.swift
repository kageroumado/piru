import Foundation
import GRDB
import os

private nonisolated let logger = Logger(subsystem: "dev.yumeji.piru", category: "SubstanceStore")

/// The pharmacology / pharmacokinetics read layer extracted from `SubstanceStore`: the per-substance
/// binding, PK, molar-mass, metabolism, and resolved `PharmacologyParameters` reads. Split out so the
/// core store stays under the file-length budget; the off-main batch resolve (`pharmacologyParametersBatchOffMain`)
/// lives here alongside the cached interactive accessors it shares assembly logic with.
extension SubstanceStore {
    /// Every binding row associated with a specific substance, resolved by
    /// canonical name. Used by the detail view's "Receptor Literature"
    /// disclosure (pharma-nerd tier) to show the full Ki/EC50 table with
    /// per-row source attribution. Returns rows sorted by tightest Ki first.
    func bindings(forSubstanceName name: String) -> [BindingHit] {
        guard let substanceID = substanceID(forNameOrAlias: name) else { return [] }
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
                           p.notes, p.confidence, src.slug AS source_slug, c.doi, c.pmid
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
        let referenceDoseMg = substanceID(forNameOrAlias: name).flatMap {
            Self.referenceDoseMg(substanceID: $0, db: substancesDB, order: enabledSourceOrder)
        }
        return Self.assemblePharmacologyParameters(
            name: name,
            molarMass: molarMass(forSubstanceName: routed.name),
            pk: pharmacokinetics(forSubstanceName: routed.name),
            bindingHits: bindings(forSubstanceName: routed.name),
            doseScale: routed.scale,
            doseScaleConfidence: routed.confidence,
            referenceDoseMg: referenceDoseMg,
            // §5c: keyed on the active compound (Kratom→Mitragynine), defaulting to full-agonist 1.0.
            intrinsicEfficacy: ToleranceStore.intrinsicEfficacyByName[routed.name.lowercased()] ?? 1,
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
            let referenceDoseMg = referenceDoseIDs[name.lowercased()].flatMap {
                Self.referenceDoseMg(substanceID: $0, db: queue, order: order)
            }
            out[name] = assemblePharmacologyParameters(
                name: name,
                molarMass: id.flatMap { molarMass(substanceID: $0, db: queue) },
                pk: id.map { pharmacokineticsRows(substanceID: $0, db: queue) } ?? [],
                bindingHits: id.map { bindingRows(substanceID: $0, db: queue) } ?? [],
                doseScale: routed.scale,
                doseScaleConfidence: routed.confidence,
                referenceDoseMg: referenceDoseMg,
                intrinsicEfficacy: ToleranceStore.intrinsicEfficacyByName[routed.name.lowercased()] ?? 1,
            )
        }
        return out
    }

    /// Assemble the occupancy-pipeline inputs from already-read rows. `nonisolated static` so the
    /// cached instance path and the off-main batch path share identical resolution logic.
    private nonisolated static func assemblePharmacologyParameters(
        name: String, molarMass: Double?, pk: [PKRouteHit], bindingHits: [BindingHit],
        doseScale: Double = 1, doseScaleConfidence: ConfidenceTier = .high,
        referenceDoseMg: Double? = nil, intrinsicEfficacy: Double = 1,
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
        let vd = primaryRow?.vdLPerKg
        // Bioavailability: use the measured F when the coherent row carries one; otherwise default to
        // 1.0 (full fraction-absorbed), flagged `.unverified`. Absolute oral F is underivable without
        // an IV arm for most recreational drugs, and their stored Vd is an apparent V/F — so F = 1 is
        // the *consistent* reading (the F cancels in C = F·dose/((V/F)·wt)), never an invented number.
        // See `PharmacologyParameters.bioavailabilityFraction`.
        let measuredF = primaryRow?.bioavailabilityPct.map { $0 / 100 }
        let f = measuredF ?? 1.0
        let fConfidence: ConfidenceTier = measuredF != nil ? (primaryRow?.confidence ?? .unverified) : .unverified
        let halfLife = primaryRow?.halfLifeMin

        // Time-to-peak for a real absorption rate (§3): prefer the coherent primary row's own Tmax, else
        // the best-graded PK row that carries one. Tmax is a rate descriptor independent of the F/Vd
        // apparent-V/F coupling, so borrowing it from another row (when the primary lacks one) is safe.
        let tmaxRow = (primaryRow?.tmaxMin != nil)
            ? primaryRow
            : (pk.first { $0.confidence != .unverified && $0.tmaxMin != nil } ?? pk.first { $0.tmaxMin != nil })
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
            return .init(
                target: b.target, action: action, halfMaxNanomolar: halfMax,
                kind: kind, confidence: b.confidence,
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
            resolvedVdConfidence = primaryRow?.confidence ?? .unverified
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
                           m.metabolite_active, m.metabolite_potency_vs_parent_pct, m.notes,
                           src.slug AS source_slug, c.doi, c.pmid
                      FROM metabolism m
                      JOIN sources src ON src.id = m.source_id
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
                        metaboliteActive: (row["metabolite_active"] as Int64?).map { $0 != 0 },
                        metabolitePotencyVsParentPct: row["metabolite_potency_vs_parent_pct"],
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
}
