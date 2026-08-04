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
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path.path, isDirectory: &isDir) else {
            return Loaded(entries: [], warning: "Curated source not found at \(path.path) — proceeding without it.")
        }
        do {
            let decoded: [BundledSubstance]
            if isDir.boolValue {
                // Directory of one-substance-per-file JSON (the current layout).
                let files = (try? FileManager.default.contentsOfDirectory(at: path, includingPropertiesForKeys: nil))?
                    .filter { $0.pathExtension == "json" }
                    .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
                var subs: [BundledSubstance] = []
                for f in files {
                    guard let d = try? Data(contentsOf: f) else { continue }
                    if let one = try? JSONDecoder().decode(BundledSubstance.self, from: d) {
                        subs.append(one)
                    }
                }
                decoded = subs
            } else {
                // Legacy single-file overlay: bare array OR {substances: [...]}.
                let data = try Data(contentsOf: path)
                if let direct = try? JSONDecoder().decode([BundledSubstance].self, from: data) {
                    decoded = direct
                } else if let wrapped = try? JSONDecoder().decode(Wrapped.self, from: data) {
                    decoded = wrapped.substances
                } else {
                    return Loaded(
                        entries: [],
                        warning: "Curated overlay at \(path.path) failed to decode as either [Substance] or {substances: [...]}; ignored.",
                    )
                }
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
                    cas: $0.cas,
                )
            }
            return Loaded(entries: entries, warning: nil)
        } catch {
            return Loaded(
                entries: [],
                warning: "Curated overlay at \(path.path) errored: \(error.localizedDescription); ignored.",
            )
        }
    }

    private struct Wrapped: Codable {
        let substances: [BundledSubstance]
    }
}
