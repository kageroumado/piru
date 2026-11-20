import Testing
@testable import Piru

@Suite("Double.doseFormatted")
struct DoseFormattedTests {
    @Test
    func zero() {
        #expect(0.0.doseFormatted == "0")
    }

    @Test
    func `Large values (>=100) round to integer`() {
        #expect(100.0.doseFormatted == "100")
        #expect(250.7.doseFormatted == "251")
        #expect(9_999.0.doseFormatted == "9999")
        #expect(10_000.0.doseFormatted == "10000")
    }

    @Test
    func `Medium values (10–99) show up to 1 decimal`() {
        #expect(10.0.doseFormatted == "10")
        #expect(10.5.doseFormatted == "10.5")
        #expect(44.664389.doseFormatted == "44.7")
    }

    @Test
    func `Small values (1–9) show up to 2 decimals`() {
        #expect(1.0.doseFormatted == "1")
        #expect(3.339983.doseFormatted == "3.34")
        #expect(5.10.doseFormatted == "5.1")
    }

    @Test
    func `Sub-unit values (<1) show up to 2 decimals`() {
        #expect(0.677132.doseFormatted == "0.68")
        #expect(0.5.doseFormatted == "0.5")
        #expect(0.10.doseFormatted == "0.1")
    }

    @Test
    func `Negative values`() {
        #expect((-5.0).doseFormatted == "-5")
        #expect((-0.677).doseFormatted == "-0.68")
    }
}

@Suite("String.unitDisplay")
struct UnitDisplayTests {
    @Test
    func `A count unit reads singular at exactly one`() {
        #expect("tabs".unitDisplay(for: 1) == "tab")
        #expect("caps".unitDisplay(for: 1) == "cap")
        #expect("units".unitDisplay(for: 1) == "unit")
    }

    @Test
    func `A count unit stays plural at zero and two`() {
        #expect("tabs".unitDisplay(for: 0) == "tabs")
        #expect("tabs".unitDisplay(for: 2) == "tabs")
        #expect("caps".unitDisplay(for: 0.5) == "caps")
    }

    @Test
    func `The stored casing is kept`() {
        #expect("Tabs".unitDisplay(for: 1) == "Tab")
        #expect("CAPS".unitDisplay(for: 1) == "CAP")
    }

    @Test
    func `Mass, volume and other units pass through`() {
        #expect("mg".unitDisplay(for: 1) == "mg")
        #expect("g".unitDisplay(for: 1) == "g")
        #expect("mL".unitDisplay(for: 1) == "mL")
        #expect("drops".unitDisplay(for: 1) == "drops")
    }

    @Test
    func `Every inventory count unit is singularized`() {
        #expect(InventoryMath.countUnits.isSubset(of: String.singularizableCountUnits))
        for unit in InventoryMath.countUnits {
            #expect(unit.unitDisplay(for: 1) == String(unit.dropLast()))
        }
    }
}
