import Foundation
import Testing
@testable import Piru

@Suite("Product Code Keys")
struct ProductCodeKeyTests {
    // MARK: - Check digits

    @Test
    func `GS1 check digit matches known codes`() {
        #expect(ProductCodeKey.checkDigit("340094949729") == "4")
        #expect(ProductCodeKey.checkDigit("03600029145") == "2")
        #expect(ProductCodeKey.checkDigit("12a") == nil)
    }

    // MARK: - GTIN normalization

    @Test
    func `EAN-13 pads to a 14-digit key`() {
        #expect(ProductCodeKey.gtin14(fromGTIN: "3400949497294") == "03400949497294")
    }

    @Test
    func `UPC-A pads to a 14-digit key`() {
        #expect(ProductCodeKey.gtin14(fromGTIN: "350458586015") == "00350458586015")
    }

    @Test
    func `A bad check digit is rejected`() {
        #expect(ProductCodeKey.gtin14(fromGTIN: "3400949497295") == nil)
        #expect(ProductCodeKey.gtin14(fromGTIN: "12345") == nil)
    }

    // MARK: - NDC → GTIN

    @Test
    func `A package NDC becomes its 003-prefixed GTIN in every hyphenation`() {
        let expected = "00350458586015"
        #expect(ProductCodeKey.gtin14(fromNDC: "50458-586-01") == expected)
        #expect(ProductCodeKey.gtin14(fromNDC: "5045858601") == expected)
        // 11-digit 5-4-2 with the product segment zero-padded.
        #expect(ProductCodeKey.gtin14(fromNDC: "50458-0586-01") == expected)
    }

    @Test
    func `NDC-derived GTIN agrees with the printed UPC-A`() {
        // The UPC-A on a US box is 3 + NDC-10 + check — the same key.
        #expect(ProductCodeKey.gtin14(fromNDC: "50458-586-01") == ProductCodeKey.gtin14(fromGTIN: "350458586015"))
    }

    @Test
    func `A product NDC without a package segment has no barcode`() {
        #expect(ProductCodeKey.gtin14(fromNDC: "50458-586") == nil)
    }

    @Test
    func `A printed NDC line resolves to its GTIN`() {
        #expect(ProductCodeKey.gtin14(fromText: "NDC 50458-586-01 · Rx only") == "00350458586015")
        #expect(ProductCodeKey.gtin14(fromText: "NDC: 50458-586-01") == "00350458586015")
        #expect(ProductCodeKey.gtin14(fromText: "Lot 50458-586-01") == nil)
    }

    // MARK: - Barcode payloads

    @Test
    func `A GS1 element string yields its GTIN first`() {
        let payload = "0103400949497294" + "17261231" + "10ABC123"
        #expect(ProductCodeKey.candidates(forBarcode: payload).first == "03400949497294")
    }

    @Test
    func `A plain EAN-13 payload is its own key`() {
        #expect(ProductCodeKey.candidates(forBarcode: "3400949497294") == ["03400949497294"])
    }

    @Test
    func `Garbage yields no candidates`() {
        #expect(ProductCodeKey.candidates(forBarcode: "hello").isEmpty)
    }

    // MARK: - Country routing

    @Test
    func `GS1 prefixes route to their registries`() {
        #expect(ProductCodeKey.countryCode(ofGTIN14: "03400949497294") == "FR")
        #expect(ProductCodeKey.countryCode(ofGTIN14: "00350458586015") == "US")
        #expect(ProductCodeKey.countryCode(ofGTIN14: "04012345678901") == "DE")
        #expect(ProductCodeKey.countryCode(ofGTIN14: "06901234567892") == nil)
    }
}
