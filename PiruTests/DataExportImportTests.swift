import Foundation
import SwiftData
import Testing
@testable import Piru

// MARK: - Helpers

/// In-memory ModelContainer with the full Piru schema.
private func makeTestContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    return try ModelContainer(
        for: DoseEntry.self, SubstanceColor.self, UserColor.self,
        DailyDoseItem.self, FavoriteSubstance.self,
        configurations: config,
    )
}

// MARK: - Filename tests

@Suite("DataExportImport — filename")
struct DataExportImportTests {
    @Test
    func `Export filename contains Piru prefix and ISO timestamp marker`() {
        let filename = DataExportImport.exportFilename
        #expect(filename.hasPrefix("Piru "))
        #expect(filename.count > 5)
        #expect(filename.contains("T"))
    }

    @Test
    func `Export filename is non-empty and well-formed`() {
        let f1 = DataExportImport.exportFilename
        #expect(!f1.isEmpty)
        #expect(f1.hasPrefix("Piru "))
    }
}

// MARK: - Round-trip tests

@Suite("DataExportImport — round-trip")
@MainActor
struct DataExportImportRoundTripTests {
    // MARK: Core DoseEntry fields

    @Test
    func `DoseEntry core fields survive export → import`() throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)

        let t1 = Date(timeIntervalSince1970: 1_700_000_000)
        let t2 = Date(timeIntervalSince1970: 1_700_100_000)
        let t3 = Date(timeIntervalSince1970: 1_700_200_000)

        context.insert(DoseEntry(
            substance: "Caffeine",
            amount: 200,
            unit: "mg",
            route: .oral,
            timestamp: t1,
            notes: "morning coffee",
            tags: ["productive"],
        ))
        context.insert(DoseEntry(
            substance: "Melatonin",
            amount: 500,
            unit: "µg",
            route: .sublingual,
            timestamp: t2,
            notes: nil,
            tags: [],
        ))
        context.insert(DoseEntry(
            substance: "Magnesium Glycinate",
            amount: 400,
            unit: "mg",
            route: .oral,
            timestamp: t3,
            notes: "with dinner",
            tags: ["routine", "sleep"],
        ))

        try context.save()
        let data = try DataExportImport.exportJSON(context: context)
        try DataExportImport.deleteAll(context: context)
        try context.save()

        let afterWipe = try context.fetch(FetchDescriptor<DoseEntry>())
        #expect(afterWipe.isEmpty)

        try DataExportImport.importJSON(data: data, context: context)
        try context.save()

        let imported = try context.fetch(FetchDescriptor<DoseEntry>(sortBy: [SortDescriptor(\.timestamp)]))
        #expect(imported.count == 3)

        let caffeine = try #require(imported.first { $0.substance == "Caffeine" })
        #expect(caffeine.amount == 200)
        #expect(caffeine.unit == "mg")
        #expect(caffeine.route == .oral)
        #expect(abs(caffeine.timestamp.timeIntervalSince(t1)) < 1.0)

        let melatonin = try #require(imported.first { $0.substance == "Melatonin" })
        #expect(melatonin.amount == 500)
        #expect(melatonin.unit == "µg")
        #expect(melatonin.route == .sublingual)

        let magnesium = try #require(imported.first { $0.substance == "Magnesium Glycinate" })
        #expect(magnesium.amount == 400)
        #expect(magnesium.route == .oral)
    }

    // MARK: SubstanceColor and DailyDoseItem

    @Test
    func `SubstanceColor and DailyDoseItem survive export → import`() throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)

        let ts = Date(timeIntervalSince1970: 1_700_000_000)
        context.insert(DoseEntry(substance: "Ibuprofen", amount: 400, unit: "mg", route: .oral, timestamp: ts))

        context.insert(SubstanceColor(substance: "Ibuprofen", hexColor: "007AFF"))
        context.insert(SubstanceColor(substance: "Aspirin", hexColor: "FF3B30"))

        context.insert(DailyDoseItem(
            substance: "Vitamin D3",
            amount: 2_000,
            unit: "IU",
            route: .oral,
            sortOrder: 0,
        ))
        context.insert(DailyDoseItem(
            substance: "Omega-3",
            amount: 1_000,
            unit: "mg",
            route: .oral,
            sortOrder: 1,
        ))

        try context.save()
        let data = try DataExportImport.exportJSON(context: context)
        try DataExportImport.deleteAll(context: context)
        try context.save()
        try DataExportImport.importJSON(data: data, context: context)
        try context.save()

        let colors = try context.fetch(FetchDescriptor<SubstanceColor>())
        let colorMap = Dictionary(colors.map { ($0.substance, $0.hexColor) }, uniquingKeysWith: { first, _ in first })
        #expect(colorMap["Ibuprofen"] != nil)
        #expect(colorMap["Aspirin"] != nil)

        let dailyItems = try context.fetch(FetchDescriptor<DailyDoseItem>(sortBy: [SortDescriptor(\.sortOrder)]))
        #expect(dailyItems.count == 2)
        let vitD = try #require(dailyItems.first { $0.substance == "Vitamin D3" })
        #expect(vitD.amount == 2_000)
        #expect(vitD.unit == "IU")
        #expect(vitD.route == .oral)

        let omega = try #require(dailyItems.first { $0.substance == "Omega-3" })
        #expect(omega.sortOrder == 1)
    }

    // MARK: Tag preservation

    @Test
    func `Tags from #hashtag-style notes round-trip correctly`() throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)

        let ts = Date(timeIntervalSince1970: 1_700_000_000)
        context.insert(DoseEntry(
            substance: "L-Theanine",
            amount: 200,
            unit: "mg",
            route: .oral,
            timestamp: ts,
            notes: "feeling great #excited #grateful",
            tags: ["excited", "grateful"],
        ))

        try context.save()
        let data = try DataExportImport.exportJSON(context: context)
        try DataExportImport.deleteAll(context: context)
        try context.save()
        try DataExportImport.importJSON(data: data, context: context)
        try context.save()

        let imported = try context.fetch(FetchDescriptor<DoseEntry>())
        let entry = try #require(imported.first)
        #expect(entry.tags.contains("excited"))
        #expect(entry.tags.contains("grateful"))
        #expect(entry.tags.count == 2)
    }

    // MARK: Format detection

    @Test
    func `JSON with 'experiences' key routes to PsyLog import path`() throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)

        let psylogJSON = """
        {
            "experiences": [{
                "title": "Test",
                "isFavorite": false,
                "creationDate": 1700000000000,
                "sortDate": 1700000000000,
                "text": "",
                "ingestions": [{
                    "substanceName": "Caffeine",
                    "dose": 100.0,
                    "time": 1700000000000,
                    "administrationRoute": "ORAL",
                    "notes": "",
                    "units": "mg"
                }]
            }],
            "substanceCompanions": [],
            "customUnits": [],
            "customSubstances": [],
            "dailyDoseItems": []
        }
        """
        let data = Data(psylogJSON.utf8)
        try DataExportImport.importJSON(data: data, context: context)

        let imported = try context.fetch(FetchDescriptor<DoseEntry>())
        #expect(imported.count == 1)
        #expect(imported.first?.substance == "Caffeine")
        #expect(imported.first?.amount == 100.0)
    }

    @Test
    func `JSON without 'experiences' key routes to legacy import path`() throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let ts = Date(timeIntervalSince1970: 1_700_000_000)
        let legacyJSON = """
        {
            "doseEntries": [{
                "substance": "Melatonin",
                "amount": 3.0,
                "unit": "mg",
                "route": "oral",
                "timestamp": "\(ISO8601DateFormatter().string(from: ts))",
                "notes": null,
                "tags": []
            }],
            "dailyDoseItems": [],
            "substanceColors": [],
            "userColors": []
        }
        """
        let data = Data(legacyJSON.utf8)
        try DataExportImport.importJSON(data: data, context: context)

        let imported = try context.fetch(FetchDescriptor<DoseEntry>())
        #expect(imported.count == 1)
        #expect(imported.first?.substance == "Melatonin")
        #expect(imported.first?.amount == 3.0)
        #expect(imported.first?.route == .oral)
    }

    // MARK: Empty export

    @Test
    func `Empty context exports valid JSON that imports cleanly`() throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)

        let data = try DataExportImport.exportJSON(context: context)
        #expect(!data.isEmpty)

        let json = try #require(try? JSONSerialization.jsonObject(with: data) as? [String: Any])
        // The default export is the Piru-native format.
        #expect(json["piruExportVersion"] as? Int == 1)

        try DataExportImport.importJSON(data: data, context: context)

        let entries = try context.fetch(FetchDescriptor<DoseEntry>())
        #expect(entries.isEmpty)

        // The PsyLog format still produces an importable, PW-shaped file.
        let psyLogData = try DataExportImport.exportJSON(format: .psyLog, context: context)
        let psyLogJSON = try #require(try? JSONSerialization.jsonObject(with: psyLogData) as? [String: Any])
        #expect(psyLogJSON["experiences"] != nil)
        #expect(psyLogJSON["exportSource"] as? String == "iOS Journal 15.0")
    }

    // MARK: Custom substances — release-blocker overlay path

    /// Isolated CustomSubstanceStore backed by a per-test UserDefaults suite
    /// — running the round-trip against `.shared` would pollute the user's
    /// real App Group on every CI run.
    private func makeIsolatedCustomStore() -> CustomSubstanceStore {
        let suite = "piru.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return CustomSubstanceStore.forTesting(defaults: defaults)
    }

    @Test
    func `Custom substances survive export → import with duration preserved`() throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)
        let store = makeIsolatedCustomStore()

        let duration = DurationProfile(
            onset: DurationRange(min: 5, max: 15),
            comeup: DurationRange(min: 15, max: 30),
            peak: DurationRange(min: 30, max: 90),
            offset: DurationRange(min: 60, max: 120),
            afterglow: nil,
            total: DurationRange(min: 120, max: 240),
        )
        store.add(CustomSubstanceEntry(
            name: "2-MMC",
            category: .stimulant,
            defaultRoute: .insufflation,
            unit: "mg",
            notes: "custom notes",
            duration: duration,
        ))
        // Need at least one DoseEntry — exportJSON's PsyLog shape groups
        // experiences from entries; an empty journal can still export.
        context.insert(DoseEntry(
            substance: "Caffeine",
            amount: 100,
            unit: "mg",
            route: .oral,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
        ))

        let data = try DataExportImport.exportJSON(context: context, customStore: store)

        // The exported JSON should carry the custom as a structured object,
        // not the legacy `customSubstances: []` placeholder.
        let raw = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let customs = try #require(raw["customSubstances"] as? [[String: Any]])
        #expect(customs.count == 1)
        #expect(customs.first?["name"] as? String == "2-MMC")
        #expect((customs.first?["duration"] as? [String: Any])?["peak"] != nil)

        // Importing into a fresh store recreates the same entry.
        let freshStore = makeIsolatedCustomStore()
        let freshContext = try ModelContext(makeTestContainer())
        try DataExportImport.importJSON(data: data, context: freshContext, customStore: freshStore)

        #expect(freshStore.all.count == 1)
        let imported = try #require(freshStore.all.first)
        #expect(imported.name == "2-MMC")
        #expect(imported.category == .stimulant)
        #expect(imported.defaultRoute == .insufflation)
        #expect(imported.duration?.peak?.midpoint == 60)
        #expect(imported.notes == "custom notes")
    }

    @Test
    func `Re-importing the same file is idempotent (no duplicate customs)`() throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)
        let store = makeIsolatedCustomStore()

        store.add(CustomSubstanceEntry(name: "MyCustom", category: .stimulant))
        context.insert(DoseEntry(
            substance: "Caffeine",
            amount: 50,
            unit: "mg",
            route: .oral,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
        ))
        let data = try DataExportImport.exportJSON(context: context, customStore: store)

        try DataExportImport.importJSON(data: data, context: context, customStore: store)
        try DataExportImport.importJSON(data: data, context: context, customStore: store)

        #expect(store.all.count == 1)
    }

    @Test
    func `Imported custom replaces existing entry with the same name`() throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)
        let store = makeIsolatedCustomStore()

        // Existing custom — different category and no duration.
        let preExisting = CustomSubstanceEntry(
            name: "Foo",
            category: .other,
            defaultRoute: .oral,
            unit: "mg",
            notes: "stale notes",
            duration: nil,
        )
        store.add(preExisting)
        let originalId = try #require(store.all.first).id

        // Build a JSON containing a different "Foo" with a duration profile.
        let exportContext = try ModelContext(makeTestContainer())
        let sourceStore = makeIsolatedCustomStore()
        sourceStore.add(CustomSubstanceEntry(
            name: "Foo",
            category: .stimulant,
            defaultRoute: .insufflation,
            unit: "mg",
            notes: "imported notes",
            duration: DurationProfile(
                onset: DurationRange(min: 1, max: 5),
                comeup: nil, peak: DurationRange(min: 30, max: 60),
                offset: DurationRange(min: 30, max: 60),
                afterglow: nil,
                total: DurationRange(min: 120, max: 180),
            ),
        ))
        exportContext.insert(DoseEntry(
            substance: "Caffeine",
            amount: 50,
            unit: "mg",
            route: .oral,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
        ))
        let data = try DataExportImport.exportJSON(context: exportContext, customStore: sourceStore)

        try DataExportImport.importJSON(data: data, context: context, customStore: store)

        #expect(store.all.count == 1, "Same-name custom should replace, not duplicate")
        let merged = try #require(store.all.first)
        #expect(merged.id == originalId, "Stored UUID should be preserved across the merge")
        #expect(merged.category == .stimulant)
        #expect(merged.defaultRoute == .insufflation)
        #expect(merged.notes == "imported notes")
        #expect(merged.duration?.peak?.midpoint == 45)
    }

    // MARK: exportFilename format

    @Test
    func `exportFilename has Piru prefix and ISO-ish timestamp`() {
        let filename = DataExportImport.exportFilename
        #expect(filename.hasPrefix("Piru "))

        let body = String(filename.dropFirst("Piru ".count))
        #expect(body.count == 17, "Expected yyyy-MM-ddTHHmmss (17 chars), got '\(body)'")

        let dashCount = body.count(where: { $0 == "-" })
        #expect(dashCount == 2)
        #expect(body.contains("T"))
    }
}

