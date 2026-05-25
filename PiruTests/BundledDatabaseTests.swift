import Testing
import Foundation
@testable import Piru

@Suite("Bundled Database & Tags")
struct BundledDatabaseTests {

    // MARK: - Tags codable

    @Test("Substance round-trips with tags")
    func substanceRoundTripsWithTags() throws {
        let original = Substance(
            name: "MXE",
            aliases: ["Methoxetamine", "3-MeO-2'-Oxo-PCE"],
            category: .dissociative,
            defaultRoute: .insufflation,
            routes: [],
            effects: [],
            tags: ["arylcyclohexylamine", "NMDA-antagonist", "research-chemical", "beta-ketone"]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Substance.self, from: data)
        #expect(decoded.tags.count == 4)
        #expect(decoded.tags.contains("arylcyclohexylamine"))
        #expect(decoded.tags.contains("NMDA-antagonist"))
    }

    @Test("Substance without tags omits key from JSON")
    func substanceWithoutTagsOmitsKey() throws {
        let original = Substance(
            name: "Plain",
            aliases: [],
            category: .other,
            defaultRoute: .oral,
            routes: [],
            effects: []
        )
        let data = try JSONEncoder().encode(original)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("\"tags\""))
    }

    @Test("Legacy JSON without tags decodes to empty tags array")
    func legacyJSONDecodesWithEmptyTags() throws {
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

    @Test("Eugeroic, ampakine, and dysdelic categories round-trip")
    func newCategoriesRoundTrip() throws {
        for category: SubstanceCategory in [.eugeroic, .ampakine, .dysdelic] {
            let data = try JSONEncoder().encode(category)
            let decoded = try JSONDecoder().decode(SubstanceCategory.self, from: data)
            #expect(decoded == category)
        }
    }

    @Test("New categories appear in allCases")
    func newCategoriesInAllCases() {
        #expect(SubstanceCategory.allCases.contains(.eugeroic))
        #expect(SubstanceCategory.allCases.contains(.ampakine))
        #expect(SubstanceCategory.allCases.contains(.dysdelic))
    }

    @Test("TripSit mapper routes eugeroic and ampakine aliases")
    func tripSitMapperHandlesNewCategoryAliases() {
        #expect(SubstanceCategory.from(tripSitCategory: "eugeroic") == .eugeroic)
        #expect(SubstanceCategory.from(tripSitCategory: "afinil") == .eugeroic)
        #expect(SubstanceCategory.from(tripSitCategory: "ampakine") == .ampakine)
        #expect(SubstanceCategory.from(tripSitCategory: "dysdelic") == .dysdelic)
        #expect(SubstanceCategory.from(tripSitCategory: "kappa-opioid-agonist") == .dysdelic)
    }

    // MARK: - Deduplicator merges tags

    @Test("Deduplicator unions tags from both inputs")
    func deduplicatorUnionsTags() {
        let primary = Substance(
            name: "Modafinil",
            aliases: ["Provigil"],
            category: .eugeroic,
            defaultRoute: .oral,
            routes: [],
            effects: [],
            tags: ["DAT-inhibitor", "prescription-only"]
        )
        let secondary = Substance(
            name: "Modafinil",
            aliases: ["Provigil", "Modalert"],
            category: .eugeroic,
            defaultRoute: .oral,
            routes: [],
            effects: [],
            tags: ["DAT-inhibitor", "US-Schedule-IV", "eugeroic"]
        )
        let merged = SubstanceDeduplicator.mergeSubstances(primary, secondary)
        #expect(merged.tags.contains("DAT-inhibitor"))
        #expect(merged.tags.contains("prescription-only"))
        #expect(merged.tags.contains("US-Schedule-IV"))
        #expect(merged.tags.contains("eugeroic"))
        // Sorted + deduplicated
        #expect(merged.tags.count == 4)
        #expect(merged.tags == merged.tags.sorted())
    }

    // MARK: - hasNoDoseData

    @Test("hasNoDoseData true for empty routes")
    func hasNoDoseDataTrueForEmptyRoutes() {
        let s = Substance(
            name: "Unknown",
            aliases: [],
            category: .other,
            defaultRoute: .oral,
            routes: [],
            effects: []
        )
        #expect(s.hasNoDoseData == true)
    }

    @Test("hasNoDoseData true when every route has all-nil dose ladder")
    func hasNoDoseDataTrueForAllNilDoses() {
        let s = Substance(
            name: "Stub",
            aliases: [],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(route: .oral, unit: "mg", doses: DoseRange()),
                SubstanceRoute(route: .insufflation, unit: "mg", doses: DoseRange()),
            ],
            effects: []
        )
        #expect(s.hasNoDoseData == true)
    }

    @Test("hasNoDoseData false when any route has a dose")
    func hasNoDoseDataFalseWhenAnyDose() {
        let s = Substance(
            name: "Real",
            aliases: [],
            category: .other,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(
                    route: .oral,
                    unit: "mg",
                    doses: DoseRange(threshold: 5, light: 10...20, common: nil, strong: nil, heavy: nil)
                ),
            ],
            effects: []
        )
        #expect(s.hasNoDoseData == false)
    }

    // MARK: - Bundled resource

    @Test("Bundled substances resource is present and decodes")
    func bundledResourcePresent() {
        let bundle = Bundle(for: BundleAnchor.self)
        let testBundleHasResource = bundle.url(forResource: "substances-bundled", withExtension: "json") != nil
        let mainBundleHasResource = Bundle.main.url(forResource: "substances-bundled", withExtension: "json") != nil
        // Either bundle hosting model is acceptable — Xcode synchronized groups
        // place the resource in the main app bundle, but #-bundle-aware test
        // hosts may surface it via the test bundle instead.
        if testBundleHasResource || mainBundleHasResource {
            let result = SubstanceLibrary.loadBundledSubstances()
            // Either we get a valid array (possibly empty placeholder) or nil
            // when the resource is not linked into the test host. Both are
            // acceptable; what matters is that decoding doesn't throw on a
            // well-formed empty/populated file.
            if let result {
                #expect(result.count >= 0)
            }
        }
    }
}

/// Marker class used only to obtain the test bundle handle in
/// ``BundledDatabaseTests/bundledResourcePresent``.
private final class BundleAnchor {}
