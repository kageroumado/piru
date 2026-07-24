import CryptoKit
import Foundation
import Observation
import os

private nonisolated let updaterLogger = Logger(subsystem: "dev.yumeji.piru", category: "SubstanceDBUpdater")

/// Manifest-driven, opt-in updater for the bundled substance database.
///
/// ## Why opt-in
///
/// The substance DB ships with the app. Each release pushes a fresh build to
/// the App Store. Between releases, users can pull a newer build of the same
/// data from the project's GitHub raw URL if they want — the manifest tells
/// us whether anything changed since the bundled version.
///
/// ## How it works
///
/// 1. Local baseline: parse the bundled `manifest.json`. This is the
///    *minimum* content version the app ships with.
/// 2. Effective: if `Documents/piru-substances-updated.sqlite` exists, the
///    *applied* manifest is `Documents/piru-substances-updated.manifest.json`.
///    Either way, ``SubstanceStore`` picks the right file at launch (it
///    prefers the Documents copy when present).
/// 3. Remote: fetched from ``manifestURL`` on demand. Compared via
///    ``SubstanceDBManifest/isOlderThan(_:)``.
/// 4. Download: the SQLite is fetched, its sha256 is verified against the
///    remote manifest, then *both* files are atomically moved into
///    `Documents/`.
/// 5. Apply: the next app launch picks up the Documents copy via
///    ``SubstanceStore`` re-init logic.
///
/// ## Safety
///
/// - Verifies sha256 before applying — a corrupted download is rejected.
/// - Refuses manifests with a `schema_version` newer than the app
///   understands. (Currently `1`.)
/// - Writes are atomic via temp-file + rename so a crash mid-update can't
///   leave a half-applied DB.
@MainActor
@Observable
final class SubstanceDBUpdater {
    static let shared = SubstanceDBUpdater()

