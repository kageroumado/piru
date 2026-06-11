import Foundation
import Testing
@testable import Piru

/// Builds a `SubstanceStore` that is fully isolated from the shared singleton:
/// it opens the real bundled substances DB (read-only, safe to share across
/// instances) but writes source-priority / profile / override state to a fresh
/// SQLite file in a per-call temp directory. Mutating tests use this so they
/// can't leak state into each other or into the real
/// `Documents/piru-user-prefs.sqlite` of the test host.
///
/// The cache prewarm is disabled — a short-lived test instance shouldn't pay
/// the detached full-library batch resolve it never reads.
///
/// Callers own cleanup: remove the returned `tempDir` when done, e.g.
/// `defer { try? FileManager.default.removeItem(at: tempDir) }`.
@MainActor
func makeIsolatedSubstanceStore() throws -> (store: SubstanceStore, tempDir: URL) {
    let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("piru-store-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    let bundledDB = try #require(
        Bundle(for: SubstanceStore.self).url(forResource: "piru-substances", withExtension: "sqlite"),
        "Bundled piru-substances.sqlite missing from the test host bundle",
    )
    let store = SubstanceStore(
        substancesDBURL: bundledDB,
        userPrefsDBURL: tempDir.appendingPathComponent("piru-user-prefs.sqlite"),
        prewarmsAllCache: false,
    )
    return (store, tempDir)
}
