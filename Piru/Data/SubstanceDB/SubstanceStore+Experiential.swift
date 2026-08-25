import Foundation
import GRDB
import os

private nonisolated let logger = Logger(subsystem: "dev.yumeji.piru", category: "SubstanceStore")

/// drug.community experiential reads (the intensity spectrum and the reported
/// effects) plus the offline-generated 2D molecular structure. Split out of
/// `SubstanceStore.swift` to keep that file under its length cap.
extension SubstanceStore {
    private struct RawBandEffect: Decodable {
        let name: String
        let freq: Int
    }

    /// The drug.community intensity spectrum for a substance, ordered
    /// Threshold → Overdose. Empty when the substance has no spectrum or the
    /// drug.community source is disabled. Drives the dose-intensity dial.
    func spectrumBands(forSubstanceName name: String) -> [SpectrumBand] {
        guard let substanceID = substanceID(forNameOrAlias: name) else { return [] }
        do {
            let rows = try substancesDB.read { db in
                try Row.fetchAll(db, sql: """
                    SELECT sl.band_index, sl.band_name, sl.description,
                           sl.top_effects_json
                      FROM spectrum_levels sl
                      JOIN sources src ON src.id = sl.source_id
                     WHERE sl.substance_id = ?
                       AND src.slug IN (\(reader.enabledSourceListSQL))
                     ORDER BY sl.band_index
                """, arguments: [substanceID])
            }
            let decoder = JSONDecoder()
            return rows.map { row in
                let topEffects: [BandEffect] = if let json = row["top_effects_json"] as String?,
                                                  let data = json.data(using: .utf8),
                                                  let raw = try? decoder.decode([RawBandEffect].self, from: data) {
                    raw.map { BandEffect(name: $0.name, frequency: $0.freq) }
                } else {
                    []
                }
                return SpectrumBand(
                    bandIndex: row["band_index"],
                    bandKey: row["band_name"],
                    summary: (row["description"] as String?) ?? "",
                    topEffects: topEffects,
                )
            }
        } catch {
            logger.error("spectrumBands(forSubstanceName:) failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// The drug.community reported effects for a substance, frequency-descending.
    /// Empty when the substance has no reported effects or the source is
    /// disabled. Drives the grouped, frequency-barred effects list.
    func reportedEffects(forSubstanceName name: String) -> [ReportedEffect] {
        guard let substanceID = substanceID(forNameOrAlias: name) else { return [] }
        let language = reader.language
        do {
            let rows = try substancesDB.read { db in
                try Row.fetchAll(db, sql: """
                    SELECT re.name, re.domain, re.report_count, re.emerges_band,
                           (SELECT lbl.label FROM effect_vocab_labels lbl
                             WHERE lbl.vocab_id = re.vocab_id AND lbl.language = ?) AS loc_label,
                           (SELECT lbl.label FROM effect_vocab_labels lbl
                             WHERE lbl.vocab_id = re.vocab_id AND lbl.language = 'en') AS en_label
                      FROM reported_effects re
                      JOIN sources src ON src.id = re.source_id
                     WHERE re.substance_id = ?
                       AND src.slug IN (\(reader.enabledSourceListSQL))
                     ORDER BY re.report_count DESC, re.name COLLATE NOCASE
                """, arguments: [language.rawValue, substanceID])
            }
            return rows.map { row in
                let raw: String = row["name"]
                let localized = row["loc_label"] as String?
                let english = row["en_label"] as String?
                let display: String = if language.isChinese {
                    localized ?? english ?? raw
                } else if let english, english.count <= raw.count {
                    // English keeps its own vocab label only when it isn't longer
                    // than the raw drug.community phrasing (some vocab terms are verbose).
                    english
                } else {
                    raw
                }
                return ReportedEffect(
                    name: raw,
                    displayName: display,
                    domain: EffectDomain(rawValue: row["domain"]) ?? .physical,
                    reportCount: row["report_count"],
                    emergesBand: row["emerges_band"] as Int?,
                )
            }
        } catch {
            logger.error("reportedEffects(forSubstanceName:) failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private struct RawMoleculeAtom: Decodable {
        let el: String
        let x: Double
        let y: Double
    }

    private struct RawMoleculeBond: Decodable {
        let a: Int
        let b: Int
        let order: Int
    }

    /// The substance's 2D skeletal-structure diagram, if one was generated at
    /// build time (offline, from `smiles` — see `molecule_shapes.py`). `nil`
    /// when the substance has no SMILES or the structure failed to parse
    /// (~860 substances currently have neither). Purely derived data — no
    /// source-priority gating, unlike most `SubstanceStore` queries.
    func moleculeStructure(forSubstanceName name: String) -> MoleculeStructure? {
        guard let substanceID = substanceID(forNameOrAlias: name) else { return nil }
        do {
            let row = try substancesDB.read { db in
                try Row.fetchOne(db, sql: """
                    SELECT atoms_json, bonds_json
                      FROM molecule_shapes
                     WHERE substance_id = ?
                """, arguments: [substanceID])
            }
            guard let row,
                  let atomsJSON = (row["atoms_json"] as String?)?.data(using: .utf8),
                  let bondsJSON = (row["bonds_json"] as String?)?.data(using: .utf8)
            else { return nil }
            let decoder = JSONDecoder()
            let rawAtoms = try decoder.decode([RawMoleculeAtom].self, from: atomsJSON)
            let rawBonds = try decoder.decode([RawMoleculeBond].self, from: bondsJSON)
            guard !rawAtoms.isEmpty else { return nil }
            return MoleculeStructure(
                atoms: rawAtoms.map { MoleculeAtom(element: $0.el, x: $0.x, y: $0.y) },
                bonds: rawBonds.map { MoleculeBond(a: $0.a, b: $0.b, order: $0.order) },
            )
        } catch {
            logger.error("moleculeStructure(forSubstanceName:) failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
