import Foundation
import GRDB

/// The two curated pair-shaped pharmacology tables: which drugs modulate which
/// clearing enzyme (`enzyme_modulators`), and which drug pairs react to form a
/// third active species (`combination_metabolites`). Both are whole-table reads —
/// a dozen rows each, consulted by every substance page and by the checker — so
/// they load once and are held rather than queried per lookup.
///
/// Neither is source-resolved. Both are single-source curated tables whose row
/// identity is a curated id rather than a substance, so there is no second
/// source's value to rank against.
extension SubstanceReadModel {
    /// The whole `enzyme_modulators` table with each rule's matcher names attached.
    ///
    /// A row whose `modulator_id`, origin, enzyme, direction or strength does not decode is skipped:
    /// the readout renders every one of those as a word in a sentence, so a value the app cannot
    /// name has nothing to render and must not reach the screen half-formed.
    nonisolated static func enzymeModulators(db queue: DatabaseQueue) -> [MetabolicModulation.Modulator] {
        let matchers = matchers(relation: "enzyme-modulator", db: queue)
        let rows = (try? queue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT modulator_id, origin, enzyme, direction, strength, confidence
                  FROM enzyme_modulators
                 ORDER BY rank ASC
            """)
        }) ?? []
        return rows.compactMap { row -> MetabolicModulation.Modulator? in
            guard let rawID: String = row["modulator_id"],
                  let id = MetabolicModulation.ModulatorID(rawValue: rawID),
                  let origin = (row["origin"] as String?).flatMap(MetabolicModulation.Modulator.Origin.init(rawValue:)),
                  let enzyme = (row["enzyme"] as String?).flatMap(MetabolicModulation.Enzyme.init(rawValue:)),
                  let direction = (row["direction"] as String?).flatMap(MetabolicModulation.Direction.init(rawValue:)),
                  let strength = (row["strength"] as String?).flatMap(MetabolicModulation.Strength.init(rawValue:))
            else { return nil }
            return MetabolicModulation.Modulator(
                id: id,
                origin: origin,
                enzyme: enzyme,
                direction: direction,
                strength: strength,
                confidence: (row["confidence"] as String?).flatMap(ConfidenceTier.init(rawValue:)) ?? .unverified,
                matchers: matchers[rawID]?[0] ?? [],
            )
        }
    }

    /// The whole `combination_metabolites` table with each combination's precursor slots attached.
    /// A combination with fewer than two slots is skipped — with one precursor the species is an
    /// ordinary metabolite and would be claimed to form whenever that drug alone is onboard.
    nonisolated static func combinationMetabolites(db queue: DatabaseQueue) -> [CombinationMetabolite.Definition] {
        let matchers = matchers(relation: "combination-precursor", db: queue)
        let rows = (try? queue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT combination_id, metabolite_name, confidence
                  FROM combination_metabolites
                 ORDER BY combination_id ASC
            """)
        }) ?? []
        return rows.compactMap { row -> CombinationMetabolite.Definition? in
            guard let rawID: String = row["combination_id"],
                  let id = CombinationMetabolite.CombinationID(rawValue: rawID),
                  let slots = matchers[rawID], slots.count >= 2
            else { return nil }
            return CombinationMetabolite.Definition(
                id: id,
                metaboliteName: row["metabolite_name"],
                precursors: slots.keys.sorted().map { slots[$0] ?? [] },
                confidence: (row["confidence"] as String?).flatMap(ConfidenceTier.init(rawValue:)) ?? .unverified,
            )
        }
    }

    /// One relation's matcher names, as owner id → slot → names. `pharmacology_matchers` holds several
    /// relations that must never be mixed, so the relation is always part of the query rather than a
    /// filter the caller is trusted to apply.
    private nonisolated static func matchers(
        relation: String, db queue: DatabaseQueue,
    ) -> [String: [Int: [String]]] {
        let rows = (try? queue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT owner_id, slot, matcher
                  FROM pharmacology_matchers
                 WHERE relation = ?
                 ORDER BY owner_id ASC, slot ASC, matcher ASC
            """, arguments: [relation])
        }) ?? []
        var out: [String: [Int: [String]]] = [:]
        for row in rows {
            guard let owner: String = row["owner_id"], let matcher: String = row["matcher"] else { continue }
            let slot = (row["slot"] as Int64?).map(Int.init) ?? 0
            out[owner, default: [:]][slot, default: []].append(matcher)
        }
        return out
    }
}
