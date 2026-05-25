import Foundation
import CryptoKit
import Observation
import os

nonisolated private let updaterLogger = Logger(subsystem: "dev.yumeji.piru", category: "SubstanceDBUpdater")

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

    /// Highest schema version this build understands. Bump when adding
    /// breaking changes to the manifest model.
    private static let supportedSchemaVersion = 1

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
            let remote = try await fetchRemoteManifest()
            guard remote.schemaVersion <= Self.supportedSchemaVersion else {
                state = .error("This database requires a newer version of Piru.")
                return
            }
            guard let local = currentManifest else {
                state = .updateAvailable(local: placeholderLocal(), remote: remote)
                return
            }
            if local.isOlderThan(remote) {
                state = .updateAvailable(local: local, remote: remote)
            } else {
                state = .upToDate(local: local)
            }
        } catch {
            updaterLogger.error("checkForUpdates failed: \(error.localizedDescription, privacy: .public)")
            state = .error(error.localizedDescription)
        }
    }

    /// Download the SQLite file referenced by the current `.updateAvailable`
    /// state, verify its sha256, and atomically move it into Documents/.
    /// Result lands in `.appliedNeedsRestart(...)` or `.error(...)`.
    func downloadAndApply() async {
        guard case let .updateAvailable(_, remote) = state else { return }
        state = .downloading(progress: 0)
        do {
            let sqliteURL = sqliteURL(from: remote)
            let tempFile = try await downloadFile(url: sqliteURL) { progress in
                self.state = .downloading(progress: progress)
            }
            try verifySha256(file: tempFile, expected: remote.sqliteSha256)
            try installDownloadedDB(tempFile: tempFile, manifest: remote)
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

    // MARK: - Internals

    private func fetchRemoteManifest() async throws -> SubstanceDBManifest {
        var request = URLRequest(url: manifestURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw UpdaterError.httpStatus(http.statusCode)
        }
        return try SubstanceDBManifest.jsonDecoder.decode(SubstanceDBManifest.self, from: data)
    }

    private func sqliteURL(from manifest: SubstanceDBManifest) -> URL {
        // The manifest URL points at `<base>/Piru/Data/manifest.json`. Strip
        // the trailing component and append the manifest-relative SQLite path
        // (`Piru/Data/piru-substances.sqlite`).
        let manifestRoot = manifestURL.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return manifestRoot.appendingPathComponent(manifest.sqlitePath)
    }

    private func downloadFile(url: URL, progress onProgress: @escaping @MainActor (Double) -> Void) async throws -> URL {
        let (asyncBytes, response) = try await URLSession.shared.bytes(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw UpdaterError.httpStatus(http.statusCode)
        }
        let total = max(response.expectedContentLength, 1)
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("piru-substances-\(UUID().uuidString).sqlite")
        FileManager.default.createFile(atPath: temp.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: temp) else {
            throw UpdaterError.diskWrite("Failed to open temp file for write")
        }
        defer { try? handle.close() }

        var written: Int64 = 0
        var buffer = Data(capacity: 65536)
        for try await byte in asyncBytes {
            buffer.append(byte)
            if buffer.count >= 65536 {
                try handle.write(contentsOf: buffer)
                written += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                let p = Double(written) / Double(total)
                await onProgress(min(p, 0.99))
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
        }
        await onProgress(1)
        return temp
    }

    private func verifySha256(file: URL, expected: String) throws {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let chunk = handle.readData(ofLength: 65536)
            if chunk.isEmpty { return false }
            hasher.update(data: chunk)
            return true
        }) {}
        let computed = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard computed.caseInsensitiveCompare(expected) == .orderedSame else {
            try? FileManager.default.removeItem(at: file)
            throw UpdaterError.checksumMismatch(expected: expected, actual: computed)
        }
    }

    private func installDownloadedDB(tempFile: URL, manifest: SubstanceDBManifest) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: Self.appliedSQLiteURL.path) {
            try fm.removeItem(at: Self.appliedSQLiteURL)
        }
        try fm.moveItem(at: tempFile, to: Self.appliedSQLiteURL)

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(to: Self.appliedManifestURL, options: .atomic)
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
            releaseNotes: ""
        )
    }
}

// MARK: - Errors

enum UpdaterError: LocalizedError {
    case httpStatus(Int)
    case checksumMismatch(expected: String, actual: String)
    case diskWrite(String)

    var errorDescription: String? {
        switch self {
        case .httpStatus(let code):
            return "Server returned HTTP \(code)."
        case .checksumMismatch(let expected, let actual):
            return "Downloaded database failed integrity check (expected \(expected.prefix(12))…, got \(actual.prefix(12))…)."
        case .diskWrite(let reason):
            return "Couldn't write the downloaded database: \(reason)"
        }
    }
}
