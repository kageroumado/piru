import Foundation
import GRDB
import os

extension SubstanceReadModel {
    /// Preserve each published profile independently of route normalization and
    /// source rank. Turning the source off still hides its reference records.
    func wikiDoseReferences(substanceID: Int64) -> [WikiDoseReferenceRecord] {
        do {
            return try db.read { db in
                guard try db.tableExists("drug_community_dose_references") else { return [] }
                let rows = try Row.fetchAll(db, sql: """
                    SELECT r.* FROM drug_community_dose_references r
                    JOIN sources src ON src.id = r.source_id
                    WHERE r.substance_id = ? AND src.slug IN (\(enabledSourceListSQL))
                    ORDER BY r.source_name, r.record_key
                """, arguments: [substanceID])
                return rows.compactMap { row in
                    do {
                        return try WikiDoseReferenceRecord(
                            id: row["record_key"], sourceName: row["source_name"],
                            profileSHA256: row["profile_sha256"], snapshotSHA256: row["snapshot_sha256"],
                            releaseID: row["release_id"], modelJSON: row["model_json"],
                        )
                    } catch {
                        Logger.substanceStore.error("Skipping invalid dose reference: \(error.localizedDescription, privacy: .public)")
                        return nil
                    }
                }
            }
        } catch {
            Logger.substanceStore.error("wikiDoseReferences failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}

extension SubstanceStore {
    func wikiDoseReferences(forSubstanceName name: String) -> [WikiDoseReferenceRecord] {
        guard let substanceID = substanceID(forNameOrAlias: name) else { return [] }
        return reader.wikiDoseReferences(substanceID: substanceID)
    }
}
