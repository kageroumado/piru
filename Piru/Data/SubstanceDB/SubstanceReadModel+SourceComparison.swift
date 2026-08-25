import Foundation
import GRDB

/// One source's dose ladder for a route — the raw per-source rows behind the
/// single resolved ladder the dose card shows.
///
/// The card resolves a ladder by source priority and shows one number. That
/// hides a real disagreement: for methamphetamine's oral route, "Common" is
/// 15–30 mg to drug.community, 10–25 to PsychonautWiki, 10–30 to TripSit and
/// 10–20 to freeodwiki. None of them is wrong — they are measuring different
/// populations and intents — but a reader who only sees one has no way to
/// know the spread exists.
nonisolated struct SourceDoseLadder: Identifiable, Sendable {
    let sourceSlug: String
    let unit: String
    let doses: DoseRange
    /// True for the source currently supplying the card's ladder.
    var isActive: Bool

    var id: String {
        sourceSlug
    }
}

extension SubstanceReadModel {
    /// Every source's dose ladder for one route, ordered by the user's source
    /// priority (so the active one leads), with the active one flagged.
    ///
    /// Deliberately **not** filtered to enabled sources: the point of the sheet
    /// is to show what else exists, including a source the user has switched
    /// off. Salt/isomer variants collapse to the base row — a four-way salt ×
    /// four-way source matrix is a table, not a comparison.
    func sourceDoseLadders(
        substanceID: Int64, route: RouteOfAdministration, activeSlug: String?,
    ) -> [SourceDoseLadder] {
        do {
            let rows = try db.read { db in
                try Row.fetchAll(db, sql: """
                    SELECT src.slug AS slug, d.unit AS unit, d.threshold AS threshold,
                           d.light_lower, d.light_upper, d.common_lower, d.common_upper,
                           d.strong_lower, d.strong_upper, d.heavy
                      FROM dose_ranges d
                      JOIN sources src ON src.id = d.source_id
                     WHERE d.substance_id = ?
                       AND d.route = ?
                       AND d.salt_form IS NULL
                       AND d.isomer IS NULL
                """, arguments: [substanceID, route.rawValue])
            }
            let ladders = rows.compactMap { row -> SourceDoseLadder? in
                guard let slug: String = row["slug"] else { return nil }
                let doses = DoseRange(
                    threshold: row["threshold"],
                    light: Self.rangeFrom(lower: row["light_lower"], upper: row["light_upper"]),
                    common: Self.rangeFrom(lower: row["common_lower"], upper: row["common_upper"]),
                    strong: Self.rangeFrom(lower: row["strong_lower"], upper: row["strong_upper"]),
                    heavy: row["heavy"],
                )
                guard doses.hasAnyValue else { return nil }
                return SourceDoseLadder(
                    sourceSlug: slug,
                    unit: row["unit"] ?? "mg",
                    doses: doses,
                    isActive: slug == activeSlug,
                )
            }
            // Active first, then the user's configured priority, then the rest
            // alphabetically so the order is stable between openings.
            let priority = order
            return ladders.sorted { lhs, rhs in
                if lhs.isActive != rhs.isActive { return lhs.isActive }
                let li = priority.firstIndex(of: lhs.sourceSlug) ?? Int.max
                let ri = priority.firstIndex(of: rhs.sourceSlug) ?? Int.max
                if li != ri { return li < ri }
                return lhs.sourceSlug < rhs.sourceSlug
            }
        } catch {
            return []
        }
    }
}

extension SubstanceStore {
    typealias SourceDoseLadder = Piru.SourceDoseLadder

    /// Name-keyed entry to ``SubstanceReadModel/sourceDoseLadders(substanceID:route:activeSlug:)``
    /// — the store contributes alias resolution and the active-slug lookup
    /// (provenance is a store API).
    func doseLadders(forSubstanceName name: String, route: RouteOfAdministration) -> [SourceDoseLadder] {
        guard let substanceID = substanceID(forNameOrAlias: name) else { return [] }
        let activeSlug = provenance(forSubstanceName: name)?.routesBySource[route]?.doseSource
        return reader.sourceDoseLadders(substanceID: substanceID, route: route, activeSlug: activeSlug)
    }
}
