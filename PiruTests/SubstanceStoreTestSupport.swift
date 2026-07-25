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
/// Callers own cleanup: `defer { tearDownIsolatedSubstanceStore(store, tempDir: tempDir) }`.
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

/// Tear down a store from ``makeIsolatedSubstanceStore()``: close its SQLite
/// connection *first*, then delete the temp directory.
///
/// Order matters. Deleting the directory with the connection still open unlinks
/// a file SQLite is holding, which it reports as `BUG IN CLIENT OF
/// libsqlite3.dylib: vnode unlinked while in use` — roughly twenty times per
/// full test run. Harmless in practice (the tests pass either way) but it is a
/// genuine API violation, and it buried the real signal in the test log.
@MainActor
func tearDownIsolatedSubstanceStore(_ store: SubstanceStore, tempDir: URL) {
    store.closeUserPrefsForTesting()
    try? FileManager.default.removeItem(at: tempDir)
}
