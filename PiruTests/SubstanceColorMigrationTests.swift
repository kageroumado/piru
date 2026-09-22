import Foundation
import SwiftData
import Testing
@testable import Piru

/// The store shape builds through 2.2 (52) left on disk: `SubstanceColor` as a
/// name and an sRGB hex, and the `UserColor` palette entity.
private enum Build52Schema {
    @Model
    final class SubstanceColor {
        @Attribute(.unique) var substance: String
        var hexColor: String

        init(substance: String, hexColor: String) {
            self.substance = substance
            self.hexColor = hexColor
        }
    }

    @Model
    final class UserColor {
        @Attribute(.unique) var hex: String
        var name: String
        var createdAt: Date

        init(hex: String, name: String) {
            self.hex = hex
            self.name = name
            createdAt = .now
        }
    }
}

@Suite("SubstanceColor migration", .serialized)
@MainActor
struct SubstanceColorMigrationTests {
    private func tmpStoreURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("piru-colors-\(UUID().uuidString).store")
    }

    private func seedBuild52Store(at url: URL) throws {
        try autoreleasepool {
            let container = try ModelContainer(
                for: Schema([DoseEntry.self, Build52Schema.SubstanceColor.self, Build52Schema.UserColor.self]),
                configurations: ModelConfiguration(url: url, cloudKitDatabase: .none),
            )
            let context = ModelContext(container)
            context.insert(DoseEntry(substance: "Caffeine", amount: 100))
            context.insert(Build52Schema.SubstanceColor(substance: "Caffeine", hexColor: "e08600"))
            context.insert(Build52Schema.SubstanceColor(substance: "LSD", hexColor: "8394ff"))
            context.insert(Build52Schema.UserColor(hex: "ABCDEF", name: "Mine"))
            try context.save()
        }
    }

    private func openCurrent(at url: URL) throws -> ModelContainer {
        try ModelContainer(
            for: Schema(StoreRecovery.models),
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none),
        )
    }

    @Test
    func `A build-52 store opens, and its colors read as legacy rows showing their old color`() throws {
        let url = tmpStoreURL()
        try seedBuild52Store(at: url)
        let container = try openCurrent(at: url)
        let context = ModelContext(container)

        #expect(try context.fetchCount(FetchDescriptor<DoseEntry>()) == 1)
        let rows = try context.fetch(FetchDescriptor<SubstanceColor>(sortBy: [SortDescriptor(\.substance)]))
        #expect(rows.map(\.substance) == ["Caffeine", "LSD"])
        let allLegacy = rows.allSatisfy(\.isLegacy)
        #expect(allLegacy)
        #expect(rows[0].tint == LegacyColorImport.p3(fromSRGBHex: "e08600"))
        #expect(SubstanceColorStore.legacyRowCount(in: context) == 2)
    }

    @Test
    func `Keeping turns every legacy row into a custom color of the same appearance`() throws {
        let url = tmpStoreURL()
        try seedBuild52Store(at: url)
        // Held for the test: a context that outlives its container traps.
        let container = try openCurrent(at: url)
        let context = container.mainContext
        SubstanceColorStore.resolveLegacyRows(adoptClassColors: false, in: context)

        let rows = try context.fetch(FetchDescriptor<SubstanceColor>(sortBy: [SortDescriptor(\.substance)]))
        let allCustom = rows.allSatisfy { !$0.isLegacy && !$0.usesDefault }
        #expect(allCustom)
        #expect(rows[0].tint == LegacyColorImport.p3(fromSRGBHex: "e08600"))
    }

    @Test
    func `Adopting moves every legacy row to its generated default`() async throws {
        await SubstanceStore.shared.ensureAllLoaded()
        let url = tmpStoreURL()
        try seedBuild52Store(at: url)
        // Held for the test: a context that outlives its container traps.
        let container = try openCurrent(at: url)
        let context = container.mainContext
        SubstanceColorStore.resolveLegacyRows(adoptClassColors: true, in: context)

        let rows = try context.fetch(FetchDescriptor<SubstanceColor>())
        for row in rows {
            #expect(!row.isLegacy && row.usesDefault)
            #expect(row.tint == SubstanceColorStore.defaultTint(for: row.substance))
        }
        // Class colors: caffeine lands in the stimulant hue family.
        let caffeine = try #require(rows.first { $0.substance == "Caffeine" })
        let hue = Oklch(displayP3: caffeine.tint).h
        #expect(abs(hue - SubstanceCategory.stimulant.oklchSeed.h) <= 10.5)
    }

    @Test
    func `The refresh pass leaves legacy and custom rows alone and updates stale defaults`() async throws {
        await SubstanceStore.shared.ensureAllLoaded()
        let url = tmpStoreURL()
        try seedBuild52Store(at: url)
        // Held for the test: a context that outlives its container traps.
        let container = try openCurrent(at: url)
        let context = container.mainContext
        context.insert(SubstanceColor(substance: "Ketamine", tint: .neutral, usesDefault: true))
        context.insert(SubstanceColor(substance: "MDMA", tint: .neutral, usesDefault: false))
        try context.save()

        SubstanceColorStore.refreshDefaults(in: context)

        let rows = try context.fetch(FetchDescriptor<SubstanceColor>())
        let byName = Dictionary(uniqueKeysWithValues: rows.map { ($0.substance, $0) })
        #expect(byName["Ketamine"]?.tint == SubstanceColorStore.defaultTint(for: "Ketamine"))
        #expect(byName["Ketamine"]?.tint != .neutral)
        #expect(byName["MDMA"]?.tint == .neutral)
        #expect(byName["Caffeine"]?.isLegacy == true)
    }

    @Test
    func `The mint pass gives a logged substance with no row its default`() async throws {
        let url = tmpStoreURL()
        try seedBuild52Store(at: url)
        let container = try openCurrent(at: url)
        let context = ModelContext(container)
        context.insert(DoseEntry(substance: "Modafinil", amount: 100))
        try context.save()

        let fresh = P3Color(red: 0.4, green: 0.5, blue: 0.6)
        await SubstanceColorStore.mintMissingRows(container: container) { _ in fresh }

        let rows = try ModelContext(container).fetch(FetchDescriptor<SubstanceColor>())
        let minted = try #require(rows.first { $0.substance == "Modafinil" })
        #expect(minted.usesDefault && minted.tint == fresh)
        #expect(rows.count == 3)
    }

    @Test
    func `A format-1 backup's hex colors import as custom colors of the same appearance`() throws {
        let container = try openCurrent(at: tmpStoreURL())
        let context = ModelContext(container)
        let file = #"{"piruExportVersion": 1, "substanceColors": [{"substance": "Caffeine", "hexColor": "e08600"}]}"#
        try DataExportImport.importJSON(data: Data(file.utf8), context: context)
        try context.save()

        let row = try #require(try context.fetch(FetchDescriptor<SubstanceColor>()).first)
        #expect(row.substance == "Caffeine")
        #expect(!row.isLegacy && !row.usesDefault)
        #expect(row.tint == LegacyColorImport.p3(fromSRGBHex: "e08600"))
    }
}
