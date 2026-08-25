import Foundation
import GRDB
import os

private nonisolated let logger = Logger(subsystem: "dev.yumeji.piru", category: "SubstanceStore")

/// Source attribution for the fields displayed in a substance detail
/// view. Distinct from the substance-level `sources` list (which is just
/// "every source that contributed anything") — this surfaces *which*
/// source supplied a specific field after priority resolution.
nonisolated struct RouteProvenance: Hashable {
    let doseSource: String?
    let durationSource: String?
}

nonisolated struct SubstanceProvenance: Hashable {
    let categorySource: String?
    let halfLifeSource: String?
    let mechanismSource: String?
    /// Keyed by route for O(1) lookup from per-route UI rows. Routes
    /// without any source data (e.g. the route is in `dose_ranges` but no
    /// enabled source has it after priority resolution) are simply absent.
    let routesBySource: [RouteOfAdministration: RouteProvenance]
}

/// A displayed field whose "why this source?" explainer can list the sources
/// that actually carry it. Mirrors the badged fields on the substance screen.
nonisolated enum AttributableField: Hashable {
    case dose(RouteOfAdministration)
    case duration(RouteOfAdministration)
    case category
    case halfLife
    case mechanism

    /// (table, extra WHERE fragment, extra bound args) for the availability query.
    fileprivate var query: (table: String, whereClause: String, args: [DatabaseValueConvertible]) {
        switch self {
        case let .dose(route): ("dose_ranges", "AND t.route = ?", [route.rawValue])
        case let .duration(route): ("durations", "AND t.route = ?", [route.rawValue])
        case .category: ("categories", "", [])
        case .halfLife: ("half_lives", "", [])
        case .mechanism: ("mechanisms_summary", "", [])
        }
    }
}

/// Per-field source attribution — which source actually won each displayed
/// field after priority resolution. Queries build on the same SQL fragments
/// as the resolvers themselves, so the attributed slug cannot disagree with
/// the value shown.
extension SubstanceReadModel {
    /// Resolves per-field source slugs for a substance using the same
    /// priority order as the field resolvers themselves, so the slug shown
    /// in the UI matches the source that actually won the field.
    ///
    /// Three queries total regardless of route count: one row of scalar
    /// subselects for the substance-level fields, then one `ROW_NUMBER()`
    /// window per table for the per-route winners — the same idiom
    /// ``resolveRoutes(db:substanceIDs:order:)`` uses.
    func provenance(substanceID: Int64) -> SubstanceProvenance? {
        do {
            return try db.read { db in
                // Substance-level winners, one query of three scalar subselects.
                let fieldRow = try Row.fetchOne(db, sql: """
                    SELECT
                      (SELECT src.slug FROM categories c
                         JOIN sources src ON src.id = c.source_id
                        WHERE c.substance_id = :id
                          AND src.slug IN (\(enabledSourceListSQL))
                        ORDER BY \(priorityCaseSQL) ASC LIMIT 1) AS category_source,
                      (SELECT src.slug FROM half_lives h
                         JOIN sources src ON src.id = h.source_id
                        WHERE h.substance_id = :id
                          AND src.slug IN (\(enabledSourceListSQL))
                        ORDER BY \(priorityCaseSQL) ASC LIMIT 1) AS half_life_source,
                      (SELECT src.slug FROM mechanisms_summary m
                         JOIN sources src ON src.id = m.source_id
                        WHERE m.substance_id = :id
                          AND src.slug IN (\(enabledSourceListSQL))
                        ORDER BY \(priorityCaseSQL) ASC LIMIT 1) AS mechanism_source
                """, arguments: ["id": substanceID])

                // Per-route winners, one windowed query per table. Keyed by the
                // RAW DB route string and looked up by `route.rawValue`, which
                // preserves the exact-equality semantics of a `d.route = ?`
                // probe — an `oral_er` row must not be normalized onto `.oral`.
                let winningSlugByRawRoute = { (table: String) throws -> [String: String] in
                    let rows = try Row.fetchAll(db, sql: """
                        SELECT route, slug FROM (
                          SELECT t.route AS route, src.slug AS slug,
                                 ROW_NUMBER() OVER (
                                     PARTITION BY t.route
                                     ORDER BY \(self.priorityCaseSQL) ASC) AS rn
                            FROM \(table) t
                            JOIN sources src ON src.id = t.source_id
                           WHERE t.substance_id = :id
                             AND src.slug IN (\(self.enabledSourceListSQL))
                        ) WHERE rn = 1
                    """, arguments: ["id": substanceID])
                    return Dictionary(uniqueKeysWithValues: rows.map { ($0["route"], $0["slug"]) })
                }
                let doseSlugs = try winningSlugByRawRoute("dose_ranges")
                let durationSlugs = try winningSlugByRawRoute("durations")

                let routes = try resolvedRoutes(db: db, substanceID: substanceID).map(\.route)
                var routesBySource: [RouteOfAdministration: RouteProvenance] = [:]
                routesBySource.reserveCapacity(routes.count)
                for route in routes {
                    routesBySource[route] = RouteProvenance(
                        doseSource: doseSlugs[route.rawValue],
                        durationSource: durationSlugs[route.rawValue],
                    )
                }

                return SubstanceProvenance(
                    categorySource: fieldRow?["category_source"],
                    halfLifeSource: fieldRow?["half_life_source"],
                    mechanismSource: fieldRow?["mechanism_source"],
                    routesBySource: routesBySource,
                )
            }
        } catch {
            logger.error("provenance(substanceID:) failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// The enabled sources that supply `field` for this substance, ranked by the
    /// user's current priority (winner first). Same ordering as the resolvers, so
    /// the first element is exactly the source the UI shows. Powers the badge's
    /// "why this source?" explainer — higher-priority sources absent from the list
    /// simply had no value for this field, which is *why* a lower one won.
    func sourcesProviding(_ field: AttributableField, substanceID: Int64) -> [String] {
        let (table, whereClause, args) = field.query
        do {
            return try db.read { db in
                try String.fetchAll(db, sql: """
                    SELECT DISTINCT src.slug FROM \(table) t
                      JOIN sources src ON src.id = t.source_id
                     WHERE t.substance_id = ? \(whereClause)
                       AND src.slug IN (\(enabledSourceListSQL))
                     ORDER BY \(priorityCaseSQL) ASC
                """, arguments: StatementArguments([substanceID] + args))
            }
        } catch {
            logger.error("sourcesProviding failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}

extension SubstanceStore {
    typealias RouteProvenance = Piru.RouteProvenance
    typealias SubstanceProvenance = Piru.SubstanceProvenance
    typealias AttributableField = Piru.AttributableField

    /// Name-keyed entries to the provenance resolvers — the store contributes
    /// only the alias resolution.
    func provenance(forSubstanceName name: String) -> SubstanceProvenance? {
        guard let substanceID = substanceID(forNameOrAlias: name) else { return nil }
        return reader.provenance(substanceID: substanceID)
    }

    func sourcesProviding(_ field: AttributableField, forSubstanceName name: String) -> [String] {
        guard let substanceID = substanceID(forNameOrAlias: name) else { return [] }
        return reader.sourcesProviding(field, substanceID: substanceID)
    }
}
