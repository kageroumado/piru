import Foundation
import GRDB

/// Route/salt/isomer resolution: turning the per-source `dose_ranges` and
/// `durations` rows into the folded ``SubstanceRoute`` values the app
/// consumes. Everything here is `nonisolated static`, which is what lets the
/// resolve run off the main actor during the library prewarm.
extension SubstanceReadModel {
    /// One resolved (salt-tagged or unspecified) dose/duration row for a route,
    /// before it's folded into a ``SubstanceRoute``. `salt == nil` is the
    /// unspecified/base form that the vast majority of substances use.
    struct RouteVariant {
        let salt: String?
        /// Stereoisomer code (D/S/L/R; `nil` = racemic) + its title ("Esketamine").
        let isomer: String?
        let isomerDisplayName: String?
        let unit: String
        let doses: DoseRange
        let duration: DurationProfile?
        /// Which regime this ladder describes — carried so the card can label a
        /// recreational dose on a compound that also has a clinical one.
        var doseContext: DoseContext = .unknown
        /// Curated ordering rank (0 = the default salt); `nil` sorts last.
        var rank: Int?
        /// Mass fraction of the elemental active for this salt, if known.
        var elementalFraction: Double?
    }

    /// Fold the per-salt dose/duration variants of a single route into one
    /// ``SubstanceRoute``. When salt-tagged variants exist they become
    /// ``SubstanceRoute/saltForms`` (ordered by label, default = first), and the
    /// route's top-level `unit`/`doses`/`duration` mirror that default so
    /// salt-unaware code transparently gets the default form. With no salt tags
    /// the single base variant populates the route directly (`saltForms == nil`).
    nonisolated static func makeRoute(
        route: RouteOfAdministration,
        variants: [RouteVariant],
        protocolDosing: ProtocolDosing? = nil,
        durationOfAction: DurationOfAction? = nil,
    ) -> SubstanceRoute {
        let hasSalt = variants.contains { $0.salt != nil }
        let hasIsomer = variants.contains { $0.isomer != nil }

        /// The base (unspecified) route, used when there's no form axis or nothing
        /// to fold — the single spot that mirrors a variant into the top-level route.
        func baseRoute() -> SubstanceRoute {
            let base = variants.first
            return SubstanceRoute(
                route: route, unit: base?.unit ?? "mg",
                doses: base?.doses ?? DoseRange(),
                doseContext: base?.doseContext ?? .unknown,
                duration: base?.duration,
                protocolDosing: protocolDosing, durationOfAction: durationOfAction,
            )
        }
        guard hasSalt || hasIsomer else { return baseRoute() }

        // Selectable forms: an isomer family keeps ALL variants (racemic parent
        // coexists with its enantiomers, each with its own ladder); a salt-only
        // substance keeps just the salt-tagged variants (unchanged salt behavior).
        let forms = hasIsomer ? variants : variants.filter { $0.salt != nil }

        // Racemic (nil-isomer) first — the sensible default — then curated
        // salt_rank, then label for a data-driven (not alphabetical) default.
        let ordered = forms.sorted {
            ($0.isomer == nil ? 0 : 1, $0.rank ?? Int.max, $0.salt ?? "", $0.isomer ?? "")
                < ($1.isomer == nil ? 0 : 1, $1.rank ?? Int.max, $1.salt ?? "", $1.isomer ?? "")
        }
        guard let first = ordered.first else { return baseRoute() }
        let saltForms = ordered.map {
            DoseVariant(
                saltForm: $0.salt, isomer: $0.isomer, isomerDisplayName: $0.isomerDisplayName,
                unit: $0.unit, doses: $0.doses,
                duration: $0.duration, elementalFraction: $0.elementalFraction,
            )
        }
        return SubstanceRoute(
            route: route, unit: first.unit, doses: first.doses,
            doseContext: first.doseContext, duration: first.duration,
            protocolDosing: protocolDosing, durationOfAction: durationOfAction, saltForms: saltForms,
        )
    }

