import Foundation
import SwiftData
import Testing
@testable import Piru

/// Stage 0 of the Apple Watch companion (`Specs/apple-watch-companion.md`): the sync
/// substrate, exercised with simulated payloads and no watch. Pins the wire round-trips,
/// the payload → `DoseEntry` mapping, watch→phone idempotency, and manifest assembly.
@MainActor
@Suite("WatchSync", .serialized)
struct WatchSyncTests {
    // One container for the whole suite, cleared between tests. Minting a fresh
    // in-memory store per test races CoreData's *async* context teardown — a prior
    // test's `NSManagedObjectContext` deallocating on a background queue overlaps the
    // next test's fetch and traps inside SwiftData. The app runs on a single
    // long-lived container; mirroring that here sidesteps the race. Serialized, so the
    // shared store is only ever touched by one test at a time.
    static let container: ModelContainer = {
        // swiftlint:disable:next force_try
        try! ModelContainer(
            for: Schema(StoreRecovery.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none),
        )
    }()

    /// The shared main context with user data cleared, for a test that asserts on counts.
    private func freshContext() throws -> ModelContext {
        let context = Self.container.mainContext
        for entry in try context.fetch(FetchDescriptor<DoseEntry>()) { context.delete(entry) }
        for chip in try context.fetch(FetchDescriptor<QuickLogDose>()) { context.delete(chip) }
        try context.save()
        QuickLogManager.suppressedRecents = []
        return context
    }

