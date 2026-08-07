import Foundation
import Testing
@testable import Piru

@Suite("NDC Resolver")
struct NDCResolverTests {
    // MARK: - GTIN → NDC-10 extraction

    @Test
    func `GTIN-14 strips indicator, 03 prefix, and check digit`() {
        // 0 03 1234567890 1  →  NDC-10 = 1234567890
        #expect(NDC.ndc10(from: "00312345678901") == "1234567890")
    }

    @Test
    func `UPC-A drug code (system digit 3) yields its NDC-10`() {
        // 3 1234567890 5  →  NDC-10 = 1234567890
        #expect(NDC.ndc10(from: "312345678905") == "1234567890")
    }

    @Test
    func `Non-drug GTIN (not 03-prefixed) is rejected`() {
        #expect(NDC.ndc10(from: "01234567890128") == nil)
    }

    @Test
    func `UPC-A that is not a drug (system digit not 3) is rejected`() {
        #expect(NDC.ndc10(from: "012345678905") == nil)
    }

    @Test
    func `Wrong-length code is rejected`() {
        #expect(NDC.ndc10(from: "12345") == nil)
    }

    @Test
    func `Non-digit characters are ignored before length check`() {
        #expect(NDC.ndc10(from: "0-0-3-1234567890-1") == "1234567890")
    }

    // MARK: - product_ndc candidates

    @Test
    func `NDC-10 expands to the three standard product_ndc splits`() {
        let candidates = NDC.productNDCCandidates(fromNDC10: "1234567890")
        #expect(candidates == ["12345-6789", "12345-678", "1234-5678"])
    }

    @Test
    func `Non-10-digit NDC yields no candidates`() {
        #expect(NDC.productNDCCandidates(fromNDC10: "123").isEmpty)
    }
}
