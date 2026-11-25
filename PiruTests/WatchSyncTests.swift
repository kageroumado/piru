import Foundation
import SwiftData
import Testing
@testable import Piru

/// Stage 0 of the Apple Watch companion: the sync
/// substrate, exercised with simulated payloads and no watch. Pins the wire round-trips,
/// the payload → `DoseEntry` mapping, watch→phone idempotency, and manifest assembly.
@MainActor
@Suite("WatchSync", .serialized)
struct WatchSyncTests {
    /// One container for the whole suite, cleared between tests. Minting a fresh
    /// in-memory store per test races CoreData's *async* context teardown — a prior
    /// test's `NSManagedObjectContext` deallocating on a background queue overlaps the
    /// next test's fetch and traps inside SwiftData. The app runs on a single
    /// long-lived container; mirroring that here sidesteps the race. Serialized, so the
    /// shared store is only ever touched by one test at a time.
    static let container: ModelContainer = // swiftlint:disable:next force_try
        try! ModelContainer(
            for: Schema(PiruSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none),
        )

    /// Alcohol's by-volume capability as the app resolves it. The store's index build is what
    /// installs the catalog, so touching it here is what makes the presets available.
    static func alcoholCapability() -> ByVolumeDosing {
        _ = SubstanceStore.shared
        guard let capability = ByVolumeCatalog.capability(forAnyOf: ["Alcohol"]) else {
            Issue.record("no by_volume_dosing row for Alcohol in the bundled DB")
            return ByVolumeDosing(
                concentration: .percentByVolume(densityGramsPerML: ByVolumeDosing.ethanolDensityGramsPerML),
                canonicalUnit: "g", standardUnitMass: ByVolumeDosing.usStandardDrinkGrams,
                standardUnitLabel: "drink", drinkPresets: [],
            )
        }
        return capability
    }

