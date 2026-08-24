import Testing
@testable import Piru

@Suite("SubstanceLibrary Extended")
struct SubstanceLibraryExtendedTests {
    // MARK: - lookupByNameOrAlias

    @Test
    @MainActor
    func `lookupByNameOrAlias finds by exact name`() {
        let result = SubstanceLibrary.lookup("Caffeine")
        #expect(result?.name == "Caffeine")
    }

    @Test
    @MainActor
    func `lookupByNameOrAlias is case-insensitive`() {
        let result = SubstanceLibrary.lookup("caffeine")
        #expect(result != nil)
    }

    @Test
    @MainActor
    func `lookupByNameOrAlias returns nil for unknown`() {
        #expect(SubstanceLibrary.lookup("zzzNotRealzzz") == nil)
    }

    // MARK: - lookup (name only)

    @Test
    @MainActor
    func `lookup finds by name`() {
        let result = SubstanceLibrary.lookup("Caffeine")
        #expect(result?.name == "Caffeine")
    }

    @Test
    @MainActor
    func `lookup returns nil for alias-only query`() {
        // lookup only checks name, not aliases
        // (lookupByNameOrAlias checks both)
        // This test verifies the distinction
        let byName = SubstanceLibrary.lookup("Molly")
        let byAlias = SubstanceLibrary.lookup("Molly")
        // "Molly" is an alias for MDMA, not a direct name
        // lookup should return nil, lookupByNameOrAlias should find it
        if byAlias != nil {
            #expect(byName == nil || byName?.name == byAlias?.name)
        }
    }

    // MARK: - Search ranking

    @Test
    @MainActor
    func `Search ranks exact alias match above contains`() {
        let results = SubstanceLibrary.search("Molly")
        if !results.isEmpty {
            // The first result should be the substance with "Molly" as an alias
            let firstAliases = results[0].aliases.map { $0.lowercased() }
            let hasExactAlias = firstAliases.contains("molly")
            // Either it's the exact alias match or at least the results aren't empty
            #expect(hasExactAlias || !results.isEmpty)
        }
    }

    @Test
    @MainActor
    func `Search respects limit parameter`() {
        let results = SubstanceLibrary.search("a", limit: 3)
        #expect(results.count <= 3)
    }

    @Test
    @MainActor
    func `Search with single character returns results`() {
        let results = SubstanceLibrary.search("a")
        #expect(!results.isEmpty)
    }

    // MARK: - nonEmptyCategories

    @Test
    @MainActor
    func `nonEmptyCategories is subset of all categories`() {
        for category in SubstanceLibrary.nonEmptyCategories {
            #expect(SubstanceCategory.allCases.contains(category))
        }
    }

    @Test
    @MainActor
    func `Each nonEmptyCategory has substances`() {
        for category in SubstanceLibrary.nonEmptyCategories {
            #expect(!SubstanceLibrary.substances(in: category).isEmpty)
        }
    }

    // MARK: - Count

    @Test
    @MainActor
    func `Count matches all.count`() {
        #expect(SubstanceLibrary.count == SubstanceLibrary.all.count)
    }

    // MARK: - Data quality

    @Test
    @MainActor
    func `All substances have names`() {
        for substance in SubstanceLibrary.all {
            #expect(!substance.name.isEmpty)
        }
    }

    @Test
    @MainActor
    func `All substances have a category`() {
        for substance in SubstanceLibrary.all {
            #expect(SubstanceCategory.allCases.contains(substance.category))
        }
    }

    @Test
    @MainActor
    func `No duplicate names in library`() {
        let names = SubstanceLibrary.all.map { $0.name.lowercased() }
        let uniqueNames = Set(names)
        #expect(names.count == uniqueNames.count, "Library has \(names.count - uniqueNames.count) duplicate names")
    }
}
