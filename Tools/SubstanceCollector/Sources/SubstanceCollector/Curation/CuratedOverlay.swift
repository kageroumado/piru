import Foundation

/// Loader for the optional curated overlay JSON. Schema matches the iOS
/// `Substance` Codable: an array of fully-formed records.
///
/// When present, every entry takes precedence over the same compound from any
/// web source. The overlay is hand-curated by a sister agent and is the right
/// place to fix wrong doses or add reference data for compounds the scrapers
/// missed.
enum CuratedOverlayLoader {
    struct Loaded {
        let entries: [SourcedSubstance]
        /// Optional metadata file in JSON like `{"meta": {...}, "substances": [...]}`
        let warning: String?
    }

    static func load(path: URL) -> Loaded {
        guard FileManager.default.fileExists(atPath: path.path) else {
            return Loaded(entries: [], warning: "Curated overlay not found at \(path.path) — proceeding without it.")
        }
        do {
            let data = try Data(contentsOf: path)
            // Allow either bare array OR wrapped form.
            let decoded: [BundledSubstance]
            if let direct = try? JSONDecoder().decode([BundledSubstance].self, from: data) {
                decoded = direct
            } else if let wrapped = try? JSONDecoder().decode(Wrapped.self, from: data) {
                decoded = wrapped.substances
            } else {
                return Loaded(
                    entries: [],
                    warning: "Curated overlay at \(path.path) failed to decode as either [Substance] or {substances: [...]}; ignored."
                )
            }
            let entries = decoded.map {
                // Lift chemical identifiers onto the wrapper as well, so the
                // merge/dedup pipeline can match curated entries on InChIKey/CID.
                // They also remain on the substance object (encoded by
                // BundledSubstance) for the SQLite builder to read directly.
                SourcedSubstance(
                    substance: $0,
                    provenance: .curated,
                    inchiKey: $0.inchikey,
                    pubchemCID: $0.pubchemCID,
                    cas: $0.cas
                )
            }
            return Loaded(entries: entries, warning: nil)
        } catch {
            return Loaded(
                entries: [],
                warning: "Curated overlay at \(path.path) errored: \(error.localizedDescription); ignored."
            )
        }
    }

    private struct Wrapped: Codable {
        let substances: [BundledSubstance]
    }
}