    /// Identifies a (substance, route, salt) tuple in the set-based route
    /// resolver. `salt == nil` is the unspecified/base form the vast majority
    /// of substances use; a handful (Magnesium, Lithium) carry per-salt rows.
    ///
    /// `nonisolated` so its synthesized `Hashable` conformance is usable from
    /// the `nonisolated static` resolver (which runs off-main during the
    /// library prewarm) — without it the default `MainActor` isolation would
    /// taint the conformance and reject the off-main dictionary keying.
    nonisolated struct RouteSaltKey: Hashable {
        let sid: Int64; let route: String; let salt: String?; let isomer: String?
    }

    /// The **single** set-based dose/duration route resolver, shared by the
    /// batch loader and the per-substance detail/`lookup` path. Given a set of
    /// substance ids it runs **one windowed query per table** (`dose_ranges`,
    /// `durations`) — partitioned by `(substance_id, route, salt_form, isomer)`
    /// (durations also by `phase`) and restricted to `substance_id IN (…)` —
    /// then groups the rows in Swift and assembles each substance's dose-bearing
    /// `[SubstanceRoute]` via ``makeRoute`` (the single form-fold point). This
    /// collapses the former detail-path N+1 into a constant two queries.
    ///
    /// `nonisolated` so it runs off-main during the library prewarm; every model
    /// it builds (`DoseRange`, `DurationProfile`, `SubstanceRoute`,
    /// `DoseVariant`) has a `nonisolated init`. Protocol-dosing and
    /// duration-of-action — whose model initializers are `MainActor`-isolated,
    /// and which never appeared in the browse path — are folded in afterward by
    /// the MainActor ``attachAuxiliaryRoutes(db:substanceID:doseRoutes:)`` on the
    /// detail path only. Returned arrays are **not** route-rank sorted — callers sort.
    nonisolated static func resolveRoutes(
        db: Database,
        substanceIDs: Set<Int64>,
        order: [String],
    ) throws -> [Int64: [SubstanceRoute]] {
        guard !substanceIDs.isEmpty, !order.isEmpty else { return [:] }
        let priorityCaseSQL = priorityCaseSQL(order)
        let enabledSourceListSQL = enabledSourceListSQL(order)
        // `substance_id IN (…)` over the id set. The ids are our own Int64 row
        // ids (never user input), so interpolation is safe and lets one
        // statement serve any id-set size without a parameter blowup.
        let idListSQL = substanceIDs.map(String.init).joined(separator: ", ")

        // 1. Dose ladders — highest-priority source per (substance, route, salt).
        var dosesByKey: [RouteSaltKey: (unit: String, doses: DoseRange, rank: Int?, elemental: Double?, isomerDisplay: String?, context: DoseContext)] = [:]
        for row in try Row.fetchAll(db, sql: """
            SELECT substance_id, route, salt_form, isomer, isomer_display_name, salt_rank,
                   elemental_fraction, unit, threshold, dose_context,
                   light_lower, light_upper, common_lower, common_upper,
                   strong_lower, strong_upper, heavy
              FROM (
                SELECT d.*, ROW_NUMBER() OVER (
                    PARTITION BY d.substance_id, d.route, d.salt_form, d.isomer
                    ORDER BY \(priorityCaseSQL) ASC) AS rn
                  FROM dose_ranges d
                  JOIN sources src ON src.id = d.source_id
                 WHERE d.substance_id IN (\(idListSQL))
                   AND src.slug IN (\(enabledSourceListSQL))
            ) WHERE rn = 1
        """) {
            let key = RouteSaltKey(
                sid: row["substance_id"], route: row["route"],
                salt: row["salt_form"], isomer: row["isomer"],
            )
            let dose = DoseRange(
                threshold: row["threshold"],
                light: rangeFrom(lower: row["light_lower"], upper: row["light_upper"]),
                common: rangeFrom(lower: row["common_lower"], upper: row["common_upper"]),
                strong: rangeFrom(lower: row["strong_lower"], upper: row["strong_upper"]),
                heavy: row["heavy"],
            )
            dosesByKey[key] = (
                row["unit"] ?? "mg", dose,
                (row["salt_rank"] as Int64?).map(Int.init), row["elemental_fraction"],
                row["isomer_display_name"],
                DoseContext(rawValue: row["dose_context"] ?? "") ?? .unknown,
            )
        }

        // 2. Durations — highest-priority source *per phase* so different
        // sources can contribute different phases (curated supplies onset/peak/
        // offset while PsychonautWiki fills comeup/afterglow). Keyed by
        // (substance, route, salt); a salt-tagged dose variant takes its own
        // salt's duration, the unspecified base takes the NULL-salt rows.
        let durationByKey = try resolveDurations(
            db: db, idListSQL: idListSQL,
            priorityCaseSQL: priorityCaseSQL, enabledSourceListSQL: enabledSourceListSQL,
        )

        // Assemble dose-bearing routes. Per-salt variants of a route fold into
        // one SubstanceRoute (default salt mirrored at top level by makeRoute).
        var result: [Int64: [SubstanceRoute]] = [:]
        result.reserveCapacity(substanceIDs.count)
        var variantsByID: [Int64: [String: [RouteVariant]]] = [:]
        for (key, value) in dosesByKey {
            variantsByID[key.sid, default: [:]][key.route, default: []].append(
                RouteVariant(
                    salt: key.salt, isomer: key.isomer, isomerDisplayName: value.isomerDisplay,
                    unit: value.unit, doses: value.doses,
                    duration: durationByKey[key],
                    doseContext: value.context,
                    rank: value.rank, elementalFraction: value.elemental,
                ),
            )
        }
        for (sid, variantsByRoute) in variantsByID {
            let routes = variantsByRoute.map { routeStr, variants in
                makeRoute(route: RouteOfAdministration.from(string: routeStr), variants: variants)
            }
            if !routes.isEmpty { result[sid] = routes }
        }
        return result
    }

