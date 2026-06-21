import Foundation
import SwiftData
import Testing
@testable import Piru

/// Integration tests for the encrypted-backup round-trip: export → encrypt →
/// restore → verify. The passphrase path needs no iCloud or Keychain, so it
/// runs cleanly in the test environment. This also proves backups carry the
/// full Piru-native fidelity (sessions, per-dose location, background flag,
/// tags, favourites) and that a wrong passphrase never destroys data.
// Serialized: every export writes the same fixed temp filename
// (DataExportImport.exportFilename) through the shared BackupManager, so
// concurrent tests clobber each other's file between export and restore —
// which surfaces as a spurious `.decryptionFailed` (different salt/key).
@Suite("BackupManager — round-trip", .serialized)
@MainActor
struct BackupManagerRoundTripTests {
    /// Full canonical schema (`StoreRecovery.models`) — the backup round-trip
    /// fetches entities like `InventoryItem` that a subset schema omits, and a
    /// distinct schema pollutes CoreData's process-global model registry, which
    /// crashes unrelated fetches under the parallel runner. Match the one schema
    /// every other SwiftData suite uses.
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: Schema(StoreRecovery.models), configurations: config)
    }

    @Test
    func `Encrypted passphrase backup round-trips losslessly`() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let session = Session(startDate: Date(timeIntervalSince1970: 1_700_000_000), title: "Trip", note: "the notes")
        context.insert(session)
        let dose = DoseEntry(
            substance: "MDMA", amount: 100, unit: "mg", route: .oral,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            tags: ["party"], isBackgroundMed: false,
            locationName: "Park", latitude: 51.5, longitude: -0.12,
        )
        context.insert(dose)
        dose.session = session
        context.insert(FavoriteSubstance(substance: "MDMA"))
        try context.save()

        let passphrase = "correct horse battery staple"
        let url = try await BackupManager.shared.exportEncrypted(context: context, passphrase: passphrase)
        defer { try? FileManager.default.removeItem(at: url) }

        // The encrypted file must not contain readable plaintext.
        let raw = try Data(contentsOf: url)
        #expect(!String(decoding: raw, as: UTF8.self).contains("MDMA"))

        try DataExportImport.deleteAll(context: context)
        try context.save()
        try await BackupManager.shared.restore(fromFileAt: url, passphrase: passphrase, strategy: .merge, context: context)

        let sessions = try context.fetch(FetchDescriptor<Session>())
        let restored = try #require(sessions.first { $0.title == "Trip" })
        #expect(restored.note == "the notes")
        let mdma = try #require(restored.orderedDoses.first)
        #expect(mdma.substance == "MDMA")
        #expect(mdma.locationName == "Park")
        #expect(mdma.latitude == 51.5)
        #expect(mdma.tags == ["party"])
        #expect(try context.fetch(FetchDescriptor<FavoriteSubstance>()).contains { $0.substance == "MDMA" })
    }

    @Test
    func `Wrong passphrase fails and never wipes data on replace`() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.insert(DoseEntry(
            substance: "Caffeine",
            amount: 100,
            unit: "mg",
            route: .oral,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
        ))
        try context.save()

        let url = try await BackupManager.shared.exportEncrypted(context: context, passphrase: "the right passphrase")
        defer { try? FileManager.default.removeItem(at: url) }

        // Decryption fails *before* any destructive store mutation, so even a
        // `.replace` restore with the wrong passphrase leaves data intact.
        await #expect(throws: (any Error).self) {
            try await BackupManager.shared.restore(
                fromFileAt: url, passphrase: "the WRONG passphrase", strategy: .replace, context: context,
            )
        }
        #expect(try context.fetch(FetchDescriptor<DoseEntry>()).count == 1)
    }
}
