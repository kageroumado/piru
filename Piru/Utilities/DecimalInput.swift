import Foundation

/// The one reader for a number the user typed or pasted into an amount,
/// volume, strength or concentration field.
///
/// `Double(_:)` alone reads only a dot decimal, and swapping every comma for a
/// dot turns a pasted "1,000" into 1 — a dose a thousand times too small. The
/// rules here read `.` and `,` by where they sit, let the locale settle the one
/// case that reads two ways, and refuse what nothing settles:
///
/// - **Both separators present:** the last one is the decimal and appears once,
///   and everything before it must be correctly grouped ("1,234.5", "1.234,5").
/// - **One kind, repeated:** grouping, when correctly placed ("1,000,000";
///   "1.000.000" on an English keyboard).
/// - **One separator that can only be a decimal:** fewer than three digits
///   after it, or a whole part that could not be a first group (four or more
///   digits, or a leading 0), reads as a decimal in every locale, because
///   people type the other convention's decimal into an app set to theirs
///   ("1,5", "0,125", "1,23" on an English keyboard; "1.5" in Spanish).
/// - **One separator before exactly three digits** ("1,000"): a thousand in
///   English and one in Spanish, so the locale decides when the mark is its
///   decimal or its grouping separator, and the text is refused when it is
///   neither ("1.000" in French, which groups with a space).
/// - **The locale's grouping separator before four or more digits**
///   ("1,0000" in English) is refused: it is a grouping typo as often as a
///   decimal.
///
/// Refused is the safe answer: a separator misread the other way records a
/// dose a thousand times off. Anything else that is not a number — letters,
/// exponents, `inf`/`nan`, misplaced separators, inner spaces, a bare
/// separator, fractions and superscripts — is `nil` too, so a caller can tell
/// a typo from a zero. Decimal digits in any script (Arabic-Indic, full-width
/// from a CJK IME) read as their value, with their own separators.
nonisolated enum DecimalInput {
    private static let separators: Set<Character> = [".", ","]

    /// Non-ASCII separators and signs, as the ASCII mark they stand for.
    private static let foreignMarks: [Character: Character] = [
        "\u{066B}": ".", "\u{FF0E}": ".", "\u{066C}": ",", "\u{FF0C}": ",",
        "\u{2212}": "-", "\u{FF0D}": "-", "\u{FF0B}": "+",
    ]

    /// The value of `text`, or `nil` when it is not one number read without
    /// guessing.
    static func parse(_ text: String, locale: Locale = .current) -> Double? {
        guard var body = ascii(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        var sign = ""
        if let first = body.first, first == "-" || first == "+" {
            sign = first == "-" ? "-" : ""
            body.removeFirst()
        }
        guard body.allSatisfy({ $0.isNumber || separators.contains($0) }),
              body.contains(where: \.isNumber),
              let (integer, fraction) = split(body, locale: locale),
              let digits = ungrouped(integer)
        else { return nil }
        let plain = sign + (digits.isEmpty ? "0" : digits) + (fraction.isEmpty ? "" : "." + fraction)
        guard let value = Double(plain), value.isFinite else { return nil }
        return value
    }

    /// `value` as editable text for a field this parser reads back: the
    /// locale's decimal separator, no grouping, up to nine fraction digits. A
    /// dot-decimal "1.125" seeded into a Spanish field would read back as 1125.
    static func editingText(_ value: Double, locale: Locale = .current) -> String {
        value.formatted(
            .number
                .grouping(.never)
                .precision(.fractionLength(0 ... 9))
                .locale(locale),
        )
    }

    /// `text` with every decimal digit in ASCII and every separator or sign as
    /// `.`, `,`, `-` or `+`, or `nil` when it holds anything else.
    private static func ascii(_ text: String) -> String? {
        var out = ""
        for character in text {
            if character.unicodeScalars.count == 1,
               character.unicodeScalars.first?.properties.numericType == .decimal,
               let digit = character.wholeNumberValue {
                out += String(digit)
            } else if separators.contains(character) || character == "-" || character == "+" {
                out.append(character)
            } else if let mark = foreignMarks[character] {
                out.append(mark)
            } else {
                return nil
            }
        }
        return out
    }

    /// `body` cut at its decimal separator into the integer part (grouping
    /// still in it) and the fraction digits, or `nil` when the separators
    /// can't be read without guessing.
    private static func split(_ body: String, locale: Locale) -> (integer: String, fraction: String)? {
        let marks = body.filter { separators.contains($0) }
        guard let last = marks.last else { return (body, "") }
        let decimal: Character?
        if marks.count == 1 {
            guard let lone = loneSeparatorIsDecimal(body, mark: last, locale: locale) else { return nil }
            decimal = lone ? last : nil
        } else if Set(marks).count == 2 {
            guard marks.count(where: { $0 == last }) == 1 else { return nil }
            decimal = last
        } else {
            decimal = nil
        }
        guard let decimal, let index = body.lastIndex(of: decimal) else { return (body, "") }
        let integer = String(body[..<index])
        let fraction = String(body[body.index(after: index)...])
        guard !(integer.isEmpty && fraction.isEmpty) else { return nil }
        return (integer, fraction)
    }

    /// Whether the one separator in `body` is its decimal (`true`) or a
    /// thousands separator (`false`), or `nil` when only a guess could say.
    private static func loneSeparatorIsDecimal(_ body: String, mark: Character, locale: Locale) -> Bool? {
        let parts = body.split(separator: mark, omittingEmptySubsequences: false)
        let whole = parts[0], fraction = parts[1]
        let wholeCouldGroup = (1 ... 3).contains(whole.count) && whole.first != "0"
        if !wholeCouldGroup || fraction.count < 3 { return true }
        if fraction.count > 3 { return String(mark) == locale.groupingSeparator ? nil : true }
        if String(mark) == locale.decimalSeparator { return true }
        if String(mark) == locale.groupingSeparator { return false }
        return nil
    }

    /// `integer` with its grouping separators removed, or `nil` unless it is
    /// grouped correctly: a first group of 1–3 digits that does not start with
    /// 0, then groups of exactly three, all with one separator.
    private static func ungrouped(_ integer: String) -> String? {
        guard let mark = integer.first(where: { separators.contains($0) }) else { return integer }
        let groups = integer.split(separator: mark, omittingEmptySubsequences: false)
        guard let first = groups.first, (1 ... 3).contains(first.count), first.first != "0",
              groups.dropFirst().allSatisfy({ $0.count == 3 }),
              groups.allSatisfy({ $0.allSatisfy(\.isNumber) })
        else { return nil }
        return groups.joined()
    }
}
