import Foundation
import Testing
@testable import Piru

@Suite("Pack Count Parser")
struct PackCountParserTests {
    @Test
    func `English tablets`() {
        #expect(PackCountParser.parse("28 tablets") == PackCount(count: 28, unit: .tablet))
        #expect(PackCountParser.parse("100 Tablets") == PackCount(count: 100, unit: .tablet))
    }

    @Test
    func `French comprimés and gélules`() {
        #expect(PackCountParser.parse("30 comprimés") == PackCount(count: 30, unit: .tablet))
        #expect(PackCountParser.parse("Boîte de 28 gélules") == PackCount(count: 28, unit: .capsule))
    }

    @Test
    func `German Stück and Kapseln`() {
        #expect(PackCountParser.parse("100 Stück") == PackCount(count: 100, unit: .piece))
        #expect(PackCountParser.parse("20 Kapseln") == PackCount(count: 20, unit: .capsule))
    }

    @Test
    func `Capsules`() {
        #expect(PackCountParser.parse("20 capsules") == PackCount(count: 20, unit: .capsule))
    }

    @Test
    func `A liquid's volume`() {
        #expect(PackCountParser.parse("30 mL") == PackCount(count: 30, unit: .milliliter))
        #expect(PackCountParser.parse("118 ml oral solution") == PackCount(count: 118, unit: .milliliter))
    }

    @Test
    func `A strength per volume is not a pack size`() {
        #expect(PackCountParser.parse("500 mg/5 mL") == nil)
    }

    @Test
    func `N × M packs multiply`() {
        #expect(PackCountParser.parse("2 × 14 tablets") == PackCount(count: 28, unit: .tablet))
        #expect(PackCountParser.parse("3 x 10 comprimés") == PackCount(count: 30, unit: .tablet))
        #expect(PackCountParser.parse("2x10") == PackCount(count: 20, unit: .piece))
    }

    @Test
    func `A container phrase without a noun counts as pieces`() {
        #expect(PackCountParser.parse("Boîte de 30") == PackCount(count: 30, unit: .piece))
        #expect(PackCountParser.parse("Pack of 28") == PackCount(count: 28, unit: .piece))
    }

    @Test
    func `A strength is not a pack count`() {
        #expect(PackCountParser.parse("36 mg") == nil)
        #expect(PackCountParser.parse("Concerta 36 mg extended-release") == nil)
    }

    @Test
    func `The first line with a count wins across lines`() {
        let lines = ["CONCERTA", "36 mg", "100 Tablets", "NDC 50458-586-01"]
        #expect(PackCountParser.parse(lines: lines) == PackCount(count: 100, unit: .tablet))
    }

    @Test
    func `Form is read without a count`() {
        #expect(PackCountParser.form(in: "Extended-Release Tablets") == .tablet)
        #expect(PackCountParser.form(in: "gélule à libération prolongée") == .capsule)
        #expect(PackCountParser.form(in: "Oral solution") == nil)
    }

    @Test
    func `Inventory units`() {
        #expect(PackCount(count: 1, unit: .tablet).inventoryUnit == "tabs")
        #expect(PackCount(count: 1, unit: .capsule).inventoryUnit == "caps")
        #expect(PackCount(count: 1, unit: .milliliter).inventoryUnit == "mL")
    }
}
