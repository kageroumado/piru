import Foundation
import Testing
@testable import Piru

@Suite("GS1 Parser")
struct GS1ParserTests {
    /// FNC1 group separator.
    private static let gs = "\u{1D}"

    @Test
    func `Fixed-length GTIN (AI 01) consumes exactly 14 digits`() {
        let data = GS1Parser.parse("0100312345678901")
        #expect(data.gtin == "00312345678901")
        #expect(data.expiryDate == nil)
    }

    @Test
    func `Fixed-length expiry (AI 17) reads YYMMDD`() {
        let data = GS1Parser.parse("17251231")
        #expect(data.expiryDate == "251231")
    }

    @Test
    func `Variable-length lot (AI 10) runs to end of string`() {
        let data = GS1Parser.parse("10LOT42")
        #expect(data.lotNumber == "LOT42")
    }

    @Test
    func `Variable-length lot terminates at FNC1`() {
        let data = GS1Parser.parse("10LOT42\(Self.gs)21SER99")
        #expect(data.lotNumber == "LOT42")
        #expect(data.serialNumber == "SER99")
    }

    @Test
    func `Full DSCSA payload: GTIN, expiry, lot, serial`() {
        let payload = "01" + "00312345678901"
            + "17" + "251231"
            + "10" + "LOT42" + Self.gs
            + "21" + "SER99"
        let data = GS1Parser.parse(payload)
        #expect(data.gtin == "00312345678901")
        #expect(data.expiryDate == "251231")
        #expect(data.lotNumber == "LOT42")
        #expect(data.serialNumber == "SER99")
    }

    @Test
    func `Leading FNC1 is skipped, not treated as data`() {
        let data = GS1Parser.parse(Self.gs + "0100312345678901")
        #expect(data.gtin == "00312345678901")
    }

    @Test
    func `Fixed field after a fixed field parses without a separator`() {
        // 01 (14) immediately followed by 17 (6) — no separator between fixed AIs.
        let data = GS1Parser.parse("0100312345678901" + "17251231")
        #expect(data.gtin == "00312345678901")
        #expect(data.expiryDate == "251231")
    }

    @Test
    func `Empty payload yields empty data`() {
        #expect(GS1Parser.parse("").isEmpty)
    }

    @Test
    func `Unrecognized AI value is skipped but later AIs still recover`() {
        // A variable unknown AI (99) terminates at FNC1, leaving 01 recoverable.
        let data = GS1Parser.parse("99SOMETHING\(Self.gs)0100312345678901")
        #expect(data.gtin == "00312345678901")
    }
}
