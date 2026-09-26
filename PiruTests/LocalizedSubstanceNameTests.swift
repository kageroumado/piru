import Foundation
import Testing
@testable import Piru

@Suite("LocalizedSubstanceName")
struct LocalizedSubstanceNameTests {
    private let names: [String: [String: String]] = [
        "ketamine": ["es": "Ketamina", "zh-Hans": "氯胺酮", "zh-Hant": "愷他命"],
        "caffeine": ["es": "Cafeína"],
    ]

    @Test
    func `App localizations map to the table's language tags`() {
        #expect(LocalizedSubstanceName.language(for: "es") == "es")
        #expect(LocalizedSubstanceName.language(for: "es-419") == "es")
        #expect(LocalizedSubstanceName.language(for: "zh-Hans") == "zh-Hans")
        #expect(LocalizedSubstanceName.language(for: "zh-Hant") == "zh-Hant")
        #expect(LocalizedSubstanceName.language(for: "zh-HK") == "zh-Hant")
        #expect(LocalizedSubstanceName.language(for: "zh-TW") == "zh-Hant")
        #expect(LocalizedSubstanceName.language(for: "en") == nil)
        #expect(LocalizedSubstanceName.language(for: "Base") == nil)
    }

    @Test
    func `Each language gets its own name`() {
        #expect(LocalizedSubstanceName.resolve(canonicalName: "Ketamine", language: "es", in: names) == "Ketamina")
        #expect(LocalizedSubstanceName.resolve(canonicalName: "Ketamine", language: "zh-Hans", in: names) == "氯胺酮")
        #expect(LocalizedSubstanceName.resolve(canonicalName: "Ketamine", language: "zh-Hant", in: names) == "愷他命")
    }

    @Test
    func `English and missing languages keep the canonical name`() {
        #expect(LocalizedSubstanceName.resolve(canonicalName: "Ketamine", language: nil, in: names) == nil)
        #expect(LocalizedSubstanceName.resolve(canonicalName: "Caffeine", language: "zh-Hans", in: names) == nil)
        #expect(LocalizedSubstanceName.resolve(canonicalName: "2C-B", language: "es", in: names) == nil)
    }

    @Test
    func `Lookup is case-insensitive on the canonical name`() {
        #expect(LocalizedSubstanceName.resolve(canonicalName: "KETAMINE", language: "es", in: names) == "Ketamina")
    }

    @Test
    func `An English app language never shows a localized name`() {
        // The test host runs in English, so the installed table is never consulted.
        #expect(LocalizedSubstanceName.appLanguage == nil)
        #expect(!LocalizedSubstanceName.isAvailable)
        #expect(LocalizedSubstanceName.resolve(canonicalName: "Ketamine") == nil)
    }
}
