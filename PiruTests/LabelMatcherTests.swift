import Foundation
import Testing
@testable import Piru

@Suite("Label Matcher")
struct LabelMatcherTests {
    // MARK: - Strength parsing

    @Test
    func `Parses whole-milligram strength`() {
        let s = LabelMatcher.parseStrength("36 mg")
        #expect(s?.amount == 36)
        #expect(s?.unit == "mg")
    }

    @Test
    func `Parses decimal strength with no space`() {
        let s = LabelMatcher.parseStrength("0.5mg")
        #expect(s?.amount == 0.5)
        #expect(s?.unit == "mg")
    }

    @Test
    func `Normalizes mcg to micrograms`() {
        #expect(LabelMatcher.parseStrength("500 mcg")?.unit == "µg")
        #expect(LabelMatcher.parseStrength("500 µg")?.unit == "µg")
    }

    @Test
    func `Reads strength from an openFDA per-unit string`() {
        let s = LabelMatcher.parseStrength("36 mg/1")
        #expect(s?.amount == 36)
        #expect(s?.unit == "mg")
    }

    @Test
    func `Finds strength embedded in a label line`() {
        let s = LabelMatcher.parseStrength("Concerta 36 mg extended release")
        #expect(s?.amount == 36)
        #expect(s?.unit == "mg")
    }

    @Test
    func `No strength returns nil`() {
        #expect(LabelMatcher.parseStrength("Concerta tablets") == nil)
    }

    @Test
    func `Does not misread a number glued to letters`() {
        #expect(LabelMatcher.parseStrength("lot AB12mg9") == nil)
    }

    // MARK: - Route mapping

    @Test
    func `Maps openFDA routes to Piru routes`() {
        #expect(LabelMatcher.route(fromOpenFDA: ["ORAL"]) == .oral)
        #expect(LabelMatcher.route(fromOpenFDA: ["NASAL"]) == .insufflation)
        #expect(LabelMatcher.route(fromOpenFDA: ["SUBLINGUAL"]) == .sublingual)
        #expect(LabelMatcher.route(fromOpenFDA: []) == nil)
        #expect(LabelMatcher.route(fromOpenFDA: ["UNKNOWNBODYSITE"]) == nil)
    }

    // MARK: - OCR resolution

    @Test
    func `Resolves a brand name to its canonical substance, keeping the brand`() {
        let resolved = LabelMatcher.resolve(ocrText: "Concerta 36 mg")
        #expect(resolved?.canonicalName == "Methylphenidate")
        #expect(resolved?.brandName == "Concerta")
        #expect(resolved?.strength == 36)
        #expect(resolved?.unit == "mg")
    }

    @Test
    func `Resolves a canonical name with no brand tag`() {
        let resolved = LabelMatcher.resolve(ocrText: "Caffeine")
        #expect(resolved?.canonicalName.lowercased() == "caffeine")
        #expect(resolved?.brandName == nil)
    }

    @Test
    func `Unknown text does not resolve`() {
        #expect(LabelMatcher.resolve(ocrText: "Nutrition Facts") == nil)
    }

    @Test
    func `Best candidate strips strength for a manual-search fallback`() {
        #expect(LabelMatcher.bestCandidate(in: "Rilatine 20 mg") == "Rilatine")
    }

    @Test
    func `A leading number that is part of the name is not stripped`() {
        // Only a number *with a unit* is a strength; "5" here belongs to "5-HTP".
        #expect(LabelMatcher.bestCandidate(in: "5-HTP 100 mg") == "5-HTP")
    }
}
