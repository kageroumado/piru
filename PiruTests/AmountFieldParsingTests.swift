import Foundation
import Testing
@testable import Piru

/// The quick log's amount field reads separators by the locale, and refuses
/// a number it could only guess at rather than log a dose a thousand times off.
@Suite("Amount field parsing")
@MainActor
struct AmountFieldParsingTests {
    private let english = Locale(identifier: "en_US")
    private let german = Locale(identifier: "de_DE")
    private let french = Locale(identifier: "fr_FR")
    private let swiss = Locale(identifier: "de_CH")

    @Test
    func `A thousands separator is a thousand where the locale groups with a comma`() {
        #expect(StagedDoseEditorModel.parsedAmount("1,000", locale: english) == 1_000)
        #expect(StagedDoseEditorModel.parsedAmount("12,500", locale: english) == 12_500)
        #expect(StagedDoseEditorModel.parsedAmount("1,000,000", locale: english) == 1_000_000)
        #expect(StagedDoseEditorModel.parsedAmount("1,000.5", locale: english) == 1_000.5)
    }

    @Test
    func `A decimal comma still reads as a decimal`() {
        #expect(StagedDoseEditorModel.parsedAmount("1,5", locale: german) == 1.5)
        #expect(StagedDoseEditorModel.parsedAmount("0,125", locale: german) == 0.125)
        #expect(StagedDoseEditorModel.parsedAmount("1.000,5", locale: german) == 1_000.5)
        #expect(StagedDoseEditorModel.parsedAmount("1,5", locale: english) == 1.5)
    }

    @Test
    func `The locale settles a lone separator before three digits`() {
        #expect(StagedDoseEditorModel.parsedAmount("1,000", locale: german) == 1)
        #expect(StagedDoseEditorModel.parsedAmount("1,125", locale: german) == 1.125)
        #expect(StagedDoseEditorModel.parsedAmount("1.000", locale: german) == 1_000)
        #expect(StagedDoseEditorModel.parsedAmount("1.000", locale: english) == 1)
    }

    @Test
    func `The field's own formatted text always reads back`() {
        #expect(StagedDoseEditorModel.parsedAmount("2.5", locale: german) == 2.5)
        #expect(StagedDoseEditorModel.parsedAmount("0.125", locale: german) == 0.125)
        #expect(StagedDoseEditorModel.parsedAmount("1.125", locale: english) == 1.125)
        #expect(StagedDoseEditorModel.parsedAmount("250", locale: german) == 250)
    }

    @Test
    func `A separator the locale cannot settle is refused, not guessed`() {
        // French groups with a space and Swiss German with an apostrophe, so
        // neither says what "1.000" or "1,000" means.
        #expect(StagedDoseEditorModel.parsedAmount("1.000", locale: french) == nil)
        #expect(StagedDoseEditorModel.parsedAmount("1,000", locale: swiss) == nil)
        #expect(StagedDoseEditorModel.parsedAmount("1,0000", locale: english) == nil)
        #expect(StagedDoseEditorModel.parsedAmount("1,00,000", locale: english) == nil)
        #expect(StagedDoseEditorModel.parsedAmount("1.5.5", locale: english) == nil)
        #expect(StagedDoseEditorModel.parsedAmount("10 mg", locale: english) == nil)
    }

    @Test
    func `Digits in another script read the same way, and nothing else slips through`() {
        #expect(StagedDoseEditorModel.parsedAmount("\u{0661}\u{066B}\u{0665}", locale: english) == 1.5)
        #expect(StagedDoseEditorModel.parsedAmount("\u{FF11},\u{FF10}\u{FF10}\u{FF10}", locale: english) == 1_000)
        #expect(StagedDoseEditorModel.parsedAmount("1\u{00A0}000", locale: english) == nil)
        #expect(StagedDoseEditorModel.parsedAmount("1\u{00BD}", locale: english) == nil)
        #expect(StagedDoseEditorModel.parsedAmount("1\u{00B2}", locale: english) == nil)
    }

    @Test
    func `An unreadable amount stages no amount and says so`() {
        var dose = StagedDose(substanceName: "Caffeine", amount: 100, unit: "mg", route: .oral)
        let model = StagedDoseEditorModel()

        model.amountText = "1.000,5.5"
        model.commitAmountText(to: &dose)
        #expect(model.amountTextIsUnreadable)
        #expect(!dose.isUnknownAmount)
        #expect(dose.totalAmount == 0)

        model.amountText = "1000"
        model.commitAmountText(to: &dose)
        #expect(!model.amountTextIsUnreadable)
        #expect(dose.totalAmount == 1_000)
    }
}
