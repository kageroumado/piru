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
        func tag(_ localization: String) -> String? {
            LocalizedSubstanceName.language(for: ContentLanguage(localization: localization))
        }
        #expect(tag("es") == "es")
        #expect(tag("es-419") == "es")
        #expect(tag("zh-Hans") == "zh-Hans")
        #expect(tag("zh-Hant") == "zh-Hant")
        #expect(tag("zh-HK") == "zh-Hant")
        #expect(tag("zh-TW") == "zh-Hant")
        #expect(tag("en") == nil)
        #expect(tag("Base") == nil)
    }

    @Test
    func `Spanish resolves substance text as English`() {
        #expect(!ContentLanguage.es.isChinese)
        #expect(ContentLanguage.es.clauses(column: "language") == ContentLanguage.en.clauses(column: "language"))
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

    @Test
    func `Localized names are searchable in English but never listed as aliases`() async throws {
        await SubstanceStore.shared.ensureAllLoaded()
        let hit = try #require(SubstanceLibrary.searchMatches("Ketamina", limit: 5).first)
        #expect(hit.substance.name == "Ketamine")
        #expect(hit.matchedAlias == "Ketamina")
        let amitriptyline = try #require(SubstanceLibrary.lookup("Amitriptyline"))
        #expect(!amitriptyline.aliases.contains("Amitriptilina"))
        #expect(amitriptyline.displaySubtitle?.contains("Amitriptilina") != true)
    }
}
