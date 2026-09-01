import Foundation
import Testing
@testable import Piru

/// The bundled barcode registry, as the app reads it: the table ships with
/// rows, and the two registries' flagship codes resolve to the substance
/// their box is sold as.
@MainActor
@Suite("Product Codes — bundled DB")
struct ProductCodesDatabaseTests {
    @Test
    func `The bundled database carries a barcode registry`() {
        #expect(SubstanceStore.shared.reader.productCodeCount() > 0)
    }

    @Test
    func `A US NDC barcode resolves to its substance and strength`() throws {
        // Concerta 36 mg, package NDC 50458-586-01, printed as UPC-A 350458586015.
        let hit = try #require(SubstanceStore.shared.productCode(forBarcode: "350458586015"))
        #expect(hit.canonicalName == "Methylphenidate")
        #expect(hit.codeKind == "ndc")
        #expect(hit.country == "US")
        #expect(hit.brand?.uppercased() == "CONCERTA")
        #expect(hit.parsedStrength?.amount == 36)
        #expect(hit.parsedStrength?.unit == "mg")
        #expect(hit.psid.map(PSID.isValid) == true)
    }

    @Test
    func `A French CIP13 barcode resolves with its pack size`() throws {
        // Ritaline 10 mg, 30 comprimés.
        let hit = try #require(SubstanceStore.shared.productCode(forBarcode: "3400933929404"))
        #expect(hit.canonicalName == "Methylphenidate")
        #expect(hit.codeKind == "cip13")
        #expect(hit.country == "FR")
        #expect(hit.packCount == 30)
        #expect(hit.packUnit == "tablet")
    }

    @Test
    func `A printed NDC line resolves like its barcode`() throws {
        let hit = try #require(SubstanceStore.shared.productCode(forNDCText: "NDC 50458-586-01"))
        #expect(hit.canonicalName == "Methylphenidate")
    }

    @Test
    func `An unknown barcode resolves to nothing`() {
        #expect(SubstanceStore.shared.productCode(forBarcode: "3400912345676") == nil)
    }

    @Test
    func `A reading with a known barcode identifies by barcode, with chips`() async {
        let reading = BoxReading(texts: ["CONCERTA®", "36 mg", "100 Tablets"], barcodes: ["350458586015"])
        let identified = await BoxIdentifier.identify(reading)
        #expect(identified.canonicalName == "Methylphenidate")
        #expect(identified.origin == .barcode)
        #expect(identified.strength == 36)
        #expect(identified.packCount == PackCount(count: 100, unit: .tablet))
        #expect(identified.chips.contains { $0.kind == .barcode && $0.confidence == .high })
        #expect(identified.chips.contains { $0.kind == .brand && $0.text == "Concerta" })
        #expect(identified.searchToken == nil)
    }

    @Test
    func `A reading nothing matches keeps a search token and the barcode's country`() async {
        let reading = BoxReading(texts: ["Zaltrapex", "20 comprimés"], barcodes: ["3400912345676"])
        let identified = await BoxIdentifier.identify(reading)
        #expect(identified.canonicalName == nil)
        #expect(identified.searchToken == "Zaltrapex")
        #expect(identified.barcodeCountry == "FR")
        #expect(identified.chips.contains { $0.kind == .barcode && $0.confidence == .low })
    }
}
