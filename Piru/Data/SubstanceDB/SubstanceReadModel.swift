import Foundation
import GRDB
import os

private nonisolated let logger = Logger(subsystem: "dev.yumeji.piru", category: "SubstanceStore")

/// The app's resolved content language for substance text. The requested side
/// of locale resolution — stored rows may also be `und` (undetermined), which
/// the resolver treats as an English-tier fallback. Carries the SQL fragments
/// for locale-first text resolution so every text table resolves the same way.
nonisolated enum ContentLanguage: String {
    case en
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"

    var isChinese: Bool {
        self != .en
    }

    /// Derive from the app's preferred localization (follows a per-app language
    /// override, not just the device language). Computed once per process —
    /// `preferredLocalizations` allocates on every call, this sat on the
    /// per-row render path, and iOS relaunches the app when its language
    /// changes, so the value cannot go stale.
    static let current: ContentLanguage = {
        let pref = (Bundle.main.preferredLocalizations.first ?? "en").lowercased()
        guard pref.hasPrefix("zh") else { return .en }
        if pref.contains("hant") || pref.contains("tw") || pref.contains("hk") || pref.contains("mo") {
            return .zhHant
        }
        return .zhHans
    }()

    /// Language-aware `WHERE`/`ORDER BY` fragments for a text table's `language`
    /// column. In Chinese, matching-language text floats above source priority
    /// (exact variant first, then any zh), falling back to English when no zh
    /// row exists. In English, raw zh is excluded — only English (and FreeOD's
    /// machine-translated en rows) show. `rawValue` is a fixed enum literal, so
    /// interpolating it carries no injection risk.
    func clauses(column col: String) -> (whereAnd: String, orderPrefix: String) {
        if isChinese {
            return ("", "(\(col) = '\(rawValue)') DESC, (\(col) LIKE 'zh%') DESC, ")
        }
        return (" AND \(col) IN ('en', 'und') ", "")
    }
}

/// Source-priority-aware resolution over the bundled substances DB: one value
/// snapshot of the inputs every resolver depends on — the connection, the
/// user's enabled-source order, and the content language — with the resolvers
/// as methods. ``SubstanceStore`` constructs one per resolve
/// (``SubstanceStore/reader``) and keeps for itself what a snapshot cannot own:
/// identity (the name/alias/uid indexes), the caches, connection lifecycle,
/// and user prefs.
///
/// **A new read path goes here** — a method on this type (or a
/// `SubstanceReadModel+<Concern>.swift` extension for a whole concern), keyed
/// by substance id, with its row struct as a top-level type beside it. A
/// `SubstanceStore` extension is only for API that needs the store's indexes
/// or caches, and then it delegates the SQL to this type. The store grew to
/// its lint ceiling precisely by hosting resolvers directly; the split-brain
/// rule above is what keeps that from recurring.
///
/// **Enabled-source policy** — the two kinds of content fail differently, on
/// purpose:
/// - **Prose fails open.** Text resolvers (``resolvedTextRow(db:from:selecting:substanceID:)``
///   and callers) run a strict enabled-source pass, then retry without the
///   enabled-source filter. Prose is inert reference content whose provenance
///   badge names the source; a blank overview is strictly worse, and the
///   relaxed pass also covers the empty-order launch window before source
///   prefs load.
/// - **Structured values fail closed.** Dose ladders, routes, category,
///   half-life, and equivalence tables resolve only from enabled sources —
///   they feed calculations and safety-relevant displays, so a value from a
///   source the user explicitly disabled must never leak in. Disabling every
///   source therefore legitimately blanks doses/durations while descriptions
///   remain.
/// A new resolver picks its side by that test (does the value drive behavior,
/// or is it read as text?), not by copying the nearest query.
struct SubstanceReadModel {
    /// Foreground (UI-interactive) connection — the queries a tap is waiting on.
    let db: DatabaseQueue
    /// Enabled source slugs, highest priority first.
    let order: [String]
    /// The language text fields resolve locale-first for.
    let language: ContentLanguage

    // MARK: - Source-priority SQL fragments

    var priorityCaseSQL: String {
        Self.priorityCaseSQL(order)
    }

    var enabledSourceListSQL: String {
        Self.enabledSourceListSQL(order)
    }

    /// Pure SQL builders, parameterised by the enabled-source order so they can
    /// run on a background thread during the off-main batch prewarm (see
    /// ``loadAllSubstancesBatch(db:order:)``) as well as from the main-actor
    /// per-substance resolvers.
    ///
    /// These are rebuilt on *every* `substance`/`resolveRoutes` call (and
    /// several times within each), yet the enabled-source order changes only
    /// when the user reorders sources — so the string-building (per-slug escape +
    /// join) showed up in launch profiles. A single-entry memo keyed by the
    /// order (value-compared, cheaper than rebuilding) collapses the repeats.
    /// The lock keeps it correct across the main-actor resolvers and the
    /// off-main batch prewarm sharing the same `static`.
    private nonisolated struct SourceOrderSQL {
        let order: [String]
        let priorityCase: String
        let enabledList: String
    }

    private nonisolated static let sourceOrderSQLMemo = OSAllocatedUnfairLock<SourceOrderSQL?>(initialState: nil)

    private nonisolated static func sourceOrderSQL(_ order: [String]) -> SourceOrderSQL {
        sourceOrderSQLMemo.withLock { memo in
            if let memo, memo.order == order { return memo }
            let built = SourceOrderSQL(
                order: order,
                priorityCase: buildPriorityCaseSQL(order),
                enabledList: buildEnabledSourceListSQL(order),
            )
            memo = built
            return built
        }
    }

    /// Builds a `CASE src.slug WHEN ... THEN ... END` expression that maps
    /// enabled source slugs to their priority rank. Used in `ORDER BY`.
    nonisolated static func priorityCaseSQL(_ order: [String]) -> String {
        sourceOrderSQL(order).priorityCase
    }

    nonisolated static func enabledSourceListSQL(_ order: [String]) -> String {
        sourceOrderSQL(order).enabledList
    }

    private nonisolated static func buildPriorityCaseSQL(_ order: [String]) -> String {
        guard !order.isEmpty else {
            return "999"
        }
        let cases = order.enumerated().map { idx, slug in
            "WHEN '\(slug.replacingOccurrences(of: "'", with: "''"))' THEN \(idx)"
        }.joined(separator: " ")
        return "CASE src.slug \(cases) ELSE 999 END"
    }