    /// Windowed per-(substance, route, salt, phase) duration resolution shared
    /// by ``resolveRoutes`` and the detail path's auxiliary route fill, so the
    /// phase-merge logic lives in exactly one place.
    nonisolated static func resolveDurations(
        db: Database, idListSQL: String,
        priorityCaseSQL: String, enabledSourceListSQL: String,
    ) throws -> [RouteSaltKey: DurationProfile] {
        var phasesByKey: [RouteSaltKey: [String: DurationRange]] = [:]
        for row in try Row.fetchAll(db, sql: """
            SELECT substance_id, route, salt_form, isomer, phase, min_minutes, max_minutes
              FROM (
                SELECT du.substance_id, du.route, du.salt_form, du.isomer, du.phase,
                       du.min_minutes, du.max_minutes,
                       ROW_NUMBER() OVER (
                           PARTITION BY du.substance_id, du.route, du.phase, du.salt_form, du.isomer
                           ORDER BY \(priorityCaseSQL) ASC) AS rn
                  FROM durations du
                  JOIN sources src ON src.id = du.source_id
                 WHERE du.substance_id IN (\(idListSQL))
                   AND src.slug IN (\(enabledSourceListSQL))
            ) WHERE rn = 1
        """) {
            let key = RouteSaltKey(
                sid: row["substance_id"], route: row["route"],
                salt: row["salt_form"], isomer: row["isomer"],
            )
            phasesByKey[key, default: [:]][row["phase"]] = DurationRange(
                min: row["min_minutes"], max: row["max_minutes"],
            )
        }
        var durationByKey: [RouteSaltKey: DurationProfile] = [:]
        for (key, phases) in phasesByKey {
            durationByKey[key] = DurationProfile(
                onset: phases["onset"], comeup: phases["comeup"],
                peak: phases["peak"], offset: phases["offset"],
                afterglow: phases["afterglow"], total: phases["total"],
            )
        }
        return durationByKey
    }
}
