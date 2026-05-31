import Testing
@testable import Piru

@Suite("SubstanceLibrary")
struct SubstanceLibraryTests {
    // MARK: - Library data

    @Test
    func `Library is not empty`() {
        #expect(!SubstanceLibrary.all.isEmpty)
    }

    @Test
    func `Library has substances in multiple categories`() {
        let categories = Set(SubstanceLibrary.all.map(\.category))
        #expect(categories.count > 5)
    }

    // MARK: - search()

    @Test
    func `Empty query returns empty`() {
        #expect(SubstanceLibrary.search("").isEmpty)
    }

    @Test
    func `Exact name match appears first`() {
        let results = SubstanceLibrary.search("Caffeine")
        #expect(!results.isEmpty)
        #expect(results[0].name == "Caffeine")
    }

    @Test
    func `Search is case-insensitive`() {
        let lower = SubstanceLibrary.search("caffeine")
        let upper = SubstanceLibrary.search("CAFFEINE")
        #expect(!lower.isEmpty)
        #expect(!upper.isEmpty)
        #expect(lower[0].name == upper[0].name)
    }

    @Test
    func `Prefix matches appear before contains matches`() {
        // "Amphetamine" should prefix-match before something that merely contains "amphetamine"
        let results = SubstanceLibrary.search("Amphetamine")
        #expect(!results.isEmpty)
        #expect(results[0].name == "Amphetamine")
    }

    @Test
    func `Search finds substances by alias`() {
        // MDMA has common aliases
        let results = SubstanceLibrary.search("Molly")
        #expect(!results.isEmpty)
    }

    @Test
    func `No results for nonsense query`() {
        #expect(SubstanceLibrary.search("zzznotasubstancezzz").isEmpty)
    }

    // MARK: - substances(in:)

    @Test
    func `Substances in category returns only that category`() {
        let stimulants = SubstanceLibrary.substances(in: .stimulant)
        #expect(!stimulants.isEmpty)
        for substance in stimulants {
            #expect(substance.category == .stimulant)
        }
    }

    // MARK: - byCategory

    @Test
    func `Each non-empty category is populated by substances(in:)`() {
        for category in SubstanceLibrary.nonEmptyCategories {
            let substances = SubstanceLibrary.substances(in: category)
            #expect(!substances.isEmpty)
            for substance in substances {
                #expect(substance.category == category)
            }
        }
    }

    @Test
    func `Non-empty categories partition every browsable substance exactly once`() {
        // Category browse only surfaces browsable substances — `.nonRecreational`
        // compounds (antibiotics, …) stay searchable for medication tracking but
        // are hidden from browse (see `substances(in:)` / `nonEmptyCategories`,
        // both filtered by `displayClass.surfacesInBrowse`). So the grouped sum
        // must equal the browsable count, NOT `all.count` (which also includes
        // the hidden non-recreational substances).
        let browsableCount = SubstanceLibrary.all
            .count(where: { $0.displayClass.surfacesInBrowse })
            
        let totalGrouped = SubstanceLibrary.nonEmptyCategories
            .reduce(0) { $0 + SubstanceLibrary.substances(in: $1).count }
        #expect(totalGrouped == browsableCount)
        // Everything left out of browse is exactly the non-browsable set.
        #expect(
            SubstanceLibrary.all.count - totalGrouped
                == SubstanceLibrary.all.count(where: { !$0.displayClass.surfacesInBrowse }),
        )
    }

    // MARK: - Search ranking edge cases

    @Test
    func `Search for 'lsd' finds LSD as first hit`() {
        let results = SubstanceLibrary.search("LSD", limit: 5)
        #expect(!results.isEmpty)
        #expect(results.first?.name.uppercased().contains("LSD") == true)
    }

    @Test
    func `Search is case-insensitive both ways`() {
        let upper = SubstanceLibrary.search("KETAMINE")
        let lower = SubstanceLibrary.search("ketamine")
        let mixed = SubstanceLibrary.search("Ketamine")
        #expect(!upper.isEmpty)
        #expect(upper.first?.name == lower.first?.name)
        #expect(upper.first?.name == mixed.first?.name)
    }

    @Test
    func `Fuzzy match only kicks in for queries ≥ 4 chars`() {
        // 3-char nonsense query should NOT return anything via fuzzy match.
        // (Exact/alias misses too, so the result should be empty.)
        let tooShort = SubstanceLibrary.search("zzx")
        #expect(
            tooShort.isEmpty,
            "Queries under 4 chars must not trigger fuzzy match — got \(tooShort.map(\.name))",
        )
    }

    @Test
    func `Limit parameter bounds result count`() {
        let unbounded = SubstanceLibrary.search("a", limit: 1_000)
        let bounded = SubstanceLibrary.search("a", limit: 3)
        #expect(bounded.count <= 3)
        #expect(unbounded.count >= bounded.count)
    }
}
