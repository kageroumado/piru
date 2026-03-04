import Testing
@testable import Piru

@Suite("DoseUnit")
struct DoseUnitTests {

    // MARK: - Same unit

    @Test("Same unit returns amount unchanged")
    func sameUnit() {
        #expect(DoseUnit.convert(100, from: "mg", to: "mg") == 100)
        #expect(DoseUnit.convert(50, from: "g", to: "g") == 50)
        #expect(DoseUnit.convert(200, from: "µg", to: "µg") == 200)
    }

    // MARK: - mg conversions

    @Test("mg to g")
    func mgToG() {
        let result = DoseUnit.convert(1000, from: "mg", to: "g")
        #expect(result == 1.0)
    }

    @Test("mg to µg")
    func mgToUg() {
        let result = DoseUnit.convert(1, from: "mg", to: "µg")
        #expect(result == 1000)
    }

    // MARK: - g conversions

    @Test("g to mg")
    func gToMg() {
        let result = DoseUnit.convert(1, from: "g", to: "mg")
        #expect(result == 1000)
    }

    @Test("g to µg")
    func gToUg() {
        let result = DoseUnit.convert(1, from: "g", to: "µg")
        #expect(result == 1_000_000)
    }

    // MARK: - µg conversions

    @Test("µg to mg")
    func ugToMg() {
        let result = DoseUnit.convert(500, from: "µg", to: "mg")
        #expect(result == 0.5)
    }

    @Test("µg to g")
    func ugToG() {
        let result = DoseUnit.convert(1_000_000, from: "µg", to: "g")
        #expect(result == 1.0)
    }

    // MARK: - Non-mass units

    @Test("Non-mass from-unit returns nil")
    func nonMassFrom() {
        #expect(DoseUnit.convert(10, from: "mL", to: "mg") == nil)
    }

    @Test("Non-mass to-unit returns nil")
    func nonMassTo() {
        #expect(DoseUnit.convert(10, from: "mg", to: "IU") == nil)
    }

    @Test("Both non-mass returns nil")
    func bothNonMass() {
        #expect(DoseUnit.convert(10, from: "mL", to: "IU") == nil)
    }

    // MARK: - Edge cases

    @Test("Zero amount")
    func zero() {
        #expect(DoseUnit.convert(0, from: "mg", to: "g") == 0)
    }

    @Test("Very small amount preserves precision")
    func smallAmount() {
        let result = DoseUnit.convert(0.001, from: "mg", to: "µg")
        #expect(result == 1.0)
    }
}
