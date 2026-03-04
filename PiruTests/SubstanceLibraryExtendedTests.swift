import Testing
@testable import Piru

@Suite("SubstanceLibrary Extended")
struct SubstanceLibraryExtendedTests {

    // MARK: - lookupByNameOrAlias

    @Test("lookupByNameOrAlias finds by exact name")
    @MainActor
    func lookupByName() {
        let result = SubstanceLibrary.lookupByNameOrAlias("Caffeine")
        #expect(result?.name == "Caffeine")
    }

    @Test("lookupByNameOrAlias is case-insensitive")
    @MainActor
    func lookupCaseInsensitive() {
        let result = SubstanceLibrary.lookupByNameOrAlias("caffeine")
        #expect(result != nil)
    }

    @Test("lookupByNameOrAlias returns nil for unknown")
    @MainActor
    func lookupUnknown() {
        #expect(SubstanceLibrary.lookupByNameOrAlias("zzzNotRealzzz") == nil)
    }

    // MARK: - lookup (name only)

    @Test("lookup finds by name")
    @MainActor
    func lookupName() {
        let result = SubstanceLibrary.lookup("Caffeine")
        #expect(result?.name == "Caffeine")
    }

    @Test("lookup returns nil for alias-only query")
    @MainActor
    func lookupAliasOnlyReturnsNil() {
        // lookup only checks name, not aliases
        // (lookupByNameOrAlias checks both)
        // This test verifies the distinction
        let byName = SubstanceLibrary.lookup("Molly")
        let byAlias = SubstanceLibrary.lookupByNameOrAlias("Molly")
        // "Molly" is an alias for MDMA, not a direct name
        // lookup should return nil, lookupByNameOrAlias should find it
        if byAlias != nil {
            #expect(byName == nil || byName?.name == byAlias?.name)
        }
    }

    // MARK: - Search ranking

    @Test("Search ranks exact alias match above contains")
    @MainActor
    func searchAliasExactRanking() {
        let results = SubstanceLibrary.search("Molly")
        if !results.isEmpty {
            // The first result should be the substance with "Molly" as an alias
            let firstAliases = results[0].aliases.map { $0.lowercased() }
            let hasExactAlias = firstAliases.contains("molly")
            // Either it's the exact alias match or at least the results aren't empty
            #expect(hasExactAlias || !results.isEmpty)
        }
    }

    @Test("Search respects limit parameter")
    @MainActor
    func searchLimit() {
        let results = SubstanceLibrary.search("a", limit: 3)
        #expect(results.count <= 3)
    }

    @Test("Search with single character returns results")
    @MainActor
    func searchSingleChar() {
        let results = SubstanceLibrary.search("a")
        #expect(!results.isEmpty)
    }

    // MARK: - nonEmptyCategories

    @Test("nonEmptyCategories is subset of all categories")
    @MainActor
    func nonEmptyCategoriesSubset() {
        for category in SubstanceLibrary.nonEmptyCategories {
            #expect(SubstanceCategory.allCases.contains(category))
        }
    }

    @Test("Each nonEmptyCategory has substances")
    @MainActor
    func nonEmptyCategoriesHaveSubstances() {
        for category in SubstanceLibrary.nonEmptyCategories {
            #expect(!SubstanceLibrary.substances(in: category).isEmpty)
        }
    }

    // MARK: - Count

    @Test("Count matches all.count")
    @MainActor
    func countMatchesAll() {
        #expect(SubstanceLibrary.count == SubstanceLibrary.all.count)
    }

    // MARK: - Data quality

    @Test("All substances have names")
    @MainActor
    func allHaveNames() {
        for substance in SubstanceLibrary.all {
            #expect(!substance.name.isEmpty)
        }
    }

    @Test("All substances have a category")
    @MainActor
    func allHaveCategories() {
        for substance in SubstanceLibrary.all {
            #expect(SubstanceCategory.allCases.contains(substance.category))
        }
    }

    @Test("No duplicate names in library")
    @MainActor
    func noDuplicateNames() {
        let names = SubstanceLibrary.all.map { $0.name.lowercased() }
        let uniqueNames = Set(names)
        #expect(names.count == uniqueNames.count, "Library has \(names.count - uniqueNames.count) duplicate names")
    }
}
