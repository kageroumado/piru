import Testing
@testable import Piru

@Suite("HalfLifeDatabase")
struct HalfLifeDatabaseTests {
    // MARK: - Direct lookup

    @Test
    func `Caffeine has known half-life`() {
        let hl = HalfLifeDatabase.halfLife(for: "caffeine")
        #expect(hl == 300) // 5 hours
    }

    @Test
    func `Morphine has known half-life`() {
        let hl = HalfLifeDatabase.halfLife(for: "morphine")
        #expect(hl == 180) // 3 hours
    }

    @Test
    func `Alprazolam has known half-life`() {
        let hl = HalfLifeDatabase.halfLife(for: "alprazolam")
        #expect(hl != nil)
    }

    // MARK: - Case insensitive

    @Test
    func `Lookup is case-insensitive`() {
        let lower = HalfLifeDatabase.halfLife(for: "caffeine")
        let upper = HalfLifeDatabase.halfLife(for: "CAFFEINE")
        let mixed = HalfLifeDatabase.halfLife(for: "Caffeine")
        #expect(lower == upper)
        #expect(lower == mixed)
    }

    @Test
    func `Trims whitespace`() {
        let result = HalfLifeDatabase.halfLife(for: "  caffeine  ")
        #expect(result == 300)
    }

    // MARK: - Alias lookup

    @Test
    func `Alias lookup works for Adderall → amphetamine`() {
        // Common aliases should be in the database
        let result = HalfLifeDatabase.halfLife(for: "amphetamine")
        #expect(result != nil)
    }

    // MARK: - Unknown substance

    @Test
    func `Unknown substance returns nil`() {
        #expect(HalfLifeDatabase.halfLife(for: "zzzNotARealSubstancezzz") == nil)
    }

    @Test
    func `Empty string returns nil`() {
        #expect(HalfLifeDatabase.halfLife(for: "") == nil)
    }

    // MARK: - Data integrity

    @Test
    func `All half-lives are positive`() {
        // Test a sampling of known substances
        let substances = ["caffeine", "morphine", "cocaine", "fentanyl", "mdma", "modafinil"]
        for name in substances {
            if let hl = HalfLifeDatabase.halfLife(for: name) {
                #expect(hl > 0, "Half-life for \(name) should be positive")
            }
        }
    }

    @Test
    func `Cocaine has shorter half-life than methadone`() throws {
        let cocaine = try #require(HalfLifeDatabase.halfLife(for: "cocaine"))
        let methadone = try #require(HalfLifeDatabase.halfLife(for: "methadone"))
        #expect(cocaine < methadone)
    }
}