// MARK: - Location round-trip

@Suite("DataExportImport — location")
@MainActor
struct DataExportImportLocationTests {
    @Test
    func `Per-dose locations survive a Piru → Piru round-trip`() throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)

        // Two doses on the same day with *different* places — a faithful
        // round-trip must preserve each, which only the per-ingestion location
        // can do (PsyLog's experience-level location would collapse them).
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        context.insert(DoseEntry(
            substance: "Caffeine", amount: 100, unit: "mg", route: .oral,
            timestamp: day,
            locationName: "Blue Bottle", latitude: 37.7765, longitude: -122.4231,
        ))
        context.insert(DoseEntry(
            substance: "L-Theanine", amount: 200, unit: "mg", route: .oral,
            timestamp: day.addingTimeInterval(3_600),
            locationName: "Golden Gate Park", latitude: 37.7694, longitude: -122.4862,
        ))
        try context.save()

        let data = try DataExportImport.exportJSON(context: context)
        try DataExportImport.deleteAll(context: context)
        try context.save()
        try DataExportImport.importJSON(data: data, context: context)

        let entries = try context.fetch(FetchDescriptor<DoseEntry>())
        let byName = Dictionary(uniqueKeysWithValues: entries.map { ($0.substance, $0) })

        let caffeine = try #require(byName["Caffeine"])
        #expect(caffeine.locationName == "Blue Bottle")
        #expect(caffeine.latitude == 37.7765)
        #expect(caffeine.longitude == -122.4231)
        #expect(caffeine.coordinate != nil)

        let theanine = try #require(byName["L-Theanine"])
        #expect(theanine.locationName == "Golden Gate Park")
        #expect(theanine.latitude == 37.7694)
    }

    @Test
    func `A dose with no location round-trips as nil`() throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)
        context.insert(DoseEntry(
            substance: "Vitamin D",
            amount: 1_000,
            unit: "IU",
            route: .oral,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
        ))
        try context.save()

        let data = try DataExportImport.exportJSON(context: context)
        try DataExportImport.deleteAll(context: context)
        try context.save()
        try DataExportImport.importJSON(data: data, context: context)

        let entry = try #require(try context.fetch(FetchDescriptor<DoseEntry>()).first)
        #expect(entry.locationName == nil)
        #expect(entry.latitude == nil)
        #expect(entry.coordinate == nil)
    }

    @Test
    func `Exported JSON carries an experience-level location for PsyLog compatibility`() throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)
        context.insert(DoseEntry(
            substance: "MDMA", amount: 100, unit: "mg", route: .oral,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            locationName: "Festival Grounds", latitude: 51.5, longitude: -0.12,
        ))
        try context.save()

        let data = try DataExportImport.exportJSON(format: .psyLog, context: context)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        // PsychonautWiki gate: the file must carry exportSource and no Piru-only
        // top-level keys, or PW rejects it as "legacy".
        #expect(json["exportSource"] as? String == "iOS Journal 15.0")
        #expect(json["customSubstances"] == nil)
        #expect(json["dailyDoseItems"] == nil)
        let experiences = try #require(json["experiences"] as? [[String: Any]])
        let location = try #require(experiences.first?["location"] as? [String: Any])
        #expect(location["name"] as? String == "Festival Grounds")
        #expect(location["latitude"] as? Double == 51.5)
        // Each ingestion carries the modern isHiddenInTimeline flag.
        let ingestions = try #require(experiences.first?["ingestions"] as? [[String: Any]])
        #expect(ingestions.first?["isHiddenInTimeline"] as? Bool == false)
    }

    @Test
    func `A PsyLog file with only experience-level location applies it to every ingestion`() throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)

        // A cross-app PsyLog file: location lives only on the experience, and the
        // ingestions carry no per-dose location — both doses should inherit it.
        let psyLogJSON = """
        {
          "experiences": [
            {
              "title": "1 Jan 2025",
              "creationDate": 1735732800000,
              "sortDate": 1735732800000,
              "location": { "name": "Berlin", "latitude": 52.52, "longitude": 13.405 },
              "ingestions": [
                { "substanceName": "Caffeine", "dose": 100, "time": 1735732800000, "administrationRoute": "ORAL", "units": "mg", "notes": "" },
                { "substanceName": "L-Theanine", "dose": 200, "time": 1735736400000, "administrationRoute": "ORAL", "units": "mg", "notes": "" }
              ]
            }
          ],
          "substanceCompanions": []
        }
        """
        try DataExportImport.importJSON(data: Data(psyLogJSON.utf8), context: context)

        let entries = try context.fetch(FetchDescriptor<DoseEntry>())
        #expect(entries.count == 2)
        #expect(entries.allSatisfy { $0.locationName == "Berlin" })
        #expect(entries.allSatisfy { $0.latitude == 52.52 && $0.longitude == 13.405 })
    }

    @Test
    func `A PsyLog file with no location imports doses with no location`() throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)
        let psyLogJSON = """
        {
          "experiences": [
            {
              "title": "1 Jan 2025", "creationDate": 1735732800000, "sortDate": 1735732800000,
              "ingestions": [
                { "substanceName": "Caffeine", "dose": 100, "time": 1735732800000, "administrationRoute": "ORAL", "units": "mg", "notes": "" }
              ]
            }
          ]
        }
        """
        try DataExportImport.importJSON(data: Data(psyLogJSON.utf8), context: context)
        let entry = try #require(try context.fetch(FetchDescriptor<DoseEntry>()).first)
        #expect(entry.locationName == nil)
        #expect(entry.coordinate == nil)
    }
}

