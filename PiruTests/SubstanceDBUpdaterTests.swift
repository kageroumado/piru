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
}