    /// The shared main context with user data cleared, for a test that asserts on counts.
    private func freshContext() throws -> ModelContext {
        let context = Self.container.mainContext
        for entry in try context.fetch(FetchDescriptor<DoseEntry>()) {
            context.delete(entry)
        }
        for chip in try context.fetch(FetchDescriptor<QuickLogDose>()) {
            context.delete(chip)
        }
        for med in try context.fetch(FetchDescriptor<DailyDoseItem>()) {
            context.delete(med)
        }
        for occurrence in try context.fetch(FetchDescriptor<RoutineOccurrence>()) {
            context.delete(occurrence)
        }
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

    @Test
    func `reset rejects delayed and legacy watch entries while accepting new entries`() throws {
        let context = try freshContext()
        var payload = massPayload()
        #expect(WatchDoseReceiver.ingest(payload, in: context, journalGeneration: 1) == .staleJournal)
        payload.journalGeneration = 1
        #expect(WatchDoseReceiver.ingest(payload, in: context, journalGeneration: 1) == .inserted(payload.id))
        try DataExportImport.deleteAll(context: context)
        #expect(WatchDoseReceiver.ingest(payload, in: context, journalGeneration: 2) == .staleJournal)
        #expect(try context.fetchCount(FetchDescriptor<DoseEntry>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<QuickLogDose>()) == 0)
        DoseLogService.shared.cancelPendingBookkeeping()
    }

    @Test
    func `watch reset survives relaunch and rejects reordered manifests`() throws {
        let name = "watch-reset-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(JournalResetGeneration.advance(in: defaults) == 1)
        #expect(try JournalResetGeneration.current(in: #require(UserDefaults(suiteName: name))) == 1)
        let reset = QuickLogManifest(generatedAt: Date(timeIntervalSince1970: 100), items: [], drinkPresets: [], journalGeneration: 1)
        let old = QuickLogManifest(generatedAt: Date(timeIntervalSince1970: 200), items: [], drinkPresets: [])
        #expect(!JournalResetGeneration.accepts(old, after: reset, minimumGeneration: 1))
        #expect(!JournalResetGeneration.accepts(old, after: nil, minimumGeneration: 1))
        var earlier = reset
        earlier.generatedAt = Date(timeIntervalSince1970: 50)
        #expect(!JournalResetGeneration.accepts(earlier, after: reset, minimumGeneration: 1))
        earlier.journalGeneration = 2
        #expect(JournalResetGeneration.accepts(earlier, after: reset, minimumGeneration: 1))
    }

    @Test
    func `watch tiles preserve their journal generation in outgoing entries`() {
        var item = QuickLogManifestItem(id: "caffeine", substance: "Caffeine", route: "oral", amount: 100, unit: "mg")
        item.journalGeneration = 3
        let payload = item.makePayload(id: UUID(), amount: 100, timestamp: .now)
        #expect(payload.journalGeneration == 3)
        #expect(!JournalResetGeneration.accepts(payload, generation: 4))
    }

    // MARK: - Wire round-trips

    @Test
    func `Payload survives a Codable round-trip unchanged`() throws {
        let payload = drinkPayload()
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(WatchDosePayload.self, from: data)
        #expect(decoded == payload)
    }

    @Test
    func `Payload survives the transferUserInfo dictionary bridge`() throws {
        let payload = drinkPayload()
        let userInfo = try #require(payload.userInfo())
        let decoded = try #require(WatchDosePayload(userInfo: userInfo))
        #expect(decoded == payload)
        // A foreign dictionary is not one of ours.
        #expect(WatchDosePayload(userInfo: ["other": 1]) == nil)
    }

    @Test
    func `Manifest survives the applicationContext dictionary bridge`() throws {
        let manifest = QuickLogManifest(
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            items: [QuickLogManifestItem(id: "k", substance: "Alcohol", route: "oral", amount: 14, unit: "g", isByVolume: true)],
            drinkPresets: ManifestDrinkPreset.wireForm(of: Self.alcoholCapability()),
        )
        let context = try #require(manifest.applicationContext())
        let decoded = try #require(QuickLogManifest(applicationContext: context))
        #expect(decoded == manifest)
        #expect(QuickLogManifest(applicationContext: ["nope": 1]) == nil)
    }

    // MARK: - Payload → DoseEntry mapping

    @Test
    func `makeEntry carries the id, route, timestamp, identity, and drink detail`() {
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

    @Test
    func `An unknown route rawValue falls back to oral, never a crash`() {
        var payload = massPayload()
        payload.route = "teleport"
        #expect(WatchDoseReceiver.makeEntry(from: payload).route == .oral)
    }

    @Test
    func `A drink stores canonical grams, ignoring the watch's advisory amount`() {
        var payload = drinkPayload()
        payload.amount = 999 // a wrong/stale number from the watch
        let entry = WatchDoseReceiver.makeEntry(from: payload)
        #expect(entry.amount == ByVolumeDosing.grams(volumeML: 330, abv: 5))
    }

    // MARK: - Idempotency (watch → phone)

    @Test
    func `Ingesting one payload logs exactly one dose`() throws {
        let context = try freshContext()
        let payload = massPayload()
        #expect(WatchDoseReceiver.ingest(payload, in: context) == .inserted(payload.id))
        #expect(try context.fetchCount(FetchDescriptor<DoseEntry>()) == 1)
    }

    @Test
    func `A re-delivered transfer never double-logs`() throws {
        let context = try freshContext()
        let payload = massPayload()
        let first = WatchDoseReceiver.ingest(payload, in: context)
        let second = WatchDoseReceiver.ingest(payload, in: context)
        #expect(first == .inserted(payload.id))
        #expect(second == .duplicate)
        #expect(try context.fetchCount(FetchDescriptor<DoseEntry>()) == 1)
    }

    @Test
    func `Distinct ids log distinct doses`() throws {
        let context = try freshContext()
        WatchDoseReceiver.ingest(massPayload(id: UUID()), in: context)
        WatchDoseReceiver.ingest(massPayload(id: UUID()), in: context)
        #expect(try context.fetchCount(FetchDescriptor<DoseEntry>()) == 2)
    }

    @Test
    func `A watch-logged drink folds into the phone recents as a chip`() throws {
        let context = try freshContext()
        WatchDoseReceiver.ingest(drinkPayload(), in: context)
        let chips = try context.fetch(FetchDescriptor<QuickLogDose>())
        #expect(chips.contains { $0.drinkName == "IPA" && $0.abv == 5 })
    }

    // MARK: - Manifest assembly (phone → watch)

    @Test
    func `Recents map to tiles; a favorited chip is marked and sorts first`() {
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

    @Test
    func `A favorite with no history gets a tile from its default dose`() {
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

    @Test
    func `A favorite with no history and no default is skipped, not a blank tile`() {
        let manifest = QuickLogManifestBuilder.build(
            recents: [],
            favorites: [FavoriteSubstance(substance: "Mystery")],
            generatedAt: Date(timeIntervalSince1970: 0),
        )
        #expect(manifest.items.isEmpty)
    }

    @Test
    func `An alcohol tile marks isByVolume and carries the drink presets`() {
        let drink = QuickLogDose(
            substance: "Alcohol", route: .oral, amount: 13.02, unit: "g", sortOrder: 0,
            volumeML: 330, abv: 5, drinkName: "IPA",
        )
        let manifest = QuickLogManifestBuilder.build(
            recents: [drink], favorites: [], generatedAt: Date(timeIntervalSince1970: 0),
        )
        #expect(manifest.items.first?.isByVolume == true)
        #expect(manifest.drinkPresets.count == Self.alcoholCapability().drinkPresets.count)
        #expect(manifest.drinkPresets.contains { $0.emoji == "🍺" && $0.volumeML == 330 })
    }

    @Test
    func `A manifest with no by-volume item ships no drink presets`() {
        let caffeine = QuickLogDose(substance: "Caffeine", route: .oral, amount: 100, unit: "mg", sortOrder: 0)
        let manifest = QuickLogManifestBuilder.build(
            recents: [caffeine], favorites: [], generatedAt: Date(timeIntervalSince1970: 0),
        )
        #expect(manifest.drinkPresets.isEmpty)
    }

    @Test
    func `The item limit caps how many recents ship`() {
        let recents = (0 ..< 30).map {
            QuickLogDose(substance: "S\($0)", route: .oral, amount: Double($0 + 1), unit: "mg", sortOrder: Double($0))
        }
        let manifest = QuickLogManifestBuilder.build(
            recents: recents, favorites: [], generatedAt: Date(timeIntervalSince1970: 0), itemLimit: 5,
        )
        #expect(manifest.items.count == 5)
    }

    // MARK: - My Meds

    /// Noon on a fixed day: mid-journal-day under any Day Starts At.
    private static let noon = Calendar.current.date(
        bySettingHour: 12, minute: 0, second: 0, of: Date(timeIntervalSince1970: 1_700_000_000),
    ) ?? Date(timeIntervalSince1970: 1_700_000_000)

    /// Concerta at 8:00 and 13:00, an anytime magnesium supplement, and an as-needed
    /// ibuprofen, inserted so each has its own row identity.
    private func insertMeds(in context: ModelContext) throws -> (concerta: DailyDoseItem, magnesium: DailyDoseItem) {
        let concerta = DailyDoseItem(
            substance: "Methylphenidate", amount: 36, sortOrder: 0, isBackgroundMed: true,
            releaseForm: "XR", productName: "Concerta", reminderTimesMinutes: [780, 480],
        )
        let magnesium = DailyDoseItem(substance: "Magnesium", amount: 200, sortOrder: 1, isQuiet: true)
        let ibuprofen = DailyDoseItem(substance: "Ibuprofen", amount: 400, sortOrder: 2, isAsNeeded: true)
        for item in [concerta, magnesium, ibuprofen] {
            context.insert(item)
        }
        try context.save()
        return (concerta, magnesium)
    }

    @Test
    func `My Meds ships today and tomorrow, one slot per reminder time, as-needed left out`() throws {
        let context = try freshContext()
        _ = try insertMeds(in: context)
        let days = try QuickLogManifestBuilder.medDays(
            items: context.fetch(FetchDescriptor<DailyDoseItem>(sortBy: [SortDescriptor(\.sortOrder)])),
            todayOccurrences: [], now: Self.noon, boundaryHour: 4,
        )
        #expect(days.count == 2)
        #expect(days[0].contains(Self.noon))
        #expect(days[1].start == days[0].end)
        #expect(!days[1].contains(Self.noon))
        for day in days {
            #expect(day.slots.map(\.slotMinutes) == [480, 780, nil])
            #expect(day.slots.map(\.displayName) == ["Concerta", "Concerta", "Magnesium"])
            #expect(day.slots.map(\.isQuiet) == [false, false, true])
        }
    }

    @Test
    func `Today's slot states come from its occurrences; tomorrow starts open`() throws {
        let context = try freshContext()
        let meds = try insertMeds(in: context)
        let today = Calendar.current.journalDay(for: Self.noon, boundaryHour: 4)
        let morning = RoutineOccurrence(substance: meds.concerta.substance, route: .oral, dueDay: today, slotMinutes: 480)
        morning.state = .logged
        let supplement = RoutineOccurrence(substance: meds.magnesium.substance, route: .oral, dueDay: today)
        supplement.state = .skipped
        let days = try QuickLogManifestBuilder.medDays(
            items: context.fetch(FetchDescriptor<DailyDoseItem>(sortBy: [SortDescriptor(\.sortOrder)])),
            todayOccurrences: [morning, supplement], now: Self.noon, boundaryHour: 4,
        )
        #expect(days[0].slots.map(\.taken) == [true, false, false])
        #expect(days[0].slots.map(\.skipped) == [false, false, true])
        #expect(days[1].slots.allSatisfy { !$0.taken && !$0.skipped })
    }

    @Test
    func `A slot taken on the watch logs the med as My Meds does, once`() async throws {
        await SubstanceStore.shared.ensureAllLoaded()
        let context = try freshContext()
        _ = try insertMeds(in: context)
        let now = Date()
        let day = try #require(QuickLogManifestBuilder.medDays(in: context, now: now).first)
        let slot = try #require(day.slots.first { $0.slotMinutes == 480 })

        let payload = slot.makePayload(id: UUID(), timestamp: now, journalGeneration: nil)
        #expect(payload.medSlot == slot.id)
        #expect(WatchDoseReceiver.ingest(payload, in: context) == .inserted(payload.id))
        let entry = try #require(context.fetch(FetchDescriptor<DoseEntry>()).first)
        #expect(entry.productName == "Concerta")
        #expect(entry.releaseForm == "XR")
        #expect(entry.medSlotMinutes == 480)
        #expect(entry.isBackgroundMed)
        // A med is no quick-log recent, on the phone or from the wrist.
        #expect(try context.fetchCount(FetchDescriptor<QuickLogDose>()) == 0)

        // A second wrist tap on the same slot (a fresh id) finds it already taken.
        let again = slot.makePayload(id: UUID(), timestamp: now, journalGeneration: nil)
        #expect(WatchDoseReceiver.ingest(again, in: context) == .slotTaken)
        #expect(try context.fetchCount(FetchDescriptor<DoseEntry>()) == 1)
        DoseLogService.shared.cancelPendingBookkeeping()
    }

    @Test
    func `An untick removes the dose its tick logged, or the one that ticked the slot`() async throws {
        await SubstanceStore.shared.ensureAllLoaded()
        let context = try freshContext()
        _ = try insertMeds(in: context)
        let now = Date()
        let day = try #require(QuickLogManifestBuilder.medDays(in: context, now: now).first)
        let morning = try #require(day.slots.first { $0.slotMinutes == 480 })

        // A tick from this watch, unticked by its dose's id.
        let tick = morning.makePayload(id: UUID(), timestamp: now, journalGeneration: nil)
        #expect(WatchDoseReceiver.ingest(tick, in: context) == .inserted(tick.id))
        let byID = WatchMedUntake(medSlot: morning.id, entryID: tick.id, timestamp: now, journalGeneration: nil)
        #expect(WatchDoseReceiver.untake(byID, in: context) == .removed(tick.id))
        #expect(try context.fetchCount(FetchDescriptor<DoseEntry>()) == 0)

        // A slot the watch saw ticked by the phone, unticked by its slot.
        let again = morning.makePayload(id: UUID(), timestamp: now, journalGeneration: nil)
        #expect(WatchDoseReceiver.ingest(again, in: context) == .inserted(again.id))
        let bySlot = WatchMedUntake(medSlot: morning.id, entryID: nil, timestamp: now, journalGeneration: nil)
        #expect(WatchDoseReceiver.untake(bySlot, in: context) == .removed(again.id))
        #expect(try context.fetchCount(FetchDescriptor<DoseEntry>()) == 0)
        DoseLogService.shared.cancelPendingBookkeeping()
    }

    @Test
    func `Unticking a tick the phone refused leaves the phone's dose`() async throws {
        await SubstanceStore.shared.ensureAllLoaded()
        let context = try freshContext()
        _ = try insertMeds(in: context)
        let now = Date()
        let day = try #require(QuickLogManifestBuilder.medDays(in: context, now: now).first)
        let morning = try #require(day.slots.first { $0.slotMinutes == 480 })

        // The phone took 8:00; a watch still showing it open ticks it, then unticks it.
        let phone = morning.makePayload(id: UUID(), timestamp: now, journalGeneration: nil)
        #expect(WatchDoseReceiver.ingest(phone, in: context) == .inserted(phone.id))
        let tick = morning.makePayload(id: UUID(), timestamp: now, journalGeneration: nil)
        #expect(WatchDoseReceiver.ingest(tick, in: context) == .slotTaken)
        let untick = WatchMedUntake(medSlot: morning.id, entryID: tick.id, timestamp: now, journalGeneration: nil)
        #expect(WatchDoseReceiver.untake(untick, in: context) == .nothingToRemove)
        #expect(try context.fetch(FetchDescriptor<DoseEntry>()).map(\.id) == [phone.id])
        DoseLogService.shared.cancelPendingBookkeeping()
    }

    @Test
    func `Two meds sharing a slot key keep their own ids, and each tick and untick stays with its med`() async throws {
        await SubstanceStore.shared.ensureAllLoaded()
        let context = try freshContext()
        var meds: [DailyDoseItem] = []
        for (index, (product, amount)) in [("Concerta 18", 18.0), ("Concerta 36", 36.0)].enumerated() {
            let med = DailyDoseItem(
                substance: "Methylphenidate", amount: amount, sortOrder: index,
                productName: product, reminderTimesMinutes: [480],
            )
            context.insert(med)
            meds.append(med)
        }
        try context.save()
        let day = try #require(QuickLogManifestBuilder.medDays(in: context, now: Date()).first)
        #expect(Set(day.slots.map(\.id)).count == 2)
        let small = try #require(day.slots.first { $0.productName == "Concerta 18" })
        let large = try #require(day.slots.first { $0.productName == "Concerta 36" })

        // A tick reaches its own med.
        let tick = large.makePayload(id: UUID(), timestamp: Date(), journalGeneration: nil)
        #expect(WatchDoseReceiver.ingest(tick, in: context) == .inserted(tick.id))
        let entry = try #require(context.fetch(FetchDescriptor<DoseEntry>()).first)
        #expect(entry.productName == "Concerta 36")
        #expect(entry.amount == 36)

        // The meds share one occurrence, so the other row reads taken too; unticking it
        // leaves the dose that isn't its own.
        let other = WatchMedUntake(medSlot: small.id, entryID: nil, timestamp: Date(), journalGeneration: nil)
        #expect(WatchDoseReceiver.untake(other, in: context) == .nothingToRemove)
        #expect(try context.fetchCount(FetchDescriptor<DoseEntry>()) == 1)

        // An id doesn't move when another med goes.
        context.delete(meds[0])
        try context.save()
        let after = try #require(QuickLogManifestBuilder.medDays(in: context, now: Date()).first)
        #expect(after.slots.map(\.id) == [large.id])
        DoseLogService.shared.cancelPendingBookkeeping()
    }

    @Test
    func `Two meds alike in everything are one row`() throws {
        let context = try freshContext()
        for index in 0 ..< 2 {
            context.insert(DailyDoseItem(substance: "Magnesium", amount: 200, sortOrder: index, isQuiet: true))
        }
        try context.save()
        let days = try QuickLogManifestBuilder.medDays(
            items: context.fetch(FetchDescriptor<DailyDoseItem>(sortBy: [SortDescriptor(\.sortOrder)])),
            todayOccurrences: [], now: Self.noon, boundaryHour: 4,
        )
        #expect(days.map(\.slots.count) == [1, 1])
    }

    @Test
    func `A slot skipped on the phone takes no dose from the watch`() async throws {
        await SubstanceStore.shared.ensureAllLoaded()
        let context = try freshContext()
        let concerta = try insertMeds(in: context).concerta
        let now = Date()
        let day = try #require(QuickLogManifestBuilder.medDays(in: context, now: now).first)
        let morning = try #require(day.slots.first { $0.slotMinutes == 480 })

        let key = RoutineOccurrenceService.slotKey(
            substance: concerta.substance, substanceUID: concerta.substanceUID, route: concerta.route, slotMinutes: 480,
        )
        RoutineOccurrenceService.skipToday(slotKeys: [key], in: context, now: now)
        let tick = morning.makePayload(id: UUID(), timestamp: now, journalGeneration: nil)
        #expect(WatchDoseReceiver.ingest(tick, in: context) == .slotSkipped)
        #expect(try context.fetchCount(FetchDescriptor<DoseEntry>()) == 0)
    }

    @Test
    func `An untick never removes the dose of another slot`() async throws {
        await SubstanceStore.shared.ensureAllLoaded()
        let context = try freshContext()
        _ = try insertMeds(in: context)
        let now = Date()
        let day = try #require(QuickLogManifestBuilder.medDays(in: context, now: now).first)
        let morning = try #require(day.slots.first { $0.slotMinutes == 480 })
        let afternoon = try #require(day.slots.first { $0.slotMinutes == 780 })

        let tick = morning.makePayload(id: UUID(), timestamp: now, journalGeneration: nil)
        #expect(WatchDoseReceiver.ingest(tick, in: context) == .inserted(tick.id))
        // 13:00 untaken on the phone, unticked from a stale watch: nothing ticks it.
        let withdrawn = WatchMedUntake(medSlot: afternoon.id, entryID: nil, timestamp: now, journalGeneration: nil)
        #expect(WatchDoseReceiver.untake(withdrawn, in: context) == .nothingToRemove)
        #expect(try context.fetchCount(FetchDescriptor<DoseEntry>()) == 1)
        DoseLogService.shared.cancelPendingBookkeeping()
    }

    @Test
    func `An untick crosses the bridge and is never read as a dose`() throws {
        let untake = WatchMedUntake(
            medSlot: "magnesium|oral|any", entryID: UUID(), timestamp: Date(timeIntervalSince1970: 0), journalGeneration: 2,
        )
        let userInfo = try #require(untake.userInfo())
        #expect(WatchMedUntake(userInfo: userInfo) == untake)
        #expect(WatchDosePayload(userInfo: userInfo) == nil)
        let dose = try #require(massPayload().userInfo())
        #expect(WatchMedUntake(userInfo: dose) == nil)
        #expect(!JournalResetGeneration.accepts(untake, generation: 1))
    }

    @Test
    func `A med change is numbered on the watch and answered by the phone's manifest`() throws {
        let suite = "watch-med-change-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(WatchMedChange.next(in: defaults) == 1)
        #expect(WatchMedChange.next(in: defaults) == 2)
        // A watch that takes up the phone's number counts on from it.
        WatchMedChange.record(7, in: defaults)
        #expect(WatchMedChange.next(in: defaults) == 8)

        // The number rides a tick and an untick across the bridge.
        let slot = ManifestMedSlot(
            id: "magnesium|oral|any", substance: "Magnesium", displayName: "Magnesium", route: "oral",
            amount: 200, unit: "mg", isQuiet: true, taken: false, skipped: false,
        )
        let tick = try #require(slot.makePayload(id: UUID(), timestamp: Self.noon, change: 3, journalGeneration: nil).userInfo())
        #expect(WatchDosePayload(userInfo: tick)?.medChange == 3)
        let untick = try #require(
            WatchMedUntake(medSlot: slot.id, entryID: nil, change: 4, timestamp: Self.noon, journalGeneration: nil).userInfo(),
        )
        #expect(WatchMedUntake(userInfo: untick)?.medChange == 4)

        // A manifest answers every change up to the one it names; one that names none, none.
        var manifest = QuickLogManifest(generatedAt: Self.noon, items: [])
        #expect(!manifest.answers(medChange: 1))
        manifest.handledMedChange = 3
        let context = try #require(manifest.applicationContext())
        let decoded = try #require(QuickLogManifest(applicationContext: context))
        #expect(decoded.answers(medChange: 3))
        #expect(!decoded.answers(medChange: 4))
    }

    @Test
    func `A slot whose med is gone logs as a plain watch dose`() throws {
        let context = try freshContext()
        var payload = massPayload()
        payload.medSlot = "nobody|oral|480"
        #expect(WatchDoseReceiver.ingest(payload, in: context) == .inserted(payload.id))
        let entry = try #require(context.fetch(FetchDescriptor<DoseEntry>()).first)
        #expect(entry.substance == "Caffeine")
        #expect(entry.medSlotMinutes == nil)
        DoseLogService.shared.cancelPendingBookkeeping()
    }

    @Test
    func `Med days cross the bridge, and a phone that sends none decodes as nil`() throws {
        let slot = ManifestMedSlot(
            id: "magnesium|oral|any", substance: "Magnesium", displayName: "Magnesium", route: "oral",
            amount: 200, unit: "mg", isQuiet: true, taken: false, skipped: false,
        )
        let day = ManifestMedDay(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 86_400), slots: [slot])
        let manifest = QuickLogManifest(generatedAt: Date(timeIntervalSince1970: 100), items: [], medDays: [day])
        let context = try #require(manifest.applicationContext())
        let decoded = try #require(QuickLogManifest(applicationContext: context))
        #expect(decoded == manifest)
        #expect(decoded.medDay(containing: Date(timeIntervalSince1970: 100)) == day)
        #expect(decoded.medDay(containing: Date(timeIntervalSince1970: 86_400)) == nil)

        let older = #"{"generatedAt":0,"items":[],"drinkPresets":[]}"#
        let legacy = try JSONDecoder().decode(QuickLogManifest.self, from: Data(older.utf8))
        #expect(legacy.medDays == nil)
    }

    // MARK: - Watch-side payload construction

    @Test
    func `makePayload takes a fresh id and the user's adjusted amount, keeping identity`() {
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
