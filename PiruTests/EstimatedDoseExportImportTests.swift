import Foundation
import SwiftData
import Testing
@testable import Piru

/// An in-memory container on the one canonical schema, which every test
/// container shares so SwiftData keeps a single cached model.
private func makeTestContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    return try ModelContainer(for: Schema(PiruSchema.models), configurations: config)
}

@Suite("DataExportImport — estimated doses")
@MainActor
struct EstimatedDoseExportImportTests {
    private static let start: Int64 = 1_750_000_000_000

    /// PsychonautWiki's own shape: the estimate flag, with and without a
    /// standard deviation.
    private static let pwFile = Data("""
    {
      "exportSource": "iOS Journal 15.0", "substanceCompanions": [], "customUnits": [],
      "experiences": [
        { "title": "Eyeballed", "text": "", "creationDate": \(start), "sortDate": \(start),
          "ingestions": [
            { "substanceName": "Ketamine", "dose": 10, "time": \(start), "administrationRoute": "INSUFFLATED", "units": "mg", "notes": "",
              "isDoseAnEstimate": true, "estimatedDoseStandardDeviation": 1 },
            { "substanceName": "MDMA", "dose": 100, "time": \(start + 60000), "administrationRoute": "ORAL", "units": "mg", "notes": "",
              "isDoseAnEstimate": true, "estimatedDoseStandardDeviation": null },
            { "substanceName": "Caffeine", "dose": 80, "time": \(start + 120_000), "administrationRoute": "ORAL", "units": "mg", "notes": "",
              "isDoseAnEstimate": false, "estimatedDoseStandardDeviation": null }
          ] }
      ]
    }
    """.utf8)

    @Test
    func `A PW estimate imports with its standard deviation`() throws {
        let context = try ModelContext(makeTestContainer())
        try DataExportImport.importJSON(data: Self.pwFile, context: context)

        let entries = try context.fetch(FetchDescriptor<DoseEntry>())
        let ketamine = try #require(entries.first { $0.substance == "Ketamine" })
        #expect(ketamine.isApproximate)
        #expect(ketamine.amountDeviation == 1)
        let mdma = try #require(entries.first { $0.substance == "MDMA" })
        #expect(mdma.isApproximate)
        #expect(mdma.amountDeviation == nil)
        let caffeine = try #require(entries.first { $0.substance == "Caffeine" })
        #expect(!caffeine.isApproximate)
        #expect(caffeine.amountDeviation == nil)
    }

    @Test
    func `An estimate exports to PW under its own keys and comes back`() throws {
        let source = try ModelContext(makeTestContainer())
        source.insert(DoseEntry(
            substance: "Ketamine", amount: 10, unit: "mg", route: .insufflation, timestamp: Date(ms: Self.start), amountDeviation: 1.5,
        ))
        source.insert(DoseEntry(substance: "Caffeine", amount: 80, unit: "mg", route: .oral, timestamp: Date(ms: Self.start + 60000)))
        try source.save()

        let data = try DataExportImport.exportJSON(format: .psyLog, context: source)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let ingestions = try #require((json["experiences"] as? [[String: Any]])?.flatMap { $0["ingestions"] as? [[String: Any]] ?? [] })
        let ketamine = try #require(ingestions.first { $0["substanceName"] as? String == "Ketamine" })
        #expect(ketamine["isDoseAnEstimate"] as? Bool == true)
        #expect(ketamine["estimatedDoseStandardDeviation"] as? Double == 1.5)
        let caffeine = try #require(ingestions.first { $0["substanceName"] as? String == "Caffeine" })
        #expect(caffeine["isDoseAnEstimate"] as? Bool == false)
        #expect(caffeine["estimatedDoseStandardDeviation"] is NSNull)

        let target = try ModelContext(makeTestContainer())
        try DataExportImport.importJSON(data: data, context: target)
        let entry = try #require(try target.fetch(FetchDescriptor<DoseEntry>()).first { $0.substance == "Ketamine" })
        #expect(entry.isApproximate)
        #expect(entry.amountDeviation == 1.5)
    }
}
