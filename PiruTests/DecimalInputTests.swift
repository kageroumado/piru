import Foundation
import Testing
@testable import Piru

@Suite("DecimalInput")
struct DecimalInputTests {
    private static let english = Locale(identifier: "en_US")
    private static let spanish = Locale(identifier: "es_ES")
    private static let chinese = Locale(identifier: "zh_Hans_CN")

    @Test(arguments: [
        ("1,000", 1000.0),
        ("1,000.5", 1000.5),
        ("1.000,5", 1000.5),
        ("1,234.5", 1234.5),
        ("1,5", 1.5),
        ("0,25", 0.25),
        ("0,250", 0.25),
        ("1,23", 1.23),
        ("1,2345", 1.2345),
        ("12,345,678", 12_345_678),
        ("1.000.000", 1_000_000),
        (" 2 ", 2),
        ("2", 2),
        ("1.5", 1.5),
        ("1.000", 1),
        ("0.125", 0.125),
        (".5", 0.5),
        ("5.", 5),
        ("-1.5", -1.5),
        ("２５０", 250),
        ("１．５", 1.5),
    ])
    func `Reads typed numbers on an English (dot-decimal) keyboard`(text: String, expected: Double) {
        #expect(DecimalInput.parse(text, locale: Self.english) == expected)
    }

    @Test(arguments: [
        ("1,000", 1.0),
        ("1,000.5", 1000.5),
        ("1.000,5", 1000.5),
        ("1,5", 1.5),
        ("0,25", 0.25),
        ("1,23", 1.23),
        ("1.000", 1000),
        ("12.345.678", 12_345_678),
        ("12,345,678", 12_345_678),
        ("1.5", 1.5),
        ("1.25", 1.25),
        ("0.125", 0.125),
        (" 2 ", 2),
    ])
    func `Reads typed numbers on a Spanish (comma-decimal) keyboard`(text: String, expected: Double) {
        #expect(DecimalInput.parse(text, locale: Self.spanish) == expected)
    }

    @Test(arguments: [
        "", "   ", "abc", "1,,0", "1..0", ",", ".", "-", "1e5", "inf", "nan",
        "1 000", "1,000,00", "1.2.3", "1,234.5.6", "1.2.3,4", "12mg", "1,000,5.0",
    ])
    func `Rejects what is not a number`(text: String) {
        #expect(DecimalInput.parse(text, locale: Self.english) == nil)
        #expect(DecimalInput.parse(text, locale: Self.spanish) == nil)
    }

    @Test
    func `Simplified Chinese reads like English`() {
        #expect(DecimalInput.parse("1,000", locale: Self.chinese) == 1000)
        #expect(DecimalInput.parse("1,5", locale: Self.chinese) == 1.5)
        #expect(DecimalInput.parse("2.5", locale: Self.chinese) == 2.5)
    }

    @Test(arguments: [
        1.125, 1000, 0.333333, 12.5, 250, 1_234_567.5, 0.000001,
    ])
    func `editingText reads back to the same value in every shipped locale`(value: Double) {
        for locale in [Self.english, Self.spanish, Self.chinese, Locale(identifier: "zh_Hant_TW")] {
            let text = DecimalInput.editingText(value, locale: locale)
            #expect(DecimalInput.parse(text, locale: locale) == value, "\(text) in \(locale.identifier)")
        }
    }

    @Test
    func `doseFormatted text reads as a decimal in a comma-decimal locale`() {
        for value in [1.25, 3.34, 44.7, 0.68, 250] {
            #expect(DecimalInput.parse(value.doseFormatted, locale: Self.spanish) == value)
        }
    }
}
