import Foundation
import Testing
@testable import Piru

@Suite("Bundled Database & Tags")
struct BundledDatabaseTests {
    // MARK: - Tags codable

    @Test
    func `Substance round-trips with tags`() throws {
        let original = Substance(
            name: "MXE",
            aliases: ["Methoxetamine", "3-MeO-2'-Oxo-PCE"],
            category: .dissociative,
            defaultRoute: .insufflation,
            routes: [],
            effects: [],
            tags: ["arylcyclohexylamine", "NMDA-antagonist", "research-chemical", "beta-ketone"],
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Substance.self, from: data)
        #expect(decoded.tags.count == 4)
        #expect(decoded.tags.contains("arylcyclohexylamine"))
        #expect(decoded.tags.contains("NMDA-antagonist"))
    }

    @Test
    func `Substance without tags omits key from JSON`() throws {
        let original = Substance(
            name: "Plain",
            aliases: [],
            category: .other,
            defaultRoute: .oral,
            routes: [],
            effects: [],
        )
        let data = try JSONEncoder().encode(original)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("\"tags\""))
    }

    @Test
    func `Legacy JSON without tags decodes to empty tags array`() throws {
        let legacy = #"""
        {
            "name": "LegacyDrug",
            "aliases": ["old", "vintage"],
            "category": "Stimulant",
            "defaultRoute": "oral",
            "routes": [],
            "effects": ["energetic"]
        }
        """#
        let data = try #require(legacy.data(using: .utf8))
        let decoded = try JSONDecoder().decode(Substance.self, from: data)
        #expect(decoded.tags.isEmpty)
        #expect(decoded.name == "LegacyDrug")
    }

    // MARK: - New category cases

    @Test
    func `Eugeroic, ampakine, and dysdelic categories round-trip`() throws {
        for category: SubstanceCategory in [.eugeroic, .ampakine, .dysdelic] {
            let data = try JSONEncoder().encode(category)
            let decoded = try JSONDecoder().decode(SubstanceCategory.self, from: data)
            #expect(decoded == category)
        }
    }

    @Test
    func `New categories appear in allCases`() {
        #expect(SubstanceCategory.allCases.contains(.eugeroic))
        #expect(SubstanceCategory.allCases.contains(.ampakine))
        #expect(SubstanceCategory.allCases.contains(.dysdelic))
    }

    @Test
    func `TripSit mapper routes eugeroic and ampakine aliases`() {
        #expect(SubstanceCategory.from(tripSitCategory: "eugeroic") == .eugeroic)
        #expect(SubstanceCategory.from(tripSitCategory: "afinil") == .eugeroic)
        #expect(SubstanceCategory.from(tripSitCategory: "ampakine") == .ampakine)
        #expect(SubstanceCategory.from(tripSitCategory: "dysdelic") == .dysdelic)
        #expect(SubstanceCategory.from(tripSitCategory: "kappa-opioid-agonist") == .dysdelic)
    }

    // MARK: - hasNoDoseData

    @Test
    func `hasNoDoseData true for empty routes`() {
        let s = Substance(
            name: "Unknown",
            aliases: [],
            category: .other,
            defaultRoute: .oral,
            routes: [],
            effects: [],
        )
        #expect(s.hasNoDoseData == true)
    }

    @Test
    func `hasNoDoseData true when every route has all-nil dose ladder`() {
        let s = Substance(
            name: "Stub",
            aliases: [],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange()),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange()),
            ],
            effects: [],
        )
        #expect(s.hasNoDoseData == true)
    }

    @Test
    func `hasNoDoseData false when any route has a dose`() {
        let s = Substance(
            name: "Real",
            aliases: [],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(
                    route: .oral,
                    unit: "mg",
                    doses: DoseRange(threshold: 5, light: 10 ... 20, common: nil, strong: nil, heavy: nil),
                ),
            ],
            effects: [],
        )
        #expect(s.hasNoDoseData == false)
    }

    // MARK: - Bundled resource

    @Test
    @MainActor
    func `Bundled SQLite database opens and contains substances`() {
        // Touch the shared store; will fatalError if the bundled .sqlite is
        // missing from the app bundle.
        let count = SubstanceStore.shared.count
        #expect(count > 0)
    }

    @Test
    @MainActor
    func `Source priority resolution returns at least the seeded defaults`() {
        let order = SubstanceStore.shared.enabledSourceOrder
        #expect(!order.isEmpty)
        // Curated should be highest-priority out of the box.
        #expect(order.first == "piru-curated")
    }
}

/// Marker class used only to obtain the test bundle handle in
/// ``BundledDatabaseTests/bundledResourcePresent``.
private final class BundleAnchor {}
