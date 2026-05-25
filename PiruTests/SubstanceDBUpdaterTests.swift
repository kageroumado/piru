import Testing
import Foundation
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

    @Test("Decodes the build-script JSON shape")
    func decodesBuildScriptJSON() throws {
        let data = try #require(Self.sampleJSON.data(using: .utf8))
        let manifest = try SubstanceDBManifest.jsonDecoder.decode(SubstanceDBManifest.self, from: data)
        #expect(manifest.schemaVersion == 1)
        #expect(manifest.contentVersion == "2026-05-25.0")
        #expect(manifest.substanceCount == 1629)
        #expect(manifest.sqliteSha256 == "abc123")
        #expect(manifest.sqliteSizeBytes == 4_276_224)
        #expect(manifest.releaseNotes == "Initial build.")
        #expect(manifest.sources["tripsit"]?["categories"] == 100)
    }

    @Test("isOlderThan compares lexicographically — newer date wins")
    func isOlderThanByDate() {
        let older = stubManifest(version: "2026-05-25.0")
        let newer = stubManifest(version: "2026-05-26.0")
        #expect(older.isOlderThan(newer))
        #expect(!newer.isOlderThan(older))
    }

    @Test("isOlderThan distinguishes same-day rebuilds via suffix")
    func isOlderThanBySuffix() {
        let first = stubManifest(version: "2026-05-25.0")
        let second = stubManifest(version: "2026-05-25.1")
        #expect(first.isOlderThan(second))
        #expect(!second.isOlderThan(first))
    }

    @Test("Equal versions are not older than themselves")
    func equalVersionsNotOlder() {
        let a = stubManifest(version: "2026-05-25.0")
        let b = stubManifest(version: "2026-05-25.0")
        #expect(!a.isOlderThan(b))
        #expect(!b.isOlderThan(a))
    }

    @Test("Round-trips through Codable")
    func roundTrip() throws {
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
            sqliteSizeBytes: 1024,
            releaseNotes: "Test build"
        )
    }
}

@Suite("SubstanceDBUpdater")
struct SubstanceDBUpdaterTests {

    @Test("Starts in idle state")
    @MainActor
    func startsIdle() {
        let updater = SubstanceDBUpdater.shared
        // Reset via revertToBundled which sets state to .idle. Safe even if
        // no update is applied.
        try? updater.revertToBundled()
        if case .idle = updater.state {
            return
        }
        Issue.record("Expected idle after revert; got \(updater.state)")
    }

    @Test("revertToBundled removes applied files if present")
    @MainActor
    func revertRemovesAppliedFiles() throws {
        let appliedSQLite = SubstanceDBUpdater.appliedSQLiteURL
        let fm = FileManager.default

        // Plant a fake applied file
        try Data("not really sqlite".utf8).write(to: appliedSQLite)
        #expect(fm.fileExists(atPath: appliedSQLite.path))

        try SubstanceDBUpdater.shared.revertToBundled()
        #expect(!fm.fileExists(atPath: appliedSQLite.path))
    }

    @Test("SubstanceStore.resolveSubstancesDBURL prefers applied copy")
    @MainActor
    func resolveURLPrefersApplied() throws {
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

    @Test("sqliteURL joins repo root + manifest's sqlitePath correctly")
    func sqliteURLArithmetic() {
        let manifestURL = URL(string: "https://raw.githubusercontent.com/kageroumado/piru/main/Piru/Data/manifest.json")!
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
            releaseNotes: ""
        )
        let resolved = SubstanceDBUpdater.sqliteURL(manifestURL: manifestURL, manifest: manifest)
        #expect(resolved.absoluteString == "https://raw.githubusercontent.com/kageroumado/piru/main/Piru/Data/piru-substances.sqlite")
    }

    @Test("sqliteURL handles fork repos / different branches")
    func sqliteURLAlternateRepo() {
        let manifestURL = URL(string: "https://example.com/some/owner/repo/branch/Piru/Data/manifest.json")!
        let manifest = SubstanceDBManifest(
            schemaVersion: 1, contentVersion: "", generatedAt: "", generatorVersion: "",
            substanceCount: 0, sources: [:],
            sqlitePath: "Piru/Data/piru-substances.sqlite",
            sqliteSha256: "", sqliteSizeBytes: 0, releaseNotes: ""
        )
        let resolved = SubstanceDBUpdater.sqliteURL(manifestURL: manifestURL, manifest: manifest)
        #expect(resolved.absoluteString == "https://example.com/some/owner/repo/branch/Piru/Data/piru-substances.sqlite")
    }

    // MARK: - SHA-256

    @Test("sha256Hex computes a known vector")
    func sha256KnownVector() {
        // From the FIPS test vector: empty input → e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
        #expect(SubstanceDBUpdater.sha256Hex(of: Data()) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        // "abc" → ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
        #expect(SubstanceDBUpdater.sha256Hex(of: Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test("Bundled SQLite hash matches the bundled manifest")
    func bundledHashMatchesBundledManifest() throws {
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
        #expect(computed.caseInsensitiveCompare(manifest.sqliteSha256) == .orderedSame,
                "Bundled SQLite hash diverges from manifest. Rebuild via Exports/build-sqlite-database.py.")
    }
}
