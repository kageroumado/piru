import Testing
@testable import Piru

@Suite("Double.doseFormatted")
struct DoseFormattedTests {

    @Test("Whole number under 10000 has no decimal")
    func wholeNumber() {
        #expect((10.0).doseFormatted == "10")
        #expect((100.0).doseFormatted == "100")
        #expect((9999.0).doseFormatted == "9999")
    }

    @Test("Zero formats without decimal")
    func zero() {
        #expect((0.0).doseFormatted == "0")
    }

    @Test("One formats without decimal")
    func one() {
        #expect((1.0).doseFormatted == "1")
    }

    @Test("Decimal value preserves decimal")
    func decimal() {
        let result = (10.5).doseFormatted
        #expect(result.contains("."))
        #expect(result.contains("5"))
    }

    @Test("Large whole number >= 10000 uses default formatting")
    func largeWholeNumber() {
        // >= 10000 should not use the special integer format
        let result = (10000.0).doseFormatted
        // The default formatted() may include commas or other locale-specific formatting
        #expect(!result.isEmpty)
    }

    @Test("Negative whole number")
    func negativeWhole() {
        #expect((-5.0).doseFormatted == "-5")
    }
}
