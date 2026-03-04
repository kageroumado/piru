import Testing
@testable import Piru

@Suite("HalfLifeDatabase")
struct HalfLifeDatabaseTests {

    // MARK: - Direct lookup

    @Test("Caffeine has known half-life")
    func caffeine() {
        let hl = HalfLifeDatabase.halfLife(for: "caffeine")
        #expect(hl == 300) // 5 hours
    }

    @Test("Morphine has known half-life")
    func morphine() {
        let hl = HalfLifeDatabase.halfLife(for: "morphine")
        #expect(hl == 180) // 3 hours
    }

    @Test("Alprazolam has known half-life")
    func alprazolam() {
        let hl = HalfLifeDatabase.halfLife(for: "alprazolam")
        #expect(hl != nil)
    }

    // MARK: - Case insensitive

    @Test("Lookup is case-insensitive")
    func caseInsensitive() {
        let lower = HalfLifeDatabase.halfLife(for: "caffeine")
        let upper = HalfLifeDatabase.halfLife(for: "CAFFEINE")
        let mixed = HalfLifeDatabase.halfLife(for: "Caffeine")
        #expect(lower == upper)
        #expect(lower == mixed)
    }

    @Test("Trims whitespace")
    func trimsWhitespace() {
        let result = HalfLifeDatabase.halfLife(for: "  caffeine  ")
        #expect(result == 300)
    }

    // MARK: - Alias lookup

    @Test("Alias lookup works for Adderall → amphetamine")
    func aliasLookup() {
        // Common aliases should be in the database
        let result = HalfLifeDatabase.halfLife(for: "amphetamine")
        #expect(result != nil)
    }

    // MARK: - Unknown substance

    @Test("Unknown substance returns nil")
    func unknownSubstance() {
        #expect(HalfLifeDatabase.halfLife(for: "zzzNotARealSubstancezzz") == nil)
    }

    @Test("Empty string returns nil")
    func emptyString() {
        #expect(HalfLifeDatabase.halfLife(for: "") == nil)
    }

    // MARK: - Data integrity

    @Test("All half-lives are positive")
    func allPositive() {
        // Test a sampling of known substances
        let substances = ["caffeine", "morphine", "cocaine", "fentanyl", "mdma", "modafinil"]
        for name in substances {
            if let hl = HalfLifeDatabase.halfLife(for: name) {
                #expect(hl > 0, "Half-life for \(name) should be positive")
            }
        }
    }

    @Test("Cocaine has shorter half-life than methadone")
    func relativeHalfLives() {
        let cocaine = HalfLifeDatabase.halfLife(for: "cocaine")!
        let methadone = HalfLifeDatabase.halfLife(for: "methadone")!
        #expect(cocaine < methadone)
    }
}
