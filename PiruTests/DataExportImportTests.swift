import Testing
import Foundation
import SwiftData
@testable import Piru

// MARK: - Helpers

/// In-memory ModelContainer with the full Piru schema.
private func makeTestContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
        for: DoseEntry.self, SubstanceColor.self, UserColor.self,
        DailyDoseItem.self, FavoriteSubstance.self,
        configurations: config
    )
}

// MARK: - Filename tests

@Suite("DataExportImport — filename")
struct DataExportImportTests {

    @Test("Export filename contains Piru prefix and ISO timestamp marker")
    func exportFilenameFormat() {
        let filename = DataExportImport.exportFilename
        #expect(filename.hasPrefix("Piru "))
        #expect(filename.count > 5)
        #expect(filename.contains("T"))
    }

    @Test("Export filename is non-empty and well-formed")
    func exportFilenameUnique() {
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

    @Test("DoseEntry core fields survive export → import")
    func doseEntryCoreFieldsRoundTrip() throws {
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
            tags: ["productive"]
        ))
        context.insert(DoseEntry(
            substance: "Melatonin",
            amount: 500,
            unit: "µg",
            route: .sublingual,
            timestamp: t2,
            notes: nil,
            tags: []
        ))
        context.insert(DoseEntry(
            substance: "Magnesium Glycinate",
            amount: 400,
            unit: "mg",
            route: .oral,
            timestamp: t3,
            notes: "with dinner",
            tags: ["routine", "sleep"]
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

    @Test("SubstanceColor and DailyDoseItem survive export → import")
    func substanceColorAndDailyDoseItemRoundTrip() throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)

        let ts = Date(timeIntervalSince1970: 1_700_000_000)
        context.insert(DoseEntry(substance: "Ibuprofen", amount: 400, unit: "mg", route: .oral, timestamp: ts))

        context.insert(SubstanceColor(substance: "Ibuprofen", hexColor: "007AFF"))
        context.insert(SubstanceColor(substance: "Aspirin", hexColor: "FF3B30"))

        context.insert(DailyDoseItem(
            substance: "Vitamin D3",
            amount: 2000,
            unit: "IU",
            route: .oral,
            sortOrder: 0
        ))
        context.insert(DailyDoseItem(
            substance: "Omega-3",
            amount: 1000,
            unit: "mg",
            route: .oral,
            sortOrder: 1
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
        #expect(vitD.amount == 2000)
        #expect(vitD.unit == "IU")
        #expect(vitD.route == .oral)

        let omega = try #require(dailyItems.first { $0.substance == "Omega-3" })
        #expect(omega.sortOrder == 1)
    }

    // MARK: Tag preservation

    @Test("Tags from #hashtag-style notes round-trip correctly")
    func tagPreservation() throws {
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
            tags: ["excited", "grateful"]
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

    @Test("JSON with 'experiences' key routes to PsyLog import path")
    func psylogFormatDetection() throws {
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

    @Test("JSON without 'experiences' key routes to legacy import path")
    func legacyFormatDetection() throws {
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

    @Test("Empty context exports valid JSON that imports cleanly")
    func emptyExportRoundTrip() throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)

        let data = try DataExportImport.exportJSON(context: context)
        #expect(!data.isEmpty)

        let json = try #require(try? JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["experiences"] != nil)

        try DataExportImport.importJSON(data: data, context: context)

        let entries = try context.fetch(FetchDescriptor<DoseEntry>())
        #expect(entries.isEmpty)
    }

    // MARK: exportFilename format

    @Test("exportFilename has Piru prefix and ISO-ish timestamp")
    func exportFilenameStructure() {
        let filename = DataExportImport.exportFilename
        #expect(filename.hasPrefix("Piru "))

        let body = String(filename.dropFirst("Piru ".count))
        #expect(body.count == 17, "Expected yyyy-MM-ddTHHmmss (17 chars), got '\(body)'")

        let dashCount = body.filter { $0 == "-" }.count
        #expect(dashCount == 2)
        #expect(body.contains("T"))
    }
}