    private nonisolated static func buildEnabledSourceListSQL(_ order: [String]) -> String {
        if order.isEmpty { return "''" }
        return order.map { "'\($0.replacingOccurrences(of: "'", with: "''"))'" }.joined(separator: ", ")
    }

    /// The app's effective UI language, normalized to a content-language tag
    /// ('zh-Hans' | 'zh-Hant' | 'en'). Drives locale-first text resolution so a
    /// Chinese source (FreeOD Wiki) wins for descriptions/effects when the app
    /// runs in Chinese. Reads `preferredLocalizations` so it follows the app's
    /// per-app language override, not just the device language.
    nonisolated static var contentLanguage: ContentLanguage {
        .current
    }

    // MARK: - Shared vocabulary

    /// Decodes a curated JSON-blob TEXT column (e.g. `popular_aliases`,
    /// `misconceptions`) into a Codable type. Returns nil for a NULL/empty
    /// column or malformed JSON — a bad blob degrades the affected section to
    /// absent rather than failing the whole substance resolve.
    private static func decodeJSONBlob<T: Decodable>(_: T.Type, _ raw: String?) -> T? {
        guard let raw, let data = raw.data(using: .utf8), !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    nonisolated static func rangeFrom(lower: Double?, upper: Double?) -> ClosedRange<Double>? {
        guard let lo = lower, let hi = upper, lo <= hi else { return nil }
        return lo ... hi
    }

    /// Rank routes by `RouteOfAdministration.allCases` order — oral first,
    /// sublingual second, intravenous mid-list, etc. — so substances default
    /// to the route a typical user would log first.
    private nonisolated static let routeRanks: [RouteOfAdministration: Int] = Dictionary(
        uniqueKeysWithValues: RouteOfAdministration.allCases.enumerated().map { ($1, $0) },
    )
    nonisolated static func routeRank(_ r: RouteOfAdministration) -> Int {
        routeRanks[r] ?? Int.max
    }

    /// Canonical key for collapsing near-synonymous binding targets in the
    /// mechanism *summary* — "NMDA receptor" → "nmda", so a measured row doesn't
    /// double-list a curated target. Strips a trailing "receptor(s)" word,
    /// lowercases, and collapses whitespace. Subunit-specific names
    /// ("GABA-A α4β3δ (extrasynaptic)") stay distinct from the coarse target.
    static func normalizedBindingTarget(_ target: String) -> String {
        // ReceptorTargetKey.fold drops a non-leading assay/qualifier
        // parenthetical and a trailing " receptor(s)", so a measured row stated
        // under a wordier name ("DAT (release, [3H]-DA …)", "α2δ-1 (porcine
        // cortex)", "NMDA receptor (PCP site)") collapses onto its clean
        // canonical target ("dat", "α2δ-1", "nmda") — the graded flagship rows
        // use the bare target name, the enrichment layer often appends the
        // assay in parens. A target that opens with a parenthetical keeps it:
        // it is the whole name, and stripping it made an empty dedup key.
        ReceptorTargetKey.fold(target)
    }

    // MARK: - The full per-substance record

    /// The fully-resolved record for one substance — every per-field resolver
    /// run under this snapshot's source order and language. Uncached and
    /// ~21 SQL per call; ``SubstanceStore/resolveSubstance`` is the cached
    /// entry, and `editorialColumns` is the store's per-DB column probe
    /// (an older OTA-applied copy may predate some curated columns).
    func substance(id: Int64, editorialColumns ec: Set<String>) -> Substance? {
        // Include each curated editorial column only when the opened DB actually
        // has it — an older OTA-applied copy may predate some of them.
        let editorialColumns = ["popular_aliases", "misconceptions", "combinations", "water_heat"]
            .filter { ec.contains($0) }
            .map { ", \($0)" }
            .joined()

        do {
            return try db.read { db -> Substance? in
                guard let coreRow = try Row.fetchOne(db, sql: "SELECT canonical_name, display_name, display_class, regulatory_status, duration_implausible, substance_uid, cas, inchikey, formula, pubchem_cid, molecular_weight, popularity, is_stub, drug_community_slug, freeodwiki_slug, smiles, iupac_name, logp, tpsa, hba, hbd, ld50_oral_mg_per_kg, ld50_dermal_mg_per_kg, melting_point_c, boiling_point_c\(editorialColumns) FROM substances WHERE id = ?", arguments: [id]) else {
                    return nil
                }
                let name: String = coreRow["canonical_name"]
                let displayName: String? = coreRow["display_name"]
                let displayClass = (coreRow["display_class"] as String?).flatMap(CompoundDisplayClass.init(rawValue:)) ?? .recreational
                let regulatoryStatus: String? = coreRow["regulatory_status"]
                let durationImplausible = (coreRow["duration_implausible"] as Int64? ?? 0) != 0
                let substanceUID: String? = coreRow["substance_uid"]
                let cas: String? = coreRow["cas"]
                let inchikey: String? = coreRow["inchikey"]
                let formula: String? = coreRow["formula"]
                let pubchemCID = (coreRow["pubchem_cid"] as Int64?).map(Int.init)
                let molarMass = coreRow["molecular_weight"] as Double?
                let popularity = coreRow["popularity"] as Double? ?? 0
                let isStub = (coreRow["is_stub"] as Int64? ?? 0) != 0
                let drugCommunitySlug: String? = coreRow["drug_community_slug"]
                let freeodwikiSlug: String? = coreRow["freeodwiki_slug"]
                let smiles: String? = coreRow["smiles"]
                let iupacName: String? = coreRow["iupac_name"]
                // Curated editorial JSON blobs (piru-curated, popular-substances
                // only; empty for the long tail). Decoded defensively — a
                // malformed blob degrades to absent, never a throw.
                //
                // NOTE (localization): these are stored English-only in a single
                // column, unlike `overview`/effects/mechanism which resolve by
                // `language:`. zh-Hans/zh-Hant users see English claim/correction
                // prose until translated. When authoring scales past English, move
                // to a language-keyed store (mirror `mechanisms_summary`'s
                // language PK) — a pipeline + reader change + wholesale rebuild,
                // not a user-data migration (the substance DB is a build artifact).
                let popularAliases = ec.contains("popular_aliases") ? Self.decodeJSONBlob([String].self, coreRow["popular_aliases"]) ?? [] : []
                let misconceptions = ec.contains("misconceptions") ? Self.decodeJSONBlob([MythBust].self, coreRow["misconceptions"]) ?? [] : []
                let combinations = ec.contains("combinations") ? Self.decodeJSONBlob([Combination].self, coreRow["combinations"]) ?? [] : []
                let waterHeat = ec.contains("water_heat") ? Self.decodeJSONBlob(WaterHeatGuidance.self, coreRow["water_heat"]) : nil
                let physicochemical = Physicochemical(
                    logP: coreRow["logp"] as Double?,
                    tpsa: coreRow["tpsa"] as Double?,
                    hba: (coreRow["hba"] as Int64?).map(Int.init),
                    hbd: (coreRow["hbd"] as Int64?).map(Int.init),
                    ld50OralMgPerKg: coreRow["ld50_oral_mg_per_kg"] as Double?,
                    ld50DermalMgPerKg: coreRow["ld50_dermal_mg_per_kg"] as Double?,
                    meltingPointC: coreRow["melting_point_c"] as Double?,
                    boilingPointC: coreRow["boiling_point_c"] as Double?,
                )

                // Brand names first, flagship brands ahead of form brands, then
                // alphabetical — see the batch path (D.1.7 + brand_rank).
                let aliases = try String.fetchAll(db, sql: "SELECT alias FROM aliases WHERE substance_id = ? ORDER BY COALESCE(brand_rank, 9), alias", arguments: [id])
                let peptideProfile = try resolvedPeptideProfile(db: db, substanceID: id)
                let references = try resolvedReferences(db: db, substanceID: id)

                let category = try resolvedCategory(db: db, substanceID: id)
                let tags = try resolvedTags(db: db, substanceID: id)
                var routes = try resolvedRoutes(db: db, substanceID: id)
                let effects = try resolvedEffects(db: db, substanceID: id)
                let subjectiveEffects = try resolvedSubjectiveEffects(db: db, substanceID: id)
                let halfLifeMinutes = try resolvedHalfLife(db: db, substanceID: id)
                let mechanism = try resolvedMechanism(db: db, substanceID: id)
                let overview = try resolvedDescription(db: db, substanceID: id)
                let sources = try citedSources(db: db, substanceID: id)
                let toleranceInfo = try resolvedTolerance(db: db, substanceID: id)
                let indications = try resolvedIndications(db: db, substanceID: id)
                let contraindications = try resolvedContraindications(db: db, substanceID: id)
                let diazepamEquivalent = try resolvedDiazepamEquivalent(db: db, substanceID: id)

                routes.sort { Self.routeRank($0.route) < Self.routeRank($1.route) }
                let defaultRoute = routes.first?.route
                    ?? RouteOfAdministration.from(string: tags.contains("inhalation") ? "inhalation" : "oral")

                return Substance(
                    name: name,
                    displayName: displayName,
                    aliases: aliases,
                    category: category ?? .other,
                    defaultRoute: defaultRoute,
                    routes: routes,
                    effects: effects,
                    subjectiveEffects: subjectiveEffects,
                    toleranceInfo: toleranceInfo,
                    halfLifeMinutes: halfLifeMinutes,
                    sources: sources,
                    mechanismOfAction: mechanism,
                    tags: tags,
                    displayClass: displayClass,
                    regulatoryStatus: regulatoryStatus,
                    durationImplausible: durationImplausible,
                    indications: indications,
                    contraindications: contraindications,
                    diazepamEquivalent: diazepamEquivalent,
                    substanceUID: substanceUID,
                    cas: cas,
                    inchikey: inchikey,
                    formula: formula,
                    pubchemCID: pubchemCID,
                    popularity: popularity,
                    isStub: isStub,
                    molarMass: molarMass,
                    peptideProfile: peptideProfile,
                    references: references,
                    drugCommunitySlug: drugCommunitySlug,
                    freeodwikiSlug: freeodwikiSlug,
                    overview: overview,
                    smiles: smiles,
                    iupacName: iupacName,
                    physicochemical: physicochemical.hasAnyValue ? physicochemical : nil,
                    popularAliases: popularAliases,
                    misconceptions: misconceptions,
                    combinations: combinations,
                    waterHeat: waterHeat,
                )
            }
        } catch {
            logger.error("SubstanceReadModel.substance(\(id, privacy: .public)) failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Per-field resolvers

    private func resolvedCategory(db: Database, substanceID: Int64) throws -> SubstanceCategory? {
        let row = try Row.fetchOne(db, sql: """
            SELECT c.category
              FROM categories c
              JOIN sources src ON src.id = c.source_id
             WHERE c.substance_id = ?
               AND src.slug IN (\(enabledSourceListSQL))
             ORDER BY (c.category = 'Other' AND src.slug != 'piru-curated') ASC,
                      \(priorityCaseSQL) ASC
             LIMIT 1
        """, arguments: [substanceID])
        guard let raw: String = row?["category"] else { return nil }
        return SubstanceCategory(rawValue: raw) ?? SubstanceCategory.from(tripSitCategory: raw)
    }

    private func resolvedTags(db: Database, substanceID: Int64) throws -> [String] {
        // Tags are additive — return the union across all enabled sources, hiding engine-consumed ones.
        try String.fetchAll(db, sql: """
            SELECT DISTINCT tag
              FROM tags t
              JOIN sources src ON src.id = t.source_id
             WHERE t.substance_id = ?
               AND src.slug IN (\(enabledSourceListSQL))
               AND t.hidden = 0
             ORDER BY tag
        """, arguments: [substanceID])
    }

    /// Clinical indications — additive union across enabled sources.
    private func resolvedIndications(db: Database, substanceID: Int64) throws -> [String] {
        try String.fetchAll(db, sql: """
            SELECT DISTINCT text
              FROM indications i
              JOIN sources src ON src.id = i.source_id
             WHERE i.substance_id = ?
               AND src.slug IN (\(enabledSourceListSQL))
             ORDER BY text
        """, arguments: [substanceID])
    }

    /// Contraindications + boxed warnings — boxed warnings sorted first.
    ///
    /// Grouped by content, not by row. A compound with several manufacturers has
    /// a DailyMed label per manufacturer, and each repeats the same
    /// contraindication under its own citation — so methylphenidate listed
    /// "Glaucoma" twice and "Known allergy to it" twice. One citation of the
    /// several is kept; they say the same thing.
    private func resolvedContraindications(db: Database, substanceID: Int64) throws -> [Contraindication] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT c.text, c.flag, c.is_boxed_warning, MIN(ci.url) AS url
              FROM contraindications c
              JOIN sources src ON src.id = c.source_id
              LEFT JOIN citations ci ON ci.id = c.citation_id
             WHERE c.substance_id = ?
               AND src.slug IN (\(enabledSourceListSQL))
             GROUP BY COALESCE(c.flag, c.text), c.is_boxed_warning
             ORDER BY c.is_boxed_warning DESC, COALESCE(c.text, c.flag)
        """, arguments: [substanceID])
        return rows.map {
            Contraindication(
                flag: ($0["flag"] as String?).flatMap(ContraindicationFlag.init(rawValue:)),
                text: $0["text"],
                isBoxedWarning: ($0["is_boxed_warning"] as Int64? ?? 0) != 0,
                sourceURL: $0["url"],
            )
        }
    }

    /// Diazepam-equivalency (benzodiazepines only) — highest-priority source.
    private func resolvedDiazepamEquivalent(db: Database, substanceID: Int64) throws -> DiazepamEquivalent? {
        guard let row = try Row.fetchOne(db, sql: """
            SELECT dose_mg, equivalent_diazepam_mg, display_text
              FROM diazepam_equivalents d
              JOIN sources src ON src.id = d.source_id
             WHERE d.substance_id = ?
               AND src.slug IN (\(enabledSourceListSQL))
             ORDER BY \(priorityCaseSQL) ASC
             LIMIT 1
        """, arguments: [substanceID]) else { return nil }
        return DiazepamEquivalent(
            doseMg: row["dose_mg"],
            equivalentDiazepamMg: row["equivalent_diazepam_mg"],
            displayText: row["display_text"],
        )
    }

    /// Detail-path routes for one substance.
    ///
    /// The dose/duration ladders (and the per-salt fold) come from the **single**
    /// set-based ``resolveRoutes(db:substanceIDs:order:)`` — the same code path
    /// the batch loader uses, run with a one-element id set — which is what
    /// collapses the former per-route `resolvedDoseForRoute` + per-salt
    /// `resolvedDurationForRoute` N+1 into two windowed queries.
    ///
    /// The protocol-dosing and duration-of-action layers (whose model
    /// initializers are `MainActor`-isolated, so the off-main resolver can't
    /// build them — and which the browse path never surfaced) are folded in here
    /// on the main actor: attached to the dose routes, then any
    /// protocol-/DOA-/duration-only routes are appended, matching the legacy
    /// resolver's surfacing order. Still set-based — three queries for the id,
    /// not per-route.
    ///
    /// Internal rather than `private` so `SubstanceStore+Provenance.swift` can
    /// attribute the same route set it resolves.
    func resolvedRoutes(db: Database, substanceID: Int64) throws -> [SubstanceRoute] {
        let doseRoutes = try Self.resolveRoutes(db: db, substanceIDs: [substanceID], order: order)[substanceID] ?? []
        return try attachAuxiliaryRoutes(db: db, substanceID: substanceID, doseRoutes: doseRoutes)
    }

    /// Folds protocol-dosing and duration-of-action data into a substance's
    /// dose routes and surfaces routes whose *only* data is a duration profile,
    /// a clinical schedule, or a long-acting release window. MainActor-isolated
    /// because `ProtocolDosing` / `DurationOfAction` carry MainActor-isolated
    /// initializers; the detail path is already on the main actor, and the
    /// browse path deliberately omits these (it always has).
    private func attachAuxiliaryRoutes(
        db: Database, substanceID: Int64, doseRoutes: [SubstanceRoute],
    ) throws -> [SubstanceRoute] {
        let priorityCaseSQL = self.priorityCaseSQL
        let enabledSourceListSQL = self.enabledSourceListSQL
        let idListSQL = String(substanceID)

        // Protocol dosing — highest-priority source per route, keyed by the
        // parsed `RouteOfAdministration` so it lines up with the dose routes'
        // enum (DB route strings like `intranasal`/`oral_er` normalize).
        var protocolByRoute: [RouteOfAdministration: (unit: String, dosing: ProtocolDosing)] = [:]
        for row in try Row.fetchAll(db, sql: """
            SELECT route, unit, low_amount, high_amount, frequency,
                   titration_json, course_duration, notes
              FROM (
                SELECT p.*, ROW_NUMBER() OVER (
                    PARTITION BY p.route
                    ORDER BY \(priorityCaseSQL) ASC) AS rn
                  FROM protocol_dosing p
                  JOIN sources src ON src.id = p.source_id
                 WHERE p.substance_id = \(idListSQL)
                   AND src.slug IN (\(enabledSourceListSQL))
            ) WHERE rn = 1
        """) {
            guard let frequency = row["frequency"] as String? else { continue }
            var titration: [TitrationStep]? = nil
            if let json = row["titration_json"] as String?, let data = json.data(using: .utf8) {
                titration = try? JSONDecoder().decode([TitrationStep].self, from: data)
            }
            let dosing = ProtocolDosing(
                lowAmount: row["low_amount"],
                highAmount: row["high_amount"],
                frequency: frequency,
                titration: titration,
                courseDuration: row["course_duration"],
                notes: row["notes"],
            )
            protocolByRoute[RouteOfAdministration.from(string: row["route"])] = (row["unit"] ?? "mg", dosing)
        }

        // Duration-of-action — highest-priority source per route.
        var doaByRoute: [RouteOfAdministration: DurationOfAction] = [:]
        for row in try Row.fetchAll(db, sql: """
            SELECT route, min_minutes, max_minutes
              FROM (
                SELECT da.route, da.min_minutes, da.max_minutes,
                       ROW_NUMBER() OVER (
                           PARTITION BY da.route
                           ORDER BY \(priorityCaseSQL) ASC) AS rn
                  FROM durations_of_action da
                  JOIN sources src ON src.id = da.source_id
                 WHERE da.substance_id = \(idListSQL)
                   AND src.slug IN (\(enabledSourceListSQL))
            ) WHERE rn = 1
        """) {
            guard let mn = row["min_minutes"] as Double?, let mx = row["max_minutes"] as Double? else { continue }
            doaByRoute[RouteOfAdministration.from(string: row["route"])] = DurationOfAction(minMinutes: mn, maxMinutes: mx)
        }

        // Attach protocol/DOA to the existing dose routes (re-using makeRoute so
        // the salt fold and default-mirror invariant stay single-sourced).
        var resolved: [SubstanceRoute] = doseRoutes.map { route in
            let proto = protocolByRoute[route.route]?.dosing
            let doa = doaByRoute[route.route]
            guard proto != nil || doa != nil else { return route }
            let variants: [RouteVariant] = if let saltForms = route.saltForms {
                // `saltForms` is already in curated (rank) order — preserve it by
                // feeding the index as the rank, and carry the elemental fraction,
                // so re-folding through makeRoute is order-preserving and lossless.
                saltForms.enumerated().map { idx, sv in
                    RouteVariant(
                        salt: sv.saltForm, isomer: sv.isomer, isomerDisplayName: sv.isomerDisplayName,
                        unit: sv.unit, doses: sv.doses, duration: sv.duration,
                        rank: idx, elementalFraction: sv.elementalFraction,
                    )
                }
            } else {
                [RouteVariant(
                    salt: nil, isomer: nil, isomerDisplayName: nil,
                    unit: route.unit, doses: route.doses, duration: route.duration,
                )]
            }
            return Self.makeRoute(
                route: route.route, variants: variants,
                protocolDosing: proto, durationOfAction: doa,
            )
        }
        var haveRoutes = Set(resolved.map(\.route))

        // Duration-only routes — durations but no dose ladder. Take the NULL-salt
        // (base) duration, matching the legacy `resolvedDurationForRoute` default.
        let durationByKey = try Self.resolveDurations(
            db: db, idListSQL: idListSQL,
            priorityCaseSQL: priorityCaseSQL, enabledSourceListSQL: enabledSourceListSQL,
        )
        let durationRoutes = Set(durationByKey.keys.map(\.route))
        for routeStr in durationRoutes.sorted() {
            let ra = RouteOfAdministration.from(string: routeStr)
            guard !haveRoutes.contains(ra) else { continue }
            let duration = durationByKey[RouteSaltKey(sid: substanceID, route: routeStr, salt: nil, isomer: nil)]
            resolved.append(SubstanceRoute(
                route: ra, unit: "mg", doses: DoseRange(), duration: duration,
                protocolDosing: protocolByRoute[ra]?.dosing,
                durationOfAction: doaByRoute[ra],
            ))
            haveRoutes.insert(ra)
        }

        // Protocol-only routes — a clinical schedule with no ladder/phases.
        for (ra, value) in protocolByRoute {
            guard !haveRoutes.contains(ra) else { continue }
            resolved.append(SubstanceRoute(
                route: ra, unit: value.unit, doses: DoseRange(), duration: nil,
                protocolDosing: value.dosing, durationOfAction: doaByRoute[ra],
            ))
            haveRoutes.insert(ra)
        }

        // Duration-of-action-only routes — long-acting depot window only.
        for (ra, value) in doaByRoute {
            guard !haveRoutes.contains(ra) else { continue }
            resolved.append(SubstanceRoute(
                route: ra, unit: "mg", doses: DoseRange(), duration: nil,
                protocolDosing: nil, durationOfAction: value,
            ))
            haveRoutes.insert(ra)
        }

        return resolved
    }

    /// Distinct primary references for a compound: the substance-level curated
    /// `sources` plus the citations attached to its dose / duration / half-life /
    /// mechanism / protocol facts. Binding citations are excluded — they have a
    /// dedicated Receptor Literature card and would swamp the list.
    private func resolvedReferences(db: Database, substanceID: Int64) throws -> [Citation] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT DISTINCT c.doi, c.pmid, c.url, c.title FROM citations c
             WHERE c.id IN (
                SELECT citation_id FROM substance_citations WHERE substance_id = :id
                UNION SELECT citation_id FROM dose_ranges        WHERE substance_id = :id
                UNION SELECT citation_id FROM durations          WHERE substance_id = :id
                UNION SELECT citation_id FROM half_lives         WHERE substance_id = :id
                UNION SELECT citation_id FROM mechanisms_summary WHERE substance_id = :id
                UNION SELECT citation_id FROM protocol_dosing    WHERE substance_id = :id
             )
             ORDER BY c.title, c.url, c.doi
             LIMIT 60
        """, arguments: ["id": substanceID])
        return rows.map { r in
            Citation(
                doi: r["doi"],
                pmid: (r["pmid"] as Int64?).map(Int.init),
                url: r["url"],
                title: r["title"],
            )
        }
    }

    private func resolvedPeptideProfile(db: Database, substanceID: Int64) throws -> PeptideProfile? {
        guard let row = try Row.fetchOne(db, sql: """
            SELECT sequence, supplied_form, typical_vial_mg, reconstitution_solvent,
                   storage_temperature, storage_light_sensitive, reconstituted_stability_days, iu_per_mg
              FROM peptide_profiles WHERE substance_id = ?
        """, arguments: [substanceID]) else { return nil }

        var storage: StorageRequirement? = nil
        if let temp = (row["storage_temperature"] as String?).flatMap(StorageRequirement.Temperature.init(rawValue:)) {
            storage = StorageRequirement(
                temperature: temp,
                lightSensitive: (row["storage_light_sensitive"] as Int64? ?? 0) != 0,
                reconstitutedStabilityDays: row["reconstituted_stability_days"],
            )
        }
        let profile = PeptideProfile(
            sequence: row["sequence"],
            suppliedForm: (row["supplied_form"] as String?).flatMap(SuppliedForm.init(rawValue:)),
            typicalVialMg: row["typical_vial_mg"],
            reconstitutionSolvent: row["reconstitution_solvent"],
            storage: storage,
            iuPerMg: row["iu_per_mg"],
        )
        return profile.hasAnyValue ? profile : nil
    }

    private func resolvedHalfLife(db: Database, substanceID: Int64) throws -> Double? {
        try Double.fetchOne(db, sql: """
            SELECT h.half_life_minutes
              FROM half_lives h
              JOIN sources src ON src.id = h.source_id
             WHERE h.substance_id = ?
               AND src.slug IN (\(enabledSourceListSQL))
             ORDER BY \(priorityCaseSQL) ASC
             LIMIT 1
        """, arguments: [substanceID])
    }

    /// One locale-resolved prose row from a text table that
    /// `resolvedDescription`/`resolvedMechanism` share: matching-language text
    /// floats above source priority, English/`und` is the language fallback (see
    /// ``ContentLanguage/clauses(column:)``). Runs a strict enabled-source +
    /// preferred-language pass first, then a relaxed pass that keeps the same
    /// ORDER BY and language filter but drops the enabled-source filter, so a
    /// substance that only has prose from a deprioritized source shows it rather
    /// than a blank section. The table is aliased `t`; the returned row also carries
    /// `machine_translated` + `source_slug` so callers build their typed value.
    /// `table` is a fixed internal literal (no injection surface).
    private func resolvedTextRow(
        db: Database, from table: String, selecting columns: String,
        substanceID: Int64,
    ) throws -> Row? {
        let lang = language.clauses(column: "t.language")
        // Primary: the highest-priority enabled source, in the preferred language.
        if let row = try Row.fetchOne(db, sql: """
            SELECT \(columns), t.machine_translated, src.slug AS source_slug, t.language AS row_language
              FROM \(table) t
              JOIN sources src ON src.id = t.source_id
             WHERE t.substance_id = ?
               AND src.slug IN (\(enabledSourceListSQL))
               \(lang.whereAnd)
             ORDER BY \(lang.orderPrefix)\(priorityCaseSQL) ASC
             LIMIT 1
        """, arguments: [substanceID]) {
            return row
        }
        // Fallback: prose exists, just not from an enabled source — show it
        // rather than a blank section. Only the enabled-source filter is dropped;
        // the language filter stays. Dropping it too let an English reader fall
        // through to raw zh prose whenever a compound had a Chinese row but no
        // English one (ketamine's mechanism, 137 others) — and a Chinese blob is
        // worse than a blank the bundled English template then fills. The ORDER BY
        // still floats the preferred language and the user's source priority. Also
        // covers the empty-source-order launch window (enabledSourceListSQL = ''
        // matches nothing), which would otherwise blank every overview until the
        // priority list finishes loading.
        return try Row.fetchOne(db, sql: """
            SELECT \(columns), t.machine_translated, src.slug AS source_slug, t.language AS row_language
              FROM \(table) t
              JOIN sources src ON src.id = t.source_id
             WHERE t.substance_id = ?
               \(lang.whereAnd)
             ORDER BY \(lang.orderPrefix)\(priorityCaseSQL) ASC
             LIMIT 1
        """, arguments: [substanceID])
    }

    /// Substance overview prose (descriptions table), resolved locale-first.
    private func resolvedDescription(db: Database, substanceID: Int64) throws -> SubstanceOverview? {
        guard let row = try resolvedTextRow(
            db: db, from: "descriptions", selecting: "t.text",
            substanceID: substanceID,
        ) else { return nil }
        let text: String = row["text"]
        guard !text.isEmpty else { return nil }
        return SubstanceOverview(
            text: text,
            machineTranslated: (row["machine_translated"] as Int64? ?? 0) != 0,
            sourceSlug: (row["source_slug"] as String?) ?? "freeodwiki",
        )
    }

    private func resolvedMechanism(db: Database, substanceID: Int64) throws -> MechanismOfAction? {
        let row = try resolvedTextRow(
            db: db, from: "mechanisms_summary", selecting: "t.summary, t.description",
            substanceID: substanceID,
        )

        // Union-merge bindings across sources (curated ∪ measured) into ONE row per
        // (target, action).
        //
        // **A curated `affinity_tier` outranks the derived band.** The derived band is
        // absolute — Kᵢ < 100 nM strong, EC₅₀ < 1 µM strong — and an absolute band
        // cannot say which of *this* compound's targets is the weak one. Methamphetamine
        // is the case that proves it: SERT release EC₅₀ 736 nM lands under the 1 µM
        // cutoff and dots as "strong", beside DAT 24.5 and NET 12.3 nM on the same card
        // and a ternary reading SERT 1 %. The curator had already written the answer as
        // `affinity_tier = 1`; the query was discarding it. Do not restore measured-wins
        // — a hand-set tier is a claim about this drug's own balance, which is the
        // question the dots ask.
        //
        // The derived band still does all the work where nothing is curated. Binding
        // (Kᵢ) and functional (EC₅₀/IC₅₀) keep different cutoffs because a releaser's
        // EC₅₀ runs ~10× higher than a blocker's Kᵢ for the same strength. Keep these
        // identical to `ReceptorStrength` in Substance.swift.
        let bindingRows = try Row.fetchAll(db, sql: """
            SELECT target, action,
                   COALESCE(MAX(curated_tier), MAX(derived_tier), 1) AS affinity,
                   MAX(measured) AS measured, MIN(ki_nm) AS ki_nm FROM (
                SELECT b.target, b.action, b.ki_nm, b.affinity_tier AS curated_tier,
                       CASE WHEN b.ki_nm IS NOT NULL OR b.ec50_nm IS NOT NULL OR b.ic50_nm IS NOT NULL
                            THEN 1 ELSE 0 END AS measured,
                       CASE WHEN b.ki_nm   IS NOT NULL AND b.ki_nm   <   100 THEN 3
                            WHEN b.ki_nm   IS NOT NULL AND b.ki_nm   <  1000 THEN 2
                            WHEN b.ki_nm   IS NOT NULL                        THEN 1
                            WHEN b.ec50_nm IS NOT NULL AND b.ec50_nm <  1000 THEN 3
                            WHEN b.ec50_nm IS NOT NULL AND b.ec50_nm < 10000 THEN 2
                            WHEN b.ec50_nm IS NOT NULL                        THEN 1
                            WHEN b.ic50_nm IS NOT NULL AND b.ic50_nm <  1000 THEN 3
                            WHEN b.ic50_nm IS NOT NULL AND b.ic50_nm < 10000 THEN 2
                            WHEN b.ic50_nm IS NOT NULL                        THEN 1
                            ELSE NULL END AS derived_tier
                  FROM bindings b
                  JOIN sources src ON src.id = b.source_id
                 WHERE b.substance_id = ?
                   AND src.slug IN (\(enabledSourceListSQL))
            )
             GROUP BY target, action
             ORDER BY affinity DESC, ki_nm ASC NULLS LAST, LENGTH(target) ASC
             LIMIT 40
        """, arguments: [substanceID])

        struct RawHit {
            let target: String
            let action: BindingAction
            let tier: Int
            let measured: Bool
        }
        let rawHits: [RawHit] = bindingRows.compactMap { row in
            guard let target: String = row["target"],
                  let actionRaw: String = row["action"],
                  let action = BindingAction(rawValue: actionRaw) else { return nil }
            return RawHit(target: target, action: action, tier: row["affinity"], measured: (row["measured"] as Int) == 1)
        }
        // Collapse one row per receptor for the *summary* table: a measured row often restates a curated
        // target under a wordier name ("NMDA (MK-801 site, S-enantiomer)" vs the curated "NMDA"). We keep
        // the cleanest name and the curated action label. Tier precedence is already settled per
        // (target, action) by the query above — curated first, derived band otherwise — so this pass
        // only picks between differently-*named* rows for the same receptor, preferring measured ones
        // when any exist. The full per-assay detail lives in the Receptor Literature disclosure.
        var groupOrder: [String] = []
        var groups: [String: [RawHit]] = [:]
        for hit in rawHits {
            let key = Self.normalizedBindingTarget(hit.target)
            if groups[key] == nil { groupOrder.append(key) }
            groups[key, default: []].append(hit)
        }
        let bindings: [ReceptorBinding] = groupOrder.compactMap { key in
            guard let hits = groups[key], !hits.isEmpty else { return nil }
            let measured = hits.filter(\.measured)
            let tier = (measured.isEmpty ? hits : measured).map(\.tier).max() ?? 1
            // Prefer a curated (clean, editorial) action label; else the strongest measured row's action.
            let action = hits.first { !$0.measured }?.action
                ?? measured.max(by: { $0.tier < $1.tier })?.action
                ?? hits[0].action
            let name = hits.map(\.target).min { $0.count < $1.count } ?? hits[0].target
            return ReceptorBinding(target: name, action: action, affinity: BindingAffinity(rawValue: tier) ?? .significant)
        }
        .sorted { $0.affinity > $1.affinity }

        // Surface measured bindings even when no curated summary row exists —
        // the detail view's mechanism composer fills missing summary text from
        // the per-name / category fallback, so substances with real receptor
        // data (e.g. mephedrone: DAT/NET/SERT releasingAgent) no longer fall
        // through to a generic "Modulator" placeholder. Return nil only when we
        // have neither a summary nor any binding.
        guard row != nil || !bindings.isEmpty else { return nil }

        return MechanismOfAction(
            summary: row?["summary"] ?? "",
            description: row?["description"] ?? "",
            primaryTargets: bindings.map(\.target),
            bindings: bindings,
            summaryLanguage: row?["row_language"] as String?,
        )
    }

    private func resolvedTolerance(db: Database, substanceID: Int64) throws -> ToleranceInfo? {
        guard let row = try Row.fetchOne(db, sql: """
            SELECT t.half_life_days, t.full_reset_days, t.build_rate
              FROM tolerance t
              JOIN sources src ON src.id = t.source_id
             WHERE t.substance_id = ?
               AND src.slug IN (\(enabledSourceListSQL))
               AND t.half_life_days IS NOT NULL
               AND t.full_reset_days IS NOT NULL
               AND t.build_rate IS NOT NULL
             ORDER BY \(priorityCaseSQL) ASC
             LIMIT 1
        """, arguments: [substanceID]) else { return nil }
        return ToleranceInfo(
            halfLife: row["half_life_days"],
            fullResetDays: row["full_reset_days"],
            buildRate: row["build_rate"],
        )
    }

    private func citedSources(db: Database, substanceID: Int64) throws -> [String] {
        // Source attribution shown to the user: the set of source display
        // names that contributed any fact for this substance.
        try String.fetchAll(db, sql: """
            SELECT DISTINCT src.slug FROM (
                SELECT source_id FROM categories WHERE substance_id = ?
                UNION SELECT source_id FROM dose_ranges WHERE substance_id = ?
                UNION SELECT source_id FROM durations WHERE substance_id = ?
                UNION SELECT source_id FROM half_lives WHERE substance_id = ?
                UNION SELECT source_id FROM mechanisms_summary WHERE substance_id = ?
                UNION SELECT source_id FROM bindings WHERE substance_id = ?
            ) AS uses
            JOIN sources src ON src.id = uses.source_id
            WHERE src.slug IN (\(enabledSourceListSQL))
            ORDER BY src.slug
        """, arguments: StatementArguments(Array(repeating: substanceID, count: 6) as [DatabaseValueConvertible]))
    }

    // MARK: - Reference dose

    /// The substance's **reference "heavy" dose** in mg — the escalation denominator for the deep
    /// tolerance gate (`dose ÷ reference`). Resolved from the substance's primary dose ladder: the
    /// **oral** route when it has one, else the first route that carries a usable range; within that
    /// route, `heavy ?? strong.upperBound ?? common.upperBound`. Returns `nil` when no ladder exists,
    /// so the deep gate stays closed (the conservative fallback).
    ///
    /// `nonisolated static` so both the cached instance path and the off-main batch resolve can call
    /// it on their own connection. Source priority mirrors ``resolveRoutes(db:substanceIDs:order:)``
    /// — the highest-priority enabled source per `(route, salt)` — so the reference matches the dose
    /// ladder the detail view shows.
    nonisolated static func referenceDoseMg(substanceID: Int64, db queue: DatabaseQueue, order: [String]) -> Double? {
        guard !order.isEmpty else { return nil }
        let priorityCaseSQL = priorityCaseSQL(order)
        let enabledSourceListSQL = enabledSourceListSQL(order)
        let rows: [(route: String, isomer: String?, common: Double?, strong: Double?, heavy: Double?)]
        do {
            rows = try queue.read { db in
                try Row.fetchAll(db, sql: """
                    SELECT route, isomer, common_upper, strong_upper, heavy
                      FROM (
                        SELECT d.*, ROW_NUMBER() OVER (
                            PARTITION BY d.substance_id, d.route, d.salt_form, d.isomer
                            ORDER BY \(priorityCaseSQL) ASC) AS rn
                          FROM dose_ranges d
                          JOIN sources src ON src.id = d.source_id
                         WHERE d.substance_id = ?
                           AND src.slug IN (\(enabledSourceListSQL))
                    ) WHERE rn = 1
                """, arguments: [substanceID]).map {
                    (
                        route: $0["route"] ?? "",
                        isomer: $0["isomer"],
                        common: $0["common_upper"],
                        strong: $0["strong_upper"],
                        heavy: $0["heavy"],
                    )
                }
            }
        } catch {
            logger.error("referenceDoseMg failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        func reference(_ row: (route: String, isomer: String?, common: Double?, strong: Double?, heavy: Double?)) -> Double? {
            row.heavy ?? row.strong ?? row.common
        }
        /// Prefer the racemic form so a family's reference is the parent's, not an
        /// arbitrary enantiomer's; oral first, else the first route yielding a value.
        func firstReference(preferRacemic: Bool) -> Double? {
            let candidates = preferRacemic ? rows.filter { $0.isomer == nil } : rows
            if let oral = candidates.first(where: { RouteOfAdministration.from(string: $0.route) == .oral }),
               let value = reference(oral) {
                return value
            }
            return candidates.lazy.compactMap(reference).first
        }
        return firstReference(preferRacemic: true) ?? firstReference(preferRacemic: false)
    }

    // MARK: - Batch resolution

    /// Batch-load every substance with ~12 SQL queries instead of ~21k
    /// (12 per-substance × 1785). Uses `ROW_NUMBER() OVER (PARTITION BY …)`
    /// to pick the highest-priority source per (substance, field) in a
    /// single query, then groups the rows in memory.
    nonisolated static func loadAllSubstancesBatch(db queue: DatabaseQueue, order: [String]) -> [Substance] {
        guard !order.isEmpty else { return [] }
        // Build the priority/source SQL fragments once up front so the read
        // closure captures plain strings (and statics) — that's what lets the
        // whole resolve run off the main actor.
        let priorityCaseSQL = priorityCaseSQL(order)
        let enabledSourceListSQL = enabledSourceListSQL(order)
        do {
            return try queue.read { db in
                let allRows = try Row.fetchAll(
                    db,
                    sql:
                    """
                    SELECT id, canonical_name, display_name, display_class, regulatory_status,
                           duration_implausible, popularity, is_stub, substance_uid,
                           -- Chemical identity travels with the shell. Without it a screen served
                           -- from this prewarm has no formula, mass, CAS, SMILES or InChIKey, and
                           -- the Chemistry card renders an empty grid.
                           cas, inchikey, formula, pubchem_cid, molecular_weight, smiles, iupac_name
                      FROM substances ORDER BY canonical_name COLLATE NOCASE
                    """,
                )
                let ids: [Int64] = allRows.map { $0["id"] }
                let names: [Int64: String] = Dictionary(
                    uniqueKeysWithValues:
                    allRows.map { ($0["id"], $0["canonical_name"] as String) },
                )
                // Display-name overrides — browse rows show this as the title when set.
                var displayNameByID: [Int64: String] = [:]
                // Curated popularity scores — drives the category-browse sort.
                var popularityByID: [Int64: Double] = [:]
                // Display-policy fields — loaded in the cheap batch path because
                // every browse row needs the class for filtering + dose gating.
                var displayClassByID: [Int64: CompoundDisplayClass] = [:]
                var regulatoryByID: [Int64: String] = [:]
                var durationImplausibleByID: [Int64: Bool] = [:]
                var isStubByID: [Int64: Bool] = [:]
                var substanceUIDByID: [Int64: String] = [:]
                // Chemical identity — see the SELECT above.
                var casByID: [Int64: String] = [:]
                var inchikeyByID: [Int64: String] = [:]
                var formulaByID: [Int64: String] = [:]
                var pubchemCIDByID: [Int64: Int] = [:]
                var molarMassByID: [Int64: Double] = [:]
                var smilesByID: [Int64: String] = [:]
                var iupacNameByID: [Int64: String] = [:]
                for row in allRows {
                    let sid: Int64 = row["id"]
                    if let raw: String = row["display_class"], let cls = CompoundDisplayClass(rawValue: raw) {
                        displayClassByID[sid] = cls
                    }
                    if let reg: String = row["regulatory_status"] { regulatoryByID[sid] = reg }
                    durationImplausibleByID[sid] = (row["duration_implausible"] as Int64? ?? 0) != 0
                    if let dn: String = row["display_name"] { displayNameByID[sid] = dn }
                    popularityByID[sid] = row["popularity"] as Double? ?? 0
                    isStubByID[sid] = (row["is_stub"] as Int64? ?? 0) != 0
                    if let uid: String = row["substance_uid"] { substanceUIDByID[sid] = uid }
                    if let v: String = row["cas"] { casByID[sid] = v }
                    if let v: String = row["inchikey"] { inchikeyByID[sid] = v }
                    if let v: String = row["formula"] { formulaByID[sid] = v }
                    if let v = row["pubchem_cid"] as Int64? { pubchemCIDByID[sid] = Int(v) }
                    if let v = row["molecular_weight"] as Double? { molarMassByID[sid] = v }
                    if let v: String = row["smiles"] { smilesByID[sid] = v }
                    if let v: String = row["iupac_name"] { iupacNameByID[sid] = v }
                }

                // Aliases — union across sources.
                var aliasesByID: [Int64: [String]] = [:]
                for row in try Row.fetchAll(
                    db,
                    sql:
                    // Brand names first (D.1.7), curated flagships (brand_rank 0,
                    // e.g. Ritalin) ahead of auto-derived form brands (rank 1, e.g.
                    // Concerta), then everything else alphabetical — so the "Also
                    // known as" subtitle leads with the names people know, not the
                    // alphabetically-first synonym. Findability is unaffected
                    // (search uses the normalized index).
                    "SELECT substance_id, alias FROM aliases ORDER BY COALESCE(brand_rank, 9), alias",
                ) {
                    let sid: Int64 = row["substance_id"]
                    aliasesByID[sid, default: []].append(row["alias"])
                }

                // Category — priority-resolved, with the non-informative "Other"
                // sunk below any specific category (mirrors `resolvedCategory`).
                let categoryRows = try Row.fetchAll(db, sql: """
                    SELECT substance_id, category FROM (
                        SELECT c.substance_id, c.category,
                               ROW_NUMBER() OVER (PARTITION BY c.substance_id
                                                  ORDER BY (c.category = 'Other'
                                                            AND src.slug != 'piru-curated') ASC,
                                                           \(priorityCaseSQL) ASC) AS rn
                          FROM categories c
                          JOIN sources src ON src.id = c.source_id
                         WHERE src.slug IN (\(enabledSourceListSQL))
                    ) WHERE rn = 1
                """)
                var categoryByID: [Int64: SubstanceCategory] = [:]
                for row in categoryRows {
                    let raw: String = row["category"]
                    let cat = SubstanceCategory(rawValue: raw) ?? SubstanceCategory.from(tripSitCategory: raw)
                    categoryByID[row["substance_id"]] = cat
                }

                // Additional browse homes (curated multi-class compounds).
                var extraCategoriesByID: [Int64: [SubstanceCategory]] = [:]
                for row in try Row.fetchAll(
                    db, sql: "SELECT substance_id, category FROM browse_extra_categories",
                ) {
                    let raw: String = row["category"]
                    guard let cat = SubstanceCategory(rawValue: raw) else { continue }
                    extraCategoriesByID[row["substance_id"], default: []].append(cat)
                }

                // Tags — union across enabled sources, excluding engine-consumed hidden tags.
                var tagsByID: [Int64: [String]] = [:]
                for row in try Row.fetchAll(db, sql: """
                    SELECT DISTINCT t.substance_id, t.tag
                      FROM tags t
                      JOIN sources src ON src.id = t.source_id
                     WHERE src.slug IN (\(enabledSourceListSQL))
                       AND t.hidden = 0
                     ORDER BY t.tag
                """) {
                    tagsByID[row["substance_id"], default: []].append(row["tag"])
                }

                // Routes (dose / duration / protocol / duration-of-action) —
                // resolved set-based through the single shared resolver. One
                // windowed query per table over the full id set; per-salt
                // ladders fold into `SubstanceRoute.saltForms`, and duration-/
                // protocol-/DOA-only routes are surfaced too.
                let routesByID = try Self.resolveRoutes(db: db, substanceIDs: Set(ids), order: order)

                // Half-life — priority-resolved.
                var halfLifeByID: [Int64: Double] = [:]
                for row in try Row.fetchAll(db, sql: """
                    SELECT substance_id, half_life_minutes FROM (
                        SELECT h.substance_id, h.half_life_minutes,
                               ROW_NUMBER() OVER (PARTITION BY h.substance_id
                                                  ORDER BY \(priorityCaseSQL) ASC) AS rn
                          FROM half_lives h
                          JOIN sources src ON src.id = h.source_id
                         WHERE src.slug IN (\(enabledSourceListSQL))
                    ) WHERE rn = 1
                """) {
                    halfLifeByID[row["substance_id"]] = row["half_life_minutes"]
                }

                // Effects — union, localized via the controlled vocabulary so a
                // zh user sees translated labels even on English-only-source
                // substances. DISTINCT on the resolved label folds orthography
                // variants that share a vocab_id into one entry.
                var effectsByID: [Int64: [String]] = [:]
                let effectLabelSQL = Self.localizedEffectLabelSQL(Self.contentLanguage)
                for row in try Row.fetchAll(db, sql: """
                    SELECT DISTINCT e.substance_id, \(effectLabelSQL) AS text
                      FROM effects e
                      JOIN sources src ON src.id = e.source_id
                     WHERE src.slug IN (\(enabledSourceListSQL))
                     ORDER BY text
                """) {
                    effectsByID[row["substance_id"], default: []].append(row["text"])
                }

                // Cited sources — distinct slugs touching any per-substance row.
                var sourcesByID: [Int64: [String]] = [:]
                for row in try Row.fetchAll(db, sql: """
                    SELECT DISTINCT uses.substance_id, src.slug FROM (
                        SELECT substance_id, source_id FROM categories
                        UNION SELECT substance_id, source_id FROM dose_ranges
                        UNION SELECT substance_id, source_id FROM durations
                        UNION SELECT substance_id, source_id FROM half_lives
                        UNION SELECT substance_id, source_id FROM mechanisms_summary
                        UNION SELECT substance_id, source_id FROM bindings
                    ) uses
                    JOIN sources src ON src.id = uses.source_id
                    WHERE src.slug IN (\(enabledSourceListSQL))
                    ORDER BY src.slug
                """) {
                    sourcesByID[row["substance_id"], default: []].append(row["slug"])
                }

                // Assemble. Mechanism / subjective effects / tolerance are
                // lazily resolved on detail-view open via `lookup()` — they
                // pull in 20-row binding lists and are too heavy to load for
                // every substance in the library.
                return ids.compactMap { sid in
                    guard let name = names[sid] else { return nil }
                    let aliases = aliasesByID[sid] ?? []
                    let tags = tagsByID[sid] ?? []
                    var routes = routesByID[sid] ?? []
                    // Sort by RouteOfAdministration.allCases order so the
                    // default route is the most-common ROA (oral first,
                    // then sublingual / insufflation / inhalation /
                    // intravenous / etc.). Without this the dict iteration
                    // is undefined and substances like Diazepam would
                    // default to IV instead of oral.
                    routes.sort { Self.routeRank($0.route) < Self.routeRank($1.route) }
                    let defaultRoute = routes.first?.route
                        ?? RouteOfAdministration.from(string: tags.contains("inhalation") ? "inhalation" : "oral")
                    return Substance(
                        name: name, displayName: displayNameByID[sid], aliases: aliases,
                        category: categoryByID[sid] ?? .other,
                        extraBrowseCategories: extraCategoriesByID[sid] ?? [],
                        defaultRoute: defaultRoute, routes: routes,
                        effects: effectsByID[sid] ?? [],
                        subjectiveEffects: [],
                        toleranceInfo: nil,
                        halfLifeMinutes: halfLifeByID[sid],
                        sources: sourcesByID[sid] ?? [],
                        mechanismOfAction: nil,
                        tags: tags,
                        displayClass: displayClassByID[sid] ?? .recreational,
                        regulatoryStatus: regulatoryByID[sid],
                        durationImplausible: durationImplausibleByID[sid] ?? false,
                        substanceUID: substanceUIDByID[sid],
                        cas: casByID[sid],
                        inchikey: inchikeyByID[sid],
                        formula: formulaByID[sid],
                        pubchemCID: pubchemCIDByID[sid],
                        popularity: popularityByID[sid] ?? 0,
                        isStub: isStubByID[sid] ?? false,
                        molarMass: molarMassByID[sid],
                        smiles: smilesByID[sid],
                        iupacName: iupacNameByID[sid],
                    )
                }
            }
        } catch {
            logger.error("loadAllSubstancesBatch failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}
