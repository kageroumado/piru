import Foundation

/// Mirrors the JSON written by the build pipeline (`pipeline/build/sqlite.py`,
/// invoked via `pipeline/build.sh`).
///
/// The build script emits a manifest alongside `piru-substances.sqlite`. The
/// app uses the local copy as the baseline (what's currently installed) and
/// fetches the remote copy from the project's GitHub raw URL to see whether
/// an update is available. The `sqlite_sha256` is the integrity check applied
/// after a downloaded DB lands on disk.
struct SubstanceDBManifest: Codable, Equatable, Hashable {
    /// Schema version of the manifest itself. Increment when fields change in
    /// a backwards-incompatible way; the app refuses to apply manifests with
    /// a schema_version higher than it understands.
    let schemaVersion: Int

    /// `YYYY-MM-DD.N` content build. Lexicographically comparable — a newer
    /// build sorts after an older one because the date dominates and the
    /// `.N` suffix increments within the same calendar day.
    let contentVersion: String

    let generatedAt: String
    let generatorVersion: String

    let substanceCount: Int

    /// Per-source row counts (kept as JSON for forward compat — new tables
    /// can land without breaking older clients).
    let sources: [String: [String: Int]]

    /// Repo-relative path to the SQLite file. The remote download URL is
    /// derived by joining this onto the manifest's raw URL prefix.
    let sqlitePath: String
    let sqliteSha256: String
    let sqliteSizeBytes: Int

    let releaseNotes: String

    /// JSON decoder configured with the snake_case key strategy the build
    /// script emits. Static so callers don't have to remember.
    static let jsonDecoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        return dec
    }()

    /// JSON encoder for round-tripping back to the build-script format —
    /// used when persisting the applied manifest alongside a downloaded DB.
    static let jsonEncoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.keyEncodingStrategy = .convertToSnakeCase
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return enc
    }()

    /// Returns `true` when `other` represents a newer content build than this
    /// one. The comparison treats `contentVersion` as a lexicographic string,
    /// which works because the format `YYYY-MM-DD.N` sorts chronologically.
    func isOlderThan(_ other: SubstanceDBManifest) -> Bool {
        contentVersion < other.contentVersion
    }
}