// MARK: - Three import formats + native fidelity

@Suite("DataExportImport — formats")
@MainActor
struct DataExportImportFormatTests {
    /// Piru-native export preserves the fields the PsyLog format can't: session
    /// title & note, per-dose background-med flag, tags, and location.
    @Test
    func `Piru-native round-trip preserves sessions, background flag, tags and location`() throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)

        let session = Session(startDate: Date(timeIntervalSince1970: 1_700_000_000), title: "Festival Saturday", note: "great set")
        context.insert(session)
        let dose = DoseEntry(
            substance: "MDMA", amount: 120, unit: "mg", route: .oral,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            tags: ["party"], isBackgroundMed: false,
            locationName: "Main Stage", latitude: 51.5, longitude: -0.12,
        )
        context.insert(dose)
        dose.session = session
        let med = DoseEntry(
            substance: "Magnesium", amount: 200, unit: "mg", route: .oral,
            timestamp: Date(timeIntervalSince1970: 1_700_003_600), isBackgroundMed: true,
        )
        context.insert(med)
        med.session = session
        context.insert(FavoriteSubstance(substance: "MDMA"))
        try context.save()

        let data = try DataExportImport.exportJSON(format: .piru, context: context)
        // It's the native format (not PsyLog).
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["piruExportVersion"] as? Int == 1)
        #expect((json["appVersion"] as? String)?.hasPrefix("Piru ") == true)

        try DataExportImport.deleteAll(context: context)
        try context.save()
        try DataExportImport.importJSON(data: data, context: context)

        let sessions = try context.fetch(FetchDescriptor<Session>())
        let restored = try #require(sessions.first { $0.title == "Festival Saturday" })
        #expect(restored.note == "great set")
        #expect(restored.orderedDoses.count == 2)

        let entries = try context.fetch(FetchDescriptor<DoseEntry>())
        let mdma = try #require(entries.first { $0.substance == "MDMA" })
        #expect(mdma.tags == ["party"])
        #expect(mdma.isBackgroundMed == false)
        #expect(mdma.locationName == "Main Stage")
        #expect(mdma.session?.id == restored.id)
        let mag = try #require(entries.first { $0.substance == "Magnesium" })
        #expect(mag.isBackgroundMed == true)

        let favorites = try context.fetch(FetchDescriptor<FavoriteSubstance>())
        #expect(favorites.contains { $0.substance == "MDMA" })
    }

    /// A modern PsychonautWiki file (has `exportSource`): each experience becomes
    /// a Piru session carrying its custom title, and the experience-level
    /// location is applied to every dose.
    @Test
    func `PW modern import maps experience title to a session and location to all doses`() throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)
        let json = """
        {
          "exportSource": "iOS Journal 15.0",
          "substanceCompanions": [],
          "customUnits": [],
          "experiences": [
            {
              "title": "Birthday", "text": "fun night", "creationDate": 1735732800000, "sortDate": 1735732800000,
              "location": { "name": "Berlin", "latitude": 52.52, "longitude": 13.405 },
              "ingestions": [
                { "substanceName": "MDMA", "dose": 100, "time": 1735732800000, "administrationRoute": "ORAL", "units": "mg", "notes": "", "isHiddenInTimeline": false },
                { "substanceName": "Caffeine", "dose": 80, "time": 1735736400000, "administrationRoute": "ORAL", "units": "mg", "notes": "", "isHiddenInTimeline": false }
              ]
            }
          ]
        }
        """
        try DataExportImport.importJSON(data: Data(json.utf8), context: context)

        let sessions = try context.fetch(FetchDescriptor<Session>())
        let session = try #require(sessions.first { $0.title == "Birthday" })
        #expect(session.note == "fun night")
        #expect(session.orderedDoses.count == 2)
        let entries = try context.fetch(FetchDescriptor<DoseEntry>())
        #expect(entries.count == 2)
        #expect(entries.allSatisfy { $0.locationName == "Berlin" })
        #expect(entries.allSatisfy { $0.session?.id == session.id })
    }

    /// An *old* PsychonautWiki file (no `exportSource`, carries `customSubstances`)
    /// still imports — PW old is no longer exportable but remains importable.
    @Test
    func `PW old (legacy) import still brings in doses`() throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)
        let json = """
        {
          "substanceCompanions": [{ "substanceName": "Ketamine", "color": "PURPLE" }],
          "customSubstances": [],
          "customUnits": [],
          "experiences": [
            {
              "title": "23 Mar 2024", "text": "", "creationDate": 1711200000000, "sortDate": 1711200000000,
              "ingestions": [
                { "substanceName": "Ketamine", "dose": 50, "time": 1711200000000, "administrationRoute": "INSUFFLATED", "units": "mg", "notes": "" }
              ]
            }
          ]
        }
        """
        try DataExportImport.importJSON(data: Data(json.utf8), context: context)
        let entry = try #require(try context.fetch(FetchDescriptor<DoseEntry>()).first)
        #expect(entry.substance == "Ketamine")
        #expect(entry.route == .insufflation)
        #expect(entry.amount == 50)
        // The companion colour came across too.
        let colors = try context.fetch(FetchDescriptor<SubstanceColor>())
        #expect(colors.contains { $0.substance == "Ketamine" })
    }

    /// The PsyLog export must lowercase-match PsychonautWiki's route vocabulary,
    /// or PW throws on an unknown `administrationRoute`.
    @Test
    func `PsyLog export uses route names valid in PsychonautWiki`() throws {
        let valid: Set = [
            "oral",
            "sublingual",
            "buccal",
            "insufflated",
            "rectal",
            "transdermal",
            "subcutaneous",
            "intramuscular",
            "intravenous",
            "smoked",
            "inhaled",
        ]
        let container = try makeTestContainer()
        let context = ModelContext(container)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for (i, route) in RouteOfAdministration.allCases.enumerated() {
            context.insert(DoseEntry(
                substance: "S\(i)",
                amount: 10,
                unit: "mg",
                route: route,
                timestamp: base.addingTimeInterval(Double(i) * 60),
            ))
        }
        try context.save()

        let data = try DataExportImport.exportJSON(format: .psyLog, context: context)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let experiences = try #require(json["experiences"] as? [[String: Any]])
        for exp in experiences {
            for ing in (exp["ingestions"] as? [[String: Any]]) ?? [] {
                let route = try #require(ing["administrationRoute"] as? String)
                #expect(valid.contains(route.lowercased()), "route \(route) is not a PsychonautWiki route")
            }
        }
    }
}
