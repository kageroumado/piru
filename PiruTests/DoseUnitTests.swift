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

    // MARK: - Spelling of the micro prefix

    @Test
    func `Greek mu converts exactly like the micro sign`() {
        // U+03BC GREEK SMALL LETTER MU vs U+00B5 MICRO SIGN. The catalog holds
        // both because upstreams type them differently, and matching only the
        // second meant LSD, all three fentanyl routes and sufentanil IV
        // converted to nothing at all.
        #expect(DoseUnit.convert(1_000, from: "\u{03BC}g", to: "mg") == 1.0)
        #expect(DoseUnit.convert(1, from: "mg", to: "\u{03BC}g") == 1_000)
        #expect(DoseUnit.convert(50, from: "\u{03BC}g", to: "\u{00B5}g") == 50)
    }

    @Test
    func `Written-out and abbreviated mass units convert`() {
        for spelling in ["mcg", "ug", "micrograms", "MCG"] {
            #expect(DoseUnit.convert(1_000, from: spelling, to: "mg") == 1.0, "\(spelling)")
        }
        #expect(DoseUnit.convert(1, from: "grams", to: "mg") == 1_000)
        #expect(DoseUnit.convert(5, from: "mgs", to: "mg") == 5)
    }

    @Test
    func `A qualified unit is not folded onto the bare one`() {
        // "mg (freebase)" states a basis. Treating it as plain mg would let a
        // freebase amount be compared against a salt amount as though the
        // qualifier were decoration.
        #expect(DoseUnit.convert(10, from: "mg (freebase)", to: "mg") == nil)
        #expect(DoseUnit.convert(10, from: "mg (salt)", to: "µg") == nil)
    }

    @Test
    func `A rate is not a mass`() {
        #expect(DoseUnit.convert(25, from: "µg/hr", to: "µg") == nil)
        #expect(DoseUnit.convert(25, from: "mcg/hr (patch)", to: "mg") == nil)
        #expect(DoseUnit.convert(5, from: "mg/kg", to: "mg") == nil)
    }

    @Test
    func `Identity holds for units that are not masses at all`() {
        // The inventory replay converts a stock unit to itself; it must not
        // start failing just because mL is not convertible to a mass.
        #expect(DoseUnit.convert(30, from: "mL", to: "mL") == 30)
        #expect(DoseUnit.convert(2, from: "seeds", to: "seeds") == 2)
    }

    @Test
    func `Microgram-dosed substances get a critical precision warning`() {
        // The reason the spelling mattered: an unconvertible unit made
        // dosingPrecision fall through to .none, so the sub-milligram warning
        // was suppressed on exactly the drugs whose margin is thinnest.
        let lsd = DoseRange(common: 60 ... 200)
        #expect(lsd.dosingPrecision(unit: "micrograms") == .critical)
        let fentanyl = DoseRange(common: 25 ... 50)
        #expect(fentanyl.dosingPrecision(unit: "\u{03BC}g") == .critical)
    }
}
