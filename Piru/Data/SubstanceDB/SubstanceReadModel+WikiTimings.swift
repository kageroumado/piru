import Foundation
import GRDB
import os

extension SubstanceReadModel {
    /// Every reference entry survives independently of source rank or route
    /// normalization. Disabling the source still hides its reference material.
    func wikiTimings(substanceID: Int64) -> [WikiTimingRecord] {
        do {
            return try db.read { db in
                guard try db.tableExists("drug_community_timelines") else { return [] }
                let rows = try Row.fetchAll(db, sql: """
                    SELECT t.* FROM drug_community_timelines t
                    JOIN sources src ON src.id = t.source_id
                    WHERE t.substance_id = ? AND src.slug IN (\(enabledSourceListSQL))
                    ORDER BY t.source_name, t.kind, t.entry_index
                """, arguments: [substanceID])
                return try rows.map { row in
                    try WikiTimingRecord(
                        id: row["record_key"], sourceName: row["source_name"],
                        route: row["route"], kind: row["kind"], entryIndex: row["entry_index"],
                        releaseID: row["release_id"], entryJSON: row["entry_json"],
                        timingTextJSON: row["duration_text_json"],
                        hasSourceException: (row["modeling_exclusion"] as String) == "source_exception",
                    )
                }
            }
        } catch {
            Logger.substanceStore.error("wikiTimings failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}

extension SubstanceStore {
    func wikiTimings(forSubstanceName name: String) -> [WikiTimingRecord] {
        guard let substanceID = substanceID(forNameOrAlias: name) else { return [] }
        return reader.wikiTimings(substanceID: substanceID)
    }
}
