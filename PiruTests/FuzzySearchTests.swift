import Foundation
import Testing
@testable import Piru

@Suite("Fuzzy Search")
struct FuzzySearchTests {
    // MARK: - Levenshtein Distance (tested via search behavior)

    @Test
    func `Fuzzy matches single-character typo`() {
        // "Sertrline" (missing 'a') should fuzzy-match "Sertraline"
        let results = SubstanceLibrary.search("sertrline")
        let hasSertraline = results.contains { $0.name.lowercased() == "sertraline" }
        #expect(hasSertraline, "Expected fuzzy match for 'sertrline' -> 'Sertraline'")
    }

    @Test
    func `Fuzzy matches transposed characters`() {
        // "Caffiene" (i/e transposed) should fuzzy-match "Caffeine"
        let results = SubstanceLibrary.search("caffiene")
        let hasCaffeine = results.contains { $0.name.lowercased() == "caffeine" }
        #expect(hasCaffeine, "Expected fuzzy match for 'caffiene' -> 'Caffeine'")
    }

    @Test
    func `Short queries only use exact/prefix/contains, not fuzzy`() {
        // "qqq" is 3 chars and doesn't substring-match any substance name
        // It should NOT fuzzy match because fuzzy requires >= 4 chars
        let results = SubstanceLibrary.search("qqq")
        #expect(results.isEmpty)
    }

    @Test
    func `Exact match still preferred over fuzzy`() {
        let results = SubstanceLibrary.search("caffeine")
        guard let first = results.first else {
            #expect(Bool(false), "Expected at least one result for 'caffeine'")
            return
        }
        #expect(first.name.lowercased() == "caffeine")
    }

    @Test
    func `Fuzzy does not match completely unrelated substances`() {
        let results = SubstanceLibrary.search("xyzzyplugh")
        #expect(results.isEmpty, "Completely unrelated query should match nothing")
    }

    // MARK: - Deterministic tier order

    @Test
    func `Ranked search orders each tier by length then name`() {
        let names = ["methylphenidate", "methadone", "meth", "methamphetamine", "dimethyltryptamine", "trimethoprim", "methylone"]
        var nameIndex: [String: Int64] = [:]
        var byID: [Int64: Substance] = [:]
        for (offset, name) in names.enumerated() {
            let id = Int64(offset)
            nameIndex[name] = id
            byID[id] = Substance(name: name, aliases: [], category: .stimulant, defaultRoute: .oral, routes: [], effects: [])
        }
        let ranked = SubstanceStore.rankedSearch(
            "meth", nameIndex: nameIndex, aliasIndex: [:], aliasDisplayIndex: [:],
            idToSubstance: byID, limit: 50,
        ).map(\.substance.name)
        #expect(ranked == [
            "meth", "methadone", "methylone", "methamphetamine", "methylphenidate",
            "trimethoprim", "dimethyltryptamine",
        ])
    }
}