    private func massPayload(id: UUID = UUID()) -> WatchDosePayload {
        WatchDosePayload(
            id: id, substance: "Caffeine", amount: 100, unit: "mg", route: "oral",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000), notes: "wrist log",
            substanceUID: "CAF", displayName: "Caffeine",
        )
    }

    private func drinkPayload(id: UUID = UUID()) -> WatchDosePayload {
        WatchDosePayload(
            id: id, substance: "Alcohol", amount: 13.02, unit: "g", route: "oral",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            volumeML: 330, abv: 5, drinkName: "IPA", emoji: "🍺",
        )
    }

    // MARK: - Wire round-trips

    @Test("Payload survives a Codable round-trip unchanged")
    func payloadCodableRoundTrip() throws {
        let payload = drinkPayload()
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(WatchDosePayload.self, from: data)
        #expect(decoded == payload)
    }

    @Test("Payload survives the transferUserInfo dictionary bridge")
    func payloadUserInfoBridge() throws {
        let payload = drinkPayload()
        let userInfo = try #require(payload.userInfo())
        let decoded = try #require(WatchDosePayload(userInfo: userInfo))
        #expect(decoded == payload)
        // A foreign dictionary is not one of ours.
        #expect(WatchDosePayload(userInfo: ["other": 1]) == nil)
    }

    @Test("Manifest survives the applicationContext dictionary bridge")
    func manifestContextBridge() throws {
        let manifest = QuickLogManifest(
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            items: [QuickLogManifestItem(id: "k", substance: "Alcohol", route: "oral", amount: 14, unit: "g", isByVolume: true)],
            drinkPresets: ManifestDrinkPreset.curatedAlcohol(),
        )
        let context = try #require(manifest.applicationContext())
        let decoded = try #require(QuickLogManifest(applicationContext: context))
        #expect(decoded == manifest)
        #expect(QuickLogManifest(applicationContext: ["nope": 1]) == nil)
    }

    // MARK: - Payload → DoseEntry mapping

    @Test("makeEntry carries the id, route, timestamp, identity, and drink detail")
    func makeEntryMapsFields() {
        let id = UUID()
        let entry = WatchDoseReceiver.makeEntry(from: drinkPayload(id: id))
        #expect(entry.id == id) // the dedup key
        #expect(entry.substance == "Alcohol")
        #expect(entry.amount == ByVolumeDosing.grams(volumeML: 330, abv: 5)) // canonical, not the sent value
        #expect(entry.unit == "g")
        #expect(entry.route == .oral)
        #expect(entry.volumeML == 330)
        #expect(entry.abv == 5)
        #expect(entry.drinkName == "IPA")
        #expect(entry.timestamp == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test("An unknown route rawValue falls back to oral, never a crash")
    func makeEntryUnknownRoute() {
        var payload = massPayload()
        payload.route = "teleport"
        #expect(WatchDoseReceiver.makeEntry(from: payload).route == .oral)
    }

    @Test("A drink stores canonical grams, ignoring the watch's advisory amount")
    func makeEntryRecomputesDrinkGrams() {
        var payload = drinkPayload()
        payload.amount = 999 // a wrong/stale number from the watch
        let entry = WatchDoseReceiver.makeEntry(from: payload)
        #expect(entry.amount == ByVolumeDosing.grams(volumeML: 330, abv: 5))
    }

    // MARK: - Idempotency (watch → phone)

    @Test("Ingesting one payload logs exactly one dose")
    func ingestInsertsOnce() throws {
        let context = try freshContext()
        let payload = massPayload()
        #expect(WatchDoseReceiver.ingest(payload, in: context) == .inserted(payload.id))
        #expect(try context.fetchCount(FetchDescriptor<DoseEntry>()) == 1)
    }

    @Test("A re-delivered transfer never double-logs")
    func ingestIsIdempotent() throws {
        let context = try freshContext()
        let payload = massPayload()
        let first = WatchDoseReceiver.ingest(payload, in: context)
        let second = WatchDoseReceiver.ingest(payload, in: context)
        #expect(first == .inserted(payload.id))
        #expect(second == .duplicate)
        #expect(try context.fetchCount(FetchDescriptor<DoseEntry>()) == 1)
    }

    @Test("Distinct ids log distinct doses")
    func ingestDistinctIds() throws {
        let context = try freshContext()
        WatchDoseReceiver.ingest(massPayload(id: UUID()), in: context)
        WatchDoseReceiver.ingest(massPayload(id: UUID()), in: context)
        #expect(try context.fetchCount(FetchDescriptor<DoseEntry>()) == 2)
    }

    @Test("A watch-logged drink folds into the phone recents as a chip")
    func ingestSeedsRecents() throws {
        let context = try freshContext()
        WatchDoseReceiver.ingest(drinkPayload(), in: context)
        let chips = try context.fetch(FetchDescriptor<QuickLogDose>())
        #expect(chips.contains { $0.drinkName == "IPA" && $0.abv == 5 })
    }

    // MARK: - Manifest assembly (phone → watch)

    @Test("Recents map to tiles; a favorited chip is marked and sorts first")
    func buildMarksAndSortsFavorites() {
        let caffeine = QuickLogDose(substance: "Caffeine", route: .oral, amount: 100, unit: "mg", sortOrder: 0)
        let melatonin = QuickLogDose(substance: "Melatonin", route: .oral, amount: 3, unit: "mg", sortOrder: 1)
        let favorite = FavoriteSubstance(substance: "Melatonin")

        let manifest = QuickLogManifestBuilder.build(
            recents: [caffeine, melatonin],
            favorites: [favorite],
            generatedAt: Date(timeIntervalSince1970: 0),
        )
        #expect(manifest.items.count == 2)
        #expect(manifest.items.first?.substance == "Melatonin") // favorite floated first
        #expect(manifest.items.first?.isFavorite == true)
        #expect(manifest.items.last?.isFavorite == false)
    }

    @Test("A favorite with no history gets a tile from its default dose")
    func buildAddsFavoriteWithoutRecent() {
        let favorite = FavoriteSubstance(substance: "Magnesium")
        let manifest = QuickLogManifestBuilder.build(
            recents: [],
            favorites: [favorite],
            generatedAt: Date(timeIntervalSince1970: 0),
            favoriteDefault: { _ in .init(amount: 200, unit: "mg", route: .oral, displayName: "Magnesium") },
        )
        #expect(manifest.items.count == 1)
        #expect(manifest.items.first?.amount == 200)
        #expect(manifest.items.first?.isFavorite == true)
    }

    @Test("A favorite with no history and no default is skipped, not a blank tile")
    func buildSkipsFavoriteWithNoDefault() {
        let manifest = QuickLogManifestBuilder.build(
            recents: [],
            favorites: [FavoriteSubstance(substance: "Mystery")],
            generatedAt: Date(timeIntervalSince1970: 0),
        )
        #expect(manifest.items.isEmpty)
    }

    @Test("An alcohol tile marks isByVolume and carries the drink presets")
    func buildCarriesAlcoholCapability() {
        let drink = QuickLogDose(
            substance: "Alcohol", route: .oral, amount: 13.02, unit: "g", sortOrder: 0,
            volumeML: 330, abv: 5, drinkName: "IPA",
        )
        let manifest = QuickLogManifestBuilder.build(
            recents: [drink], favorites: [], generatedAt: Date(timeIntervalSince1970: 0),
        )
        #expect(manifest.items.first?.isByVolume == true)
        #expect(manifest.drinkPresets.count == ByVolumeDosing.alcohol.drinkPresets.count)
        #expect(manifest.drinkPresets.contains { $0.emoji == "🍺" && $0.volumeML == 330 })
    }

    @Test("A manifest with no by-volume item ships no drink presets")
    func buildOmitsPresetsWhenNoAlcohol() {
        let caffeine = QuickLogDose(substance: "Caffeine", route: .oral, amount: 100, unit: "mg", sortOrder: 0)
        let manifest = QuickLogManifestBuilder.build(
            recents: [caffeine], favorites: [], generatedAt: Date(timeIntervalSince1970: 0),
        )
        #expect(manifest.drinkPresets.isEmpty)
    }

    @Test("The item limit caps how many recents ship")
    func buildRespectsItemLimit() {
        let recents = (0 ..< 30).map {
            QuickLogDose(substance: "S\($0)", route: .oral, amount: Double($0 + 1), unit: "mg", sortOrder: Double($0))
        }
        let manifest = QuickLogManifestBuilder.build(
            recents: recents, favorites: [], generatedAt: Date(timeIntervalSince1970: 0), itemLimit: 5,
        )
        #expect(manifest.items.count == 5)
    }

    // MARK: - Watch-side payload construction

    @Test("makePayload takes a fresh id and the user's adjusted amount, keeping identity")
    func itemMakesPayload() {
        let item = QuickLogManifestItem(
            id: "k", substance: "Caffeine", route: "oral", amount: 100, unit: "mg", substanceUID: "CAF",
        )
        let id = UUID()
        let payload = item.makePayload(id: id, amount: 150, timestamp: Date(timeIntervalSince1970: 0))
        #expect(payload.id == id)
        #expect(payload.amount == 150) // the crown-adjusted value, not the tile default
        #expect(payload.substance == "Caffeine")
        #expect(payload.substanceUID == "CAF")
        #expect(payload.route == "oral")
    }
}
