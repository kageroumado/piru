import Foundation
import GRDB
import os

private nonisolated let logger = Logger(subsystem: "dev.yumeji.piru", category: "SubstanceStore")

/// Per-field source attribution — which source actually won each displayed field
/// after priority resolution. Split out of ``SubstanceStore`` for file size (the
/// main type sits against the 2500-line lint cap); the resolvers whose ordering
/// this mirrors stay there.
extension SubstanceStore {
    /// Source attribution for the fields displayed in a substance detail
    /// view. Distinct from the substance-level `sources` list (which is just
    /// "every source that contributed anything") — this surfaces *which*
    /// source supplied a specific field after priority resolution.
    struct RouteProvenance: Hashable {
        let doseSource: String?
        let durationSource: String?
    }

    struct SubstanceProvenance: Hashable {
        let categorySource: String?
        let halfLifeSource: String?
        let mechanismSource: String?
        /// Keyed by route for O(1) lookup from per-route UI rows. Routes
        /// without any source data (e.g. the route is in `dose_ranges` but no
        /// enabled source has it after priority resolution) are simply absent.
        let routesBySource: [RouteOfAdministration: RouteProvenance]
    }

    /// Resolves per-field source slugs for a substance using the same
    /// priority order as the field resolvers themselves, so the slug shown
    /// in the UI matches the source that actually won the field.
    func provenance(forSubstanceName name: String) -> SubstanceProvenance? {
        guard let substanceID = substanceID(forNameOrAlias: name) else { return nil }
        do {
            return try substancesDB.read { db in
                let categorySource = try fieldSource(
                    db: db,
                    sql: """
                        SELECT src.slug FROM categories c
                          JOIN sources src ON src.id = c.source_id
                         WHERE c.substance_id = ?
                           AND src.slug IN (\(enabledSourceListSQL))
                         ORDER BY \(priorityCaseSQL) ASC LIMIT 1
                    """,
                    substanceID: substanceID,
                )
                let halfLifeSource = try fieldSource(
                    db: db,
                    sql: """
                        SELECT src.slug FROM half_lives h
                          JOIN sources src ON src.id = h.source_id
                         WHERE h.substance_id = ?
                           AND src.slug IN (\(enabledSourceListSQL))
                         ORDER BY \(priorityCaseSQL) ASC LIMIT 1
                    """,
                    substanceID: substanceID,
                )
                let mechanismSource = try fieldSource(
                    db: db,
                    sql: """
                        SELECT src.slug FROM mechanisms_summary m
                          JOIN sources src ON src.id = m.source_id
                         WHERE m.substance_id = ?
                           AND src.slug IN (\(enabledSourceListSQL))
                         ORDER BY \(priorityCaseSQL) ASC LIMIT 1
                    """,
                    substanceID: substanceID,
                )

                let routes = try resolvedRoutes(db: db, substanceID: substanceID).map(\.route)
                var routesBySource: [RouteOfAdministration: RouteProvenance] = [:]
                routesBySource.reserveCapacity(routes.count)
                for route in routes {
                    let doseSource = try fieldSource(
                        db: db,
                        sql: """
                            SELECT src.slug FROM dose_ranges d
                              JOIN sources src ON src.id = d.source_id
                             WHERE d.substance_id = ? AND d.route = ?
                               AND src.slug IN (\(enabledSourceListSQL))
                             ORDER BY \(priorityCaseSQL) ASC LIMIT 1
                        """,
                        substanceID: substanceID,
                        extra: [route.rawValue],
                    )
                    let durationSource = try fieldSource(
                        db: db,
                        sql: """
                            SELECT src.slug FROM durations du
                              JOIN sources src ON src.id = du.source_id
                             WHERE du.substance_id = ? AND du.route = ?
                               AND src.slug IN (\(enabledSourceListSQL))
                             ORDER BY \(priorityCaseSQL) ASC LIMIT 1
                        """,
                        substanceID: substanceID,
                        extra: [route.rawValue],
                    )
                    routesBySource[route] = RouteProvenance(
                        doseSource: doseSource,
                        durationSource: durationSource,
                    )
                }

                return SubstanceProvenance(
                    categorySource: categorySource,
                    halfLifeSource: halfLifeSource,
                    mechanismSource: mechanismSource,
                    routesBySource: routesBySource,
                )
            }
        } catch {
            logger.error("provenance(forSubstanceName:) failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Helper: fetch a single source slug given a `SELECT src.slug …` query.
    private func fieldSource(db: Database, sql: String, substanceID: Int64, extra: [DatabaseValueConvertible] = []) throws -> String? {
        var values: [DatabaseValueConvertible] = [substanceID]
        values.append(contentsOf: extra)
        return try String.fetchOne(db, sql: sql, arguments: StatementArguments(values))
    }
}
