import Testing
@testable import Piru

@Suite("SubstanceLibrary")
struct SubstanceLibraryTests {

    // MARK: - Library data

    @Test("Library is not empty")
    func libraryNotEmpty() {
        #expect(!SubstanceLibrary.all.isEmpty)
    }

    @Test("Library has substances in multiple categories")
    func multipleCategories() {
        let categories = Set(SubstanceLibrary.all.map(\.category))
        #expect(categories.count > 5)
    }

    // MARK: - search()

    @Test("Empty query returns empty")
    func searchEmpty() {
        #expect(SubstanceLibrary.search("").isEmpty)
    }

    @Test("Exact name match appears first")
    func searchExactNameFirst() {
        let results = SubstanceLibrary.search("Caffeine")
        #expect(!results.isEmpty)
        #expect(results[0].name == "Caffeine")
    }

    @Test("Search is case-insensitive")
    func searchCaseInsensitive() {
        let lower = SubstanceLibrary.search("caffeine")
        let upper = SubstanceLibrary.search("CAFFEINE")
        #expect(!lower.isEmpty)
        #expect(!upper.isEmpty)
        #expect(lower[0].name == upper[0].name)
    }

    @Test("Prefix matches appear before contains matches")
    func searchPrefixBeforeContains() {
        // "Amphetamine" should prefix-match before something that merely contains "amphetamine"
        let results = SubstanceLibrary.search("Amphetamine")
        #expect(!results.isEmpty)
        #expect(results[0].name == "Amphetamine")
    }

    @Test("Search finds substances by alias")
    func searchByAlias() {
        // MDMA has common aliases
        let results = SubstanceLibrary.search("Molly")
        #expect(!results.isEmpty)
    }

    @Test("No results for nonsense query")
    func searchNoResults() {
        #expect(SubstanceLibrary.search("zzznotasubstancezzz").isEmpty)
    }

    // MARK: - substances(in:)

    @Test("Substances in category returns only that category")
    func substancesInCategory() {
        let stimulants = SubstanceLibrary.substances(in: .stimulant)
        #expect(!stimulants.isEmpty)
        for substance in stimulants {
            #expect(substance.category == .stimulant)
        }
    }

    // MARK: - byCategory

    @Test("By category groups correctly")
    func byCategoryGroups() {
        let grouped = SubstanceLibrary.byCategory
        #expect(!grouped.isEmpty)

        for (category, substances) in grouped {
            for substance in substances {
                #expect(substance.category == category)
            }
        }
    }

    @Test("By category covers all substances")
    func byCategoryCoversAll() {
        let grouped = SubstanceLibrary.byCategory
        let totalGrouped = grouped.values.reduce(0) { $0 + $1.count }
        #expect(totalGrouped == SubstanceLibrary.all.count)
    }
}