    /// The base URL of the project's GitHub raw mirror. Read from Info.plist
    /// key `PiruManifestURL` so different environments (staging, fork) can
    /// override without code changes. Defaults to the canonical repo.
    let manifestURL: URL = {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "PiruManifestURL") as? String,
           let url = URL(string: raw) {
            return url
        }
        return URL(string: "https://raw.githubusercontent.com/kageroumado/piru/main/Piru/Data/manifest.json")!
    }()

    /// Fallback for ``supportedSchemaVersion`` used only if the bundled
    /// `manifest.json` cannot be read (a broken build). Keep it equal to the
    /// current bundled schema; it never governs a healthy install.
    private static let fallbackSupportedSchemaVersion = 6

    /// Highest bundled-DB `schema_version` this build's reader understands.
    ///
    /// Derived from the shipped `manifest.json` rather than hardcoded: the app
    /// ships its reader code and its bundled DB together, so the bundled
    /// manifest's schema version *is* the schema this binary supports, and it
    /// tracks the schema automatically on every rebuild. A hardcoded `1` here
    /// previously rejected every OTA update once the schema advanced to 6
    /// (`remote.schemaVersion <= 1` is false for a schema-6 manifest), so
    /// "Check for Updates" always errored with "requires a newer version."
    private static let supportedSchemaVersion: Int = {
        guard let url = Bundle.main.url(forResource: "manifest", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let manifest = try? SubstanceDBManifest.jsonDecoder.decode(SubstanceDBManifest.self, from: data)
        else { return fallbackSupportedSchemaVersion }
        return manifest.schemaVersion
    }()

    /// Coarse-grained state surface the Settings UI binds to.
    enum State: Equatable {
        case idle
        case checking
        case upToDate(local: SubstanceDBManifest)
        case updateAvailable(local: SubstanceDBManifest, remote: SubstanceDBManifest)
        case downloading(progress: Double)
        case appliedNeedsRestart(applied: SubstanceDBManifest)
        case error(String)
    }

    private(set) var state: State = .idle

    private static var documentsDir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var appliedSQLiteURL: URL {
        documentsDir.appendingPathComponent("piru-substances-updated.sqlite")
    }

    private static var appliedManifestURL: URL {
        documentsDir.appendingPathComponent("piru-substances-updated.manifest.json")
    }

    /// The manifest of the database currently in use — the applied update if
    /// present, otherwise the bundled one.
    var currentManifest: SubstanceDBManifest? {
        if let applied = loadAppliedManifest() { return applied }
        return loadBundledManifest()
    }

    // MARK: - Public API

    /// Hit the remote manifest URL, compare to the local one, update ``state``.
    /// Non-throwing — errors land in `.error(...)` state.
    func checkForUpdates() async {
        state = .checking
        do {
            let data = try await fetchRemoteManifestData()
            state = evaluateManifest(remoteData: data)
        } catch {
            updaterLogger.error("checkForUpdates failed: \(error.localizedDescription, privacy: .public)")
            state = .error(error.localizedDescription)
        }
    }

    /// Pure decision step: given the raw remote manifest bytes (or any test
    /// fixture in the same shape), figure out what state we should land in.
    /// Exposed so the state machine can be unit tested without a live
    /// `URLSession` — see `SubstanceDBUpdaterTests`.
    func evaluateManifest(remoteData: Data) -> State {
        let remote: SubstanceDBManifest
        do {
            remote = try SubstanceDBManifest.jsonDecoder.decode(SubstanceDBManifest.self, from: remoteData)
        } catch {
            return .error(error.localizedDescription)
        }
        guard remote.schemaVersion <= Self.supportedSchemaVersion else {
            return .error("This database requires a newer version of Piru.")
        }
        guard let local = currentManifest else {
            return .updateAvailable(local: placeholderLocal(), remote: remote)
        }
        return local.isOlderThan(remote)
            ? .updateAvailable(local: local, remote: remote)
            : .upToDate(local: local)
    }

    /// Download the SQLite file referenced by the current `.updateAvailable`
    /// state, verify its sha256, and atomically move it into Documents/.
    /// Result lands in `.appliedNeedsRestart(...)` or `.error(...)`.
    /// On any failure (download, checksum mismatch, install), the temp file
    /// is removed so we don't leak partial downloads into the user's temp dir.
    func downloadAndApply() async {
        guard case let .updateAvailable(_, remote) = state else { return }
        state = .downloading(progress: 0)

        var tempFile: URL?
        defer {
            if let tempFile, FileManager.default.fileExists(atPath: tempFile.path) {
                try? FileManager.default.removeItem(at: tempFile)
            }
        }

        do {
            let sqliteRemote = sqliteURL(from: remote)
            let downloaded = try await downloadFile(url: sqliteRemote) { progress in
                self.state = .downloading(progress: progress)
            }
            tempFile = downloaded
            try verifySha256(file: downloaded, expected: remote.sqliteSha256)
            try installDownloadedDB(tempFile: downloaded, manifest: remote)
            // installDownloadedDB moves the file out — null the local
            // reference so the defer doesn't try to remove a no-longer-temp
            // file at the Documents path.
            tempFile = nil
            state = .appliedNeedsRestart(applied: remote)
        } catch {
            updaterLogger.error("downloadAndApply failed: \(error.localizedDescription, privacy: .public)")
            state = .error(error.localizedDescription)
        }
    }

    /// Discard a previously applied update and revert to the bundled DB on
    /// next launch. Safe to call when no update is applied (no-op).
    func revertToBundled() throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: Self.appliedSQLiteURL.path) {
            try fm.removeItem(at: Self.appliedSQLiteURL)
        }
        if fm.fileExists(atPath: Self.appliedManifestURL.path) {
            try fm.removeItem(at: Self.appliedManifestURL)
        }
        state = .idle
    }

    /// Launch-recovery: delete a corrupt / half-applied updated DB — the SQLite
    /// file, its manifest, and any leftover `-wal`/`-shm` siblings — so the next
    /// open falls back to the bundled DB. `static` so ``SubstanceStore`` can call
    /// it during its own `init`, before any updater instance exists. Best-effort:
    /// a missing file is fine, and a failed delete is logged but not fatal.
    static func quarantineAppliedDB() {
        let fm = FileManager.default
        let targets = [
            appliedSQLiteURL,
            URL(fileURLWithPath: appliedSQLiteURL.path + "-wal"),
            URL(fileURLWithPath: appliedSQLiteURL.path + "-shm"),
            appliedManifestURL,
        ]
        for url in targets where fm.fileExists(atPath: url.path) {
            do {
                try fm.removeItem(at: url)
            } catch {
                updaterLogger.error("quarantineAppliedDB: failed to remove \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Internals

    private func fetchRemoteManifestData() async throws -> Data {
        var request = URLRequest(url: manifestURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw UpdaterError.httpStatus(http.statusCode)
        }
        return data
    }

    private func sqliteURL(from manifest: SubstanceDBManifest) -> URL {
        Self.sqliteURL(manifestURL: manifestURL, manifest: manifest)
    }

    /// Build the SQLite download URL by joining the manifest-relative
    /// `sqlite_path` onto the manifest URL's repo root.
    ///
    /// The manifest URL is structured as `<repo-root>/Piru/Data/manifest.json`
    /// — stripping the trailing two path components (`Data/manifest.json`)
    /// plus the `Piru/` segment yields the repo root that `sqlite_path` is
    /// relative to. Exposed as `internal` so the URL arithmetic can be unit
    /// tested directly.
    static func sqliteURL(manifestURL: URL, manifest: SubstanceDBManifest) -> URL {
        let repoRoot = manifestURL
            .deletingLastPathComponent() // .../Piru/Data
            .deletingLastPathComponent() // .../Piru
            .deletingLastPathComponent() // .../
        return repoRoot.appendingPathComponent(manifest.sqlitePath)
    }

    /// Hex-encoded SHA-256 of the given bytes. Exposed for testability — the
    /// file-based `verifySha256` defers to this after memory-mapping the file.
    static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).hexString
    }

    private func downloadFile(url: URL, progress onProgress: @escaping @MainActor (Double) -> Void) async throws -> URL {
        // Use URLSession.download so the framework streams to disk directly —
        // no per-byte AsyncBytes suspensions, no manual file-handle bookkeeping.
        // The trade-off is no fine-grained progress without a delegate; the
        // DB is small enough (<10 MB) that a single intermediate update is
        // honest and avoids the complexity of a downloadTask delegate.
        onProgress(0)
        let (downloadedURL, response) = try await URLSession.shared.download(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            try? FileManager.default.removeItem(at: downloadedURL)
            throw UpdaterError.httpStatus(http.statusCode)
        }

        // Move the system-chosen temp location to one we control, so error
        // paths from the verify+install steps can find and clean it.
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("piru-substances-\(UUID().uuidString).sqlite")
        do {
            try FileManager.default.moveItem(at: downloadedURL, to: temp)
        } catch {
            try? FileManager.default.removeItem(at: downloadedURL)
            throw UpdaterError.diskWrite(error.localizedDescription)
        }
        onProgress(1)
        return temp
    }

    private func verifySha256(file: URL, expected: String) throws {
        // Memory-map the file so the kernel pages bytes lazily — RAM cost is
        // bounded regardless of file size and we don't pay for hand-rolled
        // chunking. `SHA256.hash(data:)` accepts any `DataProtocol` and runs
        // in C; for a <10 MB SQLite this is the right shape.
        let data = try Data(contentsOf: file, options: .alwaysMapped)
        let computed = SHA256.hash(data: data).hexString
        guard computed.caseInsensitiveCompare(expected) == .orderedSame else {
            try? FileManager.default.removeItem(at: file)
            throw UpdaterError.checksumMismatch(expected: expected, actual: computed)
        }
    }

    private func installDownloadedDB(tempFile: URL, manifest: SubstanceDBManifest) throws {
        // Two-step atomic install. Order matters: write the manifest FIRST
        // so a disk error between steps can't leave us with an applied
        // SQLite that disowns its provenance. If step 1 fails the install
        // is a clean no-op; if step 2 fails the manifest gets rolled back
        // explicitly so `currentManifest` doesn't lie about the next launch.
        let fm = FileManager.default
        let manifestData = try SubstanceDBManifest.jsonEncoder.encode(manifest)

        let priorManifest: Data? = (try? Data(contentsOf: Self.appliedManifestURL))
        try manifestData.write(to: Self.appliedManifestURL, options: .atomic)

        do {
            if fm.fileExists(atPath: Self.appliedSQLiteURL.path) {
                try fm.removeItem(at: Self.appliedSQLiteURL)
            }
            try fm.moveItem(at: tempFile, to: Self.appliedSQLiteURL)
        } catch {
            // Roll the manifest back to whatever was there before (or remove
            // it entirely if no prior manifest existed) so the next launch
            // doesn't think a half-installed update is current.
            if let priorManifest {
                try? priorManifest.write(to: Self.appliedManifestURL, options: .atomic)
            } else {
                try? fm.removeItem(at: Self.appliedManifestURL)
            }
            throw error
        }
    }

    private func loadAppliedManifest() -> SubstanceDBManifest? {
        guard let data = try? Data(contentsOf: Self.appliedManifestURL) else { return nil }
        return try? SubstanceDBManifest.jsonDecoder.decode(SubstanceDBManifest.self, from: data)
    }

    private func loadBundledManifest() -> SubstanceDBManifest? {
        guard let url = Bundle.main.url(forResource: "manifest", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? SubstanceDBManifest.jsonDecoder.decode(SubstanceDBManifest.self, from: data)
    }

    /// Synthesised "local" placeholder used when no manifest is present
    /// (development-only edge case). Only the `contentVersion = "0"` matters
    /// — any real remote build will sort newer.
    private func placeholderLocal() -> SubstanceDBManifest {
        SubstanceDBManifest(
            schemaVersion: 1,
            contentVersion: "0",
            generatedAt: "",
            generatorVersion: "",
            substanceCount: 0,
            sources: [:],
            sqlitePath: "",
            sqliteSha256: "",
            sqliteSizeBytes: 0,
            releaseNotes: "",
        )
    }
}

// MARK: - Hex helpers

extension Sequence<UInt8> {
    /// Lowercase hex encoding of a byte sequence. Replaces the
    /// `map { String(format: "%02x", $0) }.joined()` idiom Foundation never
    /// shipped a first-class encoder for.
    var hexString: String {
        lazy.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Errors

enum UpdaterError: LocalizedError {
    case httpStatus(Int)
    case checksumMismatch(expected: String, actual: String)
    case diskWrite(String)

    var errorDescription: String? {
        switch self {
        case let .httpStatus(code):
            "Server returned HTTP \(code)."
        case let .checksumMismatch(expected, actual):
            "Downloaded database failed integrity check (expected \(expected.prefix(12))…, got \(actual.prefix(12))…)."
        case let .diskWrite(reason):
            "Couldn't write the downloaded database: \(reason)"
        }
    }
}
