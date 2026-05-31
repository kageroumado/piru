import Foundation
import Testing
@testable import Piru

@Suite("SubstanceDBManifest")
struct SubstanceDBManifestTests {
    private static let sampleJSON = #"""
    {
      "schema_version": 1,
      "content_version": "2026-05-25.0",
      "generated_at": "2026-05-25T13:43:34.163735+00:00",
      "generator_version": "build-sqlite-database.py 0.1.0",
      "substance_count": 1629,
      "sources": {
        "tripsit": {"categories": 100, "dose_ranges": 250}
      },
      "sqlite_path": "Piru/Data/piru-substances.sqlite",
      "sqlite_sha256": "abc123",
      "sqlite_size_bytes": 4276224,
      "release_notes": "Initial build."
    }
    """#

    @Test
    func `Decodes the build-script JSON shape`() throws {
        let data = try #require(Self.sampleJSON.data(using: .utf8))
        let manifest = try SubstanceDBManifest.jsonDecoder.decode(SubstanceDBManifest.self, from: data)
        #expect(manifest.schemaVersion == 1)
        #expect(manifest.contentVersion == "2026-05-25.0")
        #expect(manifest.substanceCount == 1_629)
        #expect(manifest.sqliteSha256 == "abc123")
        #expect(manifest.sqliteSizeBytes == 4_276_224)
        #expect(manifest.releaseNotes == "Initial build.")
        #expect(manifest.sources["tripsit"]?["categories"] == 100)
    }

    @Test
    func `isOlderThan compares lexicographically — newer date wins`() {
        let older = stubManifest(version: "2026-05-25.0")
        let newer = stubManifest(version: "2026-05-26.0")
        #expect(older.isOlderThan(newer))
        #expect(!newer.isOlderThan(older))
    }

    @Test
    func `isOlderThan distinguishes same-day rebuilds via suffix`() {
        let first = stubManifest(version: "2026-05-25.0")
        let second = stubManifest(version: "2026-05-25.1")
        #expect(first.isOlderThan(second))
        #expect(!second.isOlderThan(first))
    }

    @Test
    func `Equal versions are not older than themselves`() {
        let a = stubManifest(version: "2026-05-25.0")
        let b = stubManifest(version: "2026-05-25.0")
        #expect(!a.isOlderThan(b))
        #expect(!b.isOlderThan(a))
    }

    @Test
    func `Round-trips through Codable`() throws {
        let original = stubManifest(version: "2026-06-01.0")
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(original)
        let decoded = try SubstanceDBManifest.jsonDecoder.decode(SubstanceDBManifest.self, from: data)
        #expect(decoded == original)
    }

    private func stubManifest(version: String) -> SubstanceDBManifest {
        SubstanceDBManifest(
            schemaVersion: 1,
            contentVersion: version,
            generatedAt: "2026-05-25T00:00:00Z",
            generatorVersion: "test",
            substanceCount: 100,
            sources: [:],
            sqlitePath: "Piru/Data/piru-substances.sqlite",
            sqliteSha256: "deadbeef",
            sqliteSizeBytes: 1_024,
            releaseNotes: "Test build",
        )
    }
}

@Suite("SubstanceDBUpdater")
struct SubstanceDBUpdaterTests {
    @Test
    @MainActor
    func `Starts in idle state`() {
        let updater = SubstanceDBUpdater.shared
        // Reset via revertToBundled which sets state to .idle. Safe even if
        // no update is applied.
        try? updater.revertToBundled()
        if case .idle = updater.state {
            return
        }
        Issue.record("Expected idle after revert; got \(updater.state)")
    }

    @Test
    @MainActor
    func `revertToBundled removes applied files if present`() throws {
        let appliedSQLite = SubstanceDBUpdater.appliedSQLiteURL
        let fm = FileManager.default

        // Plant a fake applied file
        try Data("not really sqlite".utf8).write(to: appliedSQLite)
        #expect(fm.fileExists(atPath: appliedSQLite.path))

        try SubstanceDBUpdater.shared.revertToBundled()
        #expect(!fm.fileExists(atPath: appliedSQLite.path))
    }

    @Test
    @MainActor
    func `SubstanceStore.resolveSubstancesDBURL prefers applied copy`() throws {
        let appliedSQLite = SubstanceDBUpdater.appliedSQLiteURL
        defer { try? FileManager.default.removeItem(at: appliedSQLite) }

        try Data("fake".utf8).write(to: appliedSQLite)
        #expect(SubstanceStore.resolveSubstancesDBURL() == appliedSQLite)

        try FileManager.default.removeItem(at: appliedSQLite)
        let bundled = SubstanceStore.resolveSubstancesDBURL()
        #expect(bundled.lastPathComponent == "piru-substances.sqlite")
        #expect(bundled.path.contains(".app"))
    }

    // MARK: - URL arithmetic

    @Test
    func `sqliteURL joins repo root + manifest's sqlitePath correctly`() throws {
        let manifestURL = try #require(URL(string: "https://raw.githubusercontent.com/kageroumado/piru/main/Piru/Data/manifest.json"))
        let manifest = SubstanceDBManifest(
            schemaVersion: 1,
            contentVersion: "2026-05-25.0",
            generatedAt: "",
            generatorVersion: "",
            substanceCount: 0,
            sources: [:],
            sqlitePath: "Piru/Data/piru-substances.sqlite",
            sqliteSha256: "",
            sqliteSizeBytes: 0,
            releaseNotes: "",
        )
        let resolved = SubstanceDBUpdater.sqliteURL(manifestURL: manifestURL, manifest: manifest)
        #expect(resolved.absoluteString == "https://raw.githubusercontent.com/kageroumado/piru/main/Piru/Data/piru-substances.sqlite")
    }

    @Test
    func `sqliteURL handles fork repos / different branches`() throws {
        let manifestURL = try #require(URL(string: "https://example.com/some/owner/repo/branch/Piru/Data/manifest.json"))
        let manifest = SubstanceDBManifest(
            schemaVersion: 1, contentVersion: "", generatedAt: "", generatorVersion: "",
            substanceCount: 0, sources: [:],
            sqlitePath: "Piru/Data/piru-substances.sqlite",
            sqliteSha256: "", sqliteSizeBytes: 0, releaseNotes: "",
        )
        let resolved = SubstanceDBUpdater.sqliteURL(manifestURL: manifestURL, manifest: manifest)
        #expect(resolved.absoluteString == "https://example.com/some/owner/repo/branch/Piru/Data/piru-substances.sqlite")
    }

    // MARK: - SHA-256

    @Test
    func `sha256Hex computes a known vector`() {
        // From the FIPS test vector: empty input → e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
        #expect(SubstanceDBUpdater.sha256Hex(of: Data()) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        // "abc" → ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
        #expect(SubstanceDBUpdater.sha256Hex(of: Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test
    func `Bundled SQLite hash matches the bundled manifest`() throws {
        let bundle = Bundle.main
        guard
            let sqliteURL = bundle.url(forResource: "piru-substances", withExtension: "sqlite"),
            let manifestURL = bundle.url(forResource: "manifest", withExtension: "json")
        else {
            Issue.record("Bundled DB or manifest missing from the app bundle")
            return
        }

        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try SubstanceDBManifest.jsonDecoder.decode(SubstanceDBManifest.self, from: manifestData)

        let sqliteData = try Data(contentsOf: sqliteURL)
        let computed = SubstanceDBUpdater.sha256Hex(of: sqliteData)
        #expect(
            computed.caseInsensitiveCompare(manifest.sqliteSha256) == .orderedSame,
            "Bundled SQLite hash diverges from manifest. Rebuild via Exports/build-sqlite-database.py.",
        )
    }

    // MARK: - State machine (via evaluateManifest)

    /// Build a remote-manifest payload with a given version + schema. The
    /// state machine tests feed this into `evaluateManifest(remoteData:)`
    /// directly so the URLSession round-trip stays out of the test.
    private func remoteManifestData(version: String, schemaVersion: Int = 1) throws -> Data {
        let manifest = SubstanceDBManifest(
            schemaVersion: schemaVersion,
            contentVersion: version,
            generatedAt: "2026-05-25T00:00:00Z",
            generatorVersion: "test",
            substanceCount: 1,
            sources: [:],
            sqlitePath: "Piru/Data/piru-substances.sqlite",
            sqliteSha256: String(repeating: "0", count: 64),
            sqliteSizeBytes: 0,
            releaseNotes: "Test remote build",
        )
        return try SubstanceDBManifest.jsonEncoder.encode(manifest)
    }

    @Test
    @MainActor
    func `evaluateManifest: equal version → .upToDate`() throws {
        let updater = SubstanceDBUpdater.shared
        try? updater.revertToBundled()
        guard let local = updater.currentManifest else {
            Issue.record("Bundled manifest unavailable")
            return
        }
        let data = try remoteManifestData(version: local.contentVersion)
        let result = updater.evaluateManifest(remoteData: data)
        if case .upToDate = result { return }
        Issue.record("Expected .upToDate, got \(result)")
    }

    @Test
    @MainActor
    func `evaluateManifest: newer remote → .updateAvailable`() throws {
        let updater = SubstanceDBUpdater.shared
        try? updater.revertToBundled()
        let data = try remoteManifestData(version: "9999-12-31.0") // far future
        let result = updater.evaluateManifest(remoteData: data)
        if case .updateAvailable = result { return }
        Issue.record("Expected .updateAvailable, got \(result)")
    }

    @Test
    @MainActor
    func `evaluateManifest: unsupported schema version → .error`() throws {
        let updater = SubstanceDBUpdater.shared
        try? updater.revertToBundled()
        let data = try remoteManifestData(version: "9999-12-31.0", schemaVersion: 999)
        let result = updater.evaluateManifest(remoteData: data)
        if case .error = result { return }
        Issue.record("Expected .error for schema=999, got \(result)")
    }

    @Test
    @MainActor
    func `evaluateManifest: malformed JSON → .error`() {
        let updater = SubstanceDBUpdater.shared
        let result = updater.evaluateManifest(remoteData: Data("not a manifest".utf8))
        if case .error = result { return }
        Issue.record("Expected .error for malformed JSON, got \(result)")
    }
}
