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
                SourcedSubstance(substance: $0, provenance: .curated, inchiKey: nil, pubchemCID: nil, cas: nil)
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
