import Testing
@testable import Piru

@Suite("DoseUnit")
struct DoseUnitTests {
    // MARK: - Same unit

    @Test
    func `Same unit returns amount unchanged`() {
        #expect(DoseUnit.convert(100, from: "mg", to: "mg") == 100)
        #expect(DoseUnit.convert(50, from: "g", to: "g") == 50)
        #expect(DoseUnit.convert(200, from: "µg", to: "µg") == 200)
    }

    // MARK: - mg conversions

    @Test
    func `mg to g`() {
        let result = DoseUnit.convert(1_000, from: "mg", to: "g")
        #expect(result == 1.0)
    }

    @Test
    func `mg to µg`() {
        let result = DoseUnit.convert(1, from: "mg", to: "µg")
        #expect(result == 1_000)
    }

    // MARK: - g conversions

    @Test
    func `g to mg`() {
        let result = DoseUnit.convert(1, from: "g", to: "mg")
        #expect(result == 1_000)
    }

    @Test
    func `g to µg`() {
        let result = DoseUnit.convert(1, from: "g", to: "µg")
        #expect(result == 1_000_000)
    }

    // MARK: - µg conversions

    @Test
    func `µg to mg`() {
        let result = DoseUnit.convert(500, from: "µg", to: "mg")
        #expect(result == 0.5)
    }

    @Test
    func `µg to g`() {
        let result = DoseUnit.convert(1_000_000, from: "µg", to: "g")
        #expect(result == 1.0)
    }

    // MARK: - Non-mass units

    @Test
    func `Non-mass from-unit returns nil`() {
        #expect(DoseUnit.convert(10, from: "mL", to: "mg") == nil)
    }

    @Test
    func `Non-mass to-unit returns nil`() {
        #expect(DoseUnit.convert(10, from: "mg", to: "IU") == nil)
    }

    @Test
    func `Both non-mass returns nil`() {
        #expect(DoseUnit.convert(10, from: "mL", to: "IU") == nil)
    }

    // MARK: - Edge cases

    @Test
    func `Zero amount`() {
        #expect(DoseUnit.convert(0, from: "mg", to: "g") == 0)
    }

    @Test
    func `Very small amount preserves precision`() {
        let result = DoseUnit.convert(0.001, from: "mg", to: "µg")
        #expect(result == 1.0)
    }
}
